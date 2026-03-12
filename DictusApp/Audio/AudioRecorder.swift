// DictusApp/Audio/AudioRecorder.swift
// Wraps WhisperKit's AudioProcessor for recording with energy levels for waveform visualization.
import Foundation
import AVFoundation
import WhisperKit
import DictusCore

/// Errors that can occur during audio recording.
enum AudioRecorderError: Error, LocalizedError {
    case notReady
    case permissionDenied
    case permissionUndetermined

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "AudioRecorder is not ready — WhisperKit not initialized"
        case .permissionDenied:
            return "Microphone permission denied"
        case .permissionUndetermined:
            return "Microphone permission not yet requested"
        }
    }
}

/// Records audio using WhisperKit's built-in AudioProcessor.
///
/// WHY we use WhisperKit's AudioProcessor instead of building a custom AVAudioEngine pipeline:
/// WhisperKit's AudioProcessor already handles 16 kHz mono Float32 conversion (the exact format
/// Whisper expects), buffer management, and exposes `relativeEnergy` for waveform visualization.
/// Building our own would duplicate work and risk format mismatches.
@MainActor
class AudioRecorder: ObservableObject {
    private var whisperKit: WhisperKit?

    /// Whether audio is currently being recorded.
    @Published var isRecording = false

    /// Relative energy levels (0.0-1.0) for waveform visualization.
    /// Updated in real-time during recording from WhisperKit's AudioProcessor.
    @Published var bufferEnergy: [Float] = []

    /// Elapsed recording time in seconds.
    @Published var bufferSeconds: Double = 0

    /// Timestamp of last heartbeat write to App Group.
    /// Written from the audio callback thread at ~1Hz so the keyboard watchdog
    /// can detect the app is still recording even when main thread is throttled.
    private nonisolated(unsafe) var lastHeartbeatWrite: TimeInterval = 0

    /// Whether the audio session has been configured at least once.
    /// WHY: iOS forbids changing AVAudioSession category from background.
    /// We configure once (first recording) and keep the category set forever.
    /// Subsequent recordings just start the audio engine — no session config needed.
    private var sessionConfigured = false

    /// Whether the audio engine is currently running (even if not actively recording).
    /// WHY: We keep the engine running between recordings so iOS doesn't suspend
    /// the app (UIBackgroundModes:audio). This allows subsequent recordings from
    /// background without needing to reopen the app via URL scheme.
    private(set) var isEngineRunning = false

    /// Inject or re-use a WhisperKit instance.
    /// Called by DictationCoordinator after WhisperKit initialization.
    ///
    /// WHY we reset isEngineRunning on model switch: When the user switches models,
    /// DictationCoordinator creates a new WhisperKit instance, and the OLD
    /// instance's audio engine is gone. We must reset so the next startRecording()
    /// does a cold start with the new WhisperKit's AudioProcessor.
    func prepare(whisperKit: WhisperKit) {
        if self.whisperKit !== whisperKit {
            // Model switch — old engine is gone, need cold start next time
            self.whisperKit?.audioProcessor.stopRecording()
            isEngineRunning = false
        }
        self.whisperKit = whisperKit
    }

