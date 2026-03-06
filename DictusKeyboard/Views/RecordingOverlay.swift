// DictusKeyboard/Views/RecordingOverlay.swift
import SwiftUI

/// Full-screen recording overlay that replaces the keyboard during active recording.
/// Shows a BrandWaveform, elapsed timer, and cancel/stop controls.
///
/// WHY this replaces the keyboard:
/// Wispr Flow-inspired design -- when recording, the keyboard area transforms into
/// an immersive recording UI. This prevents accidental key presses during dictation
/// and provides clear visual feedback that the mic is active.
struct RecordingOverlay: View {
    let waveformEnergy: [Float]
    let elapsedSeconds: Double
    let isTranscribing: Bool
    let onCancel: () -> Void
    let onStop: () -> Void

    /// Adaptive foreground color -- dark on light keyboard, light on dark keyboard.
    @Environment(\.colorScheme) private var colorScheme

    /// Timer font size scales with Dynamic Type.
    ///
    /// WHY @ScaledMetric:
    /// Keyboard extensions should respect Dynamic Type. Using @ScaledMetric makes
    /// the timer font size scale proportionally with the user's text size setting,
    /// while keeping monospaced design for proper digit alignment.
    @ScaledMetric private var timerFontSize: CGFloat = 20

    /// Icon size scales with Dynamic Type.
    @ScaledMetric private var iconSize: CGFloat = 28

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.15)
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color(white: 0.15).opacity(0.5)
    }

    var body: some View {
        ZStack {
            // Transparent background -- the native iOS keyboard chrome shows through.
            // No dark rectangle, the overlay blends seamlessly with the keyboard.
            Color.clear

            if isTranscribing {
                transcribingContent
            } else {
                recordingContent
            }
        }
    }

    // MARK: - Recording state

    private var recordingContent: some View {
        VStack(spacing: 16) {
            // Top bar: cancel (left) and stop (right)
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: iconSize))
                        .foregroundColor(secondaryForeground)
                }

                Spacer()

                Button(action: onStop) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: iconSize))
                        .foregroundColor(foregroundColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Brand waveform -- 3-bar logo-inspired visualization
            //
            // WHY BrandWaveform instead of 30-bar KeyboardWaveformView:
            // Unifies the visual language between app and keyboard extension.
            // The 3-bar waveform matches the Dictus logo proportions.
            BrandWaveform(energyLevels: waveformEnergy, maxHeight: 60)
                .padding(.horizontal, 20)

            // Timer in MM:SS format -- monospaced for digit alignment
            Text(formattedTime)
                .font(.system(size: timerFontSize, weight: .medium, design: .monospaced))
                .foregroundColor(foregroundColor)

            // Status label
            Text("Listening...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)

            Spacer()
        }
    }

    // MARK: - Transcribing state

    private var transcribingContent: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                .scaleEffect(1.2)

            Text("Processing...")
                .font(.dictusBody)
                .foregroundColor(foregroundColor)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
