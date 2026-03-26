// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import Combine
import AudioToolbox
import DictusCore

/// Bridge between DictusCore's DefaultKeyboardLayer and DictusKeyboard's KeyboardLayerType.
extension DefaultKeyboardLayer {
    var asLayerType: KeyboardLayerType {
        switch self {
        case .letters: return .letters
        case .numbers: return .numbers
        }
    }
}

/// Root SwiftUI view for the keyboard extension.
/// Phase 15.5 layout: ToolbarView + (KeyboardUIView with popup overlays OR RecordingOverlay).
///
/// WHY conditional rendering instead of overlay:
/// When recording, the keyboard letters must be completely replaced by the recording UI
/// to prevent accidental key presses. SwiftUI's conditional rendering (`if/else`) fully
/// removes the inactive view from the hierarchy, freeing its memory and preventing
/// ghost touches. An overlay or ZStack would keep both views alive.
///
/// WHY keyboard logic lives here (not in a separate SwiftUI view):
/// KeyboardView.swift previously held all keyboard logic (layer state, character insertion,
/// autocorrect, etc.) and rendered SwiftUI key views. With the UIKit migration (Phase 15.5),
/// key rendering moved to KeyboardUIView (UIViewRepresentable). The logic that wires
/// keyboard actions to the text document proxy stays in SwiftUI, consolidated here to
/// avoid an unnecessary intermediate view.
struct KeyboardRootView: View {
    let controller: UIInputViewController
    let controllerID: String
    /// Bridge from UIKit touch events to SwiftUI popup overlays.
    /// Created in KeyboardViewController and shared with the UIKit KeyboardContainerView.
    /// WHY @ObservedObject (not @StateObject): The instance is owned by KeyboardViewController,
    /// not by this SwiftUI view. @ObservedObject observes without taking ownership.
    @ObservedObject var touchState: KeyboardTouchState
    @ObservedObject private var state = KeyboardState.shared
    @ObservedObject private var waveformDriver = KeyboardWaveformDriver.shared
    @State private var instanceID = String(UUID().uuidString.prefix(8))
    /// Observable state for the suggestion bar: holds current suggestions, mode, and autocorrect undo.
    /// WHY @StateObject: SuggestionState is an ObservableObject that must survive view re-renders.
    /// @StateObject ensures a single instance is created and owned by this view.
    @StateObject private var suggestionState = SuggestionState()
    @State private var isEmojiMode = false

    // MARK: - Keyboard layer and input state (migrated from KeyboardView)

    /// Which keyboard layer is currently displayed (letters, numbers, symbols, emoji).
    @State private var currentLayer: KeyboardLayerType = .letters
    /// Current shift state: off, shifted (one character), or caps locked.
    @State private var shiftState: ShiftState = .off
    /// Tracks the last typed character for the adaptive accent key.
    /// After typing a vowel (e, a, u, i, o), the adaptive key shows the most
    /// common accent for that vowel. Reset on space, delete, return, or layer switch.
    @State private var lastTypedChar: String? = nil
    /// Remembers which layer to return to when dismissing the emoji picker.
    @State private var previousLayer: KeyboardLayerType? = nil

    /// Whether shift is active (shifted or caps locked).
    private var isShifted: Bool {
        shiftState == .shifted || shiftState == .capsLocked
    }

    /// Default keyboard layer read from App Group on each appearance.
    /// Controls which layer (letters or numbers) the keyboard opens on.
    ///
    /// WHY initialized from UserDefaults (not just .letters):
    /// In SwiftUI, child .onAppear fires BEFORE parent .onAppear. If we default
    /// to .letters here and only read UserDefaults in .onAppear, KeyboardView
    /// would always see .letters on first render -- even if the user chose 123.
    /// Reading the stored value at @State init time ensures the correct layer
    /// is available when KeyboardView first renders.
    @State private var defaultLayer: KeyboardLayerType = {
        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()
        return DefaultKeyboardLayer.active.asLayerType
    }()

    /// WHY @Environment here: openURL is the SwiftUI way to open URLs.
    /// Keyboard extensions cannot access UIApplication.shared, but SwiftUI's
    /// openURL environment action works because it goes through the responder
    /// chain. We capture it here and inject it into KeyboardState via .onAppear.
    @Environment(\.openURL) private var openURL

    // MARK: - Layout dimensions