    /// Check and request microphone permission if needed.
    /// Returns true if permission is granted, false otherwise.
    func ensureMicrophonePermission() async throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .undetermined:
            // requestRecordPermission is an older API that uses a completion handler.
            // We bridge it to async using withCheckedContinuation.
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            return granted
        case .denied:
            throw AudioRecorderError.permissionDenied
        @unknown default:
            return false
        }
    }

    /// Configure the audio session. Must be called from foreground.
    ///
    /// WHY these specific options:
    /// WhisperKit's AudioProcessor internally calls setCategory(.playAndRecord, options:
    /// [.defaultToSpeaker, .allowBluetooth]) in startRecordingLive(). If we use different
    /// options, WhisperKit's setCategory call CHANGES the session config, which can reset
    /// the active state and cause "Failed to set properties '!int'" errors. By matching
    /// WhisperKit's options exactly, its setCategory is effectively a no-op.
    ///
    /// WHY setActive every time (no sessionConfigured guard):
    /// iOS interrupts the audio session when the app goes to background. Even if the
    /// category was set, setActive(true) must be called again on foreground return.
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            // Match WhisperKit's options to avoid conflicting setCategory calls
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        }
        try session.setActive(true)
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        sessionConfigured = true

        PersistentLog.log(.audioSessionConfigured(category: "playAndRecord"))
    }

    /// Start the audio engine in idle mode (not recording, just keeping it alive).
    /// Must be called from foreground. Keeps the app alive in background via
    /// UIBackgroundModes:audio so subsequent recordings work without app switch.
    func warmUp() throws {
        PersistentLog.log(.engineWarmUpAttempt(context: "warmUp called"))
        PersistentLog.log(.engineStateSnapshot(
            engineRunning: isEngineRunning,
            isRecording: isRecording,
            hasWhisperKit: whisperKit != nil,
            sessionConfigured: sessionConfigured,
            context: "warmUp-entry"
        ))
        guard let whisperKit else { throw AudioRecorderError.notReady }
        guard !isEngineRunning else {
            PersistentLog.log(.engineWarmUpSuccess(context: "already running"))
            return
        }

        if !sessionConfigured {
            try configureAudioSession()
        }

        try whisperKit.audioProcessor.startRecordingLive { [weak self] _ in
            // Write heartbeat directly from the audio callback thread (~1Hz).
            // Bypasses main thread throttling in background.
            if let self {
                let now = Date().timeIntervalSince1970
                if now - self.lastHeartbeatWrite >= 1.0 {
                    self.lastHeartbeatWrite = now
                    AppGroup.defaults.set(now, forKey: SharedKeys.recordingHeartbeat)
                }
            }
            DispatchQueue.main.async {
                guard let self, let wk = self.whisperKit else { return }
                guard self.isRecording else { return }
                // Only take the last 30 values — one per waveform bar.
                // WHY: relativeEnergy grows continuously (600+ values after 10s).
                // Using the full array compresses the entire history into 30 bars,
                // creating a timeline instead of a real-time level indicator.
                self.bufferEnergy = Array(wk.audioProcessor.relativeEnergy.suffix(30))
                self.bufferSeconds = Double(wk.audioProcessor.audioSamples.count)
                    / Double(WhisperKit.sampleRate)
            }
        }
        // WHY re-apply after startRecordingLive: WhisperKit's AudioProcessor internally
        // calls setCategory(.playAndRecord) + setActive(true), which resets this flag.
        // We must re-apply it after the engine starts to keep haptics working.
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        isEngineRunning = true

        PersistentLog.log(.audioEngineStarted)
        PersistentLog.log(.engineWarmUpSuccess(context: "engine started"))
    }

    /// Start recording audio using WhisperKit's AudioProcessor.
    ///
    /// Two modes:
    /// - **Cold start** (first recording): configures session, starts engine.
    /// - **Warm start** (engine already running from previous recording): just purges
    ///   accumulated idle samples. No engine restart needed — works from background.
    func startRecording() throws {
        PersistentLog.log(.engineStateSnapshot(
            engineRunning: isEngineRunning,
            isRecording: isRecording,
            hasWhisperKit: whisperKit != nil,
            sessionConfigured: sessionConfigured,
            context: "startRecording-entry"
        ))
        guard let whisperKit else { throw AudioRecorderError.notReady }

        // Configure session if first time (must be foreground)
        if !sessionConfigured {
            try configureAudioSession()
        }

        if isEngineRunning {
            // Engine already running (warm) — purge idle samples and start collecting
            whisperKit.audioProcessor.purgeAudioSamples(keepingLast: 0)
        } else {
            // Cold start — launch the engine
            try whisperKit.audioProcessor.startRecordingLive { [weak self] _ in
                if let self {
                    let now = Date().timeIntervalSince1970
                    if now - self.lastHeartbeatWrite >= 1.0 {
                        self.lastHeartbeatWrite = now
                        AppGroup.defaults.set(now, forKey: SharedKeys.recordingHeartbeat)
                    }
                }
                DispatchQueue.main.async {
                    guard let self, let wk = self.whisperKit else { return }
                    // Only publish energy/duration while actively recording
                    guard self.isRecording else { return }
                    self.bufferEnergy = Array(wk.audioProcessor.relativeEnergy.suffix(30))
                    self.bufferSeconds = Double(wk.audioProcessor.audioSamples.count)
                        / Double(WhisperKit.sampleRate)
                }
            }
            // Re-apply after WhisperKit reconfigures AVAudioSession internally
            try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
            isEngineRunning = true
        }
        isRecording = true
    }

    /// Collect recorded samples WITHOUT stopping the engine.
    ///
    /// WHY keep engine running: iOS requires an active audio engine to keep
    /// the app alive in background (UIBackgroundModes:audio). If we stop the
    /// engine, iOS suspends the app and the next recording request from the
    /// keyboard (via Darwin notification) would fail. By keeping the engine
    /// running, subsequent recordings can start instantly from background.
    ///
    /// The microphone indicator stays visible in the Dynamic Island/status bar,
    /// same behavior as Wispr Flow.
    func collectSamples() -> [Float] {
        guard let whisperKit else {
            PersistentLog.log(.engineCollectResult(sampleCount: 0, engineRunning: isEngineRunning))
            return []
        }
        isRecording = false
        let samples = Array(whisperKit.audioProcessor.audioSamples)

        PersistentLog.log(.engineCollectResult(sampleCount: samples.count, engineRunning: isEngineRunning))

        // Reset published state
        bufferEnergy = []
        bufferSeconds = 0

        return samples
    }

    /// Fully stop the engine and return samples. Use for cancel/cleanup only.
    /// After this, the next recording will need a cold start (foreground required).
    func stopRecording() -> [Float] {
        guard let whisperKit else { return [] }
        whisperKit.audioProcessor.stopRecording()
        isRecording = false
        isEngineRunning = false
        PersistentLog.log(.audioEngineStopped)
        let samples = Array(whisperKit.audioProcessor.audioSamples)

        bufferEnergy = []
        bufferSeconds = 0

        return samples
    }

    /// Fully deactivate audio. Call when app is truly done with audio.
    func deactivateSession() {
        whisperKit?.audioProcessor.stopRecording()
        isEngineRunning = false
        PersistentLog.log(.audioEngineStopped)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionConfigured = false
    }
}
