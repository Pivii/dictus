// DictusApp/Audio/SpeechModelProtocol.swift
// Protocol abstraction for multi-engine speech-to-text.
import Foundation
import WhisperKit
import DictusCore

/// Common interface for all speech-to-text engines (WhisperKit, Parakeet, etc.).
///
/// WHY a protocol:
/// Dictus supports multiple STT engines — WhisperKit and Parakeet. Instead of
/// embedding engine-specific code in TranscriptionService, each engine conforms
/// to this protocol. TranscriptionService dispatches to whichever engine is active.
/// This makes adding new engines trivial: implement the protocol, register in the catalog.
protocol SpeechModelProtocol {
    /// Human-readable engine name for logging and UI.
    var engineName: String { get }

    /// Whether the engine is initialized and ready to transcribe.
    var isReady: Bool { get }

    /// Prepare the engine with a specific model variant.
    /// - Parameter modelIdentifier: The catalog identifier (e.g., "openai_whisper-small").
    func prepare(modelIdentifier: String) async throws

    /// Transcribe audio samples to text.
    /// - Parameters:
    ///   - audioSamples: Float32 audio samples at 16 kHz mono.
    ///   - language: BCP-47 language code (e.g., "fr", "en"), or `nil` to let
    ///     the engine auto-detect the spoken language (issue #226 Auto-detect
    ///     mode — Whisper's built-in language detection).
    /// - Returns: Transcribed text string.
    func transcribe(audioSamples: [Float], language: String?) async throws -> String

    /// Run one inference on generated silence and throw the result away (issue #426).
    ///
    /// WHY every engine has to answer this: loading a model is not the same as being
    /// ready to run one. The Neural Engine specializes per tensor shape at the FIRST
    /// inference, so whichever call is first pays that cost — and until this existed
    /// that call was always the user's first dictation, 4.1 s slower than the next one
    /// on the same clip. The coordinator calls this inside the load, before the engine
    /// is published, so the cost lands where the user is already watching a preparation
    /// state.
    ///
    /// Distinct from `UnifiedAudioEngine.warmUp()` (#106), which warms the audio
    /// engine. Different subsystem, similar name; hence "warm inference" throughout.
    func runWarmInference() async throws
}

/// Failures raised while preparing a speech model for transcription.
///
/// WHY a dedicated error type (issue #249):
/// The dictation path used to hand WhisperKit the model *name* with downloads
/// enabled, so a missing or unreachable model surfaced WhisperKit's own English
/// developer-facing string ("Model not found. Please check the model or repo name
/// and try again.") straight into the keyboard's error banner. These cases carry
/// localised, user-actionable text instead, while `diagnosticDescription` keeps the
/// English technical detail for `PersistentLog`.
///
/// This shape is now named and shared: `DiagnosableError`, in
/// `DictationFailureMessage.swift`, is #313's generalisation of this type.
enum SpeechModelError: DiagnosableError {
    /// The selected variant is absent from the local model repository, or its
    /// folder holds no compiled Core ML bundle.
    case modelNotInstalled(identifier: String)

    /// The model files are present but the engine failed to load them.
    case engineLoadFailed(identifier: String, underlying: Error)

    /// The load completed, but the app had already stopped waiting for it: the user
    /// left the preparation screen, or the launch deadline expired (issue #428).
    ///
    /// WHY this is an error and not a silent success: the in-flight load is shared, and
    /// every caller parked on it reads a plain `return` as "the engine is ready". One of
    /// those callers is a cold-start dictation, which would then write `.ready` with no
    /// engine behind it and call `transcribe` on nothing. An abandoned load has to fail
    /// its awaiters so they can rethrow and start a load of their own.
    case loadAbandoned(identifier: String)

