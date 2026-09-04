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

    /// The FluidAudio cache directory when it holds a complete model set, otherwise `nil`.
    ///
    /// WHY it lives here (issue #252):
    /// This is the single place that binds FluidAudio's own constants — the cache location
    /// and the file names it loads — to the completeness rule in `ParakeetModelRepository`.
    /// `DictationCoordinator` uses it to fail fast before starting an init task, and
    /// `prepare` uses it to guard the load itself, so neither has to know the layout.
    /// Reading the names from `ModelNames.ASR` rather than restating them means a
    /// dependency bump that renames a bundle is a compile-time change, not a silent one.
    ///
    /// IMPORTANT: `AsrModels.defaultCacheDirectory` resolves Application Support for the
    /// *current process*, so this must be called from DictusApp. FluidAudio is not linked
    /// into the keyboard extension, which could not load a model anyway.
    static func installedModelCacheDirectory(version: AsrModelVersion = .v3) -> URL? {
        ParakeetModelRepository.installedCacheDirectory(
            AsrModels.defaultCacheDirectory(for: version),
            requiredModelBundles: ModelNames.ASR.requiredModels,
            vocabularyFileName: ModelNames.ASR.vocabularyFile
        )
    }

    /// Load and initialize Parakeet v3 models from the local FluidAudio cache.
    ///
    /// WHY this never downloads (issue #252):
    /// This used to call `AsrModels.downloadAndLoad`, which loads locally when the files
    /// are cached but starts a HuggingFace download when they are not — during dictation,
    /// while the user waits, with no progress and no way to cancel. That is the asymmetry
    /// issue #249 removed for Whisper: downloading is the model manager's job, where
    /// progress and cancellation already exist. The cache is verified first and the load
    /// is strictly local; an absent or partial cache fails fast with the same localised
    /// message the Whisper path produces.
    ///
    /// The model manager still works: `ModelManager.downloadParakeetModel` downloads the
    /// repo itself through `ModelRepoDownloader` and only then calls this method, which
    /// performs the Core ML compilation step.
    ///
    /// - Parameter modelIdentifier: Ignored for Parakeet (only one model version: v3),
    ///   apart from labelling the error and the diagnostic log.
    func prepare(modelIdentifier: String) async throws {
        guard !isInitialized else { return }

        guard let cacheDirectory = Self.installedModelCacheDirectory() else {
            let error = SpeechModelError.modelNotInstalled(identifier: modelIdentifier)
            PersistentLog.log(.diagnosticProbe(
                component: "ParakeetLoad",
                instanceID: modelIdentifier,
                action: "localModelMissing",
                details: error.diagnosticDescription
            ))
            throw error
        }

        do {
            // Compile the cached Parakeet v3 CoreML models. `load` reads the bundles the
            // guard above verified; it does not resolve anything over the network.
            let models = try await AsrModels.load(from: cacheDirectory, version: .v3)

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

    /// One discarded inference on generated silence, so the first real one does not pay
    /// the Neural Engine's per-shape specialization (issue #426).
    ///
    /// UNMEASURED ON PARAKEET, and deliberately done anyway. #426 measured the gap on
    /// WhisperKit and flagged Parakeet as the same structural question without a number
    /// behind it. What is known: FluidAudio's own `prewarm` only pre-allocates
    /// `MLMultiArray`s in a cache and runs no inference, so nothing in the load path
    /// specializes anything. What is not known is how much that costs here. The
    /// `WarmInference` log line carries the duration so a device session answers it.
    ///
    /// Safe to run ahead of a real transcription because `AsrManager.transcribe` resets
    /// its decoder state after every call — its own documented "stateless architecture"
    /// — so a throwaway pass cannot leak into the dictation that follows.
    ///
    /// It goes through `transcribe` rather than the manager directly: warming the exact
    /// path production uses is the whole point.
    func runWarmInference() async throws {
        do {
            _ = try await transcribe(audioSamples: WarmInferenceAudio.silence(), language: nil)
        } catch TranscriptionError.noSpeechDetected {
            // The expected outcome, and a success for this purpose: the model ran on
            // two seconds of silence and heard no words. `transcribe` refuses an empty
            // result because a user is normally waiting for text; here nobody is. Left
            // to propagate it would log every Parakeet warm inference as a failure.
        }
    }

    /// Shortest clip FluidAudio accepts: one second at the 16 kHz the pipeline
    /// already resamples to. Its own error message states the requirement.
    private static let minimumSampleCount = 16_000

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

        // Parakeet's own one-second floor, declared here rather than discovered there.
        //
        // WHY (#313, field report 2026-08-08): below this, FluidAudio throws, and its
        // sentence — "Parakeet: Invalid audio data provided. Must be at least 1 second of
        // 16kHz audio." — reached the keyboard toolbar verbatim, naming an internal
        // component and a sample rate to someone who had simply stopped the mic a beat
        // early. It is reachable on any ordinary tap because the coordinator's floor is
        // 0.5 s and this one is 1.0 s, so recordings in between pass ours and fail this.
        // Refusing it ourselves is what lets the user read a notice instead.
        guard audioSamples.count >= Self.minimumSampleCount else {
            throw TranscriptionError.noSpeechDetected(
                context: "\(audioSamples.count) samples, below Parakeet's \(Self.minimumSampleCount) floor")
        }

        do {
            let result = try await asrManager.transcribe(audioSamples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw TranscriptionError.noSpeechDetected(context: "empty Parakeet transcription result")
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
enum ParakeetEngineError: Error, DiagnosableError {
    case unavailable

    /// User-facing text. Written to `DictationErrorChannel` and displayed by whichever
    /// surface the user is on — the keyboard's toolbar, the app's failure screen, or both.
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "This model needs a newer version of iOS. Open Dictus and choose another model.",
                          comment: "Shown when the selected model requires an iOS version this device does not run (issue #313).")
        }
    }

    /// English technical detail for the log. Never shown to the user.
    var diagnosticDescription: String {
        switch self {
        case .unavailable:
            return "Parakeet engine is not available on this iOS version"
        }
    }
}
