// DictusApp/Views/RecordingView.swift
// Full-screen recording UI with waveform, stop button, and elapsed time.
import SwiftUI
import DictusCore

/// Full-screen view shown during dictation (recording, transcribing, ready states).
///
/// WHY this is a separate view from ContentView:
/// Single Responsibility — RecordingView handles the recording UI exclusively.
/// ContentView decides *when* to show it based on coordinator status.
struct RecordingView: View {
    @EnvironmentObject var coordinator: DictationCoordinator

    var body: some View {
        ZStack {
            // Dark background for recording focus
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Status-dependent content
                switch coordinator.status {
                case .recording:
                    recordingContent
                case .transcribing:
                    transcribingContent
                case .ready:
                    readyContent
                case .failed:
                    failedContent
                default:
                    // For .idle, .requested — show nothing (shouldn't normally appear)
                    EmptyView()
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Recording State

    /// Shows live waveform + elapsed time + stop button during recording.
    private var recordingContent: some View {
        VStack(spacing: 32) {
            // Elapsed time display
            Text(formattedTime)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.white)

            // Live audio waveform visualization
            WaveformView(energyLevels: coordinator.bufferEnergy)
                .frame(height: 80)
                .padding(.horizontal)

            // Stop button
            Button(action: {
                coordinator.stopDictation()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.red)
            }
            .accessibilityLabel("Arreter l'enregistrement")
        }
    }

    // MARK: - Transcribing State

    /// Shows a progress indicator while WhisperKit processes the audio.
    private var transcribingContent: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))

            Text("Transcription en cours...")
                .font(.title2)
                .foregroundColor(.white)
        }
    }

    // MARK: - Ready State

    /// Shows a checkmark briefly after transcription completes.
    private var readyContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            if let result = coordinator.lastResult {
                Text(result)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineLimit(4)
            }

            Text("Terminé")
                .font(.title2)
                .foregroundColor(.white)
        }
    }

    // MARK: - Failed State

    private var failedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Erreur")
                .font(.title2)
                .foregroundColor(.white)

            Button("Reessayer") {
                coordinator.startDictation()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    // MARK: - Helpers

    /// Format elapsed seconds as "M:SS".
    ///
    /// WHY not use DateComponentsFormatter:
    /// For a simple "minutes:seconds" format, manual formatting is simpler and avoids
    /// the overhead of creating a formatter object on every view update.
    private var formattedTime: String {
        let totalSeconds = Int(coordinator.bufferSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - WaveformView

/// Displays audio energy levels as animated bars.
///
/// WHY HStack of RoundedRectangles:
/// This is the standard approach for audio waveform visualization in SwiftUI.
/// Each bar represents a recent energy sample from WhisperKit's AudioProcessor.
/// The `relativeEnergy` values are 0.0-1.0, mapped to bar height.
struct WaveformView: View {
    let energyLevels: [Float]

    /// Number of bars to display in the waveform.
    private let barCount = 50

    var body: some View {
        HStack(spacing: 2) {
            // Show the most recent energy values
            ForEach(Array(displayLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4, height: max(CGFloat(level) * 60 + 3, 3))
            }
        }
        .frame(height: 66)
        // Animate waveform changes smoothly
        .animation(.easeOut(duration: 0.1), value: energyLevels.count)
    }

    /// Get the last N energy levels, padded with zeros if needed.
    private var displayLevels: [Float] {
        let levels = energyLevels.suffix(barCount)
        if levels.count < barCount {
            return Array(repeating: Float(0), count: barCount - levels.count) + levels
        }
        return Array(levels)
    }
}

#Preview("Recording") {
    RecordingView()
        .environmentObject(DictationCoordinator.shared)
}
