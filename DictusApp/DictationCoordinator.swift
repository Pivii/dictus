// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via UnifiedAudioEngine + transcription via TranscriptionService.
import Foundation
import Combine
import AVFoundation
import UIKit
import DictusCore
import WhisperKit

/// Manages the dictation lifecycle in the main app.
/// Phase 3.1: Observes keyboard stop/cancel signals via Darwin notifications,
/// forwards waveform energy to App Group for keyboard visualization.
///
/// WHY this class is @MainActor and uses static let shared:
/// - @MainActor ensures all @Published property updates happen on the main thread (required by SwiftUI)
/// - Singleton pattern because there's only ever one dictation session active at a time,
///   and multiple views need to observe the same coordinator (ContentView, RecordingView)
@MainActor
class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    // MARK: - Published State

    @Published var status: DictationStatus = .idle
    @Published var lastResult: String?

    /// Forwarded from UnifiedAudioEngine for waveform visualization in RecordingView.
    @Published var bufferEnergy: [Float] = []

    /// Forwarded from UnifiedAudioEngine for elapsed time display in RecordingView.
    @Published var bufferSeconds: Double = 0

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private let audioEngine = UnifiedAudioEngine()
    private let transcriptionService = TranscriptionService()

    /// Whether the audio engine is currently running.
    /// Used by DictusApp to detect "warm but engine-dead" state after Power button stop.
    var isEngineRunning: Bool { audioEngine.isEngineRunning }

    /// Transcription timeout watchdog: fires after 30s in .transcribing state.
    /// WHY 30s: WhisperKit transcription of a typical dictation (<60s audio) should
    /// complete in under 10s even on older devices. 30s provides generous margin
    /// while still catching genuinely stuck transcriptions.
    private var transcriptionWatchdog: Timer?

    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private var dictationTask: Task<Void, Never>?

    /// Set when cold start dictation is deferred because the app is .inactive.
    /// Cleared in didBecomeActive when the retry happens.
    private var pendingColdStartDictation = false

    /// Task that resolves when WhisperKit is fully loaded.
    /// WHY: Both init() pre-load and startDictation() call ensureEngineReady().
    /// If startDictation() arrives while pre-load is still running, it must AWAIT
    /// the ongoing init instead of starting a duplicate one. This Task acts as
    /// a concurrency lock — the first caller creates it, subsequent callers await it.
    private var initTask: Task<Void, Error>?

    /// Re-entry flag for stopDictation. Prevents the 3+ concurrent transcribe()
    /// calls observed in #144 when a user taps stop multiple times during a model
    /// swap (turbo load). Set synchronously on entry, cleared in the Task's defer.
    private var isTranscribingInFlight = false

    /// Timestamp of last waveform write to App Group.
    /// Used to throttle writes to ~5Hz (every 200ms) to avoid overwhelming UserDefaults
    /// with high-frequency updates from the audio engine's energy callback.
    private var lastWaveformWriteDate = Date.distantPast

    /// Combine subscriptions forwarding UnifiedAudioEngine's published values to coordinator.
    private var energyCancellable: AnyCancellable?
    private var secondsCancellable: AnyCancellable?

    private init() {
        // Forward UnifiedAudioEngine's energy levels and seconds to coordinator.
        // NOTE: App Group forwarding for the keyboard is handled directly from
        // the audio thread in UnifiedAudioEngine's processBuffer.
        energyCancellable = audioEngine.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                guard let self else { return }
                self.bufferEnergy = energy
                // Only forward to Dynamic Island when user is actively recording
                guard self.audioEngine.isRecording else { return }
                LiveActivityManager.shared.updateWaveform(levels: energy)
            }
        secondsCancellable = audioEngine.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.bufferSeconds = seconds
            }

        // Observe keyboard-initiated stop/cancel signals via Darwin notifications.
        observeKeyboardSignals()

        // Clear stale transcription left over from a previous crash or missed pickup.
        // 5-minute threshold: if the keyboard didn't read it by now, it never will.
        if let ts = defaults.object(forKey: SharedKeys.lastTranscriptionTimestamp) as? Double,
           Date().timeIntervalSince1970 - ts > 300 {
            defaults.removeObject(forKey: SharedKeys.lastTranscription)
            defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
            defaults.synchronize()
        }

        // Phase 37 instrumentation: snapshot device capabilities once per app launch
        // so the log stream has a stable anchor for per-device gating analysis.
        let snapshot = DeviceCapabilities.current()
        PersistentLog.log(.deviceCapabilitySnapshot(
            model: snapshot.deviceModelIdentifier,
            ramGB: snapshot.physicalMemoryGB,
            availableMemoryMB: snapshot.availableMemoryMB,
            thermalState: snapshot.thermalState.logLabel
        ))

        // Pre-load WhisperKit + audio session eagerly on app launch.
        // WHY: The first recording via URL scheme takes 4-5s if we load lazily.
        // By loading in init(), the model is ready when the keyboard triggers dictation.
        //
        // WHY configure audio session BEFORE the Task:
        // iOS forbids AVAudioSession.setActive(true) from background. The async Task
        // may not run until after the app is backgrounded. By configuring synchronously
        // in init(), we guarantee the session is active while still in the foreground.
        try? audioEngine.configureAudioSession()

        Task {
            let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
            guard modelReady else {
                self.setModelLoadState(.idle, reason: "init-preload-no-model")
                return
            }

            self.setModelLoadState(.loading, reason: "init-preload")
            do {
                try await ensureEngineReady()
                PersistentLog.log(.engineWarmUpAttempt(context: "init-preload"))
                try audioEngine.warmUp()
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                self.setModelLoadState(.ready, reason: "init-preload-success")
            } catch {
                PersistentLog.log(.engineWarmUpFailed(context: "init-preload", error: error.localizedDescription))
                self.setModelLoadState(.idle, reason: "init-preload-failed")
            }
        }

        // Stop audio engine when user taps Power button in Dynamic Island.
        // WHY here (not in LiveActivityManager):
        // The audio engine is owned by DictationCoordinator.
        // StopStandbyIntent posts this notification because it can't reference coordinator
        // directly (the intent file is compiled into DictusWidgets too).
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DictusStopStandbyRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Sync LiveActivityManager state — the intent already ended the activity
                // but the manager doesn't know. Without this, currentActivity stays non-nil
                // and ensureActivityAlive() is a no-op on next dictation (#50).
                LiveActivityManager.shared.stopStandbyActivity()

                // Stop any active recording first
                if self.status == .recording {
                    self.cancelDictation()
                }
                // Kill the audio engine — removes the orange mic indicator
                if self.audioEngine.isEngineRunning {
                    self.audioEngine.deactivateSession()
                }
                PersistentLog.log(.engineWarmUpFailed(context: "standby-power-off", error: "user stopped standby"))
            }
        }

        // Cancel any in-flight dictation when the audio session is interrupted
        // (phone call, Siri, etc.) or media services are reset. UnifiedAudioEngine
        // already tore down the engine; we just need to clean up the dictation
        // pipeline state and notify the keyboard that the recording failed
        // (issue #106).
        NotificationCenter.default.addObserver(
            forName: .dictusAudioSessionInterrupted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAudioInterruptionDuringDictation()
            }
        }

        // WHY observe didBecomeActive (not willEnterForeground):
        // willEnterForeground fires while the audio session is still interrupted.
        // didBecomeActive fires AFTER the app is fully active and the audio session
        // interruption has ended — the audio engine can safely start at this point.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                PersistentLog.log(.engineStateSnapshot(
                    engineRunning: self.audioEngine.isEngineRunning,
                    isRecording: self.audioEngine.isRecording,
                    hasWhisperKit: self.whisperKit != nil,
                    sessionConfigured: true,
                    context: "didBecomeActive"
                ))

                // Wall-clock backstop for Phase B's idle-release timer (issue #106).
                // If iOS suspended the main queue while we were backgrounded, the
                // asyncAfter scheduled in scheduleIdleRelease may fire late. On
                // foreground transition we have a reliable runloop again — this
                // call releases the warm state if the idle interval already
                // expired during the suspension. Must happen BEFORE warmUp below,
                // otherwise we'd warm an engine that should be released.
                self.audioEngine.enforceIdleReleaseIfDue()

                // Recover DI if it was lost (Activity.request fails from background on cold start).
                // Must happen BEFORE pendingColdStartDictation so transitionToRecording finds an activity.
                LiveActivityManager.shared.ensureActivityAlive()

                // Retry deferred cold start dictation now that app is fully active.
                // WHY here: URL scheme launches fire handleIncomingURL at .inactive state,
                // where engine.start() fails. startDictation sets pendingColdStartDictation
                // and returns. Now that we're .active, retry the full startDictation flow.
                if self.pendingColdStartDictation {
                    self.pendingColdStartDictation = false
                    // Only retry if keyboard is still waiting (watchdog hasn't reset to idle)
                    let keyboardStatus = self.defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil"
                    PersistentLog.log(.coldStartRetry(keyboardStatus: keyboardStatus))
                    if keyboardStatus == DictationStatus.requested.rawValue {
                        self.startDictation(fromURL: true)
                    }
                    return
                }

                guard !self.audioEngine.isEngineRunning else {
                    PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive-already-running"))
                    return
                }
                let modelReady = self.defaults.bool(forKey: SharedKeys.modelReady)
                guard modelReady else {
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive", error: "modelReady=false"))
                    return
                }

                do {
                    try self.audioEngine.configureAudioSession()
                    PersistentLog.log(.engineWarmUpAttempt(context: "didBecomeActive"))
                    self.setModelLoadState(.loading, reason: "didBecomeActive-warmup")
                    try await self.ensureEngineReady()
                    try self.audioEngine.warmUp()
                    PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive"))
                    self.setModelLoadState(.ready, reason: "didBecomeActive-success")
                } catch {
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive", error: error.localizedDescription))
                    self.setModelLoadState(.idle, reason: "didBecomeActive-failed")
                }
            }
        }
    }

    // MARK: - Public API

    /// Start the recording pipeline.
    /// Called from URL scheme (first time) or Darwin notification (subsequent times).
    ///
    /// Two paths:
    /// - WARM START: engine already running → purge idle samples + startRecording()
    /// - COLD START: engine not running → startRecording() starts it (<100ms) + load model in parallel
    ///
    /// - Parameter fromURL: If true, the app was opened via URL scheme from the keyboard.
    func startDictation(fromURL: Bool = false) {
        // Clear previous recording state before starting new recording.
        // WHY here (not in stopDictation): DI tap and lockscreen paths call
        // startDictation directly without going through stopDictation first.
        // The old result must be cleared regardless of entry path so
        // RecordingView never shows a stale transcription card.
        lastResult = nil
        bufferEnergy = []
        bufferSeconds = 0
        // Cancel any polish still running from the previous dictation (#141).
        PolishCoordinator.shared.cancelInflight()
        PersistentLog.log(.statusChanged(from: status.rawValue, to: "clearing-for-new", source: "startDictation-reset"))

        // Guard against duplicate calls while actively recording or transcribing.
        guard status == .idle || status == .failed || status == .ready || status == .requested else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Ignoring duplicate startDictation — already \(self.status.rawValue, privacy: .public)")
            }
            return
        }

        // WHY this early return (only for Darwin notification path, NOT URL scheme):
        // iOS forbids starting an audio engine from background. If the engine isn't
        // running and we're in background (Darwin notification from keyboard), attempting
        // to start will fail. The keyboard's fallback opens the URL scheme after 500ms.
        let appState = UIApplication.shared.applicationState
        if !fromURL && appState != .active && !audioEngine.isEngineRunning {
            PersistentLog.log(.dictationDeferred(reason: "no engine running, appState=\(appState.rawValue)"))
            return
        }

        PersistentLog.log(.dictationStarted(fromURL: fromURL, appState: "\(appState.rawValue)", engineRunning: audioEngine.isEngineRunning))

        // Check if a model is downloaded and ready.
        // Force a cross-process sync before reading — right after a URL-scheme wake
        // the App Group defaults can return a stale `false`, producing a bogus
        // "no model downloaded" error on the first attempt (observed in #102).
        defaults.synchronize()
        let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
        guard modelReady else {
            PersistentLog.log(.dictationFailed(error: "No model downloaded"))
            handleError("No model downloaded. Open Dictus to download a model.")
            return
        }

        // Refuse new dictation if an explicit model swap is in flight.
        // Issue #144: tapping the mic during a turbo load caused the keyboard to
        // queue dispatches that all collapsed into 3+ concurrent transcribe()
        // calls when the load resolved. Reading the App Group state lets us short-
        // circuit cleanly — the keyboard's overlay UI surfaces the wait to the user.
        //
        // Issue #167: URL-scheme cold-start launches arrive while the init-preload
        // is still loading the model. Failing here would route first-use dictation
        // into `failed` state. Skip the guard for fromURL=true and let the existing
        // cold-start defer at line ~368 park the request as `pendingColdStartDictation`
        // — the retry's `ensureEngineReady` awaits the in-flight initTask via its lock.
        let currentLoadState = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        if currentLoadState == ModelLoadState.loading.rawValue && !fromURL {
            PersistentLog.log(.dictationDeferred(reason: "model load in flight (state=loading)"))
            handleError(String(localized: "Model is loading. Please wait."))
            return
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        // Play start sound BEFORE configuring the audio session.
        // WHY before: Once the audio session is configured with .playAndRecord,
        // AudioServicesPlaySystemSound may be suppressed.
        SoundFeedbackService.playRecordStart()

        // Configure audio session NOW while we're in the foreground.
        try? audioEngine.configureAudioSession()

        if audioEngine.isEngineRunning {
            // WARM START: engine already running → purge + record (instant)
            dictationTask = Task {
                do {
                    let hasPermission = try await audioEngine.ensureMicrophonePermission()
                    guard hasPermission else {
                        handleError("Microphone permission denied")
                        return
                    }
                    updateStatus(.recording)
                    LiveActivityManager.shared.transitionToRecording()
                    try audioEngine.startRecording()
                    PersistentLog.log(.audioEngineStarted)
                    await verifyAudioFlow()
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Warm start: \(error.localizedDescription)"))
                    handleError(error.localizedDescription)
                }
            }
        } else {
            // COLD START: engine not running → start engine + record + load model in parallel
            //
            // WHY defer when not .active:
            // URL scheme launches fire handleIncomingURL while app is still .inactive.
            // AVAudioEngine.start() fails with AUIOClient_StartIO error from non-active state.
            // Deferring to didBecomeActive guarantees the app is fully active.
            if appState != .active {
                pendingColdStartDictation = true
                PersistentLog.log(.dictationDeferred(
                    reason: "cold start deferred to didBecomeActive, appState=\(appState.rawValue)"))
                return
            }

            dictationTask = Task {
                do {
                    let hasPermission = try await audioEngine.ensureMicrophonePermission()
                    guard hasPermission else {
                        handleError("Microphone permission denied")
                        return
                    }
                    try audioEngine.startRecording()
                    updateStatus(.recording)
                    LiveActivityManager.shared.transitionToRecording()
                    PersistentLog.log(.audioEngineStarted)
                    await verifyAudioFlow()

                    // Load the transcription model in parallel while recording
                    self.setModelLoadState(.loading, reason: "cold-start-load")
                    try await ensureEngineReady()
                    let loadedName = self.currentModelName ?? "unknown"
                    PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
                    self.setModelLoadState(.ready, reason: "cold-start-success")
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Cold start engine load: \(error.localizedDescription)"))
                    self.setModelLoadState(.idle, reason: "cold-start-failed")
                    self.handleError(error.localizedDescription)
                }
            }
        }
    }

    /// Called when user taps the stop button.
    /// Stops recording and starts transcription using the already-loaded model.
    ///
    /// Single path: collectSamples() (keeps engine alive) → transcribe → done.
    /// No more branching between AudioRecorder and RawAudioCapture.

    /// Minimum audio duration required for transcription (in seconds).
    /// WHY 0.5s: WhisperKit handles clips ≥0.5s reliably for short words (oui, non, ok).
    /// Below 0.5s, it tends to hallucinate (invent words not spoken).
    /// Previous value was 1.0s (Parakeet requirement), but Parakeet is no longer used
    /// in the dictation pipeline — only WhisperKit via keyboard.
    private let minimumRecordingDuration: TimeInterval = 0.5

    func stopDictation() {
        // Issue #144 re-entry guard: refuse if a transcription is already in flight.
        // Without this, tapping stop multiple times during a long model swap (e.g.
        // turbo load) spawned 3+ concurrent transcribe() calls that cancelled each
        // other with Swift.CancellationError. The flag is set synchronously here
        // (before the async Task) so a second stopDictation() can never slip past.
        guard !isTranscribingInFlight else {
            PersistentLog.log(.dictationDeferred(reason: "stop ignored — transcription already in flight"))
            return
        }
        isTranscribingInFlight = true

        dictationTask?.cancel()

        dictationTask = Task {
            defer { self.isTranscribingInFlight = false }
            do {
                let samples = audioEngine.collectSamples()

                guard !samples.isEmpty else {
                    handleError("No audio recorded")
                    return
                }

                let audioDuration = Double(samples.count) / 16000.0

                guard audioDuration >= minimumRecordingDuration else {
                    PersistentLog.log(.recordingTooShort(durationMs: Int(audioDuration * 1000)))
                    handleError("Recording too short")
                    return
                }

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording stopped. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", audioDuration), privacy: .public)s")
                }

                updateStatus(.transcribing)
                LiveActivityManager.shared.transitionToTranscribing()
                // Arm watchdog: if DI fails to leave .recording, force recovery after 10s.
                // If transitionToTranscribing succeeded, the watchdog's guard exits harmlessly.
                LiveActivityManager.shared.startRecordingWatchdog()
                SoundFeedbackService.playRecordStop()

                try await ensureEngineReady()
                let rawText = try await transcriptionService.transcribe(audioSamples: samples)

                // Polish layer (#141) — passes raw through when toggle off, when language
                // detection skips, when the engine throws/cancels, or when the guardrail rejects.
                let activeModelID = defaults.string(forKey: SharedKeys.activeModel) ?? ""
                let sttEngine = ModelInfo.forIdentifier(activeModelID)?.engine ?? .whisperKit
                let text = await PolishCoordinator.shared.polish(raw: rawText, sttEngine: sttEngine)

                // Append trailing separator so chained dictations don't stick together
                let finalText: String
                if let last = text.last, ".!?…".contains(last) {
                    finalText = text + " "
                } else {
                    finalText = text + ". "
                }

                // Write result to App Group
                lastResult = finalText
                status = .ready
                defaults.set(finalText, forKey: SharedKeys.lastTranscription)
                defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
                defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
                defaults.synchronize()

                DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
                LiveActivityManager.shared.endWithResult(preview: finalText)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Transcription complete: \(finalText, privacy: .private)")
                }

                cleanupRecordingKeys()
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                }
                handleError(error.localizedDescription)
            }
        }
    }

    /// Cancel the current dictation without transcribing.
    /// Called when the keyboard sends a cancel signal via Darwin notification.
    func cancelDictation() {
        dictationTask?.cancel()
        dictationTask = nil
        // Reset the transcribe re-entry flag so the next stop/cancel cycle can proceed.
        isTranscribingInFlight = false
        stopTranscriptionWatchdog()

        // Discard samples but keep engine alive for next recording
        _ = audioEngine.collectSamples()

        // Reset all state
        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()
        SoundFeedbackService.playRecordCancel()
        // Return Dynamic Island to standby (cancel = no transcription, go back to "On")
        Task { await LiveActivityManager.shared.returnToStandby() }
        // Arm watchdog: safety net if returnToStandby's guard rejects.
        LiveActivityManager.shared.startRecordingWatchdog()
        updateStatus(.idle)

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation cancelled by keyboard")
        }
    }

    /// Reset status to idle (e.g., after user returns to keyboard).
    func resetStatus() {
        updateStatus(.idle)
        // Keep lastResult so HomeView can display the last transcription card.
    }

    /// Handle an audio session interruption that fired while dictation was active.
    ///
    /// UnifiedAudioEngine has already stopped the engine and posted the in-process
    /// notification. We only need to clean up the dictation pipeline: cancel the
    /// in-flight task, drop accumulated samples, write a "failed" status to App
    /// Group so the keyboard's overlay closes, and notify the user via the Live
    /// Activity (LiveActivityManager handles its own end via the same notification).
    /// Issue #106.
    private func handleAudioInterruptionDuringDictation() {
        let wasActive = (status == .recording || status == .requested || status == .transcribing)
        guard wasActive else {
            // Engine died while idle — nothing to roll back. The standby DI is
            // dismissed by LiveActivityManager via the same notification.
            return
        }

        dictationTask?.cancel()
        dictationTask = nil
        isTranscribingInFlight = false
        stopTranscriptionWatchdog()

        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()

        // updateStatus(.failed) handles both the App Group write and the Darwin
        // statusChanged post — no manual duplication needed (issue #106 review).
        updateStatus(.failed)

        if #available(iOS 14.0, *) {
            DictusLogger.app.warning("Dictation cancelled by audio session interruption")
        }
    }

    // MARK: - Private Helpers

    /// Register Darwin notification observers for keyboard stop/cancel signals.
    private func observeKeyboardSignals() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.stopRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let requested = self.defaults.bool(forKey: SharedKeys.stopRequested)
                if requested {
                    self.defaults.set(false, forKey: SharedKeys.stopRequested)
                    self.defaults.synchronize()
                    self.stopDictation()
                }
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.cancelRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let requested = self.defaults.bool(forKey: SharedKeys.cancelRequested)
                if requested {
                    self.defaults.set(false, forKey: SharedKeys.cancelRequested)
                    self.defaults.synchronize()
                    self.cancelDictation()
                }
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let appState = UIApplication.shared.applicationState
                PersistentLog.log(.engineDarwinStartReceived(
                    appState: "\(appState.rawValue)",
                    engineRunning: self.audioEngine.isEngineRunning
                ))
                self.startDictation()
            }
        }
    }

    /// Forward waveform energy data to App Group for the keyboard extension to display.
    /// Throttled to ~5Hz (every 200ms) to avoid overwhelming UserDefaults.
    private func forwardWaveformToAppGroup(energy: [Float]) {
        guard status == .recording else { return }

        let now = Date()
        guard now.timeIntervalSince(lastWaveformWriteDate) >= 0.2 else { return }
        lastWaveformWriteDate = now

        let cappedEnergy = Array(energy.suffix(30))
        if let data = try? JSONEncoder().encode(cappedEnergy) {
            defaults.set(data, forKey: SharedKeys.waveformEnergy)
        }
        defaults.set(bufferSeconds, forKey: SharedKeys.recordingElapsedSeconds)
        defaults.synchronize()

        DarwinNotificationCenter.post(DarwinNotificationName.waveformUpdate)
    }

    /// Clean up recording-related App Group keys after recording completes or is cancelled.
    private func cleanupRecordingKeys() {
        // NOTE: Do NOT clear lastTranscription here — the keyboard extension reads it
        // asynchronously via Darwin notification. Clearing it here would race with the
        // keyboard and delete the transcription before it can be inserted.
        // Stale transcriptions are cleaned up on app launch (5-min threshold in init).
        defaults.removeObject(forKey: SharedKeys.waveformEnergy)
        defaults.removeObject(forKey: SharedKeys.recordingElapsedSeconds)
        defaults.removeObject(forKey: SharedKeys.recordingHeartbeat)
        defaults.set(false, forKey: SharedKeys.stopRequested)
        defaults.set(false, forKey: SharedKeys.cancelRequested)
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        defaults.synchronize()
    }

    /// Initialize the appropriate STT engine based on the active model.
    ///
    /// WHY engine-aware:
    /// The user can select either a WhisperKit or Parakeet model. This method
    /// checks the active model's engine type and initializes the correct engine.
    ///
    /// Falls back to the active model from App Group, then to "openai_whisper-small".
    private func ensureEngineReady(preferredModel: String? = nil) async throws {
        let modelName = preferredModel
            ?? defaults.string(forKey: SharedKeys.activeModel)
            ?? "openai_whisper-small"

        let modelInfo = ModelInfo.forIdentifier(modelName)
        let engine = modelInfo?.engine ?? .whisperKit

        switch engine {
        case .parakeet:
            try await ensureParakeetReady(modelName: modelName)
        case .whisperKit:
            try await ensureWhisperKitEngineReady(modelName: modelName)
        }
    }

    /// Initialize WhisperKit with the preferred model if not already loaded.
    private func ensureWhisperKitEngineReady(modelName: String) async throws {
        if whisperKit != nil, currentModelName == modelName {
            return
        }

        if let existingTask = initTask {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Engine init already in progress — awaiting existing task")
            }
            try await existingTask.value
            return
        }

        let task = Task<Void, Error> {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Initializing WhisperKit with model: \(modelName, privacy: .public)")
            }

            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                prewarm: true,
                load: true,
                download: true
            )

            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.currentModelName = modelName

            // Share with TranscriptionService only — UnifiedAudioEngine doesn't need WhisperKit
            transcriptionService.prepare(whisperKit: kit)

            let whisperKitEngine = WhisperKitEngine()
            whisperKitEngine.setWhisperKit(kit)
            transcriptionService.prepare(engine: whisperKitEngine)

            if #available(iOS 14.0, *) {
                DictusLogger.app.info("WhisperKit ready with model: \(modelName, privacy: .public)")
            }
        }
        initTask = task

        do {
            try await task.value
            initTask = nil
        } catch {
            initTask = nil
            throw error
        }
    }

    /// Initialize Parakeet engine (iOS 17+ only).
    private func ensureParakeetReady(modelName: String) async throws {
        if currentModelName == modelName, whisperKit == nil {
            return
        }

        if #available(iOS 17.0, *) {
            if let existingTask = initTask {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Parakeet init already in progress — awaiting existing task")
                }
                try await existingTask.value
                return
            }

            let task = Task<Void, Error> {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Initializing ParakeetEngine for model: \(modelName, privacy: .public)")
                }

                let parakeetEngine = ParakeetEngine()
                try await parakeetEngine.prepare(modelIdentifier: modelName)

                self.whisperKit = nil
                self.currentModelName = modelName

                transcriptionService.prepare(engine: parakeetEngine)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("ParakeetEngine ready for model: \(modelName, privacy: .public)")
                }
            }
            initTask = task

            do {
                try await task.value
                initTask = nil
            } catch {
                initTask = nil
                throw error
            }
        } else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("Parakeet not available on iOS 16 — falling back to WhisperKit small")
            }
            try await ensureWhisperKitEngineReady(modelName: "openai_whisper-small")
        }
    }

    /// Reads the list of downloaded model identifiers from App Group UserDefaults.
    private func readDownloadedModels() -> [String] {
        guard let data = defaults.data(forKey: SharedKeys.downloadedModels),
              let models = try? JSONDecoder().decode([String].self, from: data) else {
            if let active = defaults.string(forKey: SharedKeys.activeModel) {
                return [active]
            }
            return []
        }
        return models
    }

    // MARK: - Transcription Watchdog

    private func startTranscriptionWatchdog() {
        stopTranscriptionWatchdog()
        transcriptionWatchdog = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.status == .transcribing else { return }
                PersistentLog.log(.watchdogReset(source: "appTranscription", staleState: "transcribing"))
                self.cancelDictation()
            }
        }
    }

    private func stopTranscriptionWatchdog() {
        transcriptionWatchdog?.invalidate()
        transcriptionWatchdog = nil
    }

    /// Write dictation status to App Group so the keyboard can observe it.
    private func updateStatus(_ newStatus: DictationStatus) {
        let oldStatus = status
        PersistentLog.log(.statusChanged(from: oldStatus.rawValue, to: newStatus.rawValue, source: "coordinator"))
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()

        if newStatus == .transcribing {
            startTranscriptionWatchdog()
        } else if oldStatus == .transcribing {
            stopTranscriptionWatchdog()
        }

        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Verify audio samples are actually being captured after startRecording.
    /// Detects "zombie engine" state where engine.isRunning but tap receives no buffers.
    /// If 0 samples after 2s, force-restarts the engine and retries once.
    private func verifyAudioFlow() async {
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch { return } // Task cancelled (user stopped recording)

        guard status == .recording else { return }

        let sampleCount = audioEngine.currentSampleCount
        if sampleCount > 0 { return } // Healthy — samples flowing

        PersistentLog.log(.dictationFailed(error: "Zombie engine: 0 samples after 2s, force-restarting"))

        // Force restart: stop engine, reconfigure, restart
        audioEngine.forceRestart()
        do {
            try audioEngine.startRecording()
        } catch {
            handleError("Micro indisponible. Relancez l'application.")
            return
        }

        // Check again after restart
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch { return }

        guard status == .recording else { return }

        if audioEngine.currentSampleCount == 0 {
            handleError("Micro indisponible. Relancez l'application.")
        } else {
            PersistentLog.log(.engineWarmUpSuccess(context: "zombie-recovery"))
        }
    }

    /// Handle errors by updating status and writing error to App Group.
    private func handleError(_ message: String) {
        defaults.set(message, forKey: SharedKeys.lastError)
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        defaults.synchronize()
        updateStatus(.failed)
        LiveActivityManager.shared.endWithFailure()
        // Arm watchdog: safety net if endWithFailure's transition guard rejects.
        LiveActivityManager.shared.startRecordingWatchdog()
    }

    // MARK: - Model load orchestration (issue #144)

    /// Read the current persisted model load state from the App Group.
    /// SwiftUI views read this through NotificationCenter posts emitted by
    /// `setModelLoadState` (see `Notification.Name.dictusModelLoadStateChanged`).
    var modelLoadState: ModelLoadState {
        let raw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        return ModelLoadState(rawValue: raw) ?? .idle
    }

    /// Update the tri-state load flag, persist it to the App Group so the keyboard
    /// can gate mic taps, and broadcast a notification so any in-app overlay can react.
    /// Must be called on the main actor (the class is @MainActor).
    func setModelLoadState(_ newState: ModelLoadState, reason: String) {
        let oldRaw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        guard oldRaw != newState.rawValue else { return }
        defaults.set(newState.rawValue, forKey: SharedKeys.modelLoadState)
        defaults.synchronize()
        PersistentLog.log(.modelLoadStateChanged(from: oldRaw, to: newState.rawValue, reason: reason))
        NotificationCenter.default.post(
            name: .dictusModelLoadStateChanged,
            object: nil,
            userInfo: ["state": newState.rawValue, "reason": reason]
        )
    }

    /// Eagerly load the active model into RAM. Called from `ModelManager.selectModel`
    /// after a model swap so the user does not have to wait for the first mic tap to
    /// trigger the lazy load (issue #144 — turbo swap took 1-3 minutes which collapsed
    /// into a cancellation storm without this proactive path).
    ///
    /// Safe to call repeatedly: the underlying `initTask` lock dedupes concurrent loads.
    func preloadActiveModel() {
        Task {
            self.setModelLoadState(.loading, reason: "selectModel-proactive")
            do {
                try await ensureEngineReady()
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                self.setModelLoadState(.ready, reason: "selectModel-proactive-success")
            } catch {
                PersistentLog.log(.engineWarmUpFailed(
                    context: "selectModel-proactive",
                    error: error.localizedDescription
                ))
                self.setModelLoadState(.idle, reason: "selectModel-proactive-failed")
            }
        }
    }
}

extension Notification.Name {
    /// Posted by `DictationCoordinator.setModelLoadState` whenever the persisted
    /// `SharedKeys.modelLoadState` changes. UI overlays observe this to dismiss
    /// themselves once the model is `.ready` (issue #144).
    static let dictusModelLoadStateChanged = Notification.Name("DictusModelLoadStateChanged")
}
