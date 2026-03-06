// DictusApp/Onboarding/TestRecordingPage.swift
// Step 5 of onboarding: test recording to validate the full dictation pipeline.
import SwiftUI
import DictusCore

/// Final onboarding step: test the dictation pipeline end-to-end.
///
/// WHY a test recording in onboarding:
/// This validates that microphone, model, and transcription all work together.
/// It gives the user confidence that everything is set up correctly before
/// they start using the keyboard in real apps. If something fails, they can
/// retry immediately instead of discovering issues later.
struct TestRecordingPage: View {
    let onComplete: () -> Void

    @EnvironmentObject var coordinator: DictationCoordinator

    @State private var hasRecorded = false
    @State private var transcriptionResult: String?
    @State private var showError = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Waveform visualization
            BrandWaveform(
                energy: coordinator.status == .recording
                    ? Float(coordinator.bufferEnergy.last ?? 0)
                    : 0,
                maxHeight: 80
            )
            .padding(.bottom, 32)

            // Title
            Text("Testez la dictee")
                .font(.dictusHeading)
                .foregroundColor(.white)
                .padding(.bottom, 12)

            // Prompt
            Text(promptText)
                .font(.dictusBody)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

            // Recording / transcription controls
            if coordinator.status == .recording {
                // Stop button during recording
                Button(action: { coordinator.stopDictation() }) {
                    ZStack {
                        Circle()
                            .fill(Color.dictusRecording)
                            .frame(width: 72, height: 72)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.bottom, 16)

                Text(formattedDuration)
                    .font(.dictusCaption)
                    .foregroundColor(.white.opacity(0.7))

            } else if coordinator.status == .transcribing {
                // Transcribing indicator
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.dictusAccent)
                    Text("Transcription en cours...")
                        .font(.dictusCaption)
                        .foregroundColor(.white.opacity(0.7))
                }

            } else if let result = transcriptionResult {
                // Show transcription result
                Text(result)
                    .font(.dictusBody)
                    .foregroundColor(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .dictusGlass()
                    .padding(.horizontal, 32)

            } else {
                // Mic button to start recording
                AnimatedMicButton(status: .idle) {
                    startTestRecording()
                }
            }

            // Error feedback
            if showError, let error = errorMessage {
                Text(error)
                    .font(.dictusCaption)
                    .foregroundColor(.dictusRecording)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
            }

            Spacer()

            // Bottom buttons
            if showError {
                Button(action: {
                    showError = false
                    errorMessage = nil
                    startTestRecording()
                }) {
                    Text("Reessayer")
                        .font(.dictusSubheading)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.dictusAccent)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)

            } else if transcriptionResult != nil {
                Button(action: {
                    coordinator.resetStatus()
                    onComplete()
                }) {
                    Text("Terminer")
                        .font(.dictusSubheading)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.dictusSuccess)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onChange(of: coordinator.status) { newStatus in
            handleStatusChange(newStatus)
        }
    }

    // MARK: - Private

    private var promptText: String {
        if coordinator.status == .recording {
            return "Parlez maintenant..."
        } else if transcriptionResult != nil {
            return "Voici votre transcription :"
        } else {
            return "Dites quelque chose !"
        }
    }

    private var formattedDuration: String {
        let seconds = Int(coordinator.bufferSeconds)
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func startTestRecording() {
        transcriptionResult = nil
        showError = false
        errorMessage = nil
        coordinator.startDictation()
    }

    private func handleStatusChange(_ newStatus: DictationStatus) {
        switch newStatus {
        case .ready:
            // Transcription complete — capture result
            if let result = coordinator.lastResult, !result.isEmpty {
                transcriptionResult = result
                hasRecorded = true
            }
        case .failed:
            showError = true
            errorMessage = coordinator.lastResult ?? "La transcription a echoue. Verifiez que le modele est telecharge."
        default:
            break
        }
    }
}
