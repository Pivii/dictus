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

    /// Start recording audio using WhisperKit's AudioProcessor.
    ///
    /// WHY we configure AVAudioSession with `.record` category and `.measurement` mode:
    /// - `.record` tells iOS this app captures audio (required for microphone access)
    /// - `.measurement` provides the rawest audio signal with minimal processing
    /// - `.duckOthers` lowers other audio (like music) while recording
    func startRecording() throws {
        guard let whisperKit else { throw AudioRecorderError.notReady }

        // Configure AVAudioSession for recording.
        // WHY .playAndRecord instead of .record: allows background activation.
        // WHY we catch setActive errors: session may already be active from a
        // previous recording. That's fine — we just start the engine.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        do {
            try session.setActive(true)
        } catch {
            // Session may already be active — that's OK for subsequent recordings
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("AVAudioSession setActive warning (may already be active): \(error.localizedDescription)")
            }
        }

        // Use WhisperKit's AudioProcessor — it handles format conversion to 16 kHz mono Float32
        try whisperKit.audioProcessor.startRecordingLive { [weak self] _ in
            // This callback fires each time a new audio buffer arrives.
            // We read energy levels and sample count to update the UI.
            DispatchQueue.main.async {
                guard let self, let wk = self.whisperKit else { return }
                self.bufferEnergy = wk.audioProcessor.relativeEnergy
                self.bufferSeconds = Double(wk.audioProcessor.audioSamples.count)
                    / Double(WhisperKit.sampleRate)
            }
        }
        isRecording = true
    }

    /// Stop recording and return accumulated audio samples.
    ///
    /// The returned [Float] array contains 16 kHz mono audio samples ready for
    /// WhisperKit's `transcribe(audioArray:)` method.
    func stopRecording() -> [Float] {
        whisperKit?.audioProcessor.stopRecording()
        isRecording = false
        let samples = Array(whisperKit?.audioProcessor.audioSamples ?? [])

        // Reset published state
        bufferEnergy = []
        bufferSeconds = 0

        // WHY we keep the audio session active instead of deactivating:
        // With UIBackgroundModes:audio, iOS keeps the app alive as long as the
        // audio session is active. If we deactivate here, iOS may suspend the app,
        // and the next recording request from the keyboard (via Darwin notification)
        // will fail with "Session activation failed" because a backgrounded app
        // cannot activate a new audio session.
        // The microphone hardware is released when the audio engine stops (above),
        // so other apps can use audio normally.
        return samples
    }

    /// Explicitly deactivate the audio session.
    /// Call this only when the app is done with audio entirely (e.g., user closes the app).
    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
