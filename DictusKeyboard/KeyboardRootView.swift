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
    @State private var isEmojiMode = false

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
                // KBD-05: The system-provided Apple dictation mic icon below the keyboard cannot be
                // removed by third-party keyboard extensions. No public API exists to suppress it.
                // Users can disable it in Settings > General > Keyboard > Enable Dictation.
                // Our mic button in ToolbarView is the Dictus-specific dictation trigger.

                // Hide toolbar in emoji mode to give full height to emoji picker
                if !isEmojiMode {
                    ToolbarView(
                        hasFullAccess: controller.hasFullAccess,
                        dictationStatus: state.dictationStatus,
                        onMicTap: { state.startRecording() }
                    )
                }

                KeyboardView(
                    controller: controller,
                    hasFullAccess: controller.hasFullAccess,
                    isEmojiMode: $isEmojiMode
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

            // Pre-allocate haptic generators so the first key tap has zero latency.
            // Without this, the Taptic Engine needs ~2-5ms to spin up on first use.
            HapticFeedback.warmUp()
        }
    }
}
