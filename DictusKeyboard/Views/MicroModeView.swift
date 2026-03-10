// DictusKeyboard/Views/MicroModeView.swift
// Dictation-only keyboard mode: large centered mic button + bottom utility row.
import SwiftUI
import DictusCore

/// Minimal keyboard layout for dictation-first users.
///
/// WHY a separate view instead of conditionals in KeyboardRootView:
/// Each keyboard mode has distinct layout logic. Extracting into separate views
/// keeps KeyboardRootView as a thin router and makes each mode independently
/// maintainable. Single Responsibility Principle.
///
/// Layout:
/// - Large centered mic button (~120pt wide pill) with "Dicter" label below
/// - Bottom utility row: emoji, space, return, delete
/// - No globe button (iOS provides a system globe for all third-party keyboards)
/// - Uses totalHeight parameter to match other modes' height (no layout jump)
struct MicroModeView: View {
    let controller: UIInputViewController
    let dictationStatus: DictationStatus
    let onMicTap: () -> Void
    let totalHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Top area: centered mic button with label (takes remaining space)
            VStack(spacing: 12) {
                Spacer()

                // Large mic button -- pill shape, ~120pt wide.
                // WHY not using scaleEffect on AnimatedMicButton:
                // scaleEffect causes blur on retina displays because it rasterizes
                // the view at its original size then scales the bitmap. Instead we
                // build a custom large pill button with the same visual language.
                Button(action: onMicTap) {
                    ZStack {
                        // Glass background pill
                        Capsule()
                            .fill(micFillColor)
                            .frame(width: 120, height: 56)
                            .dictusGlass(in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(micStrokeColor, lineWidth: 2)
                                    .frame(width: 130, height: 66)
                            )

                        // Mic icon
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(GlassPressStyle(pressedScale: 0.92))
                // WHY .requested is included: prevents double-taps during the 500ms
                // Darwin notification window where the app hasn't yet confirmed recording
                // start. Tapping during .requested can race with the URL fallback.
                .disabled(dictationStatus == .recording || dictationStatus == .transcribing || dictationStatus == .requested)

                Text("Dicter")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Bottom utility row: emoji, space, return, delete
            // WHY these four keys: micro mode users still need basic text editing
            // (space between words, line breaks, delete typos) and emoji access.
            HStack(spacing: 0) {
                // Emoji button -- cycles to next input method which includes emoji.
                // WHY advanceToNextInputMode: this is the standard iOS API for keyboard
                // extensions. There is no public API to jump directly to emoji keyboard.
                utilityButton(icon: "face.smiling") {
                    controller.advanceToNextInputMode()
                    HapticFeedback.keyTapped()
                }

                // Space bar -- takes remaining width
                Button {
                    controller.textDocumentProxy.insertText(" ")
                    HapticFeedback.keyTapped()
                } label: {
                    Text("espace")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color(.systemBackground).opacity(0.6))
                        .cornerRadius(6)
                }
                .padding(.horizontal, 4)

                // Return key
                utilityButton(icon: "return") {
                    controller.textDocumentProxy.insertText("\n")
                    HapticFeedback.keyTapped()
                }

                // Delete key
                utilityButton(icon: "delete.left") {
                    controller.textDocumentProxy.deleteBackward()
                    HapticFeedback.keyTapped()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .frame(height: 50) // Match standard keyboard bottom row height
        }
        .frame(height: totalHeight)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Helpers

    /// Uniform utility button for the bottom row (emoji, return, delete).
    @ViewBuilder
    private func utilityButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 44, height: 42)
                .background(Color(.systemGray4).opacity(0.5))
                .cornerRadius(6)
        }
    }

    private var micFillColor: Color {
        switch dictationStatus {
        case .recording:
            return .dictusRecording
        case .transcribing:
            return .dictusAccentHighlight.opacity(0.5)
        default:
            return .dictusAccent
        }
    }

    private var micStrokeColor: Color {
        switch dictationStatus {
        case .recording:
            return Color.dictusRecording.opacity(0.5)
        default:
            return Color.dictusAccent.opacity(0.4)
        }
    }
}
