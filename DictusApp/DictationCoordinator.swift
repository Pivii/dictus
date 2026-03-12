// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via AudioRecorder + transcription via TranscriptionService.
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

    /// Forwarded from AudioRecorder for waveform visualization in RecordingView.
    @Published var bufferEnergy: [Float] = []

    /// Forwarded from AudioRecorder for elapsed time display in RecordingView.
    @Published var bufferSeconds: Double = 0

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()

    /// Lightweight audio capture for cold start recording while WhisperKit loads.
    /// WHY: On cold start, WhisperKit takes 3-4s to initialize. RawAudioCapture uses
    /// a plain AVAudioEngine to start recording in <100ms. Samples are later passed
    /// to WhisperKit's transcribe(audioArray:) once it finishes loading.
    private let rawCapture = RawAudioCapture()

    /// Transcription timeout watchdog: fires after 30s in .transcribing state.
    /// WHY 30s: WhisperKit transcription of a typical dictation (<60s audio) should
    /// complete in under 10s even on older devices. 30s provides generous margin
    /// while still catching genuinely stuck transcriptions.
    private var transcriptionWatchdog: Timer?

    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private var dictationTask: Task<Void, Never>?

    /// Task that resolves when WhisperKit is fully loaded.
    /// WHY: Both init() pre-load and startDictation() call ensureEngineReady().
    /// If startDictation() arrives while pre-load is still running, it must AWAIT
    /// the ongoing init instead of starting a duplicate one. This Task acts as
    /// a concurrency lock — the first caller creates it, subsequent callers await it.
    private var initTask: Task<Void, Error>?

    /// Timestamp of last waveform write to App Group.
    /// Used to throttle writes to ~5Hz (every 200ms) to avoid overwhelming UserDefaults
    /// with high-frequency updates from the audio recorder's energy callback.
    private var lastWaveformWriteDate = Date.distantPast

    /// Combine subscription forwarding AudioRecorder's published values to coordinator.
    ///
    /// WHY Combine sink instead of direct observation:
    /// AudioRecorder is a separate ObservableObject. We need to forward its @Published
    /// properties to DictationCoordinator's @Published properties so RecordingView can
    /// observe a single source of truth (the coordinator).
    private var energyCancellable: AnyCancellable?
    private var secondsCancellable: AnyCancellable?

    /// Combine subscriptions for RawAudioCapture (used during cold start).
    private var rawEnergyCancellable: AnyCancellable?
    private var rawSecondsCancellable: AnyCancellable?

    private init() {
        // Forward AudioRecorder's energy levels and seconds to coordinator.
        // NOTE: App Group forwarding for the keyboard is now handled directly from
        // the audio thread in AudioRecorder's startRecordingLive callback.
        energyCancellable = audioRecorder.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                self?.bufferEnergy = energy
            }
        secondsCancellable = audioRecorder.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.bufferSeconds = seconds
            }

        // Forward RawAudioCapture's energy and seconds (used during cold start recording).
        // NOTE: App Group forwarding for the keyboard is handled directly from the audio
        // thread in RawAudioCapture.processBuffer (bypasses main thread throttling in bg).
        // This sink only updates the coordinator's @Published properties for in-app UI.
        rawEnergyCancellable = rawCapture.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                guard let self, self.rawCapture.isCapturing else { return }
                self.bufferEnergy = energy
            }
        rawSecondsCancellable = rawCapture.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                guard let self, self.rawCapture.isCapturing else { return }
                self.bufferSeconds = seconds
            }

        // Observe keyboard-initiated stop/cancel signals via Darwin notifications.
        //
        // WHY Darwin notifications for keyboard -> app signaling:
        // The keyboard extension runs in a separate process. It cannot call methods
        // on DictationCoordinator directly. Instead, it sets a Bool flag in App Group
        // UserDefaults and posts a Darwin notification. The app observes the notification,
        // reads the flag, resets it, and acts.
        observeKeyboardSignals()

        // Pre-load WhisperKit + audio session eagerly on app launch.
        // WHY: The first recording via URL scheme takes 4-5s if we load lazily.
        // By loading in init(), the model is ready when the keyboard triggers dictation.
        // The user sees the app briefly (iOS standard "◄ Back" in status bar),
        // but recording starts instantly instead of waiting for model loading.
        //
        // WHY configure audio session BEFORE the Task:
        // iOS forbids AVAudioSession.setActive(true) from background. The async Task
        // may not run until after the app is backgrounded (e.g., when opened via URL
        // scheme from the keyboard). By configuring synchronously in init(), we guarantee
        // the session is active while the app is still in the foreground.
        try? audioRecorder.configureAudioSession()

        Task {
            let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
            guard modelReady else { return }

            do {
                try await ensureEngineReady()
                PersistentLog.log(.engineWarmUpAttempt(context: "init-preload"))
                try audioRecorder.warmUp()
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
            } catch {
                PersistentLog.log(.engineWarmUpFailed(context: "init-preload-audioRecorder", error: error.localizedDescription))
                // Fallback: warm up RawAudioCapture if AudioRecorder can't (Parakeet model)
                do {
                    try rawCapture.warmUp()
                    PersistentLog.log(.engineWarmUpSuccess(context: "init-preload-rawCapture-fallback"))
                    PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                } catch {
                    PersistentLog.log(.engineWarmUpFailed(context: "init-preload-rawCapture", error: error.localizedDescription))
                }
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
                    engineRunning: self.audioRecorder.isEngineRunning,
                    isRecording: self.audioRecorder.isRecording,
                    hasWhisperKit: self.whisperKit != nil,
                    sessionConfigured: true, // can't access private, but session was configured in init
                    context: "didBecomeActive"
                ))
                guard !self.audioRecorder.isEngineRunning && !self.rawCapture.isEngineRunning else {
                    PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive-already-running"))
                    return
                }
                let modelReady = self.defaults.bool(forKey: SharedKeys.modelReady)
                guard modelReady else {
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive", error: "modelReady=false"))
                    return
                }

                do {
                    try self.audioRecorder.configureAudioSession()
                    PersistentLog.log(.engineWarmUpAttempt(context: "didBecomeActive"))
                    try await self.ensureEngineReady()
                    try self.audioRecorder.warmUp()
                    PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive"))
                } catch {
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive-audioRecorder", error: error.localizedDescription))
                    // Fallback: if AudioRecorder can't warm up (Parakeet model = no WhisperKit),
                    // warm up RawAudioCapture instead to keep an engine alive in background.
                    do {
                        try self.rawCapture.warmUp()
                        PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive-rawCapture-fallback"))
                    } catch {
                        PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive-rawCapture-fallback", error: error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Public API

    /// Start the recording pipeline.
    /// Called from URL scheme (first time) or Darwin notification (subsequent times).
    ///
    /// - Parameter fromURL: If true, the app was opened via URL scheme from the keyboard.
    ///   On cold start, this triggers auto-background after 0.5s so the user returns
    ///   to the keyboard automatically while recording continues in background.
    func startDictation(fromURL: Bool = false) {
        // Guard against duplicate calls while actively recording or transcribing.
        // Allow .ready (previous transcription just finished) and .idle — both are valid
        // states to start a new recording from.
        guard status == .idle || status == .failed || status == .ready || status == .requested else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Ignoring duplicate startDictation — already \(self.status.rawValue)")
            }
            return
        }

        // WHY this early return (only for Darwin notification path, NOT URL scheme):
        // iOS forbids starting an audio engine from background. If the engine isn't
        // running and we're in background (Darwin notification from keyboard), attempting
        // to start will fail. By returning early WITHOUT changing status, the keyboard's
        // dictationStatus stays ".requested". After 500ms, the keyboard's fallback opens
        // the dictus:// URL scheme, which brings the app to foreground. Then
        // handleIncomingURL calls startDictation() again — this time from foreground.
        //
        // WHY NOT when fromURL:
        // When opened via URL scheme, the app IS transitioning to foreground, but
        // applicationState may still be .inactive (not yet .active). Returning early
        // here would prevent cold start recording entirely. RawAudioCapture doesn't
        // need audioRecorder's engine — it has its own AVAudioEngine.
        let appState = UIApplication.shared.applicationState
        let anyEngineRunning = audioRecorder.isEngineRunning || rawCapture.isEngineRunning
        if !fromURL && appState != .active && !anyEngineRunning {
            PersistentLog.log(.dictationDeferred(reason: "no engine running, appState=\(appState.rawValue)"))
            return
        }

        PersistentLog.log(.dictationStarted(fromURL: fromURL, appState: "\(appState.rawValue)", engineRunning: anyEngineRunning))

        // Check if a model is downloaded and ready
        let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
        guard modelReady else {
            PersistentLog.log(.dictationFailed(error: "No model downloaded"))
            handleError("No model downloaded. Open Dictus to download a model.")
            return
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        // Configure audio session NOW while we're in the foreground.
        // WHY before the Task: ensureEngineReady() takes 4-5s on cold start.
        // By then the app may be backgrounded (opened via URL from keyboard).
        // iOS forbids setActive(true) from background, so this must happen first.
        try? audioRecorder.configureAudioSession()

        // Determine which recording path to use:
        // 1. WARM WhisperKit: AudioRecorder engine running → purge + collect (fastest)
        // 2. WARM Parakeet: RawAudioCapture engine running → purge + collect (fast)
        // 3. COLD: Neither engine running → start RawAudioCapture + load engine in parallel
        let useWhisperKitWarm = whisperKit != nil && audioRecorder.isEngineRunning
        let useRawCaptureWarm = rawCapture.isEngineRunning && !useWhisperKitWarm

        if useWhisperKitWarm {
            // WARM START PATH: WhisperKit already loaded, engine running
            dictationTask = Task {
                do {
                    let hasPermission = try await audioRecorder.ensureMicrophonePermission()
                    guard hasPermission else {
                        handleError("Microphone permission denied")
                        return
                    }
                    updateStatus(.recording)
                    try audioRecorder.startRecording()
                    PersistentLog.log(.audioEngineStarted)
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Warm WhisperKit start: \(error.localizedDescription)"))
                    handleError(error.localizedDescription)
                }
            }
        } else if useRawCaptureWarm {
            // WARM PARAKEET PATH: RawAudioCapture engine already running
            // Purge idle samples and start collecting fresh audio.
            dictationTask = Task {
                do {
                    let hasPermission = try await audioRecorder.ensureMicrophonePermission()
                    guard hasPermission else {
                        handleError("Microphone permission denied")
                        return
                    }
                    rawCapture.purgeIdleSamples()
                    updateStatus(.recording)
                    PersistentLog.log(.audioEngineStarted)
                    PersistentLog.log(.engineStateSnapshot(
                        engineRunning: rawCapture.isEngineRunning,
                        isRecording: true,
                        hasWhisperKit: whisperKit != nil,
                        sessionConfigured: true,
                        context: "warm-parakeet-start"
                    ))
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Warm Parakeet start: \(error.localizedDescription)"))
                    handleError(error.localizedDescription)
                }
            }
        } else {
            // COLD START PATH: No engine running — use RawAudioCapture + load engine in parallel
            dictationTask = Task {
                do {
                    let hasPermission = try await audioRecorder.ensureMicrophonePermission()
                    guard hasPermission else {
                        handleError("Microphone permission denied")
                        return
                    }
                    try rawCapture.startCapture()
                    updateStatus(.recording)
                    PersistentLog.log(.audioEngineStarted)

                    try await ensureEngineReady()
                    let loadedName = self.currentModelName ?? "unknown"
                    PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Cold start engine load: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Called when user taps the stop button.
    /// Stops recording and starts transcription using the already-loaded model.
    ///
    /// Two paths:
    /// - **RawAudioCapture active** (cold start): stop raw capture, ensure WhisperKit is ready,
    ///   transcribe the raw samples, then warm up audioRecorder for subsequent recordings.
    /// - **AudioRecorder active** (warm start): collect samples from WhisperKit's AudioProcessor
    ///   and transcribe (existing flow).
    /// Minimum audio duration required for transcription (in seconds).
    /// WHY 1.0s: Parakeet requires at least 1 second of 16kHz audio.
    /// WhisperKit also produces garbage on very short clips. Enforcing this
    /// prevents the cascade: short clip → transcription error → user retaps
    /// rapidly → even shorter clips → more errors.
    private let minimumRecordingDuration: TimeInterval = 1.0

    func stopDictation() {
        dictationTask?.cancel()

        dictationTask = Task {
            do {
                let samples: [Float]

                if rawCapture.isCapturing {
                    // RAWCAPTURE PATH: audio was captured via RawAudioCapture.
                    // Use collectSamples (keep engine alive) when Parakeet is active,
                    // stopCapture (kill engine) when WhisperKit will take over.
                    let isParakeetActive = self.whisperKit == nil
                    if isParakeetActive {
                        samples = rawCapture.collectSamples()
                    } else {
                        samples = rawCapture.stopCapture()
                    }

                    guard !samples.isEmpty else {
                        handleError("No audio recorded")
                        return
                    }

                    let audioDuration = Double(samples.count) / 16000.0

                    // Reject recordings shorter than minimum duration.
                    // WHY here (not in the keyboard): The keyboard doesn't know the actual
                    // sample count — only the app has the audio data. Checking here prevents
                    // Parakeet's "Invalid audio data" error and gives a friendly message.
                    guard audioDuration >= minimumRecordingDuration else {
                        PersistentLog.log(.recordingTooShort(durationMs: Int(audioDuration * 1000)))
                        handleError("Recording too short")
                        return
                    }

                    PersistentLog.log(.engineStateSnapshot(
                        engineRunning: rawCapture.isEngineRunning,
                        isRecording: rawCapture.isCapturing,
                        hasWhisperKit: !isParakeetActive,
                        sessionConfigured: true,
                        context: "stop-rawCapture-samples=\(samples.count)-dur=\(String(format: "%.1f", audioDuration))s"
                    ))

                    updateStatus(.transcribing)
                    try await ensureEngineReady()

                    let text = try await transcriptionService.transcribe(audioSamples: samples)

                    // Warm up the appropriate engine for subsequent recordings.
                    if isParakeetActive {
                        // Parakeet: RawAudioCapture still alive (collectSamples kept it running).
                        PersistentLog.log(.engineWarmUpSuccess(context: "post-stop-parakeet-rawCapture-alive"))
                    } else {
                        // WhisperKit: warm up AudioRecorder, RawAudioCapture was stopped.
                        PersistentLog.log(.engineWarmUpAttempt(context: "post-coldstart-transcription"))
                        do {
                            try audioRecorder.warmUp()
                            PersistentLog.log(.engineWarmUpSuccess(context: "post-coldstart-transcription"))
                        } catch {
                            PersistentLog.log(.engineWarmUpFailed(context: "post-coldstart-transcription", error: error.localizedDescription))
                        }
                    }

                    // Write result to App Group
                    lastResult = text
                    status = .ready
                    defaults.set(text, forKey: SharedKeys.lastTranscription)
                    defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
                    defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
                    defaults.synchronize()

                    DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                    DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)

                    if #available(iOS 14.0, *) {
                        DictusLogger.app.info("Transcription complete: \(text)")
                    }

                    cleanupRecordingKeys()
                } else {
                    // WARM START PATH: existing flow via WhisperKit's AudioProcessor
                    samples = audioRecorder.collectSamples()

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
                        DictusLogger.app.info("Recording stopped. Samples: \(samples.count), Duration: \(String(format: "%.1f", audioDuration))s")
                    }

                    // Transcribe with the already-loaded model (no model switching).
                    updateStatus(.transcribing)
                    let text = try await transcriptionService.transcribe(audioSamples: samples)

                    // Write result to App Group
                    lastResult = text
                    status = .ready
                    defaults.set(text, forKey: SharedKeys.lastTranscription)
                    defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
                    defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
                    defaults.synchronize()

                    DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                    DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)

                    if #available(iOS 14.0, *) {
                        DictusLogger.app.info("Transcription complete: \(text)")
                    }

                    cleanupRecordingKeys()
                }
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Transcription failed: \(error.localizedDescription)")
                }
                handleError(error.localizedDescription)
            }
        }
    }

    /// Cancel the current dictation without transcribing.
    /// Called when the keyboard sends a cancel signal via Darwin notification.
    ///
    /// WHY cancel is different from stop:
    /// Stop triggers transcription of recorded audio. Cancel discards everything —
    /// the user changed their mind and doesn't want any text inserted.
    func cancelDictation() {
        dictationTask?.cancel()
        dictationTask = nil
        stopTranscriptionWatchdog()

        if rawCapture.isCapturing {
            let isParakeetActive = whisperKit == nil
            if isParakeetActive {
                // Parakeet: discard samples but keep engine alive
                _ = rawCapture.collectSamples()
                PersistentLog.log(.engineWarmUpSuccess(context: "post-cancel-parakeet-rawCapture-alive"))
            } else {
                // WhisperKit: stop raw capture, warm up AudioRecorder
                _ = rawCapture.stopCapture()
                PersistentLog.log(.engineWarmUpAttempt(context: "post-cancel-coldstart"))
                do {
                    try audioRecorder.warmUp()
                    PersistentLog.log(.engineWarmUpSuccess(context: "post-cancel-coldstart"))
                } catch {
                    PersistentLog.log(.engineWarmUpFailed(context: "post-cancel-coldstart", error: error.localizedDescription))
                }
            }
        } else {
            // Warm start path: discard samples but keep engine alive for next recording.
            _ = audioRecorder.collectSamples()
        }

        // Reset all state
        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()
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

    // MARK: - Private Helpers

    /// Register Darwin notification observers for keyboard stop/cancel signals.
    ///
    /// WHY nonisolated(unsafe) and DispatchQueue.main.async:
    /// Darwin notification callbacks fire on an arbitrary thread (they use C function pointers).
    /// DictationCoordinator is @MainActor, so we must hop back to the main thread before
    /// accessing any properties or calling methods.
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

        // Observe keyboard-initiated start recording signal.
        // WHY: When the app is already running in background, the keyboard can trigger
        // recording via Darwin notification instead of opening the URL scheme. This avoids
        // bringing the app to the foreground — the user stays in their current app.
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let appState = UIApplication.shared.applicationState
                PersistentLog.log(.engineDarwinStartReceived(
                    appState: "\(appState.rawValue)",
                    engineRunning: self.audioRecorder.isEngineRunning
                ))
                self.startDictation()
            }
        }
    }

    /// Forward waveform energy data to App Group for the keyboard extension to display.
    /// Throttled to ~5Hz (every 200ms) to avoid overwhelming UserDefaults.
    ///
    /// WHY throttle to 5Hz:
    /// AudioRecorder publishes energy updates at ~60Hz (every audio buffer callback).
    /// Writing to UserDefaults + synchronize + Darwin notification at 60Hz would cause
    /// excessive disk I/O and cross-process overhead. 5Hz provides smooth-enough waveform
    /// animation in the keyboard while keeping overhead minimal.
    private func forwardWaveformToAppGroup(energy: [Float]) {
        // Only forward during active recording
        guard status == .recording else { return }

        // Throttle: only write if 200ms+ since last write
        let now = Date()
        guard now.timeIntervalSince(lastWaveformWriteDate) >= 0.2 else { return }
        lastWaveformWriteDate = now

        // Cap to 30 values (one per waveform bar) before encoding.
        // WHY: AudioRecorder already sends .suffix(30), but this is a safety cap
        // to ensure the keyboard never receives oversized arrays.
        let cappedEnergy = Array(energy.suffix(30))

        // Encode energy as JSON and write to App Group
        if let data = try? JSONEncoder().encode(cappedEnergy) {
            defaults.set(data, forKey: SharedKeys.waveformEnergy)
        }
        defaults.set(bufferSeconds, forKey: SharedKeys.recordingElapsedSeconds)
        defaults.synchronize()

        // Signal keyboard that new waveform data is available
        DarwinNotificationCenter.post(DarwinNotificationName.waveformUpdate)
    }

    /// Clean up recording-related App Group keys after recording completes or is cancelled.
    /// Safety reset to prevent stale data from being read by the keyboard extension.
    private func cleanupRecordingKeys() {
        defaults.removeObject(forKey: SharedKeys.waveformEnergy)
        defaults.removeObject(forKey: SharedKeys.recordingElapsedSeconds)
        defaults.removeObject(forKey: SharedKeys.recordingHeartbeat)
        defaults.set(false, forKey: SharedKeys.stopRequested)
        defaults.set(false, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
    }

    /// Initialize the appropriate STT engine based on the active model.
    ///
    /// WHY engine-aware:
    /// The user can select either a WhisperKit or Parakeet model. This method
    /// checks the active model's engine type and initializes the correct engine.
    /// For WhisperKit models, it uses the existing WhisperKit initialization path.
    /// For Parakeet models (iOS 17+ only), it creates a ParakeetEngine.
    ///
    /// Falls back to the active model from App Group, then to "openai_whisper-small".
    /// Handles lazy initialization and model switching if the user changes model.
    private func ensureEngineReady(preferredModel: String? = nil) async throws {
        let modelName = preferredModel
            ?? defaults.string(forKey: SharedKeys.activeModel)
            ?? "openai_whisper-small"

        // Resolve the model's engine type from the catalog
        let modelInfo = ModelInfo.forIdentifier(modelName)
        let engine = modelInfo?.engine ?? .whisperKit

        // Route to the correct engine initialization
        switch engine {
        case .parakeet:
            try await ensureParakeetReady(modelName: modelName)
        case .whisperKit:
            try await ensureWhisperKitEngineReady(modelName: modelName)
        }
    }

    /// Initialize WhisperKit with the preferred model if not already loaded.
    private func ensureWhisperKitEngineReady(modelName: String) async throws {
        // If WhisperKit is already loaded with the same model, reuse it
        if whisperKit != nil, currentModelName == modelName {
            return
        }

        // If an init is already in progress (e.g., pre-load from init()),
        // await it instead of starting a duplicate initialization.
        if let existingTask = initTask {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Engine init already in progress — awaiting existing task")
            }
            try await existingTask.value
            return
        }

        // Create and store the init task so concurrent callers can await it
        let task = Task<Void, Error> {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Initializing WhisperKit with model: \(modelName)")
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

            // Share the instance with AudioRecorder and TranscriptionService
            audioRecorder.prepare(whisperKit: kit)
            transcriptionService.prepare(whisperKit: kit)

            // Also set up the WhisperKitEngine as the active protocol engine
            let whisperKitEngine = WhisperKitEngine()
            whisperKitEngine.setWhisperKit(kit)
            transcriptionService.prepare(engine: whisperKitEngine)

            if #available(iOS 14.0, *) {
                DictusLogger.app.info("WhisperKit ready with model: \(modelName)")
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
    ///
    /// WHY separate from WhisperKit initialization:
    /// Parakeet uses a completely different SDK (FluidAudio) with its own download,
    /// compilation, and transcription pipeline. It cannot share WhisperKit's
    /// AudioProcessor or audio engine. On cold start with Parakeet, we still use
    /// RawAudioCapture for instant recording, then transcribe via ParakeetEngine.
    private func ensureParakeetReady(modelName: String) async throws {
        // Already loaded with same model
        if currentModelName == modelName, whisperKit == nil {
            // Parakeet doesn't use whisperKit, so nil whisperKit + matching model = already ready
            return
        }

        if #available(iOS 17.0, *) {
            // If an init is already in progress, await it
            if let existingTask = initTask {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Parakeet init already in progress — awaiting existing task")
                }
                try await existingTask.value
                return
            }

            let task = Task<Void, Error> {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Initializing ParakeetEngine for model: \(modelName)")
                }

                let parakeetEngine = ParakeetEngine()
                try await parakeetEngine.prepare(modelIdentifier: modelName)

                // Clear WhisperKit references since we're using Parakeet now
                self.whisperKit = nil
                self.currentModelName = modelName

                // Set ParakeetEngine as active transcription engine
                transcriptionService.prepare(engine: parakeetEngine)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("ParakeetEngine ready for model: \(modelName)")
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
            // iOS 16: Parakeet is not available, fall back to WhisperKit small
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("Parakeet not available on iOS 16 — falling back to WhisperKit small")
            }
            try await ensureWhisperKitEngineReady(modelName: "openai_whisper-small")
        }
    }

    /// Reads the list of downloaded model identifiers from App Group UserDefaults.
    ///
    /// WHY read from App Group instead of holding a ModelManager reference:
    /// Loose coupling — the coordinator doesn't need to know about ModelManager's
    /// UI state or lifecycle. It only needs the list of available models, which
    /// ModelManager persists to the shared App Group. This also means the keyboard
    /// extension could use the same pattern in the future.
    private func readDownloadedModels() -> [String] {
        guard let data = defaults.data(forKey: SharedKeys.downloadedModels),
              let models = try? JSONDecoder().decode([String].self, from: data) else {
            // Fallback: if no models stored yet, check for active model
            if let active = defaults.string(forKey: SharedKeys.activeModel) {
                return [active]
            }
            return []
        }
        return models
    }

    // MARK: - Transcription Watchdog

    /// Start a one-shot 30s timer that auto-cancels if transcription hangs.
    /// WHY non-repeating: We only need one fire — if transcription hasn't
    /// completed in 30s, it's stuck and should be cancelled.
    private func startTranscriptionWatchdog() {
        stopTranscriptionWatchdog()
        transcriptionWatchdog = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Must dispatch to main for @MainActor-isolated properties
            DispatchQueue.main.async {
                guard self.status == .transcribing else { return }
                PersistentLog.log(.watchdogReset(source: "appTranscription", staleState: "transcribing"))
                self.cancelDictation()
            }
        }
    }

    /// Invalidate and nil the transcription watchdog timer.
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

        // Manage transcription watchdog based on status transitions
        if newStatus == .transcribing {
            startTranscriptionWatchdog()
        } else if oldStatus == .transcribing {
            stopTranscriptionWatchdog()
        }

        // Signal keyboard that status changed
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Handle errors by updating status and writing error to App Group.
    private func handleError(_ message: String) {
        defaults.set(message, forKey: SharedKeys.lastError)
        defaults.synchronize()
        updateStatus(.failed)
    }
}