    /// User-facing text. Written to `DictationErrorChannel` and displayed by whichever
    /// surface the user is on — the keyboard's toolbar, the app's failure screen, or both.
    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return String(localized: "This model is not installed. Open Dictus and download it in the Models tab.")
        case .engineLoadFailed:
            return String(localized: "The transcription model could not be loaded. Open Dictus and try again.")
        case .loadAbandoned:
            // A NOTICE, not a fault (#313). Nothing is broken: a load the app stopped
            // waiting for is the expected outcome of a deadline expiring or of the user
            // leaving the preparation screen, and tapping again starts or joins the next
            // one. "Interrupted", which this said first, reads as damage and sends the
            // user looking for something to fix. Same register as `noWordsDetected`:
            // state the situation, name the one action that works, assign no blame.
            return String(localized: "The model is still getting ready. Tap the microphone again.")
        }
    }

    /// Whether this is a load the app walked away from rather than a failure of the
    /// model files. The wrapping in `ensureEngineReady` preserves it: a caller told
    /// "preparation was interrupted, tap again" can act on that, where "the model could
    /// not be loaded" would send them looking for a broken download (issue #428).
    var isLoadAbandoned: Bool {
        if case .loadAbandoned = self { return true }
        return false
    }

    /// English technical detail for the log. Never shown to the user.
    var diagnosticDescription: String {
        switch self {
        case .modelNotInstalled(let identifier):
            return "model not installed locally: \(identifier)"
        case .engineLoadFailed(let identifier, let underlying):
            return "engine load failed for \(identifier): \(underlying)"
        case .loadAbandoned(let identifier):
            return "load abandoned before it completed: \(identifier)"
        }
    }
}

/// WhisperKit engine conforming to SpeechModelProtocol.
///
/// WHY a wrapper class instead of making TranscriptionService conform directly:
/// TranscriptionService orchestrates the transcription pipeline (error handling,
/// settings reading, post-processing). WhisperKitEngine is a thin adapter that
/// maps WhisperKit's API to the protocol, keeping concerns separate.
class WhisperKitEngine: SpeechModelProtocol {
    var engineName: String { "WhisperKit" }

    /// The underlying WhisperKit instance, injected from DictationCoordinator.
    private var whisperKit: WhisperKit?

    /// The model folder currently loaded, to avoid redundant reinitialization.
    private var loadedModelName: String?

    var isReady: Bool {
        whisperKit != nil
    }

    /// Accept a pre-initialized WhisperKit instance (from DictationCoordinator).
    ///
    /// WHY this separate method:
    /// DictationCoordinator already manages WhisperKit's lifecycle (pre-loading at
    /// launch, audio session configuration). Rather than duplicating that logic,
    /// the coordinator passes its WhisperKit instance to the engine.
    func setWhisperKit(_ kit: WhisperKit) {
        self.whisperKit = kit
    }

