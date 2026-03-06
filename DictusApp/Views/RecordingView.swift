// DictusApp/Views/RecordingView.swift
// Full-screen recording UI with brand waveform, stop button, and elapsed time.
import SwiftUI
import DictusCore

/// Full-screen view shown during dictation (recording, transcribing, ready states).
///
/// WHY this is a separate view from ContentView:
/// Single Responsibility -- RecordingView handles the recording UI exclusively.
/// ContentView decides *when* to show it based on coordinator status.
struct RecordingView: View {
    @EnvironmentObject var coordinator: DictationCoordinator

    var body: some View {
        ZStack {
            // Dark background for recording focus -- uses brand color instead of Color.black
            Color.dictusBackground.ignoresSafeArea()

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
                    // For .idle, .requested -- show nothing (shouldn't normally appear)
                    EmptyView()
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Recording State

    /// Shows BrandWaveform + elapsed time + stop button during recording.
    ///
    /// WHY BrandWaveform instead of 50-bar WaveformView:
    /// The 3-bar brand waveform matches the Dictus logo identity and provides
    /// a cleaner, more branded recording experience. The energy is computed from
    /// the most recent buffer values for smooth animation.
    private var recordingContent: some View {
        VStack(spacing: 32) {
            // Elapsed time display -- monospaced for timer readability
            Text(formattedTime)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)

            // Brand waveform driven by live audio energy
            BrandWaveform(energyLevels: coordinator.bufferEnergy, maxHeight: 120)
                .padding(.horizontal)

            // Stop button with branded accent color
            Button(action: {
                coordinator.stopDictation()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.dictusRecording)
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
                .progressViewStyle(CircularProgressViewStyle(tint: .dictusAccent))

            Text("Transcription en cours...")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Ready State

    /// Shows a checkmark briefly after transcription completes.
    private var readyContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.dictusSuccess)

            if let result = coordinator.lastResult {
                Text(result)
                    .font(.dictusBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineLimit(4)
                    .padding()
                    .dictusGlass()
            }

            Text("Termine")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Failed State

    private var failedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Erreur")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)

            Button("Reessayer") {
                coordinator.startDictation()
            }
            .buttonStyle(.borderedProminent)
            .tint(.dictusAccent)
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

#Preview("Recording") {
    RecordingView()
        .environmentObject(DictationCoordinator.shared)
}