    /// Height of just the 4-row keyboard area (without toolbar).
    private var keyboardHeight: CGFloat {
        let rows: CGFloat = 4
        // With zero-spacing layout, each key's frame includes rowSpacing.
        // Total = rows * (keyHeight + rowSpacing).
        let standardHeight = rows * (KeyMetrics.keyHeight + KeyMetrics.rowSpacing)

        if currentLayer == .emoji {
            // Emoji picker takes full height: toolbar (48pt) + keyboard + bottom spacer (8pt)
            // are hidden by the parent, so we expand to fill that space.
            return standardHeight + 48 + 8
        }
        return standardHeight
    }

    /// Toolbar height -- must match ToolbarView's frame height (52pt: 48pt content + 4pt top padding).
    private let toolbarHeight: CGFloat = 52

    /// Total content height (toolbar + keyboard). RecordingOverlay uses this
    /// to cover the full area, preventing layout shift when switching to recording.
    private var totalContentHeight: CGFloat {
        toolbarHeight + keyboardHeight
    }

    /// Whether the recording overlay should be visible.
    /// Extracted as a computed property for clear animation binding.
    private var showsOverlay: Bool {
        let isActiveStatus = state.dictationStatus == .requested
            || state.dictationStatus == .recording
            || state.dictationStatus == .transcribing
        guard isActiveStatus else { return false }

        // Normal path: this controller is the registered active one
        if state.activeControllerID == controllerID && state.isKeyboardVisible {
            return true
        }

        // Fallback: active recording but no controller registered yet.
        // During cold start app transitions, iOS can rapidly create/destroy
        // keyboard controllers. viewWillAppear may not have fired on the
        // current controller, leaving activeControllerID == nil.
        // Show overlay anyway -- only one controller is visible on screen.
        if state.activeControllerID == nil {
            return true
        }

        return false
    }

    // MARK: - Keyboard row data (migrated from KeyboardView)

