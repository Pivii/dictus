// DictusCore/Sources/DictusCore/Polish/PolishPipeline.swift
import Foundation
import NaturalLanguage

/// The engine-facing polish transform, factored out of `PolishCoordinator` so
/// the app AND the off-device eval harness run the *same* code on a given input
/// — single source of truth. The coordinator keeps the app-only concerns
/// (toggle, duration gate, metrics ring, prewarm, in-flight cancellation); this
/// enum owns the deterministic transform around the LLM call.
public enum PolishPipeline {

    /// Outcome of one engine-facing transform. Mirrors what `PolishCoordinator`
    /// records in metrics. `engineOutput` is the decoded polished text — present
    /// even when the guardrail rejected it (so callers can inspect what was
    /// rejected), `nil` only when the engine threw or was cancelled.
    public struct Result: Sendable {
        public let engineOutput: String?
        public let outcome: PolishMetrics.Outcome
        /// Pure LLM call duration (`engine.polish`).
        public let engineMs: Int
        /// Marker decode + NBSP + guardrail, measured after the engine returned.
        public let postprocessMs: Int

        public init(engineOutput: String?, outcome: PolishMetrics.Outcome, engineMs: Int, postprocessMs: Int) {
            self.engineOutput = engineOutput
            self.outcome = outcome
            self.engineMs = engineMs
            self.postprocessMs = postprocessMs
        }
    }

    /// Run the transform on `preprocessed` (already past the verbal-punctuation
    /// pre-pass): encode newlines → `engine.polish` → decode + FR typography →
    /// guardrails. Honours `Task.isCancelled` so a caller wrapping this in a
    /// cancellable `Task` gets `.cancelled` when a newer request supersedes it.
    public static func transform(preprocessed: String,
                                 engine: PolishEngineProtocol,
                                 target: SupportedLanguage,
                                 mode: PolishMode) async -> Result {
        // Encode newlines as a marker so the model can't "naturalise" them into
        // ", " + capital — see `PolishPostpass`. Sub-millisecond, kept out of the
        // engine timing below.
        let engineInput = PolishPostpass.encodeForEngine(preprocessed)
        let engineStart = Date()
        do {
            let polishedRaw = try await engine.polish(
                raw: engineInput, targetLanguage: target, mode: mode
            )
            let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
            let postStart = Date()
            // Restore newlines + FR typography BEFORE the guardrail so the
            // char-ratio compares apples to apples (both sides use `\n`).
            let polished = PolishPostpass.decodeFromEngine(polishedRaw, language: target)
            if Task.isCancelled {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                return Result(engineOutput: polished, outcome: .cancelled, engineMs: engineMs, postprocessMs: postMs)
            }
            // Guardrail baseline is the preprocessed text — what the engine
            // actually saw (modulo the newline marker the post-pass undid).
            guard PolishGuardrail.accepts(raw: preprocessed, polished: polished, mode: mode) else {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                return Result(engineOutput: polished, outcome: .rejectedGuardrail, engineMs: engineMs, postprocessMs: postMs)
            }
            guard PolishGuardrail.detectedLanguageMatches(polished: polished, target: target) else {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                return Result(engineOutput: polished, outcome: .rejectedGuardrail, engineMs: engineMs, postprocessMs: postMs)
            }
            let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
            return Result(engineOutput: polished, outcome: .success, engineMs: engineMs, postprocessMs: postMs)
        } catch is CancellationError {
            let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
            return Result(engineOutput: nil, outcome: .cancelled, engineMs: engineMs, postprocessMs: 0)
        } catch {
            let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
            return Result(engineOutput: nil, outcome: .engineFailed, engineMs: engineMs, postprocessMs: 0)
        }
    }

    /// The string the user actually receives, given a transform `Result` and the
    /// deterministic pre-pass output. On `.success` it's the accepted engine
    /// output; on EVERY other outcome (gibberish-skip, engine failure, guardrail
    /// rejection, cancellation) it's the deterministic floor — the pre-pass text
    /// with newline markers decoded and target-language typography applied.
    ///
    /// Crucially it is NEVER the literal `raw`: a non-success must not throw away
    /// the free, deterministic verbal-punctuation work (otherwise the user sees
    /// the spoken command words "virgule" / "point" left in the text). This
    /// matches what the coordinator's `< engineMinDuration` gate already returns.
    /// (#185)
    public static func resolvedOutput(_ result: Result,
                                      preprocessed: String,
                                      target: SupportedLanguage) -> String {
        if result.outcome == .success, let output = result.engineOutput {
            return output
        }
        return PolishPostpass.decodeFromEngine(preprocessed, language: target)
    }

    // MARK: - Language detection + mode selection

    /// Default top-language confidence below which text is treated as gibberish
    /// and polish is skipped. ADR 0002 leaves the exact threshold open; 0.5 is a
    /// starting point tuned from logs.
    public static let defaultConfidenceThreshold: Double = 0.5

    /// Detect the dominant language, or `nil` when confidence is below
    /// `confidenceThreshold` (treated as gibberish → skip).
    public static func detectLanguage(in text: String,
                                      confidenceThreshold: Double = defaultConfidenceThreshold) -> SupportedLanguage? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let top = hypotheses.max(by: { $0.value < $1.value }),
              top.value >= confidenceThreshold else {
            return nil
        }
        return SupportedLanguage(rawValue: top.key.rawValue)
    }

    /// Choose the polish mode. Whisper respects the language picker upstream →
    /// always Natural. Parakeet auto-detects → Repair when detected ≠ target.
    public static func mode(sttEngine: SpeechEngine,
                            detected: SupportedLanguage,
                            target: SupportedLanguage) -> PolishMode {
        switch sttEngine {
        case .whisperKit:
            return .natural
        case .parakeet:
            return detected == target ? .natural : .repair
        }
    }
}
