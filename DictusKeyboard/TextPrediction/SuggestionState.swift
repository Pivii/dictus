// DictusKeyboard/TextPrediction/SuggestionState.swift
// Observable state for the suggestion bar UI, bridging TextPredictionEngine to SwiftUI.
import UIKit
import DictusCore

/// The current mode of the suggestion bar.
///
/// WHY an enum:
/// The suggestion bar displays different content depending on context:
/// - idle: empty bar (user just typed a space or field is empty)
/// - completions: showing word completions for partial input
/// - corrections: showing spell corrections for a complete misspelled word
/// The UI layer uses this to style the bar differently per mode.
enum SuggestionMode {
    case idle
    case completions
    case corrections
    case predictions      // After space: showing n-gram predicted next words
    case undoAvailable    // After autocorrect: showing undo option for previous correction
}

/// Tracks the last autocorrection so the user can undo it.
///
/// WHY:
/// Autocorrect can be wrong. iOS convention is that tapping the suggestion bar
/// after an autocorrection undoes it. We store the original + corrected word
/// and whether a space was auto-inserted, so undo can restore exact state.
struct AutocorrectState {
    let originalWord: String
    let correctedWord: String
    let insertedSpace: Bool
}

/// Observable suggestion state for SwiftUI binding.
///
/// WHY ObservableObject:
/// The suggestion bar is a SwiftUI view that needs to reactively update when
/// suggestions change. @Published properties trigger SwiftUI re-renders
/// automatically when the engine produces new suggestions.
///
/// WHY a separate class from TextPredictionEngine:
/// Separation of concerns: TextPredictionEngine is pure logic (testable without UI),
/// SuggestionState is the UI-facing adapter that holds @Published state and
/// handles UITextDocumentProxy interaction.
class SuggestionState: ObservableObject {

    /// Process-wide shared instance.
    /// Per-controller instances were being retained by SwiftUI's @ObservedObject backing
    /// store past their owning KeyboardViewController.deinit (#134). Sharing makes the
    /// leak no-op since all observers point to the same instance — only one keyboard
    /// is visible at a time.
    static let shared = SuggestionState()

    @Published var suggestions: [String] = []
    @Published var mode: SuggestionMode = .idle
    @Published var currentWord: String = ""

    /// Tracks an autocorrection that can be undone by tapping the suggestion bar.
    /// Set when autocorrect fires on space, cleared on next space or undo tap.
    @Published var pendingUndo: AutocorrectState?

    /// Words the user has rejected autocorrection for (undo'd).
    /// After undo, the same word should not be re-corrected on the next space.
    /// Cleared when the user starts typing a new word.
    var rejectedWords: Set<String> = []

    /// Policy derived from the host field's input traits (#200).
    /// Refreshed on the main thread by DictusKeyboardBridge/KeyboardViewController
    /// whenever the field can have changed (appearance, text/selection change,
    /// each keystroke). Cached here because updateAsync/updatePredictions run on
    /// a background queue and cannot read UITextDocumentProxy themselves.
    var hostPolicy: HostFieldPolicy = .allowed

    /// Shared engine — heavy resources (frequency dict, trie) are process-wide singletons
    /// to avoid the per-controller leak documented in #134.
    private let engine = TextPredictionEngine.shared

    private init() {}

    /// Serial background queue for suggestion computation.
    /// WHY serial: Ensures suggestion computations don't race each other.
    /// WHY .userInitiated: Suggestions are user-facing but not blocking the touch pipeline.
    private let suggestionQueue = DispatchQueue(
        label: "com.pivi.dictus.suggestions",
        qos: .userInitiated
    )

    /// Current in-flight suggestion work. Cancelled when a new keystroke arrives.
    /// WHY DispatchWorkItem: Thread-safe cancellation built into GCD.
    /// Without coalescing, rapid typing queues 6-10 suggestion computations per second,
    /// all running to completion. With coalescing, only the latest keystroke runs.
    private var currentSuggestionWork: DispatchWorkItem?

