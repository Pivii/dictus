// DictusApp/Audio/TranscriptionService.swift
// Encapsulates WhisperKit transcription with French language settings and post-processing.
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
            return "TranscriptionService is not ready — WhisperKit not initialized"
        case .emptyAudio:
            return "No audio samples to transcribe"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

/// Handles WhisperKit transcription with French language configuration.
///
/// WHY this is a separate class from AudioRecorder:
/// Single Responsibility — AudioRecorder handles recording, TranscriptionService handles
/// transcription. This also makes it easy to swap or test each independently.
///
/// Phase 2.3 additions:
/// - Supports loading/switching WhisperKit instances for different models
class TranscriptionService {
    private var whisperKit: WhisperKit?

    /// The folder path of the currently loaded model, used to detect when
    /// we need to reinitialize WhisperKit for a different model.
    private var loadedModelFolder: String?

    /// Inject or re-use a WhisperKit instance.
    func prepare(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// Prepare TranscriptionService with a specific model at a given path.
    ///
    /// WHY a separate prepare method for model paths:
    /// SmartModelRouter may select a different model for each transcription based
    /// on audio duration. When the selected model differs from the currently loaded
    /// one, we need to reinitialize WhisperKit with the new model. This method
    /// handles that switch transparently.
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

    /// Transcribe audio samples to text using WhisperKit.
    ///
    /// - Parameter audioSamples: Array of Float32 audio samples at 16 kHz mono
    ///   (as returned by `AudioRecorder.stopRecording()`).
    /// - Returns: Transcribed text with filler words removed and punctuation preserved.
    ///
    /// WHY these DecodingOptions:
    /// - `language` — Reads from App Group settings, defaulting to "fr" if never set.
    ///   No model reload needed — WhisperKit accepts the language parameter per transcription call.
    /// - `temperature: 0.0` — Greedy decoding = fastest and most deterministic output
    /// - `usePrefillPrompt: true` — Enables language-specific prompt prefill for better accuracy
    /// - `usePrefillCache: true` — Caches prefill results between transcriptions for speed
    /// - `skipSpecialTokens: true` — Removes Whisper's special tokens from output
    ///
    /// WHY settings are read at transcription time (not cached):
    /// Changes in SettingsView write to App Group UserDefaults immediately. Reading here
    /// means the next dictation uses the updated language/filler preference without
    /// requiring app restart or notification-based refresh.
    ///
    func transcribe(audioSamples: [Float]) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        // Read user settings from App Group at transcription time
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let language = defaults?.string(forKey: SharedKeys.language) ?? "fr"

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