    /// Returns the key definitions for the current layer, filtering out mic keys.
    private var currentRows: [[KeyDefinition]] {
        switch currentLayer {
        case .letters:
            // Use dynamic layout (AZERTY or QWERTY) based on App Group preference.
            // Filter out .mic keys from every row -- the mic button now lives in the
            // toolbar above the keyboard (Plan 03-02). Filtering all rows (not just row 4)
            // is a safety measure in case layouts are restructured in the future.
            return KeyboardLayout.currentLettersRows().map { row in
                row.filter { $0.type != .mic }
            }
        case .numbers: return KeyboardLayout.numbersRows
        case .symbols: return KeyboardLayout.symbolsRows
        case .emoji: return [] // Not used -- emoji picker replaces the keyboard rows
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Conditional: recording overlay (full area) OR toolbar + keyboard
            if showsOverlay {
                RecordingOverlay(
                    dictationStatus: state.dictationStatus,
                    waveformEnergy: state.waveformEnergy,
                    elapsedSeconds: state.recordingElapsed,
                    waveformDriver: waveformDriver,
                    onCancel: { state.requestCancel() },
                    onStop: { state.requestStop() }
                )
                .frame(height: totalContentHeight)
            } else {
                // Single keyboard layout -- no more mode switching.
                // The only variable is which layer opens first (letters vs numbers),
                // controlled by the user's DefaultKeyboardLayer preference.

                // Hide toolbar in emoji mode to give full height to emoji picker
                if !isEmojiMode {
                    ToolbarView(
                        hasFullAccess: controller.hasFullAccess,
                        dictationStatus: state.dictationStatus,
                        onMicTap: { state.startRecording() },
                        suggestions: suggestionState.suggestions,
                        suggestionMode: suggestionState.mode,
                        onSuggestionTap: { index in
                            handleSuggestionTap(index: index)
                        }
                    )
                }

                // Emoji picker or UIKit keyboard with popup overlays
                if currentLayer == .emoji {
                    EmojiPickerView(
                        onEmojiInsert: { emoji in
                            controller.textDocumentProxy.insertText(emoji)
                        },
                        onDelete: {
                            controller.textDocumentProxy.deleteBackward()
                        },
                        onDismiss: {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(KeySound.modifier)
                            currentLayer = previousLayer ?? .letters
                            previousLayer = nil
                            isEmojiMode = false
                        }
                    )
                } else {
                    ZStack(alignment: .top) {
                        // Transparent spacer — the UIKit KeyboardContainerView sits
                        // BEHIND the hosting view in the kbInputView hierarchy.
                        // allowsHitTesting(false) makes SwiftUI return nil for this area,
                        // so UIKit's hitTest chain falls through to the container behind.
                        Color.clear
                            .frame(height: keyboardHeight)
                            .allowsHitTesting(false)

                        // Trackpad overlay stays inside ZStack (fills keyboard area)
                        if touchState.isTrackpadActive {
                            Color(.systemBackground).opacity(0.6)
                                .cornerRadius(8)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    // Popup overlays outside ZStack frame via .overlay -- won't clip on first row
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            // Key popup overlay (SwiftUI, reads from touchState)
                            if let label = touchState.pressedKeyLabel, !touchState.showingAccents {
                                KeyPopup(label: label)
                                    .position(x: touchState.pressedKeyFrame.midX,
                                              y: touchState.pressedKeyFrame.minY - 25)
                                    .allowsHitTesting(false)
                            }

                            // Accent popup overlay with edge clamping
                            if touchState.showingAccents {
                                let accentCount = CGFloat(touchState.accentOptions.count)
                                let totalWidth = accentCount * 36
                                let halfWidth = totalWidth / 2
                                let kbWidth = touchState.keyboardWidth
                                let rawX = touchState.accentKeyFrame.midX
                                let clampedX = max(halfWidth, min(rawX, kbWidth - halfWidth))

                                AccentPopup(
                                    accents: touchState.accentOptions,
                                    selectedIndex: touchState.selectedAccentIndex
                                )
                                .position(x: clampedX,
                                          y: touchState.accentKeyFrame.minY - 25)
                                .allowsHitTesting(false)
                            }
                        }
                        .frame(width: touchState.keyboardWidth > 0 ? touchState.keyboardWidth : nil,
                               height: keyboardHeight)
                    }
                }

                if !isEmojiMode {
                    Spacer().frame(height: 8)
                }
            }
        }
        // WHY .clear: The UIInputView with .keyboard style provides the
        // native blurred keyboard background. Any opaque color here would
        // hide that native styling and look wrong (e.g., pure white in light
        // mode instead of the native grayish tint). Transparent lets the
        // system keyboard chrome show through correctly.
        .background(Color.clear)
        .onChange(of: showsOverlay) { _, isShowing in
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "showsOverlayChanged",
                details: "isShowing=\(isShowing) status=\(state.dictationStatus.rawValue) visible=\(state.isKeyboardVisible) owner=\(state.activeControllerID ?? "none") controllerID=\(controllerID)"
            ))
            syncWaveformDriver()
        }
        .onChange(of: state.dictationStatus) { _, newStatus in
            let showsOverlay = newStatus == .requested || newStatus == .recording || newStatus == .transcribing
            if showsOverlay {
                PersistentLog.log(.overlayShown(status: newStatus.rawValue))
            } else {
                PersistentLog.log(.overlayHidden(status: newStatus.rawValue))
            }
            syncWaveformDriver()
        }
        .onChange(of: state.waveformEnergy) { _, _ in
            syncWaveformDriver()
        }
        .onChange(of: state.activeControllerID) { _, newOwner in
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "activeControllerChanged",
                details: "newOwner=\(newOwner ?? "none") controllerID=\(controllerID)"
            ))
            if newOwner == controllerID {
                defaultLayer = DefaultKeyboardLayer.active.asLayerType
            }
            syncWaveformDriver()
        }
        .onChange(of: state.isKeyboardVisible) { _, _ in
            syncWaveformDriver()
        }
        // React to parent changing defaultLayer (e.g. keyboard reappearance
        // after user changed the default in Settings, or after recording overlay
        // dismisses and this view is recreated by SwiftUI's conditional rendering).
        .onChange(of: defaultLayer) { _, newLayer in
            currentLayer = newLayer
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictusTextDidChange)) { _ in
            // External text changes (paste, cursor move) may expose a sentence ending.
            checkAutocapitalize()
        }
        // ── UIKit container wiring via onChange ──
        // These replace the UIViewRepresentable Coordinator that previously
        // handled state changes. The container lives in UIKit (KeyboardViewController),
        // so we access it via the controller reference.
        .onChange(of: currentLayer) { _, _ in
            rebuildKeys()
        }
        .onChange(of: shiftState) { _, newState in
            guard let vc = controller as? KeyboardViewController,
                  let container = vc.keyboardContainer else { return }
            container.updateShift(newState == .shifted || newState == .capsLocked)
            container.updateShiftIcon(newState)
        }
        .onChange(of: lastTypedChar) { _, _ in
            guard let vc = controller as? KeyboardViewController,
                  let container = vc.keyboardContainer else { return }
            container.updateAccentState(lastTypedChar: lastTypedChar, isShifted: isShifted)
            container.updateReturnKeyType()
        }
        .onAppear {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "onAppear",
                details: "status=\(state.dictationStatus.rawValue) visible=\(state.isKeyboardVisible) owner=\(state.activeControllerID ?? "none") controllerID=\(controllerID)"
            ))
            // Provide controller reference to KeyboardState for auto-insert.
            // WHY here and not in init: KeyboardState is created by @StateObject
            // before the view body runs. The controller is only available as a
            // View property, so we pass it on first appearance.
            state.controller = controller
            state.openURL = { url in openURL(url) }

            // Re-read default layer in case user changed settings since extension loaded.
            defaultLayer = DefaultKeyboardLayer.active.asLayerType

            // Set the starting layer from the user's preference.
            currentLayer = defaultLayer

            // Set initial shift state based on text field content.
            // Empty field = capitalize first letter (standard iOS behavior).
            checkAutocapitalize()

            // Pre-allocate haptic generators so the first key tap has zero latency.
            // Without this, the Taptic Engine needs ~2-5ms to spin up on first use.
            HapticFeedback.warmUp()

            // Refresh cached haptic enabled state from UserDefaults.
            // This fires every time the keyboard opens, ensuring the cached value
            // reflects any changes made in Settings since last keyboard session.
            HapticFeedback.refreshEnabledState()

            // Set prediction engine language from App Group shared preference.
            let lang = AppGroup.defaults.string(forKey: SharedKeys.language) ?? "fr"
            suggestionState.setLanguage(lang)

            // Build initial keyboard keys in the UIKit container
            rebuildKeys()

            syncWaveformDriver()
        }
        .onDisappear {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "onDisappear",
                details: "status=\(state.dictationStatus.rawValue) controllerID=\(controllerID)"
            ))
            syncWaveformDriver(forceHidden: true)
        }
    }

    // MARK: - Waveform sync

    private func syncWaveformDriver(forceHidden: Bool = false) {
        waveformDriver.sync(
            presenterID: controllerID,
            status: state.dictationStatus,
            energyLevels: state.waveformEnergy,
            isVisible: !forceHidden && showsOverlay
        )
    }

    // MARK: - UIKit Container Wiring

    /// Build (or rebuild) the keyboard keys in the UIKit container.
    /// Called on initial appearance and on every layer change.
    private func rebuildKeys() {
        guard let vc = controller as? KeyboardViewController,
              let container = vc.keyboardContainer else { return }
        container.buildKeys(rows: currentRows, actions: makeActions())
        // Apply current shift state after rebuild
        container.updateShift(isShifted)
        container.updateShiftIcon(shiftState)
        container.updateAccentState(lastTypedChar: lastTypedChar, isShifted: isShifted)
        container.updateReturnKeyType()
    }

    /// Create the KeyboardActions struct with all callbacks wired to the text document proxy.
    /// Extracted from the former inline KeyboardUIView instantiation.
    private func makeActions() -> KeyboardActions {
        KeyboardActions(
            onCharacter: { char in insertCharacter(char) },
            onDelete: {
                // Autocorrect undo: if backspace pressed immediately after
                // autocorrect, restore the original word instead of normal delete.
                if let undo = suggestionState.lastAutocorrect {
                    let proxy = controller.textDocumentProxy
                    let deleteCount = undo.correctedWord.count + (undo.insertedSpace ? 1 : 0)
                    for _ in 0..<deleteCount {
                        proxy.deleteBackward()
                    }
                    proxy.insertText(undo.originalWord)
                    suggestionState.lastAutocorrect = nil
                    lastTypedChar = nil
                    checkAutocapitalize()
                    DispatchQueue.main.async {
                        suggestionState.update(proxy: controller.textDocumentProxy)
                    }
                    return true
                }
                let before = controller.textDocumentProxy.documentContextBeforeInput
                guard before != nil && !before!.isEmpty else {
                    return false
                }
                controller.textDocumentProxy.deleteBackward()
                lastTypedChar = nil
                checkAutocapitalize()
                DispatchQueue.main.async {
                    suggestionState.update(proxy: controller.textDocumentProxy)
                }
                return true
            },
            onWordDelete: {
                suggestionState.lastAutocorrect = nil
                deleteWordBackward()
                lastTypedChar = nil
                checkAutocapitalize()
                DispatchQueue.main.async {
                    suggestionState.update(proxy: controller.textDocumentProxy)
                }
            },
            onSpace: {
                performAutocorrectIfNeeded()
                controller.textDocumentProxy.insertText(" ")
                lastTypedChar = nil
                suggestionState.clear()
                checkAutocapitalize()
            },
            onReturn: {
                suggestionState.lastAutocorrect = nil
                controller.textDocumentProxy.insertText("\n")
                lastTypedChar = nil
                suggestionState.clear()
                checkAutocapitalize()
            },
            onGlobe: {
                controller.advanceToNextInputMode()
            },
            onEmoji: {
                previousLayer = currentLayer
                currentLayer = .emoji
                isEmojiMode = true
            },
            onLayerSwitch: {
                suggestionState.lastAutocorrect = nil
                suggestionState.clear()
                toggleLettersNumbers()
            },
            onSymbolToggle: {
                suggestionState.lastAutocorrect = nil
                suggestionState.clear()
                toggleNumbersSymbols()
            },
            onAccentAdaptive: { char in
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(KeySound.letter)
                suggestionState.lastAutocorrect = nil
                if AccentedCharacters.shouldReplace(afterTyping: lastTypedChar) {
                    controller.textDocumentProxy.deleteBackward()
                }
                insertCharacter(char)
            },
            onCursorMove: { offset in
                controller.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            },
            onShiftChanged: { newState in
                shiftState = newState
            },
            onReturnKeyType: {
                controller.textDocumentProxy.returnKeyType ?? .default
            }
        )
    }

    // MARK: - Suggestion Handling

    /// Handles a tap on one of the suggestion bar slots.
    ///
    /// WHY two modes:
    /// - Completion mode: the user is typing a word and taps a completion.
    ///   We replace the partial word with the full suggestion and add a space
    ///   so the user can continue typing the next word immediately.
    /// - Accent mode: the user typed a single vowel and wants an accent variant.
    ///   We replace just the vowel character without adding a space, because
    ///   the user may continue typing the same word.
    private func handleSuggestionTap(index: Int) {
        guard index < suggestionState.suggestions.count else { return }
        let suggestion = suggestionState.suggestions[index]
        let proxy = controller.textDocumentProxy

        let addSpace = suggestionState.mode == .completions
        replaceCurrentWord(
            proxy: proxy,
            currentWord: suggestionState.currentWord,
            replacement: suggestion,
            addSpace: addSpace
        )

        suggestionState.lastAutocorrect = nil
        suggestionState.clear()
        HapticFeedback.keyTapped()
    }

    /// Replaces the word currently being typed with a replacement string.
    ///
    /// WHY deleteBackward loop:
    /// UITextDocumentProxy doesn't support selecting or replacing text directly.
    /// The only way to "replace" is to delete the current word character by character
    /// and then insert the replacement. This is the standard pattern used by all
    /// third-party iOS keyboards.
    private func replaceCurrentWord(
        proxy: UITextDocumentProxy,
        currentWord: String,
        replacement: String,
        addSpace: Bool
    ) {
        for _ in 0..<currentWord.count {
            proxy.deleteBackward()
        }
        proxy.insertText(replacement)
        if addSpace {
            proxy.insertText(" ")
        }
    }

    // MARK: - Character insertion (migrated from KeyboardView)

    private func insertCharacter(_ char: String) {
        // NOTE: Audio + haptic are now fired in UIKit button's touchesBegan handler,
        // NOT here. This matches Apple's native keyboard: feedback fires on press
        // (touchDown), not on release (touchUp/insert).

        // Any character input clears the autocorrect undo state.
        // The undo window is only valid immediately after the autocorrection.
        suggestionState.lastAutocorrect = nil

        // Track last typed character for the adaptive accent key.
        // The accent key uses this to decide whether to show apostrophe or an accent.
        lastTypedChar = char

        controller.textDocumentProxy.insertText(char)

        // Auto-unshift after one character (unless caps locked)
        if shiftState == .shifted {
            shiftState = .off
        }

        // Update suggestions on BACKGROUND queue with coalescing.
        // WHY updateAsync: Moves extractLastWord + engine.suggestions() off main thread.
        // WHY read context here: UITextDocumentProxy must be read on main thread.
        // WHY DispatchQueue.main.async: proxy reads can be stale immediately after
        // insertText(). Deferring by one runloop tick ensures documentContextBeforeInput
        // reflects the newly inserted character.
        DispatchQueue.main.async {
            let context = controller.textDocumentProxy.documentContextBeforeInput
            suggestionState.updateAsync(context: context)
        }
    }

    // MARK: - Autocapitalize (migrated from KeyboardView)

    /// Check whether autocapitalisation should activate shift.
    /// Respects the host app's autocapitalizationType: .none disables autocap entirely,
    /// .sentences (default) capitalizes after ". ", "! ", "? ", newline, or empty field.
    ///
    /// WHY only auto-SHIFT, never auto-unshift:
    /// Auto-unshift is already handled by insertCharacter() (shifts off after one char).
    /// If we auto-unshifted here, it would fight with manual shift taps.
    /// Caps lock is never touched by autocap -- it's always a deliberate user action.
    private func checkAutocapitalize() {
        let proxy = controller.textDocumentProxy

        // Respect autocapitalizationType from the host text field.
        // .none = never autocap (e.g., email, password fields).
        // .sentences = capitalize after sentence-ending punctuation (default).
        // .words and .allCharacters are less common; we handle .sentences and .none.
        if let autocapType = proxy.autocapitalizationType,
           autocapType == .none {
            return
        }

        let before = proxy.documentContextBeforeInput ?? ""

        let shouldCap: Bool
        if before.isEmpty {
            // Empty field = capitalize first letter
            shouldCap = true
        } else if before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? ") {
            // After sentence-ending punctuation followed by space
            shouldCap = true
        } else if before.hasSuffix("\n") {
            // After newline
            shouldCap = true
        } else {
            shouldCap = false
        }

        // Only auto-activate shift; don't interfere with caps lock or manual shift
        if shouldCap && shiftState == .off {
            shiftState = .shifted
        }
    }

    // MARK: - Word deletion (migrated from KeyboardView)

    /// Delete backward to the previous word boundary.
    /// Since UITextDocumentProxy doesn't provide deleteWordBackward(),
    /// we read the text before the cursor, find the last word boundary
    /// (space or start of string), and delete that many characters.
    private func deleteWordBackward() {
        let proxy = controller.textDocumentProxy
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            // Nothing to delete -- fall back to single char delete
            proxy.deleteBackward()
            return
        }

        // Trim trailing spaces first (delete spaces before the word)
        var trimmed = before
        var trailingSpaces = 0
        while trimmed.hasSuffix(" ") {
            trimmed = String(trimmed.dropLast())
            trailingSpaces += 1
        }

        // Find the last word boundary (space) in the remaining text
        let charsInWord: Int
        if let lastSpace = trimmed.lastIndex(of: " ") {
            charsInWord = trimmed.distance(from: trimmed.index(after: lastSpace), to: trimmed.endIndex)
        } else {
            // No space found -- delete everything remaining
            charsInWord = trimmed.count
        }

        let totalToDelete = trailingSpaces + charsInWord
        for _ in 0..<totalToDelete {
            proxy.deleteBackward()
        }
    }

    // MARK: - Layer switching (migrated from KeyboardView)

    private func toggleLettersNumbers() {
        if currentLayer == .letters {
            currentLayer = .numbers
        } else {
            currentLayer = .letters
            shiftState = .off
        }
    }

    private func toggleNumbersSymbols() {
        if currentLayer == .numbers {
            currentLayer = .symbols
        } else {
            currentLayer = .numbers
        }
    }

    // MARK: - Autocorrect (migrated from KeyboardView)

    /// Checks the current word for misspellings and auto-corrects if enabled.
    ///
    /// Called before inserting a space (or punctuation). If autocorrect is enabled
    /// and the current word is misspelled, the word is replaced with the best
    /// correction. The original word is stored so backspace can undo the correction.
    ///
    /// WHY before space (not after):
    /// If we correct after inserting the space, the cursor would be after the space
    /// and we'd need to move back, correct, then move forward. Correcting before
    /// the space keeps the proxy in the right position for a simple delete+insert.
    private func performAutocorrectIfNeeded() {
        guard suggestionState.autocorrectEnabled else { return }

        let currentWord = suggestionState.currentWord
        guard !currentWord.isEmpty else { return }

        guard let correction = suggestionState.performSpellCheck(currentWord) else { return }

        // Don't autocorrect to the same word
        guard correction.lowercased() != currentWord.lowercased() else { return }

        let proxy = controller.textDocumentProxy

        // Delete the current word and insert the correction
        for _ in 0..<currentWord.count {
            proxy.deleteBackward()
        }
        proxy.insertText(correction)

        // Store undo state so immediate backspace can restore the original word
        suggestionState.lastAutocorrect = AutocorrectState(
            originalWord: currentWord,
            correctedWord: correction,
            insertedSpace: true
        )
    }
}
