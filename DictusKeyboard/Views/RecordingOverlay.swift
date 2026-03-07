// DictusKeyboard/Views/RecordingOverlay.swift
import SwiftUI
import DictusCore

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
        VStack(spacing: 0) {
            // Top bar: cancel (left) and stop (right) — fixed height
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
            .padding(.vertical, 8)

            // Waveform fills all remaining vertical space between buttons and footer.
            // WHY GeometryReader: The waveform must adapt to whatever space is
            // available rather than using a fixed maxHeight that can overflow.
            GeometryReader { geo in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)

                    BrandWaveform(
                        energyLevels: waveformEnergy,
                        maxHeight: geo.size.height * 0.7
                    )
                    .padding(.horizontal, 2)

                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            // Footer: timer + status — fixed height
            Text(formattedTime)
                .font(.system(size: timerFontSize, weight: .medium, design: .monospaced))
                .foregroundColor(foregroundColor)
                .padding(.bottom, 4)

            Text("Listening...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Transcribing state

    private var transcribingContent: some View {
        VStack(spacing: 16) {
            Spacer()

            ProcessingAnimation(height: 40)

            Text("Transcription...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)

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