    /// Load a model from scratch into this engine.
    ///
    /// NOTHING CALLS THIS TODAY. The live load path is
    /// `DictationCoordinator.ensureWhisperKitEngineReady`, which builds the `WhisperKit`
    /// instance itself and hands it over through `setWhisperKit`. Whoever revives this
    /// method has to call `runWarmInference()` after the load and before handing the
    /// engine out, or they re-create issue #426: `prewarm: true, load: true` compiles
    /// and loads the weights and runs no inference, so the Neural Engine's per-shape
    /// specialization lands in the user's first dictation instead.
    func prepare(modelIdentifier: String) async throws {
        // Skip if same model is already loaded
        if loadedModelName == modelIdentifier, whisperKit != nil {
            return
        }

        // Load from the local repository only (issue #249). Downloading belongs to
        // the model manager, never to a transcription path — see the equivalent
        // guard in DictationCoordinator.ensureWhisperKitEngineReady.
        guard let modelFolder = WhisperModelRepository.installedModelFolderURL(for: modelIdentifier) else {
            throw SpeechModelError.modelNotInstalled(identifier: modelIdentifier)
        }

        let config = WhisperKitConfig(
            model: modelIdentifier,
            modelFolder: modelFolder.path,
            // Issue #370: A12/A13 need the audio encoder off the Neural Engine.
            computeOptions: WhisperComputeOptions.current(),
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.loadedModelName = modelIdentifier
    }

    /// One discarded inference, with every knob that could make it silently useless
    /// pinned down (issue #426).
    ///
    /// The options deliberately differ from `transcribe` above in exactly two places,
    /// and neither changes a tensor shape — which is all that specialization depends on:
    ///
    /// - `temperatureFallbackCount: 0`. Silence trips `logProbThreshold` easily, and the
    ///   production value of 5 would buy up to six full decode passes for a result that
    ///   is about to be thrown away.
    /// - `sampleLength: 16`. `TextDecoder.decodeText` loops
    ///   `for tokenIndex in prefilledIndex..<min(sampleLength, 223)`, and `prefilledIndex`
    ///   is the prefill cache length — 3 or 4 with `usePrefillPrompt: true`. A sample
    ///   length at or below that runs the decoder ZERO times and specializes only the
    ///   encoder. Sixteen leaves room above the prefill without letting the loop run on.
    ///
    /// `chunkingStrategy` is left off because it cannot apply: `WhisperKit.transcribe`
    /// only consults it when the buffer exceeds one 30 s window, and this one is 2 s. It
    /// therefore takes `runTranscribeTask` directly — the same path each VAD chunk of a
    /// real recording takes, padded to the same 480 000-sample window.
    ///
    /// The language is fixed rather than read from the user's policy: the prefill token
    /// differs, the shapes do not, and a load has no business reaching into the
    /// dictation language snapshot.
    func runWarmInference() async throws {
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            temperatureFallbackCount: 0,
            sampleLength: 16,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: false,
            skipSpecialTokens: true
        )

        _ = try await whisperKit.transcribe(
            audioArray: WarmInferenceAudio.silence(),
            decodeOptions: options
        )
    }

    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        // Variant A — `.vad` only. Issue #168 audit found WhisperAX canonical
        // defaults to chunkingStrategy = .vad. Earlier attempts on #163 combined
        // .vad with threshold tweaks (noSpeechThreshold, logProbThreshold) which
        // regressed long-form turbo. Testing .vad in isolation here.
        //
        // `language` is optional since #226: nil means the user chose Auto-detect
        // and Whisper picks the language token itself instead of being forced.
        //
        // WHY `detectLanguage` must be explicit in auto mode:
        // WhisperKit's `detectLanguage` defaults to `!usePrefillPrompt`
        // (Configurations.swift), and Dictus passes `usePrefillPrompt: true` —
        // so with `language: nil` alone, detection stays OFF and the prefill
        // falls back to the `<|en|>` token. Device testing showed exactly that:
        // French speech came out quasi-translated to English and Mandarin
        // produced "[speaking in Chinese]" subtitle-style annotations.
        // `detectLanguage: true` is designed to work together with the prefill
        // (the detected token replaces the forced one). In follow/explicit
        // modes the language is set and detection stays off, as before.
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        // Auto-detect observability (#226): surface what Whisper decided so
        // exported logs can validate the fix (e.g. detected=zh for Mandarin).
        // Only logged in auto mode — in follow/explicit the language is forced.
        if language == nil {
            let detected = results.first?.language ?? "unknown"
            PersistentLog.log(.diagnosticProbe(
                component: "WhisperKitEngine",
                instanceID: "languageDetection",
                action: "detected",
                details: "detected=\(detected)"
            ))
        }

        let totalSegments = results.reduce(0) { $0 + $1.segments.count }
        let totalCharCount = results.reduce(0) { $0 + $1.text.count }
        let lastSegmentEnd = results.flatMap { $0.segments }.map { $0.end }.max() ?? 0
        let audioDurationSec = Float(audioSamples.count) / 16_000.0
        PersistentLog.log(.diagnosticProbe(
            component: "WhisperKitEngine",
            instanceID: "transcribe",
            action: "segmentsReturned",
            details: "results=\(results.count) segments=\(totalSegments) chars=\(totalCharCount) audioSec=\(String(format: "%.2f", audioDurationSec)) lastSegmentEndSec=\(String(format: "%.2f", lastSegmentEnd))"
        ))

        let text = results.map { $0.text }.joined(separator: " ")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            // Nothing wrong happened: the model ran on a normal-length clip and heard
            // no words. A notice, not a fault (#313).
            throw TranscriptionError.noSpeechDetected(context: "empty WhisperKit transcription result")
        }

        return trimmed
    }
}
