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

    /// Standard keyboard height for 4 rows of keys.
    /// Used by both KeyboardView and RecordingOverlay to ensure identical heights,
    /// preventing jarring resize when switching between them.
    private var keyboardHeight: CGFloat {
        let rows: CGFloat = 4
        return (rows * KeyMetrics.keyHeight)
            + ((rows - 1) * KeyMetrics.rowSpacing)
            + 8  // vertical padding
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full Access banner — persistent when disabled
            if !controller.hasFullAccess {
                FullAccessBanner()
            }

            // Toolbar always visible: gear icon (left) + mic button (right)
            ToolbarView(
                hasFullAccess: controller.hasFullAccess,
                dictationStatus: state.dictationStatus
            )

            // Conditional: normal keyboard OR recording overlay
            if state.dictationStatus == .recording || state.dictationStatus == .transcribing {
                RecordingOverlay(
                    waveformEnergy: state.waveformEnergy,
                    elapsedSeconds: state.recordingElapsed,
                    isTranscribing: state.dictationStatus == .transcribing,
                    onCancel: { state.requestCancel() },
                    onStop: { state.requestStop() }
                )
                .frame(height: keyboardHeight)
            } else {
                KeyboardView(
                    controller: controller,
                    hasFullAccess: controller.hasFullAccess
                )
            }
        }
        .background(Color(.secondarySystemBackground))
        .onAppear {
            // Provide controller reference to KeyboardState for auto-insert.
            // WHY here and not in init: KeyboardState is created by @StateObject
            // before the view body runs. The controller is only available as a
            // View property, so we pass it on first appearance.
            state.controller = controller
        }
    }
}
