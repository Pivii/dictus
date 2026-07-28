// DictusApp/Audio/TranscriptionService.swift
// Encapsulates speech-to-text transcription with multi-engine routing.
import Foundation
import WhisperKit
import DictusCore

/// Errors that can occur during transcription.
enum TranscriptionError: Error, LocalizedError {
    case notReady
    case emptyAudio
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "TranscriptionService is not ready — no engine initialized"
        case .emptyAudio:
            return "No audio samples to transcribe"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

/// Handles transcription with multi-engine routing via SpeechModelProtocol.
///
/// WHY this is a separate class from UnifiedAudioEngine:
/// Single Responsibility — UnifiedAudioEngine handles recording, TranscriptionService handles
/// transcription. This also makes it easy to swap or test each independently.
///
/// Phase 10.3 additions:
/// - SpeechModelProtocol-based engine routing (WhisperKit or Parakeet)
/// - Backward-compatible: existing prepare(whisperKit:) still works
class TranscriptionService {
    private var whisperKit: WhisperKit?

    /// The active STT engine, set via prepare(engine:).
    /// WHY a protocol reference:
    /// DictationCoordinator creates the appropriate engine (WhisperKitEngine or
    /// ParakeetEngine) based on the user's active model. TranscriptionService
    /// doesn't know or care which engine it is — it just calls transcribe().
    private var activeEngine: SpeechModelProtocol?

    /// The folder path of the currently loaded model, used to detect when
    /// we need to reinitialize WhisperKit for a different model.
    private var loadedModelFolder: String?

