// DictusApp/Views/RecordingView.swift
// Stable-layout recording screen: waveform + mic button always in place, text appears below.
import SwiftUI
import DictusCore

/// Determines the context in which RecordingView is shown.
///
/// WHY a mode enum instead of separate views:
/// The recording experience should feel identical whether the user reaches it
/// from onboarding or from HomeView's "Nouvelle dictee" button.
/// The only difference is what happens when the user finishes:
/// - onboarding: calls onComplete to advance onboarding
/// - standalone: user taps mic again for new recording, or X to dismiss
enum RecordingMode {
    case onboarding
    case standalone
}

/// Stable-layout recording screen with always-visible waveform and fixed mic button.
///
/// WHY stable layout instead of state-driven visibility:
/// Elements appearing/disappearing causes jarring layout shifts. The waveform and mic
/// button stay in place across all states — only their visual appearance changes:
/// - Idle: flat waveform, blue mic
/// - Recording: animated waveform, red stop button
/// - Transcribing: sinusoidal waveform, disabled shimmer mic
/// - Result: flat waveform, blue mic (ready for new recording), text below
///
/// Transcription text appears BELOW the fixed elements, so nothing moves.
struct RecordingView: View {
    let mode: RecordingMode
    var onComplete: (() -> Void)?

    @EnvironmentObject var coordinator: DictationCoordinator

    @State private var transcriptionResult: String?
    @State private var showResult = false
    @State private var showError = false
    @State private var errorMessage: String?
    /// Brief "Copie !" feedback when user taps the transcription result.
    @State private var showCopiedFeedback = false

    init(mode: RecordingMode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.dictusBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button (top-left) — standalone only
                HStack {
                    if mode == .standalone {
                        Button {
                            coordinator.resetStatus()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color.dictusSurface.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                }

                Spacer()

                // MARK: - Waveform (always visible)
                // WHY always visible: Creates stable visual anchor. Flat bars when
                // idle/result, audio-driven when recording, sinusoidal when processing.
                waveformSection
                    .padding(.horizontal)
                    .frame(height: 120)

                // MARK: - Status text (duration or processing indicator)
                statusText
                    .frame(height: 30)
                    .padding(.top, 8)

                // MARK: - Mic / Stop button (always in same position)
                micOrStopButton
                    .frame(height: 100)
                    .padding(.top, 16)

                // MARK: - Result area (text appears here after transcription)
                resultSection
                    .frame(minHeight: 80)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                // Onboarding finish button
                if mode == .onboarding && showResult {
                    Button(action: {
                        coordinator.resetStatus()
                        onComplete?()
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
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .animation(.easeOut(duration: 0.3), value: showResult)
        .animation(.easeOut(duration: 0.3), value: showCopiedFeedback)
        .onChange(of: coordinator.status) { newStatus in
            handleStatusChange(newStatus)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Waveform Section

    /// Always-visible waveform that changes behavior based on state.
    @ViewBuilder
    private var waveformSection: some View {
        if coordinator.status == .recording {
            // Live audio-driven waveform
            BrandWaveform(
                energyLevels: coordinator.bufferEnergy,
                maxHeight: 120
            )
            .opacity(0.5)
        } else if coordinator.status == .transcribing {
            // Sinusoidal processing wave
            BrandWaveform(maxHeight: 120, isProcessing: true)
                .opacity(0.3)
        } else {
            // Flat/idle waveform — all bars at minimum height
            BrandWaveform(
                energyLevels: Array(repeating: Float(0), count: 30),
                maxHeight: 120
            )
            .opacity(0.15)
        }
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        if coordinator.status == .recording {
            Text(formattedTime)
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .foregroundStyle(.secondary)
        } else if coordinator.status == .transcribing {
            Text("Transcription en cours...")
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
        } else if showCopiedFeedback {
            Text("Copie !")
                .font(.dictusCaption)
                .foregroundStyle(Color.dictusSuccess)
        } else if showResult {
            Text("Touchez le texte pour copier")
                .font(.dictusCaption)
                .foregroundStyle(.secondary.opacity(0.6))
        } else {
            // Empty placeholder to maintain layout
            Text(" ")
                .font(.dictusCaption)
        }
    }

    // MARK: - Mic / Stop Button

    /// Always-present button that changes appearance based on state.
    /// WHY always present: Prevents layout jumps. The button is the visual anchor
    /// of the screen — it transforms in place (mic → stop → shimmer → mic).
    @ViewBuilder
    private var micOrStopButton: some View {
        if coordinator.status == .recording {
            // Red stop button
            Button(action: stopRecording) {
                ZStack {
                    Circle()
                        .fill(Color.dictusRecording)
                        .frame(width: 80, height: 80)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }
            .accessibilityLabel("Arreter l'enregistrement")
        } else if coordinator.status == .transcribing {
            // Shimmer mic during processing (disabled)
            AnimatedMicButton(status: .transcribing) {}
                .disabled(true)
        } else {
            // Idle / result state: mic button ready for (new) recording
            AnimatedMicButton(status: .idle) {
                startRecording()
            }
        }
    }

    // MARK: - Result Section

    /// Transcription result or error, shown below the fixed elements.
    @ViewBuilder
    private var resultSection: some View {
        if showResult, let result = transcriptionResult {
            // WHY tap-to-copy: The main use case is dictating text to paste elsewhere.
            // One tap copies to clipboard — faster than selecting all + copy.
            Button {
                UIPasteboard.general.string = result
                showCopiedFeedback = true
                HapticFeedback.recordingStopped()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopiedFeedback = false
                }
            } label: {
                Text(result)
                    .font(.dictusBody)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.dictusSurface.opacity(0.5))
                    )
            }
            .transition(.opacity)
        } else if showError, let error = errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                Text(error)
                    .font(.dictusCaption)
                    .foregroundColor(.dictusRecording)
                    .multilineTextAlignment(.center)
            }
        } else {
            // Empty placeholder — maintains vertical space
            Color.clear
        }
    }

    // MARK: - Actions

    private func startRecording() {
        // Reset previous result state
        transcriptionResult = nil
        showResult = false
        showError = false
        errorMessage = nil
        showCopiedFeedback = false

        HapticFeedback.recordingStarted()
        coordinator.startDictation()
    }

    private func stopRecording() {
        HapticFeedback.recordingStopped()
        coordinator.stopDictation()
    }

    // MARK: - Status Handling

    private func handleStatusChange(_ newStatus: DictationStatus) {
        switch newStatus {
        case .ready:
            if let result = coordinator.lastResult, !result.isEmpty {
                transcriptionResult = result
                withAnimation(.easeOut(duration: 0.4)) {
                    showResult = true
                }
            }
        case .failed:
            showError = true
            errorMessage = coordinator.lastResult ?? "La transcription a echoue. Verifiez que le modele est telecharge."
        default:
            break
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let totalSeconds = Int(coordinator.bufferSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Recording - Idle") {
    RecordingView(mode: .standalone)
        .environmentObject(DictationCoordinator.shared)
}