    /// Whether autocorrect is enabled (reads from App Group shared preferences).
    var autocorrectEnabled: Bool {
        AppGroup.defaults.object(forKey: SharedKeys.autocorrectEnabled) as? Bool ?? true
    }

    /// Updates suggestions based on the current text input state.
    ///
    /// Called on every keystroke from the keyboard view.
    ///
    /// HOW IT WORKS:
    /// 1. Extract the last partial word from the text before the cursor
    /// 2. Check spell correction engine (same engine that fires on space)
    /// 3. If correction found: show [original | **correction** | alternative] (standard mobile layout)
    /// 4. If no correction: show UITextChecker completions
    /// 5. If no partial word (after space/newline), go idle
    ///
    /// WHY show correction in bar:
    /// The bar must preview what space will do. Standard iOS keyboard behavior:
    /// center slot (bold) = what gets auto-applied on space. If the bar shows
    /// completions but space applies a different correction, that's confusing.
    func update(proxy: UITextDocumentProxy) {
        // Host field traits gate (#200): search/URL/email fields get no suggestions.
        hostPolicy = HostInputTraits.policy(for: proxy)
        guard hostPolicy.suggestionsAllowed else {
            clear()
            return
        }

        guard let context = proxy.documentContextBeforeInput, !context.isEmpty else {
            clear()
            return
        }

        // If text ends with space or newline, no partial word to complete.
        // Don't clear predictions — they were set by handleSpace()/updatePredictions().
        if let lastChar = context.last, lastChar.isWhitespace || lastChar.isNewline {
            if mode != .predictions {
                clear()
            }
            return
        }

        // Extract the last word using substring enumeration
        let partial = extractLastWord(from: context)
        guard !partial.isEmpty else {
            clear()
            return
        }

        currentWord = partial

        // Guard: skip spell correction for tokens containing digits (#74)
        let containsDigit = partial.unicodeScalars.contains {
            CharacterSet.decimalDigits.contains($0)
        }
        if containsDigit {
            // Show completions only (no corrections) for numeric tokens
            let completions = engine.suggestions(for: partial)
            suggestions = completions.isEmpty ? [] : completions
            mode = completions.isEmpty ? .idle : .completions
            return
        }

        // Extract previous word for n-gram context boosting
        let previousWord = extractPreviousWord(from: context, currentWord: partial)

        // Check spell correction first (mirrors what handleSpace will do)
        if autocorrectEnabled,
           !rejectedWords.contains(partial.lowercased()),
           let result = engine.spellCheck(
               partial,
               previousWord: previousWord,
               isAtSentenceStart: ProperNounGuard.isAtSentenceStart(context: context, word: partial)
           ),
           result.correction.lowercased() != partial.lowercased() {
            // Standard mobile layout: [original | correction (bold) | alternative]
            var correctionSuggestions = [partial, result.correction]
            if let firstAlt = result.alternatives.first {
                correctionSuggestions.append(firstAlt)
            }
            suggestions = correctionSuggestions
            mode = .corrections
            return
        }

        // No correction — show word completions
        let completions = engine.suggestions(for: partial)
        if completions.isEmpty {
            suggestions = []
            mode = .idle
        } else {
            suggestions = completions
            mode = .completions
        }
    }

