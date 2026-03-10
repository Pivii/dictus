// DictusApp/Audio/ParakeetEngine.swift
// FluidAudio-based Parakeet STT engine, iOS 17+ only.
import Foundation
import DictusCore

// FluidAudio requires iOS 17+ but Dictus targets iOS 16. The Swift compiler
// forbids importing a module whose minimum deployment target exceeds the app's.
// To work around this, FluidAudio is gated behind a FLUIDAUDIO_AVAILABLE custom
// compilation condition. When the user decides to ship Parakeet (at the go/no-go
// checkpoint), they enable this flag in DictusApp build settings:
//   OTHER_SWIFT_FLAGS = $(inherited) -DFLUIDAUDIO_AVAILABLE
// AND link FluidAudio to DictusApp (Xcode > Target > Frameworks).
//
// This approach is preferred over raising the deployment target to iOS 17,
// which would drop iOS 16 device support entirely.
#if FLUIDAUDIO_AVAILABLE
import FluidAudio
#endif

/// Parakeet v3 speech-to-text engine using FluidAudio SDK.
///
/// WHY @available(iOS 17.0, *):
/// FluidAudio's CoreML models require APIs only available on iOS 17+.
/// Dictus targets iOS 16, so all Parakeet code is gated. On iOS 16 devices,
/// Parakeet models don't appear in the catalog and this class is never instantiated.
///
/// IMPORTANT: Never run Parakeet model load simultaneously with WhisperKit prewarm.
/// Both use the Neural Engine for CoreML compilation. Simultaneous compilation
/// causes ANE "E5 bundle" crashes. The caller (DictationCoordinator) must serialize
/// engine initialization — only one engine loads at a time.
@available(iOS 17.0, *)
class ParakeetEngine: SpeechModelProtocol {
    var engineName: String { "Parakeet" }

    #if FLUIDAUDIO_AVAILABLE
    private var asrManager: AsrManager?
    #endif

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
        #if FLUIDAUDIO_AVAILABLE
        guard !isInitialized else { return }

        do {
            // Download and compile Parakeet v3 CoreML models
            let models = try await AsrModels.downloadAndLoad(version: .v3)

            // Initialize the ASR manager for transcription
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)

            self.asrManager = manager
            self.isInitialized = true

            if #available(iOS 14.0, *) {
                DictusLogger.app.info("ParakeetEngine: v3 models loaded and ready")
            }
        } catch {
            isInitialized = false
            asrManager = nil

            if #available(iOS 14.0, *) {
                DictusLogger.app.error("ParakeetEngine: initialization failed — \(error.localizedDescription)")
            }
            throw error
        }
        #else
        throw ParakeetEngineError.unavailable
        #endif
    }

    /// Transcribe audio samples using Parakeet v3.
    ///
    /// - Parameters:
    ///   - audioSamples: Float32 audio samples at 16 kHz mono.
    ///   - language: Language code. Parakeet v3 supports 25 European languages
    ///     including French. The language parameter is passed but Parakeet
    ///     auto-detects language from audio content.
    /// - Returns: Transcribed text.
    func transcribe(audioSamples: [Float], language: String) async throws -> String {
        #if FLUIDAUDIO_AVAILABLE
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
        #else
        throw ParakeetEngineError.unavailable
        #endif
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
