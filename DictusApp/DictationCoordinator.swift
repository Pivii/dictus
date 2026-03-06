// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via AudioRecorder + transcription via TranscriptionService.
import Foundation
import UIKit
import Combine
import AVFoundation
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
    private var isInitializing = false

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
    }

    // MARK: - Public API

    /// Whether the current dictation was triggered by a URL scheme (app came to foreground)
    /// vs a Darwin notification (app stays in background). When true, the app auto-returns
    /// to the previous app after recording starts.
    private var launchedViaURL = false

    /// Called when the app receives dictus://dictate URL.
    /// Starts the full recording pipeline.
    ///
    /// Phase 2.3: Now checks SharedKeys.modelReady before starting.
    /// If no model is downloaded, writes a descriptive error instead of crashing.
    ///
    /// - Parameter fromURL: true when triggered by URL scheme (app foregrounded),
    ///   false when triggered by Darwin notification (app stays in background).
    func startDictation(fromURL: Bool = false) {
        // Guard against duplicate URL calls — iOS can fire dictus://dictate twice.
        // If we're already recording or initializing, ignore the duplicate.
        guard status == .idle || status == .failed else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Ignoring duplicate startDictation — already \(self.status.rawValue)")
            }
            return
        }

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation started via URL scheme")
        }

        // Check if a model is downloaded and ready
        let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
        guard modelReady else {
            handleError("No model downloaded. Open Dictus to download a model.")
            return
        }

        launchedViaURL = fromURL

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

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

                // Step 3b: Auto-return to previous app if launched via URL.
                // WHY: When the keyboard opens dictus://dictate, iOS brings DictusApp
                // to the foreground. But the user wants to stay in their app — the
                // recording happens in background (UIBackgroundModes: audio).
                // We send the app to background so the user returns automatically.
                if launchedViaURL {
                    returnToPreviousApp()
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
    /// Stops recording and starts transcription.
    ///
    /// Phase 2.3: Uses SmartModelRouter to select the best model based on
    /// recorded audio duration. Short clips (< 5s) use fast models, longer
    /// clips use accurate models.
    func stopDictation() {
        dictationTask?.cancel()

        dictationTask = Task {
            do {
                // Step 1: Stop recording and get audio samples
                let samples = audioRecorder.stopRecording()

                guard !samples.isEmpty else {
                    handleError("No audio recorded")
                    return
                }

                // Step 2: Calculate audio duration for smart routing
                let audioDuration = bufferSeconds

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording stopped. Samples: \(samples.count), Duration: \(String(format: "%.1f", audioDuration))s")
                }

                // Step 3: Use SmartModelRouter to select the best model
                // Read downloaded models from App Group (loose coupling — no reference to ModelManager)
                let downloadedModels = readDownloadedModels()
                let selectedModel = SmartModelRouter.selectModel(
                    audioDuration: audioDuration,
                    downloadedModels: downloadedModels
                )

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("SmartModelRouter selected: \(selectedModel) for \(String(format: "%.1f", audioDuration))s audio")
                }

                // Step 4: Ensure WhisperKit is loaded with the selected model
                // If the router selected a different model than currently loaded,
                // this will reinitialize WhisperKit with the new model.
                if !selectedModel.isEmpty {
                    try await ensureWhisperKitReady(preferredModel: selectedModel)
                }

                // Step 5: Transcribe (FillerWordFilter.clean() is applied inside TranscriptionService)
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
                self.startDictation(fromURL: false)
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

    /// Send the app to background, returning to whatever app was previously active.
    ///
    /// WHY this technique: When a keyboard extension opens our URL scheme, iOS brings
    /// DictusApp to the foreground. But the user wants to stay in their original app.
    /// We send the `suspend` selector through the responder chain, which tells iOS to
    /// background this app. The active AVAudioSession + UIBackgroundModes:audio keeps
    /// the recording alive in background.
    ///
    /// This technique is used by Wispr Flow and other dictation keyboards. The selector
    /// exists on URLSessionTask (public API). If Apple ever blocks it, behavior degrades
    /// gracefully: the user taps the "◄ Back" chevron manually.
    private func returnToPreviousApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let selector = NSSelectorFromString("suspend")
            UIControl().sendAction(selector, to: UIApplication.shared, for: nil)
        }
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
