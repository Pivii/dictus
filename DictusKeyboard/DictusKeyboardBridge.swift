// DictusKeyboard/DictusKeyboardBridge.swift
// Delegate bridge from giellakbd-ios GiellaKeyboardView key events to Dictus text actions.
// Created for Phase 18 Plan 02 -- wires the vendored UICollectionView keyboard
// to textDocumentProxy operations with haptic feedback and 3-category key sounds.

import UIKit
import AudioToolbox
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
/// - Plays haptic feedback via DictusCore's HapticFeedback
/// - Plays 3-category key sounds via AudioServicesPlaySystemSound
/// - Manages shift/capslock page state on the keyboard view
/// - Handles auto-full-stop (double-space -> period)
final class DictusKeyboardBridge: NSObject,
    GiellaKeyboardViewDelegate,
    GiellaKeyboardViewKeyboardKeyDelegate
{
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
        switch key.type {
        case .input(let character, let alternate):
            if alternate == "accent" {
                handleAdaptiveAccentKey()
            } else if character == "\u{1F600}" {
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
            AudioServicesPlaySystemSound(KeySound.modifier)
            controller?.advanceToNextInputMode()

        case .keyboardMode, .splitKeyboard, .normalKeyboard,
             .sideKeyboardLeft, .sideKeyboardRight:
            // iPad keyboard mode keys -- not supported on iPhone, no-op
            AudioServicesPlaySystemSound(KeySound.modifier)

        case .spacer, .caps:
            // Spacer is a layout element, caps is handled by double-tap shift
            break
        }
    }

    func didTriggerDoubleTap(forKey key: KeyDefinition) {
        switch key.type {
        case .shift:
            // Double-tap shift activates caps lock
            // Haptic already fired in touchesBegan
            AudioServicesPlaySystemSound(KeySound.modifier)
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
        switch key.type {
        case .backspace:
            handleWordDelete()
        default:
            break
        }
    }

    func didMoveCursor(_ movement: Int) {
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
    /// Inserts the character, plays letter sound, auto-unshifts after one letter,
    /// then rechecks autocapitalization (e.g., typing "." may prepare shift for next char).
    /// NOTE: Haptic fires in GiellaKeyboardView.touchesBegan() for ALL keys on touchDown.
    private func handleInputKey(_ character: String) {
        // Clear rejected words when starting a new word
        if suggestionState?.currentWord.isEmpty == true {
            suggestionState?.rejectedWords.removeAll()
        }

        AudioServicesPlaySystemSound(KeySound.letter)

        // Insert the character. When on shifted/capslock page, the key definition
        // already contains the uppercase character, so we insert as-is.
        controller?.textDocumentProxy.insertText(character)
        secondToLastInsertedCharacter = lastInsertedCharacter
        lastInsertedCharacter = character

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
        AudioServicesPlaySystemSound(KeySound.delete)

        controller?.textDocumentProxy.deleteBackward()
        secondToLastInsertedCharacter = nil
        lastInsertedCharacter = nil

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
        AudioServicesPlaySystemSound(KeySound.delete)
        suggestionState?.pendingUndo = nil
        guard let proxy = controller?.textDocumentProxy,
              let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            // Fallback: single character delete if no text context
            controller?.textDocumentProxy.deleteBackward()
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
        AudioServicesPlaySystemSound(KeySound.modifier)
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
            let proxy = controller?.textDocumentProxy

            // Boundary-safe replacement (#191): re-read the LIVE context and
            // verify it still ends with the word we plan to replace, with a
            // proper boundary before it. Under proxy desync (rapid delete/retype
            // producing phantom words like "quee"), the captured freshWord can
            // disagree with the document — a blind count-based delete would eat
            // the preceding space ("pense quee" -> "penseque"). On failure we
            // skip the correction and fall through to a normal space.
            let liveContext = proxy?.documentContextBeforeInput
            switch AutocorrectReplacement.check(context: liveContext, word: freshWord) {
            case .ok(let deleteCount):
                #if DEBUG
                AutocorrectDebugLog.applyBefore(
                    word: freshWord,
                    correction: result.correction,
                    prevWord: previousWord,
                    contextTail: Self.contextTail(liveContext)
                )
                #endif

                for _ in 0..<deleteCount {
                    proxy?.deleteBackward()
                }
                #if DEBUG
                AutocorrectDebugLog.applyAfterDelete(
                    contextTail: Self.contextTail(proxy?.documentContextBeforeInput)
                )
                #endif

                proxy?.insertText(result.correction)
                proxy?.insertText(" ")
                lastInsertedCharacter = " "

                #if DEBUG
                AutocorrectDebugLog.applyAfterInsert(
                    contextTail: Self.contextTail(proxy?.documentContextBeforeInput)
                )
                AutocorrectDebugLog.autocorrectApplied(
                    original: freshWord,
                    corrected: result.correction,
                    prevWord: previousWord
                )
                #endif

                // Store undo state — user can tap suggestion bar to revert
                state.pendingUndo = AutocorrectState(
                    originalWord: freshWord,
                    correctedWord: result.correction,
                    insertedSpace: true
                )
                HapticFeedback.autocorrectApplied()
                // Trigger n-gram predictions after autocorrection too.
                // The corrected word + space is now in the proxy — predict what comes next.
                state.clear()
                state.rejectedWords.removeAll()
                let correctedContext = controller?.textDocumentProxy.documentContextBeforeInput
                state.updatePredictions(context: correctedContext)
                updateCapitalization()
                updateAccentKeyDisplay()
                return

            case .failed(let reason):
                // Proxy desync detected — do NOT correct, do NOT delete.
                // Fall through to the normal space path below so the user
                // keeps their typed word and still gets a space.
                #if DEBUG
                AutocorrectDebugLog.replacementAborted(
                    word: freshWord,
                    reason: reason,
                    contextTail: Self.contextTail(liveContext)
                )
                #endif
            }
        }

        // Repetition learning: word was NOT corrected (user typed it as-is).
        // Track usage — after 2 occurrences of an unknown word, learn it.
        if let state = suggestionState, !freshWord.isEmpty {
            let word = freshWord
            if UserDictionary.shared.recordUsage(word) {
                // Word just crossed the learning threshold — notify prediction engine
                state.learnWord(word)
            }
        }

        // Normal space handling with double-space period detection
        if !handleAutoFullStop() {
            controller?.textDocumentProxy.insertText(" ")
            lastInsertedCharacter = " "
        } else {
            // Auto-full-stop changed the text (". " instead of "  ").
            // Invalidate any pending autocorrect undo — the text no longer matches
            // what the undo expects, so backspace should not try to restore.
            suggestionState?.pendingUndo = nil
            lastInsertedCharacter = " "
        }

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
        AudioServicesPlaySystemSound(KeySound.modifier)
        suggestionState?.pendingUndo = nil
        controller?.textDocumentProxy.insertText("\n")
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
        AudioServicesPlaySystemSound(KeySound.letter)

        let label = FrenchAdaptiveKey.label(
            afterTyping: lastInsertedCharacter,
            precedingChar: secondToLastInsertedCharacter
        )

        if FrenchAdaptiveKey.shouldReplace(afterTyping: lastInsertedCharacter, precedingChar: secondToLastInsertedCharacter) {
            // Replace previous vowel with accented version
            controller?.textDocumentProxy.deleteBackward()
            controller?.textDocumentProxy.insertText(label)
        } else {
            // Insert apostrophe (or apostrophe after "qu" bigram)
            controller?.textDocumentProxy.insertText(label)
        }

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
        AudioServicesPlaySystemSound(KeySound.modifier)
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
        AudioServicesPlaySystemSound(KeySound.modifier)

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
        AudioServicesPlaySystemSound(KeySound.modifier)

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
        AudioServicesPlaySystemSound(KeySound.modifier)

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
