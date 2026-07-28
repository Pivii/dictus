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

    func prepare(modelIdentifier: String) async throws {
        // Skip if same model is already loaded
        if loadedModelName == modelIdentifier, whisperKit != nil {
            return
        }

        let config = WhisperKitConfig(
            model: modelIdentifier,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )

        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.loadedModelName = modelIdentifier
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
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

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
            throw TranscriptionError.transcriptionFailed("Empty transcription result")
        }

        return trimmed
    }
}
