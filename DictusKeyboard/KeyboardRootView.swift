// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the keyboard extension.
/// Phase 3 layout: FullAccessBanner + ToolbarView + (KeyboardView OR RecordingOverlay).
///
/// WHY conditional rendering instead of overlay:
/// When recording, the keyboard letters must be completely replaced by the recording UI
/// to prevent accidental key presses. SwiftUI's conditional rendering (`if/else`) fully
/// removes the inactive view from the hierarchy, freeing its memory and preventing
/// ghost touches. An overlay or ZStack would keep both views alive.
struct KeyboardRootView: View {
    let controller: UIInputViewController
    @StateObject private var state = KeyboardState()

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

    /// Toolbar height — must match ToolbarView's intrinsic height.
    private let toolbarHeight: CGFloat = 44

    /// Total content height (toolbar + keyboard). RecordingOverlay uses this
    /// to cover the full area, preventing layout shift when switching to recording.
    private var totalContentHeight: CGFloat {
        toolbarHeight + keyboardHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full Access banner — persistent when disabled
            if !controller.hasFullAccess {
                FullAccessBanner()
            }

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
                // Toolbar visible only when not recording
                ToolbarView(
                    hasFullAccess: controller.hasFullAccess,
                    dictationStatus: state.dictationStatus,
                    onMicTap: { state.startRecording() }
                )

                KeyboardView(
                    controller: controller,
                    hasFullAccess: controller.hasFullAccess
                )
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
        }
    }
}
