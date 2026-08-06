// DictusApp/Views/RecordingView.swift
// Stable-layout recording screen: waveform + mic button always in place, text appears below.
import SwiftUI
import DictusCore

/// Determines the context in which RecordingView is shown.
///
/// WHY a mode enum instead of separate views:
/// The recording experience should feel identical whether the user reaches it
/// from onboarding or from HomeView's "New dictation" button.
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
    /// Brief "Copié !" feedback when user taps the transcription result.
    @State private var showCopiedFeedback = false
    /// Two-step dismissal: animate out first, then reset coordinator status.
    @State private var isDismissing = false

    /// The stage this screen draws, which trails `coordinator.status` by up to
    /// `TranscribingStageHold.minimumDisplayDuration` (#309).
    ///
    /// WHY this screen and not only the keyboard overlay: the two share one visual
    /// vocabulary, and someone dictating inside DictusApp waits on this screen. Fixing
    /// the flash on one surface and not the other would make them disagree about what
    /// the phone is doing within the same second.
    @State private var displayedStatus: DictationStatus = .idle

    /// The rule. Pure and tested in DictusCore; the timer below is this surface's.
    @State private var hold = TranscribingStageHold()

    /// Fires when a held stage becomes drawable. At most one is ever in flight.
    @State private var holdTask: Task<Void, Never>?

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
                            HapticFeedback.recordingStopped()
                            // Step 1: animate RecordingView out
                            withAnimation(.easeOut(duration: 0.25)) {
                                isDismissing = true
                            }
                            // Step 2: after animation, reset status (no animation leak to HomeView).
                            // Generation guard (issue #60): if a new dictation started while the
                            // dismiss animation ran, this stale reset must not tear it down.
                            let generation = coordinator.dictationGeneration
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                guard coordinator.dictationGeneration == generation else { return }
                                coordinator.resetStatus()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 40, height: 40)
                                .dictusGlass(in: Circle())
                        }
                        .frame(width: 44, height: 44)
                        .buttonStyle(GlassPressStyle(pressedScale: 1.35))
                        .padding(.leading, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                }

                // MARK: - Upper zone: result text (centered between top and waveform)
                // WHY above waveform: The waveform+mic are anchored in the bottom
                // third. Placing the result in the large empty upper zone avoids
                // pushing anything down when text appears.
                ZStack {
                    if showResult, let result = transcriptionResult {
                        // WHY GeometryReader + ScrollView combo:
                        // GeometryReader gives us the available height so we can
                        // vertically center short text. ScrollView handles long text
                        // that exceeds the zone. Short text sits centered; long text scrolls.
                        GeometryReader { geo in
                            ScrollView {
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
                                        .dictusGlass(in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(GlassPressStyle(pressedScale: 0.96))
                                .padding(.horizontal, 32)
                                .frame(minHeight: geo.size.height)
                            }
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
                                .padding(.horizontal, 32)

                            if mode == .onboarding {
                                Button("Retry") {
                                    errorMessage = nil
                                    showError = false
                                    showResult = false
                                }
                                .font(.dictusBody)
                                .foregroundColor(.dictusAccent)
                                .padding(.top, 8)
                            }
                        }
                    }

                    // Onboarding: auto-advance handled in handleStatusChange
                }
                .frame(maxHeight: .infinity)

                // MARK: - Waveform (always visible, anchored in bottom third)
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

                Spacer()
                    .frame(height: 40)
            }
        }
        .opacity(isDismissing ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: showResult)
        .animation(.easeOut(duration: 0.3), value: showCopiedFeedback)
        .onChange(of: coordinator.status) { newStatus in
            // `handleStatusChange` is deliberately still driven by the real status: it
            // does not draw a stage, it reveals the result text and the error, and a
            // terminal status preempts the hold anyway (#309).
            handleStatusChange(newStatus)
            advanceDisplayedStatus(to: newStatus)
        }
        // A screen that appears mid-dictation adopts the stage in flight at once,
        // rather than starting from `.idle` and pretending to enter it.
        .onAppear { advanceDisplayedStatus(to: coordinator.status) }
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
            // Reset, not merely cancel: `.onAppear` re-adopts the stage in flight, and
            // a decision left pending here would be re-affirmed as "already decided"
            // with no timer left to draw it. A fresh hold draws whatever it is handed.
            //
            // The drawn stage is reset with it, and the two must move together. A fresh
            // hold believes `.idle` is on screen; if the coordinator has also returned
            // to `.idle` by the time the screen comes back, `apply` answers `.unchanged`
            // and nothing reassigns `displayedStatus` -- leaving the travelling peak and
            // "Traitement..." drawn over an idle screen. Resetting only one of the two
            // is what makes them disagree.
            hold = TranscribingStageHold()
            displayedStatus = .idle
        }
        .navigationBarHidden(true)
    }

    // MARK: - Waveform Section

    /// Always-visible waveform that changes behavior based on state.
    /// Single BrandWaveform instance — properties change dynamically instead of
    /// swapping 3 separate instances. Prevents ghost CADisplayLinks when the app
    /// continues its run loop in background (UIBackgroundModes:audio).
    private var waveformSection: some View {
        BrandWaveform(
            energyLevels: displayedStatus == .recording
                ? coordinator.bufferEnergy
                : Array(repeating: Float(0), count: 30),
            maxHeight: 120,
            animation: waveformAnimation,
            isActive: displayedStatus == .recording || isPostRecordingStage
        )
        .opacity(displayedStatus == .recording ? 0.5 :
                 isPostRecordingStage ? 0.3 : 0.15)
    }

    /// The animation for the current stage.
    ///
    /// This screen draws the same three animations as the keyboard overlay, from
    /// the same `ProcessingWaveform` maths (#267). An earlier round shared one
    /// animation across both post-recording stages, on the argument that the
    /// distinction belongs where the user waits during a keyboard dictation. Device
    /// testing settled it the other way: someone dictating inside DictusApp is
    /// waiting on this screen, and it owes them the same answer.
    ///
    /// Driven by `displayedStatus` rather than the coordinator's, so the animation and
    /// the label below change together (#309).
    private var waveformAnimation: WaveformAnimation {
        switch displayedStatus {
        case .recording:
            return .micLevels
        case .transcribing:
            return .sweep
        case .processing:
            return .travellingPeak
        case .idle, .requested, .ready, .failed:
            return .still
        }
    }

    /// Whether the pipeline is past the microphone and working on the audio or the
    /// transcript. Drives opacity and the disabled mic button, both of which are
    /// the same for either stage.
    private var isPostRecordingStage: Bool {
        displayedStatus == .transcribing || displayedStatus == .processing
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        if displayedStatus == .recording {
            Text(formattedTime)
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .foregroundStyle(.secondary)
        } else if displayedStatus == .transcribing {
            Text("Transcribing...")
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
        } else if displayedStatus == .processing {
            // The waveform is shared between the two stages here, but the label is
            // not: naming the wrong stage is the complaint #267 exists to fix, and
            // it costs a user dictating inside DictusApp the same six seconds of
            // wondering whether the app has hung.
            Text("Processing...")
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
        } else if showCopiedFeedback {
            Text("Copied!")
                .font(.dictusCaption)
                .foregroundStyle(Color.dictusSuccess)
        } else if showResult {
            Text("Tap text to copy")
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
        if displayedStatus == .recording {
            // Red stop button with glass ring
            Button(action: stopRecording) {
                ZStack {
                    // Glass ring behind the stop button
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 96, height: 96)
                        .dictusGlass(in: Circle())
                    Circle()
                        .fill(Color.dictusRecording)
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                }
            }
            .buttonStyle(GlassPressStyle(pressedScale: 0.88))
            .accessibilityLabel("Stop recording")
        } else if isPostRecordingStage {
            // Shimmer mic during processing (disabled). The status is passed
            // through rather than pinned to `.transcribing` so the button reflects
            // the stage it is actually in (#267); the shimmer is the same for both.
            AnimatedMicButton(status: displayedStatus) {}
                .disabled(true)
        } else {
            // Idle / result state: mic button ready for (new) recording
            AnimatedMicButton(status: .idle) {
                startRecording()
            }
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

    // MARK: - Stage display (#309)

    /// Move `displayedStatus` toward `status`, honouring the transcription floor.
    ///
    /// The decision is `TranscribingStageHold`'s, in DictusCore, where it is tested.
    /// What lives here is only this screen's timer — a `Task` rather than a `Timer`,
    /// because it has to be cancelled from the view and cancellation is what keeps a
    /// terminal status from ever waiting behind a stage that no longer matters.
    private func advanceDisplayedStatus(to status: DictationStatus) {
        switch hold.apply(status, now: Date()) {
        case .unchanged:
            break
        case .draw(let drawn):
            holdTask?.cancel()
            holdTask = nil
            displayedStatus = drawn
        case .hold(_, let interval):
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                if case .draw(let drawn) = hold.release(now: Date()) {
                    displayedStatus = drawn
                }
            }
        }
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
                // Auto-advance to success screen in onboarding mode
                // Shows transcription result for 1.5s then triggers onComplete
                if mode == .onboarding {
                    // Generation guard (issue #60): if the user started a new dictation
                    // during the 1.5s delay, this stale auto-advance must not fire.
                    let generation = coordinator.dictationGeneration
                    Task {
                        try? await Task.sleep(for: .milliseconds(1500))
                        await MainActor.run {
                            guard coordinator.dictationGeneration == generation else { return }
                            coordinator.resetStatus()
                            onComplete?()
                        }
                    }
                }
            }
        case .failed:
            showError = true
            errorMessage = coordinator.lastResult ?? String(localized: "Transcription failed. Check that the model is downloaded.")
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