    /// Async suggestion update: takes pre-read context string (read on main thread),
    /// then dispatches computation to background. Cancels previous in-flight work.
    ///
    /// WHY a separate method from update(proxy:):
    /// update(proxy:) reads UITextDocumentProxy directly and runs synchronously on main.
    /// updateAsync takes a pre-read context string so the heavy computation
    /// (extractLastWord + engine lookups) runs on a background queue.
    /// The synchronous update() is still used by delete/undo paths where fresh proxy
    /// context is needed immediately.
    func updateAsync(context: String?) {
        // Host field traits gate (#200): reads the cached policy — this method
        // dispatches to a background queue and cannot touch the proxy itself.
        guard hostPolicy.suggestionsAllowed else {
            clear()
            return
        }

        guard let context = context, !context.isEmpty else {
            clear()
            return
        }

        // If text ends with whitespace, no partial word to complete.
        // BUT don't clear if we're showing predictions — handleSpace() already
        // triggered updatePredictions(), and clearing here would race with the
        // async prediction result. Predictions are the correct state after space.
        if let lastChar = context.last, lastChar.isWhitespace || lastChar.isNewline {
            if mode != .predictions && mode != .undoAvailable {
                clear()
            }
            return
        }

        // Cancel previous in-flight computation
        currentSuggestionWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let partial = self.extractLastWord(from: context)
            guard !partial.isEmpty else {
                DispatchQueue.main.async { self.clear() }
                return
            }

            // Guard: skip spell correction for tokens containing digits (#74)
            let containsDigit = partial.unicodeScalars.contains {
                CharacterSet.decimalDigits.contains($0)
            }
            if containsDigit {
                let completions = self.engine.suggestions(for: partial)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.currentWord = partial
                    self.suggestions = completions.isEmpty ? [] : completions
                    self.mode = completions.isEmpty ? .idle : .completions
                }
                return
            }

            // Extract previous word for n-gram context boosting
            let previousWord = self.extractPreviousWord(from: context, currentWord: partial)

            // Check spell correction first (mirrors what handleSpace will do)
            let spellResult: (correction: String, alternatives: [String])?
            if self.autocorrectEnabled,
               !self.rejectedWords.contains(partial.lowercased()) {
                spellResult = self.engine.spellCheck(
                    partial,
                    previousWord: previousWord,
                    isAtSentenceStart: ProperNounGuard.isAtSentenceStart(context: context, word: partial)
                )
            } else {
                spellResult = nil
            }

            // Compute completions as fallback
            let completions = self.engine.suggestions(for: partial)

            // Publish on main thread (required for @Published)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Check cancellation before publishing stale results
                guard !(self.currentSuggestionWork?.isCancelled ?? true) else { return }

                self.currentWord = partial

