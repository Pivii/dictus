// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via AudioRecorder + transcription via TranscriptionService.
import Foundation
import Combine
import AVFoundation
import UIKit
import DictusCore
import WhisperKit

/// Manages the dictation lifecycle in the main app.
/// Phase 2.3: Integrated with SmartModelRouter for duration-based model selection
/// and FillerWordFilter (applied in TranscriptionService).
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
    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private var dictationTask: Task<Void, Never>?

    /// Task that resolves when WhisperKit is fully loaded.
    /// WHY: Both init() pre-load and startDictation() call ensureWhisperKitReady().
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

    private init() {
        // Forward AudioRecorder's energy levels and seconds to coordinator
        energyCancellable = audioRecorder.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                self?.bufferEnergy = energy
                self?.forwardWaveformToAppGroup(energy: energy)
            }
        secondsCancellable = audioRecorder.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.bufferSeconds = seconds
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
                try await ensureWhisperKitReady()
                try audioRecorder.warmUp()
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("WhisperKit + audio engine pre-loaded at launch")
                }
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.warning("Pre-load failed (will retry when app returns to foreground): \(error.localizedDescription)")
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
                guard !self.audioRecorder.isEngineRunning else { return }
                let modelReady = self.defaults.bool(forKey: SharedKeys.modelReady)
                guard modelReady else { return }

                do {
                    try self.audioRecorder.configureAudioSession()
                    try await self.ensureWhisperKitReady()
                    try self.audioRecorder.warmUp()
                    if #available(iOS 14.0, *) {
                        DictusLogger.app.info("Audio engine warmed up on foreground return")
                    }
                } catch {
                    if #available(iOS 14.0, *) {
                        DictusLogger.app.warning("Foreground warmUp failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Public API

    /// Start the recording pipeline.
    /// Called from URL scheme (first time) or Darwin notification (subsequent times).
    func startDictation() {
        // Guard against duplicate calls while actively recording or transcribing.
        // Allow .ready (previous transcription just finished) and .idle — both are valid
        // states to start a new recording from.
        guard status == .idle || status == .failed || status == .ready else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Ignoring duplicate startDictation — already \(self.status.rawValue)")
            }
            return
        }

        // WHY this early return:
        // iOS forbids starting an audio engine from background. If the engine isn't
        // running and we're in background (Darwin notification from keyboard), attempting
        // to start will fail. By returning early WITHOUT changing status, the keyboard's
        // dictationStatus stays ".requested". After 500ms, the keyboard's fallback opens
        // the dictus:// URL scheme, which brings the app to foreground. Then
        // handleIncomingURL calls startDictation() again — this time from foreground.
        let isBackground = UIApplication.shared.applicationState != .active
        if isBackground && !audioRecorder.isEngineRunning {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Deferring dictation — engine not running and app in background (keyboard URL fallback will bring us to foreground)")
            }
            return
        }

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation started")
        }

        // Check if a model is downloaded and ready
        let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
        guard modelReady else {
            handleError("No model downloaded. Open Dictus to download a model.")
            return
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        // Configure audio session NOW while we're in the foreground.
        // WHY before the Task: ensureWhisperKitReady() takes 4-5s on cold start.
        // By then the app may be backgrounded (opened via URL from keyboard).
        // iOS forbids setActive(true) from background, so this must happen first.
        try? audioRecorder.configureAudioSession()

        dictationTask = Task {
            do {
                // Step 1: Check microphone permission
                let hasPermission = try await audioRecorder.ensureMicrophonePermission()
                guard hasPermission else {
                    handleError("Microphone permission denied")
                    return
                }

                // Step 2: Initialize WhisperKit if not already ready
                try await ensureWhisperKitReady()

                // Step 3: Start recording
                updateStatus(.recording)
                try audioRecorder.startRecording()

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording started successfully")
                }
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Failed to start dictation: \(error.localizedDescription)")
                }
                handleError(error.localizedDescription)
            }
        }
    }

    /// Called when user taps the stop button.
    /// Stops recording and starts transcription using the already-loaded model.
    func stopDictation() {
        dictationTask?.cancel()

        dictationTask = Task {
            do {
                // Step 1: Collect audio samples WITHOUT stopping the engine.
                // Engine keeps running so iOS doesn't suspend us — allows
                // subsequent recordings from background via Darwin notification.
                let samples = audioRecorder.collectSamples()

                guard !samples.isEmpty else {
                    handleError("No audio recorded")
                    return
                }

                let audioDuration = Double(samples.count) / 16000.0

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording stopped. Samples: \(samples.count), Duration: \(String(format: "%.1f", audioDuration))s")
                }

                // Transcribe with the already-loaded model (no model switching).
                // WHY no SmartModelRouter: switching models reinitializes WhisperKit,
                // which kills the warm audio engine and breaks background recording.
                // The user's chosen model is loaded once and reused for all recordings.
                updateStatus(.transcribing)
                let text = try await transcriptionService.transcribe(audioSamples: samples)

                // Step 6: Write result to App Group
                // IMPORTANT: Write both lastTranscription AND status to UserDefaults
                // BEFORE posting any Darwin notifications. This prevents a race condition
                // where the keyboard reads UserDefaults between two separate notifications
                // and sees status=ready but lastTranscription is still nil.
                lastResult = text
                status = .ready
                defaults.set(text, forKey: SharedKeys.lastTranscription)
                defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
                defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
                defaults.synchronize()

                // Post notifications after ALL writes are complete
                DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Transcription complete: \(text)")
                }

                // Step 7: Clean up recording keys from App Group
                cleanupRecordingKeys()

                // Step 8: Brief delay for checkmark flash before returning to idle
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if status == .ready {
                    updateStatus(.idle)
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

        // Stop recording and discard the audio samples
        _ = audioRecorder.stopRecording()

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
        lastResult = nil
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
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Start recording requested via Darwin notification (background)")
                }
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

        // Encode energy as JSON and write to App Group
        if let data = try? JSONEncoder().encode(energy) {
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
        defaults.set(false, forKey: SharedKeys.stopRequested)
        defaults.set(false, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
    }

    /// Initialize WhisperKit with the preferred model if not already loaded.
    ///
    /// Phase 2.3: Now accepts an optional preferredModel parameter from SmartModelRouter.
    /// Falls back to the active model from App Group, then to "openai_whisper-tiny".
    ///
    /// WHY we support model switching:
    /// SmartModelRouter may select different models for different audio durations.
    /// A 3-second voice note should use tiny/base for speed, while a 30-second
    /// dictation benefits from small/medium for accuracy. This method handles
    /// lazy initialization AND model switching.
    private func ensureWhisperKitReady(preferredModel: String? = nil) async throws {
        let modelName = preferredModel
            ?? defaults.string(forKey: SharedKeys.activeModel)
            ?? "openai_whisper-tiny"

        // If WhisperKit is already loaded with the same model, reuse it
        if whisperKit != nil, currentModelName == modelName {
            return
        }

        // If an init is already in progress (e.g., pre-load from init()),
        // await it instead of starting a duplicate initialization.
        if let existingTask = initTask {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("WhisperKit init already in progress — awaiting existing task")
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

    /// Write dictation status to App Group so the keyboard can observe it.
    private func updateStatus(_ newStatus: DictationStatus) {
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()

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
