// DictusKeyboard/DictusKeyboardBridge.swift
// Delegate bridge from giellakbd-ios GiellaKeyboardView key events to Dictus text actions.
// Created for Phase 18 Plan 02 -- wires the vendored UICollectionView keyboard
// to textDocumentProxy operations. Haptic and key sound both fire on touchDown in
// GiellaKeyboardView, not here (#286).

import UIKit
import DictusCore

/// Adapts GiellaKeyboardView delegate callbacks into Dictus keyboard actions.
///
/// WHY a separate bridge class (not making KeyboardViewController the delegate):
/// 1. Single Responsibility: The bridge handles ONLY key event translation.
///    KeyboardViewController handles view lifecycle, height, and hosting.
/// 2. Testability: The bridge can be tested in isolation with a mock proxy.
/// 3. Decoupling: If the vendored delegate protocol changes, only this file changes.
///
/// The bridge receives key events from the UICollectionView keyboard and:
/// - Inserts/deletes text via textDocumentProxy
/// - Manages shift/capslock page state on the keyboard view
/// - Handles auto-full-stop (double-space -> period)
///
/// It emits no key click. The click and the key-tap haptic both fire on touchDown in
/// GiellaKeyboardView, the only layer that knows when a finger lands. The bridge hears
/// about a key once its action is due, and for every letter that is on touchUp —
/// sounding the click from here is what made typing feel out of sync with the
/// haptic (#286). The haptics that remain here are the ones with no touchDown to
/// attach to: the cursor-movement tick, and the emoji toggle's own feedback.
final class DictusKeyboardBridge: NSObject,
    GiellaKeyboardViewDelegate,
    GiellaKeyboardViewKeyboardKeyDelegate {
    // MARK: - Dependencies

    /// Weak reference to the input view controller for textDocumentProxy access.
    /// WHY weak: The controller owns the bridge (strong ref). If the bridge held
    /// a strong ref back, it would create a retain cycle.
    weak var controller: UIInputViewController?

    /// Reference to the keyboard view for page state management (shift/symbols).
    /// WHY weak: The keyboard view is owned by the controller's view hierarchy.
    weak var keyboardView: GiellaKeyboardView?

    /// Reference to the suggestion state for triggering prediction updates.
    /// WHY weak: The controller owns SuggestionState. Bridge must not create a retain cycle.
    weak var suggestionState: SuggestionState?

    /// Callback to toggle emoji picker visibility. Set by KeyboardViewController.
    var onEmojiToggle: (() -> Void)?

    // MARK: - Shift state tracking

    /// Timestamp of the last shift tap, used to detect double-tap for caps lock.
    /// If two shift taps occur within 300ms, we activate caps lock.
    private var lastShiftTapTime: TimeInterval = 0

    /// Threshold for double-tap detection (300ms matches iOS native behavior).
    private static let doubleTapThreshold: TimeInterval = 0.3

    /// Tracks whether shift was activated by the user tapping shift (true)
    /// or by autocapitalization (false). This distinction matters because:
    /// - Manual shift: returns to .normal after ONE character typed (one-shot shift)
    /// - Autocap shift: also returns to .normal after one character, but updateCapitalization
    ///   may re-apply shift if conditions still hold (e.g., still at start of sentence)
    private var isManualShift = false

    /// Last character inserted by the keyboard, tracked locally to avoid IPC latency.
    /// Used by adaptive accent key (Phase 19 Plan 03) and as supplement to proxy reads.
    private(set) var lastInsertedCharacter: String?

    /// Second-to-last character, used for 2-char context (e.g., "qu" detection).
    /// When the user types "qu", lastInsertedCharacter="u" and secondToLastInsertedCharacter="q",
    /// allowing AccentedCharacters to detect the bigram and show apostrophe instead of u-grave.
    private var secondToLastInsertedCharacter: String?

    // MARK: - GiellaKeyboardViewDelegate

    func didTriggerKey(_ key: KeyDefinition) {
        // The first keystroke after a dictation ends its undo offer (#266). The
        // safety check would refuse anyway once the typed character lands, but the
        // proxy's view of the document can lag the keystroke by an event, and an
        // offer that is still on screen for that one event is an offer that can be
        // tapped. Ending it at the source does not depend on the host's timing.
        if Self.editsDocument(key) {
            KeyboardState.shared.invalidateDictationUndo(reason: "keystroke")
        }

        switch key.type {
        case .input(let character, let alternate):
            if alternate == "accent" {
                handleAdaptiveAccentKey()
            } else if character == KeyboardLayouts.emojiKeyGlyph {
                // Emoji button: identified by the emoji glyph on the key.
                // No alternate text so the key shows only the smiley icon.
                handleEmojiToggle()
            } else {
                handleInputKey(character)
            }

        case .backspace:
            handleBackspace()

        case .spacebar:
            handleSpace()

        case .returnkey:
            handleReturn()

        case .shift:
            handleShift()

        case .symbols:
            handleSymbolsToggle()

        case .shiftSymbols:
            handleShiftSymbolsToggle()

        case .comma:
            handleInputKey(",")

        case .fullStop:
            handleInputKey(".")

        case .tab:
            handleInputKey("\t")

        case .keyboard:
            // Globe/next keyboard button -- advance to next input method
            controller?.advanceToNextInputMode()

        case .keyboardMode, .splitKeyboard, .normalKeyboard,
             .sideKeyboardLeft, .sideKeyboardRight:
            // iPad keyboard mode keys -- not supported on iPhone, no-op.
            // The click still plays on touchDown, from KeySound.category(for:).
            break

        case .spacer, .caps:
            // Spacer is a layout element, caps is handled by double-tap shift
            break
        }
    }

    /// Whether triggering `key` changes the document, as opposed to changing only
    /// what the keyboard itself is showing.
    ///
    /// Used by the dictation undo offer (#266): shift, the symbol layers, the globe
    /// and the emoji key leave the field exactly as the dictation left it, so the
    /// offer survives them. Switching to the symbol layer to type a character does
    /// end the offer — on the character, not on the layer switch.
    ///
    /// The emoji key is an `.input` key carrying the smiley glyph rather than a
    /// type of its own; `didTriggerKey` tells the two apart the same way.
    private static func editsDocument(_ key: KeyDefinition) -> Bool {
        switch key.type {
        case .input(let character, _):
            return character != KeyboardLayouts.emojiKeyGlyph
        case .backspace, .spacebar, .returnkey, .comma, .fullStop, .tab:
            return true
        default:
            return false
        }
    }

    func didTriggerDoubleTap(forKey key: KeyDefinition) {
        switch key.type {
        case .shift:
            // Double-tap shift activates caps lock.
            // Haptic and click already fired in touchesBegan.
            keyboardView?.page = .capslock
            lastShiftTapTime = 0 // Reset to prevent triple-tap confusion
            isManualShift = false // Caps lock is its own mode, not "manual shift"

        default:
            // Other keys don't have double-tap behavior in our layout
            break
        }
    }

    func didSwipeKey(_ key: KeyDefinition) {
        // Swipe key inserts the alternate character (e.g., swipe down on "e" for accent)
        // For now, treat same as regular trigger -- Phase 19 will add accent handling
        didTriggerKey(key)
    }

    func didTriggerHoldKey(_ key: KeyDefinition) {
        // Held backspace does not pass through didTriggerKey, and it is the very
        // key someone reaches for when they want the dictation gone (#266).
        if Self.editsDocument(key) {
            KeyboardState.shared.invalidateDictationUndo(reason: "keystroke-hold")
        }

        switch key.type {
        case .backspace:
            handleWordDelete()
        default:
            break
        }
    }

    /// Perform `key`'s auto-repeat action and report whether a deletion was actually
    /// issued.
    ///
    /// WHY the keyboard view asks rather than just calling and assuming (#390): the
    /// repeat tick used to fire its haptic and its click unconditionally, so a repeat
    /// that had outlived its controller kept tapping the user's wrist while every
    /// deletion went nowhere. `controller` is weak and dies with the keyboard, which
    /// makes "is there still a document to delete into" a question this class can
    /// answer and the view cannot.
    ///
    /// WHY the answer is not simply "did the document change": a host may withhold
    /// `documentContextBeforeInput` -- a secure field reports none -- while still
    /// accepting the deletion, so gating the feedback on the context alone would
    /// silence a backspace that works, and #286 must not regress.
    func didTriggerRepeat(_ key: KeyDefinition, wordMode: Bool) -> KeyRepeatOutcome {
        guard let proxy = controller?.textDocumentProxy else { return .unavailable }
        guard !hasNothingToDelete(proxy) else { return .nothingToDelete }

        if wordMode {
            didTriggerHoldKey(key)
        } else {
            didTriggerKey(key)
        }
        return .deleted
    }

    /// Whether the held backspace provably has nothing left to delete.
    ///
    /// WHY three conditions rather than just the context (#419): **"nothing before the
    /// cursor" does not mean "nothing to delete"**. Select all three words of a field
    /// and the selection starts at offset 0, so the before-context is empty while a
    /// perfectly valid deletion is pending. A context-only rule shipped once and was
    /// reverted for exactly that case; `selectedText` (iOS 11+) is what tells the two
    /// apart, and it is why this predicate can exist at all.
    ///
    /// `hasText` comes from `UIKeyInput`, which `UITextDocumentProxy` inherits. It
    /// answers with a boolean rather than with content, so a host that withholds the
    /// context can still answer it -- which is what a secure field needs, since there
    /// an empty context must never be read as an empty document.
    ///
    /// **Not verified.** No case could be constructed in the simulator in which this
    /// extension serves a secure field: iOS declined to offer Dictus at all to a host
    /// app that merely had a secure field in its hierarchy. If a secure field did
    /// report `hasText == false` while holding text, the cost is a missing tap on a
    /// backspace that still works -- not a deletion that fails to happen.
    private func hasNothingToDelete(_ proxy: UITextDocumentProxy) -> Bool {
        guard !proxy.hasText else { return false }
        guard (proxy.selectedText ?? "").isEmpty else { return false }
        return (proxy.documentContextBeforeInput ?? "").isEmpty
    }

    func didMoveCursor(_ movement: Int) {
        // Moving the caret is what the undo check tests for, so drop the offer
        // here rather than wait for the host to report the selection change (#266).
        KeyboardState.shared.invalidateDictationUndo(reason: "cursor-moved")

        // Spacebar trackpad cursor movement
        controller?.textDocumentProxy.adjustTextPosition(byCharacterOffset: movement)
        HapticFeedback.cursorMoved()
    }

    // MARK: - GiellaKeyboardViewKeyboardKeyDelegate

    @objc func didTriggerKeyboardButton(sender: UIView, forEvent event: UIEvent) {
        // Globe key callback from GiellaKeyboardView's invisible overlay button.
        // handleInputModeList is Apple's dedicated API for the input-switch key: it
        // advances to the next keyboard on tap AND shows the keyboard picker menu on
        // long-press (advanceToNextInputMode only covers the tap). It requires the full
        // touch stream, hence .allTouchEvents on the button.
        controller?.handleInputModeList(from: sender, with: event)
    }

    // MARK: - Host Field Policy (#200)

    /// Re-reads the host field's input traits and updates the cached policy on
    /// SuggestionState. Called whenever the focused field can have changed:
    /// keyboard appearance, textDidChange/selectionDidChange, and before
    /// autocorrect-on-space.
    ///
    /// WHY cached on SuggestionState: updateAsync/updatePredictions run on a
    /// background queue and cannot read UITextDocumentProxy (main-thread only).
    func refreshHostPolicy() {
        guard let proxy = controller?.textDocumentProxy else { return }
        let policy = HostInputTraits.policy(for: proxy)
        guard policy != suggestionState?.hostPolicy else { return }

        #if DEBUG
        AutocorrectDebugLog.hostPolicy(
            autocorrectAllowed: policy.autocorrectAllowed,
            suggestionsAllowed: policy.suggestionsAllowed,
            reason: policy.reason
        )
        #endif

        suggestionState?.hostPolicy = policy
        if !policy.suggestionsAllowed {
            // Empty the bar immediately — stale suggestions from the previous
            // field must not survive into a no-suggestions field.
            suggestionState?.clear()
        }
    }

    // MARK: - Key Action Handlers

    /// Handle character input (letters, numbers, punctuation).
    /// Inserts the character, auto-unshifts after one letter, then rechecks
    /// autocapitalization (e.g., typing "." may prepare shift for next char).
    /// NOTE: Haptic and click fire in GiellaKeyboardView.touchesBegan() for ALL keys
    /// on touchDown, so neither is emitted here.
    private func handleInputKey(_ character: String) {
        // Clear rejected words when starting a new word
        if suggestionState?.currentWord.isEmpty == true {
            suggestionState?.rejectedWords.removeAll()
        }

        // Insert the character. When on shifted/capslock page, the key definition
        // already contains the uppercase character, so we insert as-is.
        controller?.textDocumentProxy.insertText(character)
        secondToLastInsertedCharacter = lastInsertedCharacter
        lastInsertedCharacter = character

        #if DEBUG
        // #530 probe: our own insert, measured immediately. If the mirror does not
        // grow by exactly this character, the divergence starts here.
        MirrorProbe.shared.record(.insert(character))
        MirrorProbe.shared.probe(
            event: "key-insert",
            mirror: controller?.textDocumentProxy.documentContextBeforeInput
        )
        #endif

        // Auto-unshift after one character (unless caps locked).
        // This matches iOS native behavior: shift is "one-shot" unless locked.
        if let page = keyboardView?.page, page == .shifted {
            keyboardView?.page = .normal
            isManualShift = false
        }

        // Recheck autocapitalization after the character was inserted.
        // Example: typing "." won't trigger autocap yet (need space after),
        // but typing after "Hello. " should capitalize.
        updateCapitalization()
        updateAccentKeyDisplay()

        // Trigger suggestion update after every character input.
        let context = controller?.textDocumentProxy.documentContextBeforeInput
        suggestionState?.updateAsync(context: context)
    }

    /// Handle backspace/delete key. Always deletes one character.
    /// Autocorrect undo is handled by tapping the suggestion bar, not backspace.
    private func handleBackspace() {
        controller?.textDocumentProxy.deleteBackward()
        secondToLastInsertedCharacter = nil
        lastInsertedCharacter = nil

        #if DEBUG
        // #530 probe: THE suspect event. The issue's hypothesis is that this
        // deleteBackward() is not reflected in the mirror before the next insert,
        // so the mirror keeps "ton" and the next keystroke appends "n" to it.
        // If that is right, `off` becomes +1 on this line or the one after it.
        MirrorProbe.shared.record(.deleteBackward)
        MirrorProbe.shared.probe(
            event: "key-delete",
            mirror: controller?.textDocumentProxy.documentContextBeforeInput
        )
        #endif

        // Check if the corrected word is still intact in the text after deletion.
        // Keep undo alive if either "correctedWord " or "correctedWord" (without space) is found.
        // This allows undo even after deleting just the trailing space.
        if let undo = suggestionState?.pendingUndo {
            let context = controller?.textDocumentProxy.documentContextBeforeInput ?? ""
            if !context.contains(undo.correctedWord) {
                suggestionState?.pendingUndo = nil
            }
        }

        updateCapitalization()
        updateAccentKeyDisplay()
        let context = controller?.textDocumentProxy.documentContextBeforeInput
        suggestionState?.updateAsync(context: context)
    }

    /// Delete one word backwards (used during accelerated backspace repeat).
    ///
    /// WHY word-level: After holding backspace for ~10 characters, users expect faster
    /// deletion. Switching to word-level matches iOS native behavior where long backspace
    /// hold starts eating whole words.
    ///
    /// The algorithm: trim trailing spaces, find the previous word boundary (last space),
    /// delete everything from cursor back to that boundary.
    private func handleWordDelete() {
        suggestionState?.pendingUndo = nil
        guard let proxy = controller?.textDocumentProxy,
              let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            // Fallback: single character delete if no text context
            controller?.textDocumentProxy.deleteBackward()
            #if DEBUG
            MirrorProbe.shared.record(.deleteBackward)
            MirrorProbe.shared.probe(
                event: "word-delete-fallback",
                mirror: controller?.textDocumentProxy.documentContextBeforeInput
            )
            #endif
            return
        }

        // Trim trailing spaces
        var trimmed = before
        var trailingSpaces = 0
        while trimmed.hasSuffix(" ") {
            trimmed = String(trimmed.dropLast())
            trailingSpaces += 1
        }

        // Find word boundary (last space in trimmed text)
        let charsInWord: Int
        if let lastSpace = trimmed.lastIndex(of: " ") {
            charsInWord = trimmed.distance(from: trimmed.index(after: lastSpace), to: trimmed.endIndex)
        } else {
            charsInWord = trimmed.count
        }

        // Delete trailing spaces + word (at least 1 character)
        let total = trailingSpaces + charsInWord
        for _ in 0..<max(1, total) {
            proxy.deleteBackward()
        }
        #if DEBUG
        MirrorProbe.shared.record(.replace(deleted: max(1, total), inserted: ""))
        MirrorProbe.shared.probe(
            event: "word-delete",
            mirror: proxy.documentContextBeforeInput
        )
        #endif
        secondToLastInsertedCharacter = nil
        lastInsertedCharacter = nil
        updateCapitalization()
        let context = controller?.textDocumentProxy.documentContextBeforeInput
        suggestionState?.updateAsync(context: context)
    }

    /// Handle spacebar press with autocorrect and auto-full-stop detection.
    ///
    /// Autocorrect flow: Before inserting the space, check if the current word is
    /// misspelled. If so, replace it with the correction and store undo state so
    /// backspace can restore the original word.
    ///
    /// WHY autocorrect-on-space (not on every keystroke): This matches iOS native
    /// behavior -- corrections appear only when the user finishes the word (space/return).
    /// Correcting mid-word would be disorienting as the text changes while typing.
    private func handleSpace() {
        secondToLastInsertedCharacter = lastInsertedCharacter

        // Next space after autocorrect = undo window closes
        suggestionState?.pendingUndo = nil

        // Read the current word directly from the text field (synchronous, main thread).
        // WHY not use state.currentWord: it's updated by an async background queue.
        // If the user types fast and hits space before the async update completes,
        // state.currentWord can be stale (missing last characters). Using the stale
        // count for deleteBackward would leave orphan characters (first-letter duplication).
        let freshWord: String = {
            guard let context = controller?.textDocumentProxy.documentContextBeforeInput,
                  !context.isEmpty,
                  let lastChar = context.last,
                  !lastChar.isWhitespace, !lastChar.isNewline else { return "" }
            var word = ""
            context.enumerateSubstrings(in: context.startIndex..., options: .byWords) { sub, _, _, _ in
                if let s = sub { word = s }
            }
            return word
        }()

        // Guard: never autocorrect tokens containing digits (#74).
        // WHY CharacterSet.decimalDigits: covers all Unicode digits (0-9 plus other scripts).
        // Tokens like "test123", "h2o", "3pm" should be inserted as-is.
        let containsDigit = freshWord.unicodeScalars.contains {
            CharacterSet.decimalDigits.contains($0)
        }
        if containsDigit {
            // Skip autocorrect — insert space normally
            controller?.textDocumentProxy.insertText(" ")
            lastInsertedCharacter = " "
            #if DEBUG
            MirrorProbe.shared.record(.insert(" "))
            MirrorProbe.shared.probe(
                event: "space-digit-skip",
                mirror: controller?.textDocumentProxy.documentContextBeforeInput
            )
            #endif
            suggestionState?.clear()
            suggestionState?.rejectedWords.removeAll()
            let ctx = controller?.textDocumentProxy.documentContextBeforeInput
            suggestionState?.updatePredictions(context: ctx)
            updateCapitalization()
            updateAccentKeyDisplay()
            return
        }

        // Autocorrect check before space insertion.
        // Only trigger if autocorrect is enabled, there's a current word, the word
        // was not previously rejected by the user, and the spell checker offers a
        // different correction.
        // Extract previous word for n-gram context boost
        let previousWord: String? = {
            guard let ctx = controller?.textDocumentProxy.documentContextBeforeInput else { return nil }
            var words: [String] = []
            ctx.enumerateSubstrings(in: ctx.startIndex..., options: .byWords) { sub, _, _, _ in
                if let s = sub { words.append(s) }
            }
            // Last word in context is freshWord; the one before is previousWord
            guard words.count >= 2 else { return nil }
            return words[words.count - 2]
        }()

        // Refresh the host-traits policy right before the apply decision (#200):
        // the proxy read is cheap and this is the freshest possible signal.
        refreshHostPolicy()

        // Sentence position for the proper-noun guard (#199): an unknown
        // capitalized word mid-sentence is preserved; at sentence start the
        // capitalization is just autocap, so corrections stay enabled there.
        let atSentenceStart: Bool = {
            guard let ctx = controller?.textDocumentProxy.documentContextBeforeInput else { return true }
            return ProperNounGuard.isAtSentenceStart(context: ctx, word: freshWord)
        }()

        // Whether the learning path below may record this word. Learning means
        // "the pipeline evaluated the word and chose not to correct it" — NOT
        // "the word reached the space key". Words typed where autocorrect never
        // ran (search/URL fields, #200) or whose replacement was aborted by the
        // boundary check (possibly phantom words, #191) must not be learned:
        // a learned word bypasses autocorrect everywhere afterwards, which is
        // how test typing in Safari's search bar broke "lai"/"Cest" in Messages.
        //
        // The user's own autocorrect switch counts as such a case (#287 decision 8).
        // With autocorrect off `spellCheck` never runs, so nothing vets the word:
        // "bonjuor" typed twice would clear the trie filter below and become
        // permanently immune. Reading only the host policy here — as this line did
        // until #287 — made the comment above untrue in exactly that configuration.
        var wordWasEvaluated: Bool = {
            guard let state = suggestionState else { return false }
            return state.autocorrectEnabled && state.hostPolicy.autocorrectAllowed
        }()

        if let state = suggestionState, state.autocorrectEnabled,
           state.hostPolicy.autocorrectAllowed,
           !freshWord.isEmpty,
           !state.rejectedWords.contains(freshWord.lowercased()),
           let result = state.performSpellCheck(
               freshWord,
               previousWord: previousWord,
               isAtSentenceStart: atSentenceStart
           ),
           result.correction.lowercased() != freshWord.lowercased() {
            // Boundary-safe replacement (#191): re-read the LIVE context and
            // verify it still ends with the word we plan to replace, with a
            // proper boundary before it. Under proxy desync (rapid delete/retype
            // producing phantom words like "quee"), the captured freshWord can
            // disagree with the document — a blind count-based delete would eat
            // the preceding space ("pense quee" -> "penseque"). On failure we
            // skip the correction and fall through to a normal space.
            let liveContext = controller?.textDocumentProxy.documentContextBeforeInput
            switch AutocorrectReplacement.check(context: liveContext, word: freshWord) {
            case .ok(let deleteCount):
                applyAutocorrect(
                    state: state,
                    freshWord: freshWord,
                    correction: result.correction,
                    previousWord: previousWord,
                    deleteCount: deleteCount
                )
                return

            case .failed(let reason):
                // Proxy desync detected — do NOT correct, do NOT delete.
                // Fall through to the normal space path below so the user
                // keeps their typed word and still gets a space. The word may
                // be a phantom ("quee") — don't learn it either.
                wordWasEvaluated = false
                #if DEBUG
                AutocorrectDebugLog.replacementAborted(
                    word: freshWord,
                    reason: reason,
                    contextTail: Self.contextTail(liveContext)
                )
                #endif
            }
        }

        // Repetition learning: the pipeline evaluated the word and did NOT
        // correct it (user typed it as-is). Track usage — at the repetition
        // threshold, learn it. Skipped when autocorrect never ran (see
        // wordWasEvaluated above): those words were not vetted by the pipeline.
        //
        // The dictionary check is the gate this site was missing (#287 decision 2).
        // Passive typing states nothing about intent, so the only word worth
        // recording here is one the base dictionary does not have: a word it does
        // have is never autocorrected anyway, so an entry for it protects nothing
        // while #288 would go on to feed it into speech recognition. Six ordinary
        // French phrases used to leave 22 entries behind, 20 of them trie words.
        //
        // The check belongs here rather than inside UserDictionary because the undo
        // site must NOT be subject to it — see `UserDictionary.recordUsage`.
        if let state = suggestionState, !freshWord.isEmpty, wordWasEvaluated,
           state.isUnknownToDictionary(freshWord) {
            UserDictionary.shared.recordUsage(freshWord)
        }

        // Normal space handling with double-space period detection
        if !handleAutoFullStop() {
            controller?.textDocumentProxy.insertText(" ")
            lastInsertedCharacter = " "
            #if DEBUG
            MirrorProbe.shared.record(.insert(" "))
            #endif
        } else {
            // Auto-full-stop changed the text (". " instead of "  ").
            // Invalidate any pending autocorrect undo — the text no longer matches
            // what the undo expects, so backspace should not try to restore.
            suggestionState?.pendingUndo = nil
            lastInsertedCharacter = " "
        }
        #if DEBUG
        // #530 criterion 1 asks for a reading at every spacebar press, including the
        // ones that do not correct anything. `handleAutoFullStop` records its own
        // replacement, so by here the prediction is up to date on both branches.
        MirrorProbe.shared.probe(
            event: "space",
            mirror: controller?.textDocumentProxy.documentContextBeforeInput
        )
        #endif

        // After space, clear current word and trigger n-gram predictions.
        // WHY updatePredictions instead of updateAsync: After finishing a word,
        // the user wants to see predicted next words (n-gram), not completions
        // for a partial word (which doesn't exist yet after a space).
        // Also clear rejected words -- the user has moved on to a new word.
        suggestionState?.clear()
        suggestionState?.rejectedWords.removeAll()
        let context = controller?.textDocumentProxy.documentContextBeforeInput
        suggestionState?.updatePredictions(context: context)

        // After space (or period+space), recheck autocap.
        updateCapitalization()
        updateAccentKeyDisplay()
    }

    /// Handle return/newline key.
    /// After inserting newline, recheck autocapitalization -- many apps use
    /// .sentences autocap which should capitalize after a newline.
    private func handleReturn() {
        suggestionState?.pendingUndo = nil
        controller?.textDocumentProxy.insertText("\n")
        #if DEBUG
        MirrorProbe.shared.record(.insert("\n"))
        MirrorProbe.shared.probe(
            event: "return",
            mirror: controller?.textDocumentProxy.documentContextBeforeInput
        )
        #endif
        secondToLastInsertedCharacter = lastInsertedCharacter
        lastInsertedCharacter = "\n"
        suggestionState?.clear()
        updateCapitalization()
        updateAccentKeyDisplay()
    }

    /// Insert a predicted word and trigger chained prediction.
    /// Called from KeyboardRootView when user taps a prediction in the suggestion bar.
    ///
    /// WHY separate from handleSpace: prediction tap must bypass autocorrect.
    /// The predicted word is already correct (it comes from the n-gram model).
    /// Going through handleSpace() would trigger autocorrect which might
    /// "correct" a perfectly valid prediction.
    func handlePredictionTap(word: String) {
        let proxy = controller?.textDocumentProxy
        proxy?.insertText(word + " ")
        lastInsertedCharacter = " "
        #if DEBUG
        MirrorProbe.shared.record(.insert(word + " "))
        MirrorProbe.shared.probe(event: "prediction-tap", mirror: proxy?.documentContextBeforeInput)
        #endif
        secondToLastInsertedCharacter = nil

        // Chain predictions: query n-gram engine for what comes after this word
        suggestionState?.pendingUndo = nil
        let context = proxy?.documentContextBeforeInput
        suggestionState?.updatePredictions(context: context)

        updateCapitalization()
        updateAccentKeyDisplay()
    }

    /// Handle the adaptive accent key tap.
    /// After a vowel: replaces the vowel with its most common French accent.
    /// After a consonant or other character: inserts an apostrophe.
    ///
    /// WHY replace instead of appending: French accented characters are single Unicode
    /// code points (e.g., e-acute = U+00E9), not base + combining mark. Replacing the
    /// previous character with the accented version is how iOS native French keyboards
    /// handle accent insertion as well.
    private func handleAdaptiveAccentKey() {
        let label = FrenchAdaptiveKey.label(
            afterTyping: lastInsertedCharacter,
            precedingChar: secondToLastInsertedCharacter
        )

        if FrenchAdaptiveKey.shouldReplace(afterTyping: lastInsertedCharacter, precedingChar: secondToLastInsertedCharacter) {
            // Replace previous vowel with accented version
            controller?.textDocumentProxy.deleteBackward()
            controller?.textDocumentProxy.insertText(label)
            #if DEBUG
            MirrorProbe.shared.record(.replace(deleted: 1, inserted: label))
            #endif
        } else {
            // Insert apostrophe (or apostrophe after "qu" bigram)
            controller?.textDocumentProxy.insertText(label)
            #if DEBUG
            MirrorProbe.shared.record(.insert(label))
            #endif
        }
        #if DEBUG
        MirrorProbe.shared.probe(
            event: "accent-key",
            mirror: controller?.textDocumentProxy.documentContextBeforeInput
        )
        #endif

        secondToLastInsertedCharacter = lastInsertedCharacter
        lastInsertedCharacter = label

        // Auto-unshift after accent insertion (same as regular character)
        if let page = keyboardView?.page, page == .shifted {
            keyboardView?.page = .normal
            isManualShift = false
        }

        updateCapitalization()
        updateAccentKeyDisplay()
        let context = controller?.textDocumentProxy.documentContextBeforeInput
        suggestionState?.updateAsync(context: context)
    }

    /// Handle emoji button tap: triggers the emoji picker toggle.
    private func handleEmojiToggle() {
        HapticFeedback.keyTapped()
        onEmojiToggle?()
    }

    /// Update the accent key's displayed label based on lastInsertedCharacter.
    /// Called after every keystroke so the accent key always shows the correct symbol:
    /// an accent character after a vowel, or apostrophe otherwise.
    private func updateAccentKeyDisplay() {
        let label = FrenchAdaptiveKey.label(
            afterTyping: lastInsertedCharacter,
            precedingChar: secondToLastInsertedCharacter
        )
        keyboardView?.updateAccentKeyLabel(label)
    }

    /// Handle single shift tap: cycle through normal -> shifted -> normal.
    /// Double-tap within 300ms activates caps lock.
    ///
    /// WHY we handle double-tap here AND in didTriggerDoubleTap:
    /// The GiellaKeyboardView fires didTriggerDoubleTap for keys with supportsDoubleTap,
    /// but we also detect it here as a fallback because the timing can differ between
    /// the gesture recognizer and our manual tracking. Both paths lead to .capslock.
    private func handleShift() {
        guard let kbView = keyboardView else { return }

        let now = Date.timeIntervalSinceReferenceDate

        // Check if this is a double-tap (within 300ms of last shift tap)
        if (now - lastShiftTapTime) < Self.doubleTapThreshold {
            // Double-tap -> caps lock
            kbView.page = .capslock
            lastShiftTapTime = 0
            isManualShift = false
            return
        }

        lastShiftTapTime = now

        // Single tap: toggle between normal and shifted
        switch kbView.page {
        case .normal:
            kbView.page = .shifted
            isManualShift = true
        case .shifted:
            kbView.page = .normal
            isManualShift = false
        case .capslock:
            kbView.page = .normal
            isManualShift = false
        default:
            // On symbols pages, shift doesn't do anything
            break
        }
    }

    /// Handle 123/ABC layer switch.
    /// Toggles between letter pages (normal/shifted/capslock) and symbols1.
    private func handleSymbolsToggle() {
        guard let kbView = keyboardView else { return }

        switch kbView.page {
        case .normal, .shifted, .capslock:
            kbView.page = .symbols1
        case .symbols1, .symbols2:
            kbView.page = .normal
        }
    }

    /// Handle #+=/123 toggle on symbols pages.
    /// Toggles between symbols1 and symbols2.
    private func handleShiftSymbolsToggle() {
        guard let kbView = keyboardView else { return }

        switch kbView.page {
        case .symbols1:
            kbView.page = .symbols2
        case .symbols2:
            kbView.page = .symbols1
        default:
            break
        }
    }

    /// Applies a validated autocorrection: deletes the typed word, inserts the
    /// correction + trailing space, stores undo state and refreshes predictions.
    /// Only called after AutocorrectReplacement.check confirmed the live context
    /// ends with `freshWord` (#191) — `deleteCount` comes from that check.
    ///
    /// That check can be satisfied by a proxy that is lying, which is what #530
    /// measured and what destroys the user's text here. The delete below is still
    /// the blind loop, deliberately: #530's diagnostic round must not perturb what
    /// it measures. See `MirrorProbe` and `WordBoundaryDelete` for what has already
    /// been ruled out.
    private func applyAutocorrect(
        state: SuggestionState,
        freshWord: String,
        correction: String,
        previousWord: String?,
        deleteCount: Int
    ) {
        let proxy = controller?.textDocumentProxy

        #if DEBUG
        AutocorrectDebugLog.applyBefore(
            word: freshWord,
            correction: correction,
            prevWord: previousWord,
            contextTail: Self.contextTail(proxy?.documentContextBeforeInput)
        )
        #endif

        for _ in 0..<deleteCount {
            proxy?.deleteBackward()
        }
        #if DEBUG
        MirrorProbe.shared.record(.replace(deleted: deleteCount, inserted: ""))
        MirrorProbe.shared.probe(
            event: "autocorrect-deleted",
            mirror: proxy?.documentContextBeforeInput
        )
        AutocorrectDebugLog.applyAfterDelete(
            contextTail: Self.contextTail(proxy?.documentContextBeforeInput)
        )
        #endif

        proxy?.insertText(correction)
        proxy?.insertText(" ")
        lastInsertedCharacter = " "

        #if DEBUG
        MirrorProbe.shared.record(.insert(correction + " "))
        MirrorProbe.shared.probe(
            event: "autocorrect-applied",
            mirror: proxy?.documentContextBeforeInput
        )
        AutocorrectDebugLog.applyAfterInsert(
            contextTail: Self.contextTail(proxy?.documentContextBeforeInput)
        )
        AutocorrectDebugLog.autocorrectApplied(
            original: freshWord,
            corrected: correction,
            prevWord: previousWord
        )
        #endif

        // Store undo state — user can tap suggestion bar to revert
        state.pendingUndo = AutocorrectState(
            originalWord: freshWord,
            correctedWord: correction,
            insertedSpace: true
        )
        // No haptic on autocorrect (#224): the spacebar touchDown tick already fired
        // ~100ms earlier, and stacking a second haptic reads as a keyboard glitch.
        // Feedback is visual instead — the suggestion bar pulses its undo chip
        // (SuggestionBarView). HapticFeedback.autocorrectApplied() is kept in
        // DictusCore so re-adding is a one-line change if dogfooding shows
        // silent correction hurts awareness.
        // Trigger n-gram predictions after autocorrection too.
        // The corrected word + space is now in the proxy — predict what comes next.
        state.clear()
        state.rejectedWords.removeAll()
        let correctedContext = controller?.textDocumentProxy.documentContextBeforeInput
        state.updatePredictions(context: correctedContext)
        updateCapitalization()
        updateAccentKeyDisplay()
    }

    /// Last ~30 characters of a context string, for DEBUG replacement logs.
    /// Keeps log lines short while showing the text around the replacement site.
    static func contextTail(_ context: String?) -> String {
        guard let context = context else { return "<nil>" }
        return String(context.suffix(30))
    }

    // MARK: - Auto-full-stop

    /// Replaces double-space with ". " (period + space).
    /// This is the standard iOS auto-punctuation behavior:
    /// If the user types two spaces in a row after a word character,
    /// replace "  " with ". " to end the sentence.
    ///
    /// Returns `true` if the substitution was performed (". " was inserted),
    /// `false` if no substitution happened (caller should insert a normal space).
    ///
    /// WHY called BEFORE inserting the space: We need to check what's already
    /// in the text buffer. The caller checks the return value to decide whether
    /// to insert an additional space.
    @discardableResult
    private func handleAutoFullStop() -> Bool {
        guard let proxy = controller?.textDocumentProxy,
              let text = proxy.documentContextBeforeInput,
              text.count >= 2 else { return false }

        // Called BEFORE inserting second space. Buffer has: [char][space]
        // Check: last char is space, char before space is not space and not period
        guard text.hasSuffix(" ") else { return false }
        let beforeSpace = text[text.index(text.endIndex, offsetBy: -2)]
        guard beforeSpace != " " && beforeSpace != "." else { return false }

        // Replace trailing space with ". "
        proxy.deleteBackward()
        proxy.insertText(". ")
        #if DEBUG
        MirrorProbe.shared.record(.replace(deleted: 1, inserted: ". "))
        #endif
        return true
    }

    // MARK: - Autocapitalization

    /// Checks the textDocumentProxy's autocapitalization type and sets the keyboard
    /// page to .shifted when appropriate.
    ///
    /// This implements the standard iOS autocapitalization behavior:
    /// - `.sentences`: Capitalize at start of text field and after sentence-ending
    ///   punctuation (.!?) followed by a space or newline.
    /// - `.words`: Capitalize at start of text field and after each space.
    /// - `.allCharacters`: Always caps lock.
    /// - `.none`: Never autocapitalize.
    ///
    /// WHY guard against capslock: If the user has manually activated caps lock
    /// (via double-tap shift), autocapitalization must not interfere. The user
    /// explicitly wants ALL CAPS and tapping shift will deactivate it.
    func updateCapitalization() {
        guard let proxy = controller?.textDocumentProxy else { return }
        guard let kbView = keyboardView else { return }

        // Don't override user's caps lock
        guard kbView.page != .capslock else { return }
        // Only autocap on letter pages (not symbols)
        guard kbView.page == .normal || kbView.page == .shifted else { return }

        let autocapType = proxy.autocapitalizationType ?? .sentences

        switch autocapType {
        case .sentences:
            let beforeInput = proxy.documentContextBeforeInput ?? ""
            if beforeInput.isEmpty {
                // Beginning of text field -- capitalize first letter
                kbView.page = .shifted
                isManualShift = false
            } else {
                let trimmed = beforeInput.trimmingCharacters(in: .whitespaces)
                let lastChar = trimmed.last
                // Force unwrap: `&&` short-circuits, so the unwrap is only
                // evaluated once the `lastChar != nil` conjunct to its left has
                // already succeeded.
                // swiftlint:disable:next force_unwrapping
                let endsWithSentencePunctuation = lastChar != nil && ".!?".contains(lastChar!)
                let lastInputChar = beforeInput.last

                if endsWithSentencePunctuation && (lastInputChar == " " || lastInputChar == "\n") {
                    // After sentence-ending punctuation + space/newline -> capitalize
                    kbView.page = .shifted
                    isManualShift = false
                } else if lastInputChar == "\n" {
                    // After a newline (return key) -> capitalize for new paragraph
                    kbView.page = .shifted
                    isManualShift = false
                } else if kbView.page == .shifted && !isManualShift {
                    // Was shifted from autocap, now typing regular text -> return to normal
                    kbView.page = .normal
                }
            }

        case .words:
            let beforeInput = proxy.documentContextBeforeInput ?? ""
            if beforeInput.isEmpty || beforeInput.last == " " || beforeInput.last == "\n" {
                kbView.page = .shifted
                isManualShift = false
            } else if kbView.page == .shifted && !isManualShift {
                kbView.page = .normal
            }

        case .allCharacters:
            kbView.page = .capslock

        default: // .none
            break
        }
    }
}