                // Undo available: show original word as first slot, fill remaining with completions
                if let undo = self.pendingUndo {
                    var undoSuggestions = [undo.originalWord]
                    undoSuggestions.append(contentsOf: completions.prefix(2))
                    self.suggestions = undoSuggestions
                    self.mode = .undoAvailable
                } else if let result = spellResult,
                   result.correction.lowercased() != partial.lowercased() {
                    // Spell correction (standard mobile layout)
                    var correctionSuggestions = [partial, result.correction]
                    if let firstAlt = result.alternatives.first {
                        correctionSuggestions.append(firstAlt)
                    }
                    self.suggestions = correctionSuggestions
                    self.mode = .corrections
                } else if !completions.isEmpty {
                    self.suggestions = completions
                    self.mode = .completions
                } else {
                    self.suggestions = []
                    self.mode = .idle
                }
            }
        }

        currentSuggestionWork = work
        suggestionQueue.async(execute: work)
    }

    /// Delegates spell-checking to the engine.
    /// Returns the best correction and alternatives for a misspelled word, or nil if correct.
    func performSpellCheck(_ word: String) -> (correction: String, alternatives: [String])? {
        return engine.spellCheck(word)
    }

    /// Spell check with optional previous word context for n-gram boosting.
    /// When previousWord is provided, correction candidates are reranked by bigram frequency.
    /// isAtSentenceStart drives the proper-noun guard (#199); defaults to true
    /// (conservative — corrections stay enabled for callers without position info).
    func performSpellCheck(
        _ word: String,
        previousWord: String?,
        isAtSentenceStart: Bool = true
    ) -> (correction: String, alternatives: [String])? {
        return engine.spellCheck(word, previousWord: previousWord, isAtSentenceStart: isAtSentenceStart)
    }

    /// Resets the suggestion state to idle.
    func clear() {
        suggestions = []
        mode = .idle
        currentWord = ""
    }

    /// Updates the prediction engine's language.
    func setLanguage(_ lang: String) {
        engine.setLanguage(lang)
    }

    /// Learn a word and notify the prediction engine (no-op for trie engine).
    func learnWord(_ word: String) {
        engine.injectUserWord(word)
    }

    /// Whether the active language's dictionary does not know this word (#287).
    /// The word-boundary learning site asks before recording anything.
    func isUnknownToDictionary(_ word: String) -> Bool {
        engine.isUnknownToDictionary(word)
    }

    /// Attempts the user dictionary's one-shot prune (#287). Call from a moment
    /// with a dictionary already mounted and no load pending — see the engine.
    func pruneUserDictionaryIfPossible(trigger: String) {
        engine.pruneUserDictionaryIfPossible(trigger: trigger)
    }

    // MARK: - N-gram Predictions

    /// Updates suggestion bar with n-gram predicted next words.
    /// Called after space insertion (handleSpace) and after prediction tap (chaining).
    ///
    /// WHY a separate method from update/updateAsync:
    /// Predictions use a different data path: instead of extracting the current partial
    /// word and running spell check, we extract the last 1-2 complete words and query
    /// the n-gram engine. The result is displayed in .predictions mode, not .corrections.
    func updatePredictions(context: String?) {
        // Host field traits gate (#200): no next-word predictions in search/URL fields.
        guard hostPolicy.suggestionsAllowed else {
            clear()
            return
        }

        guard let context = context, !context.isEmpty else {
            clear()
            return
        }

        // Cancel any in-flight completion work
        currentSuggestionWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Extract last 1-2 complete words from context
            let words = self.extractLastWords(from: context, count: 2)
            guard !words.isEmpty else {
                DispatchQueue.main.async { self.clear() }
                return
            }

            let predictions = self.engine.predictNextWords(after: words)
            print("[SuggestionState] updatePredictions context=\(words) results=\(predictions)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard !(self.currentSuggestionWork?.isCancelled ?? true) else { return }

                if let undo = self.pendingUndo {
                    var undoSuggestions = [undo.originalWord]
                    undoSuggestions.append(contentsOf: predictions.prefix(2))
                    self.suggestions = undoSuggestions
                    self.mode = .undoAvailable
                } else if predictions.isEmpty {
                    self.suggestions = []
                    self.mode = .idle
                } else {
                    self.suggestions = Array(predictions.prefix(3))
                    self.mode = .predictions
                }
            }
        }

        currentSuggestionWork = work
        suggestionQueue.async(execute: work)
    }

    /// Extracts the last N complete words from text context.
    /// Used for n-gram context: "Je suis en " -> ["suis", "en"]
    ///
    /// WHY not reuse extractLastWord: that returns the partial word being typed
    /// (before cursor, no trailing space). For predictions, we need the complete
    /// words before the space -- the n-gram engine looks up what comes AFTER these words.
    private func extractLastWords(from text: String, count: Int) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                words.append(word)
            }
        }
        let start = max(0, words.count - count)
        return Array(words[start...])
    }

    // MARK: - Private

    /// Extract the word before the current partial word in the text context.
    /// "Je sui" with currentWord "sui" returns "Je".
    /// "J'ai un prblm" with currentWord "prblm" returns "un".
    ///
    /// WHY not just split on spaces: Swift's enumerateSubstrings handles
    /// Unicode word boundaries correctly (apostrophes, hyphens, etc.).
    private func extractPreviousWord(from text: String, currentWord: String) -> String? {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                words.append(word)
            }
        }
        // The last word should be currentWord; the one before it is previousWord
        guard words.count >= 2, words.last?.lowercased() == currentWord.lowercased() else {
            return nil
        }
        return words[words.count - 2]
    }

    /// Extracts the last word from a text context string.
    ///
    /// WHY manual extraction:
    /// We use Swift's built-in word boundary detection via enumerateSubstrings
    /// to correctly handle Unicode, apostrophes in French (l'homme), and
    /// other edge cases. This is more reliable than splitting on spaces.
    private func extractLastWord(from text: String) -> String {
        var lastWord = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                lastWord = word
            }
        }
        return lastWord
    }
}