    /// Inject or re-use a WhisperKit instance (backward-compatible path).
    ///
    /// WHY keep this method:
    /// DictationCoordinator injects the WhisperKit instance for the transcription path.
    /// UnifiedAudioEngine doesn't need WhisperKit — it uses native AVAudioEngine.
    func prepare(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// Set the active engine for protocol-based transcription routing.
    ///
    /// WHY a separate method from prepare(whisperKit:):
    /// The engine abstraction is layered on top of the existing WhisperKit path.
    /// When activeEngine is set, transcribe() delegates to it instead of using
    /// the raw WhisperKit instance. This allows both paths to coexist during
    /// the transition to multi-engine support.
    func prepare(engine: SpeechModelProtocol) {
        self.activeEngine = engine
    }

    /// Prepare TranscriptionService with a specific model at a given path.
    ///
    /// WHY a separate prepare method for model paths:
    /// When the user switches models, we need to reinitialize WhisperKit with
    /// the new model. This method handles that switch transparently.
    func prepare(modelPath: String) async throws {
        // Skip reinitialization if same model is already loaded
        if loadedModelFolder == modelPath, whisperKit != nil {
            return
        }

        let config = WhisperKitConfig(
            modelFolder: modelPath,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.loadedModelFolder = modelPath
    }

    /// Transcribe audio samples to text.
    ///
    /// Routes to the active SpeechModelProtocol engine if set,
    /// otherwise falls back to the direct WhisperKit path.
    ///
    /// WHY the fallback:
    /// During transition to multi-engine, the prepare(whisperKit:) path is still used.
    /// The fallback ensures zero regressions while new engine routing is added.
    ///
    /// WHY `languagePolicy` is a parameter instead of reading App Group here (#226):
    /// The STT language is decoupled from the keyboard language, and the whole
    /// dictation pipeline (STT + polish + finalization) must run on ONE
    /// consistent snapshot. DictationCoordinator captures the policy once at
    /// transcription start and passes it down, so a mid-dictation keyboard
    /// language change cannot desync transcription from polish. In particular,
    /// the keyboard toolbar switcher only ever writes SharedKeys.language, so
    /// an explicit or auto choice can never be overridden by it.
    func transcribe(audioSamples: [Float],
                    languagePolicy: TranscriptionLanguagePolicy) async throws -> String {
        let transcriptionStart = Date()

        // nil = Whisper auto-detection. Parakeet ignores the value entirely.
        let language = languagePolicy.sttLanguageCode

        // Determine active model name for logging (from the same snapshot the
        // engine choice was derived from, so logs describe the actual model).
        let modelName = languagePolicy.modelIdentifier.isEmpty
            ? "unknown" : languagePolicy.modelIdentifier
        PersistentLog.log(.transcriptionStarted(modelName: modelName))
        // Trace the resolution so device tests (#226 acceptance: Mandarin via
        // Auto-detect, toolbar-switcher non-override) can verify it from logs.
        PersistentLog.log(.diagnosticProbe(
            component: "TranscriptionService",
            instanceID: "languageResolution",
            action: "resolved",
            details: "mode=\(languagePolicy.mode.storedValue) keyboard=\(languagePolicy.keyboardLanguage.rawValue) engine=\(languagePolicy.engine.rawValue) stt=\(language ?? "auto")"
        ))

        // Route to active engine if set (multi-engine path)
        if let activeEngine {
            do {
                let result = try await activeEngine.transcribe(audioSamples: audioSamples, language: language)
                let durationMs = Int(Date().timeIntervalSince(transcriptionStart) * 1000)
                let wordCount = result.split(separator: " ").count
                PersistentLog.log(.transcriptionCompleted(durationMs: durationMs, wordCount: wordCount))
                logPerformance(modelName: modelName, audioSamples: audioSamples, transcriptionDurationMs: durationMs)
                return result
            } catch {
                PersistentLog.log(.transcriptionFailed(error: error.localizedDescription))
                throw error
            }
        }

        // Fallback: direct WhisperKit path (backward compatibility)
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        // Variant A — `.vad` only. Mirrors the change in SpeechModelProtocol.swift
        // so the legacy fallback path stays consistent with the active engine path.
        // See SpeechModelProtocol.swift for rationale.
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )

        do {
            let results: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: audioSamples,
                decodeOptions: options
            )

            let totalSegments = results.reduce(0) { $0 + $1.segments.count }
            let totalCharCount = results.reduce(0) { $0 + $1.text.count }
            let lastSegmentEnd = results.flatMap { $0.segments }.map { $0.end }.max() ?? 0
            let audioDurationSec = Float(audioSamples.count) / 16_000.0
            PersistentLog.log(.diagnosticProbe(
                component: "TranscriptionService",
                instanceID: "transcribeLegacy",
                action: "segmentsReturned",
                details: "results=\(results.count) segments=\(totalSegments) chars=\(totalCharCount) audioSec=\(String(format: "%.2f", audioDurationSec)) lastSegmentEndSec=\(String(format: "%.2f", lastSegmentEnd))"
            ))

            // Join all segment texts into a single string.
            // Whisper may produce multiple segments for longer audio.
            let text = results.map { $0.text }.joined(separator: " ")

            // Trim whitespace — Whisper sometimes adds leading/trailing spaces
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                PersistentLog.log(.transcriptionFailed(error: "Empty transcription result"))
                throw TranscriptionError.transcriptionFailed("Empty transcription result")
            }

            let durationMs = Int(Date().timeIntervalSince(transcriptionStart) * 1000)
            let wordCount = trimmed.split(separator: " ").count
            PersistentLog.log(.transcriptionCompleted(durationMs: durationMs, wordCount: wordCount))
            logPerformance(modelName: modelName, audioSamples: audioSamples, transcriptionDurationMs: durationMs)
            return trimmed
        } catch let error as TranscriptionError {
            PersistentLog.log(.transcriptionFailed(error: error.localizedDescription ?? "unknown"))
            throw error
        } catch {
            PersistentLog.log(.transcriptionFailed(error: error.localizedDescription))
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Phase 37 instrumentation: emits `transcriptionPerformance` alongside the existing
    /// `transcriptionCompleted` event. Kept as a small helper so both the multi-engine
    /// path and the legacy WhisperKit path log identical schema.
    ///
    /// `peakMemoryMB` here is a point-in-time reading of remaining jetsam headroom right
    /// after transcription, not a true peak. Paired with the prewarm delta in
    /// `modelPrewarmPeakMemory`, it gives a coarse-but-useful signal for per-device gating.
    private func logPerformance(modelName: String, audioSamples: [Float], transcriptionDurationMs: Int) {
        // WhisperKit and FluidAudio both consume audio at 16 kHz. Hardcoded to stay
        // consistent with the sample-rate assumption everywhere else in the pipeline.
        let sampleRateHz = 16_000
        let audioDurationMs = audioSamples.isEmpty ? 0 : (audioSamples.count * 1000) / sampleRateHz
        let peakMemoryMB = DeviceCapabilities.current().availableMemoryMB
        PersistentLog.log(.transcriptionPerformance(
            modelName: modelName,
            audioDurationMs: audioDurationMs,
            transcriptionDurationMs: transcriptionDurationMs,
            peakMemoryMB: peakMemoryMB
        ))
    }
}
