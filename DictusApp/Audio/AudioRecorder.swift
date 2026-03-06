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
    func prepare(whisperKit: WhisperKit) {
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

    /// Configure the audio session once. Called on first recording only.
    /// Must happen while app is in foreground — iOS forbids setCategory from background.
    func configureAudioSession() throws {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true)
        sessionConfigured = true

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("AVAudioSession configured (.playAndRecord, active)")
        }
    }

    /// Start recording audio using WhisperKit's AudioProcessor.
    ///
    /// Two modes:
    /// - **Cold start** (first recording): configures session, starts engine.
    /// - **Warm start** (engine already running from previous recording): just purges
    ///   accumulated idle samples. No engine restart needed — works from background.
    func startRecording() throws {
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
                DispatchQueue.main.async {
                    guard let self, let wk = self.whisperKit else { return }
                    // Only publish energy/duration while actively recording
                    guard self.isRecording else { return }
                    self.bufferEnergy = wk.audioProcessor.relativeEnergy
                    self.bufferSeconds = Double(wk.audioProcessor.audioSamples.count)
                        / Double(WhisperKit.sampleRate)
                }
            }
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
        guard let whisperKit else { return [] }
        isRecording = false
        let samples = Array(whisperKit.audioProcessor.audioSamples)

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
        let samples = Array(whisperKit.audioProcessor.audioSamples)

        bufferEnergy = []
        bufferSeconds = 0

        return samples
    }

    /// Fully deactivate audio. Call when app is truly done with audio.
    func deactivateSession() {
        whisperKit?.audioProcessor.stopRecording()
        isEngineRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionConfigured = false
    }
}
