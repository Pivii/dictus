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
/// WHY this is a separate class from AudioRecorder:
/// Single Responsibility — AudioRecorder handles recording, TranscriptionService handles
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
    /// DictationCoordinator and AudioRecorder still use the WhisperKit instance
    /// directly for audio recording (WhisperKit's AudioProcessor). This method
    /// injects the same WhisperKit instance for the WhisperKit transcription path.
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
    /// During transition to multi-engine, existing code paths (cold start via
    /// RawAudioCapture, warm start via AudioRecorder) still use prepare(whisperKit:).
    /// The fallback ensures zero regressions while new engine routing is added.
    func transcribe(audioSamples: [Float]) async throws -> String {
        // Read user settings from App Group at transcription time
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let language = defaults?.string(forKey: SharedKeys.language) ?? "fr"
        DictusLogger.app.info("[TranscriptionService] Language for transcription: \(language)")

        // Route to active engine if set (multi-engine path)
        if let activeEngine {
            return try await activeEngine.transcribe(audioSamples: audioSamples, language: language)
        }

        // Fallback: direct WhisperKit path (backward compatibility)
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true
        )

        do {
            let results: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: audioSamples,
                decodeOptions: options
            )

            // Join all segment texts into a single string.
            // Whisper may produce multiple segments for longer audio.
            let text = results.map { $0.text }.joined(separator: " ")

            // Trim whitespace — Whisper sometimes adds leading/trailing spaces
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                throw TranscriptionError.transcriptionFailed("Empty transcription result")
            }

            return trimmed
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }
}
