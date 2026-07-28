// DictusApp/Audio/ParakeetEngine.swift
// FluidAudio-based Parakeet STT engine, iOS 17+ only.
import Foundation
import DictusCore
import FluidAudio

/// Parakeet v3 speech-to-text engine using FluidAudio SDK.
///
/// WHY @available(iOS 17.0, *):
/// FluidAudio's CoreML models require APIs only available on iOS 17+.
/// Since Dictus now targets iOS 17, this guard is technically redundant
/// but kept as documentation and future-proofing.
///
/// IMPORTANT: Never run Parakeet model load simultaneously with WhisperKit prewarm.
/// Both use the Neural Engine for CoreML compilation. Simultaneous compilation
/// causes ANE "E5 bundle" crashes. The caller (DictationCoordinator) must serialize
/// engine initialization — only one engine loads at a time.
@available(iOS 17.0, *)
class ParakeetEngine: SpeechModelProtocol {
    var engineName: String { "Parakeet" }

    private var asrManager: AsrManager?
    private var isInitialized = false

    var isReady: Bool {
        isInitialized
    }

    /// Download and initialize Parakeet v3 models via FluidAudio.
    ///
    /// WHY AsrModels.downloadAndLoad handles everything:
    /// FluidAudio's downloadAndLoad() downloads the model from HuggingFace,
    /// caches it locally, compiles to CoreML, and returns ready-to-use model data.
    /// We don't need to manage download paths or CoreML compilation ourselves.
    ///
    /// - Parameter modelIdentifier: Ignored for Parakeet (only one model version: v3).
    func prepare(modelIdentifier: String) async throws {
        guard !isInitialized else { return }

        do {
            // Download and compile Parakeet v3 CoreML models
            let models = try await AsrModels.downloadAndLoad(version: .v3)

            // Initialize the ASR manager for transcription
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)

            self.asrManager = manager
            self.isInitialized = true

            DictusLogger.app.info("ParakeetEngine: v3 models loaded and ready")
        } catch {
            isInitialized = false
            asrManager = nil

            DictusLogger.app.error("ParakeetEngine: initialization failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Transcribe audio samples using Parakeet v3.
    ///
    /// - Parameters:
    ///   - audioSamples: Float32 audio samples at 16 kHz mono.
    ///   - language: Language code (or `nil` for Auto-detect mode, #226).
    ///     Parakeet TDT v3 auto-detects language from audio — this parameter is
    ///     a no-op either way. The "Transcription language" setting is therefore
    ///     only effective on Whisper models, which Settings documents via the
    ///     existing Parakeet caveat. Language forcing requires Qwen3-ASR (iOS 18+).
    /// - Returns: Transcribed text.
    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        guard let asrManager else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        do {
            let result = try await asrManager.transcribe(audioSamples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw TranscriptionError.transcriptionFailed("Empty Parakeet transcription result")
            }

            return text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.transcriptionFailed("Parakeet: \(error.localizedDescription)")
        }
    }
}

/// Errors specific to ParakeetEngine.
enum ParakeetEngineError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Parakeet engine is not available on this iOS version"
        }
    }
}
