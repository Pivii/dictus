// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the keyboard extension.
/// Phase 3 layout: ToolbarView + (KeyboardView OR RecordingOverlay).
///
/// WHY conditional rendering instead of overlay:
/// When recording, the keyboard letters must be completely replaced by the recording UI
/// to prevent accidental key presses. SwiftUI's conditional rendering (`if/else`) fully
/// removes the inactive view from the hierarchy, freeing its memory and preventing
/// ghost touches. An overlay or ZStack would keep both views alive.
struct KeyboardRootView: View {
    let controller: UIInputViewController
    @StateObject private var state = KeyboardState()
    /// Observable state for the suggestion bar: holds current suggestions, mode, and autocorrect undo.
    /// WHY @StateObject: SuggestionState is an ObservableObject that must survive view re-renders.
    /// @StateObject ensures a single instance is created and owned by this view.
    @StateObject private var suggestionState = SuggestionState()
    @State private var isEmojiMode = false
    /// Active keyboard mode read from App Group on each appearance.
    /// WHY @State: The mode is read once when the keyboard opens (onAppear) and
    /// doesn't change during the keyboard session. @State is sufficient — no need
    /// for @StateObject or continuous observation.
    @State private var currentMode: KeyboardMode = .full

    /// WHY @Environment here: openURL is the SwiftUI way to open URLs.
    /// Keyboard extensions cannot access UIApplication.shared, but SwiftUI's
    /// openURL environment action works because it goes through the responder
    /// chain. We capture it here and inject it into KeyboardState via .onAppear.
    @Environment(\.openURL) private var openURL

    /// Height of just the 4-row keyboard area (without toolbar).
    private var keyboardHeight: CGFloat {
        let rows: CGFloat = 4
        return (rows * KeyMetrics.keyHeight)
            + ((rows - 1) * KeyMetrics.rowSpacing)
            + 8  // vertical padding
    }

    /// Toolbar height — must match ToolbarView's intrinsic height (48pt for mic pill glow room).
    private let toolbarHeight: CGFloat = 48

    /// Total content height (toolbar + keyboard). RecordingOverlay uses this
    /// to cover the full area, preventing layout shift when switching to recording.
    private var totalContentHeight: CGFloat {
        toolbarHeight + keyboardHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Conditional: recording overlay (full area) OR toolbar + keyboard
            if state.dictationStatus == .recording || state.dictationStatus == .transcribing {
                RecordingOverlay(
                    waveformEnergy: state.waveformEnergy,
                    elapsedSeconds: state.recordingElapsed,
                    isTranscribing: state.dictationStatus == .transcribing,
                    onCancel: { state.requestCancel() },
                    onStop: { state.requestStop() }
                )
                .frame(height: totalContentHeight)
            } else {
                // Mode-based rendering: each KeyboardMode gets its own layout.
                // WHY switch instead of if/else: Swift exhaustive switch ensures we
                // handle every mode — if a new mode is added to KeyboardMode, the
                // compiler will flag this switch as incomplete.
                switch currentMode {
                case .micro:
                    MicroModeView(
                        controller: controller,
                        dictationStatus: state.dictationStatus,
                        onMicTap: { state.startRecording() },
                        totalHeight: totalContentHeight
                    )

                case .emojiMicro:
                    EmojiMicroModeView(
                        controller: controller,
                        hasFullAccess: controller.hasFullAccess,
                        dictationStatus: state.dictationStatus,
                        onMicTap: { state.startRecording() },
                        totalHeight: totalContentHeight
                    )

                case .full:
                    // KBD-05: The system-provided Apple dictation mic icon below the keyboard cannot be
                    // removed by third-party keyboard extensions. No public API exists to suppress it.
                    // Users can disable it in Settings > General > Keyboard > Enable Dictation.
                    // Our mic button in ToolbarView is the Dictus-specific dictation trigger.

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

                    KeyboardView(
                        controller: controller,
                        hasFullAccess: controller.hasFullAccess,
                        isEmojiMode: $isEmojiMode,
                        suggestionState: suggestionState
                    )

                    // Experimental: extra bottom padding to push system keyboard row
                    // (globe, dictation mic icons) further down. Wispr Flow appears to use
                    // extra height to overlay-hide the system dictation mic icon.
                    // If this doesn't work, it confirms an iOS limitation (KBD-05).
                    if !isEmojiMode {
                        Spacer().frame(height: 8)
                    }
                }
            }
        }
        // WHY .clear: The native iOS keyboard container already provides a
        // blurred background. Using secondarySystemBackground created visible
        // gray bands at the top and bottom that didn't match the native chrome.
        // Transparent background lets the native keyboard styling show through.
        .background(Color.clear)
        .onAppear {
            // Provide controller reference to KeyboardState for auto-insert.
            // WHY here and not in init: KeyboardState is created by @StateObject
            // before the view body runs. The controller is only available as a
            // View property, so we pass it on first appearance.
            state.controller = controller
            state.openURL = { url in openURL(url) }

            // Read keyboard mode from App Group each time keyboard opens.
            // WHY on every appear: The user may have changed the mode in the main app's
            // settings. The keyboard extension is a separate process, so we re-read the
            // persisted value each time the keyboard appears.
            currentMode = KeyboardMode.active

            // Pre-allocate haptic generators so the first key tap has zero latency.
            // Without this, the Taptic Engine needs ~2-5ms to spin up on first use.
            HapticFeedback.warmUp()

            // Set prediction engine language from App Group shared preference.
            let lang = AppGroup.defaults.string(forKey: SharedKeys.language) ?? "fr"
            suggestionState.setLanguage(lang)
        }
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
}
