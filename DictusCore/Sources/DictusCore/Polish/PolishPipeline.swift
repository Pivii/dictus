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
    ///
    /// Auto mode (#239): when `mode == .auto` the input language is unknown, so
    /// `target` is only the placeholder the engine API requires (the engine's
    /// auto prompt ignores it) — it is NEVER used for typography or guardrails:
    /// the decode restores newline markers only (no per-language typography;
    /// CJK full-width punctuation must survive untouched), and the language
    /// guardrail compares the output's detected language against the INPUT's
    /// detected language instead of a target — the runtime never-translate check.
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
            // Restore newlines (+ target typography outside auto mode) BEFORE
            // the guardrail so the char-ratio compares apples to apples (both
            // sides use `\n`).
            let polished = mode == .auto
                ? PolishPostpass.decodeNewlines(polishedRaw)
                : PolishPostpass.decodeFromEngine(polishedRaw, language: target)
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
            guard languageGuardrailPasses(polished: polished, preprocessed: preprocessed,
                                          target: target, mode: mode) else {
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

    /// Language guardrail dispatch. Outside auto mode, the polished output must
    /// read as `target` — catches Apple FM chat-reply contamination. In auto
    /// mode (#239) there is no target: the output must read as the same
    /// language the INPUT reads as — catches translation drift, which is the
    /// worst failure of the auto prompt. When the input's own language cannot
    /// be detected confidently, the check passes through (same philosophy as
    /// the short/low-confidence pass-throughs inside the guardrail).
    private static func languageGuardrailPasses(polished: String,
                                                preprocessed: String,
                                                target: SupportedLanguage,
                                                mode: PolishMode) -> Bool {
        guard mode == .auto else {
            return PolishGuardrail.detectedLanguageMatches(polished: polished, target: target)
        }
        guard let inputCode = detectLanguageCode(in: preprocessed) else { return true }
        return PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: inputCode)
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
    ///
    /// Auto mode (#239): no deterministic pass ran (they are per-language), so
    /// the floor is `preprocessed` UNCHANGED — worst case output == input, per
    /// the acceptance criteria. `target` is the engine placeholder and must not
    /// leak typography here either.
    public static func resolvedOutput(_ result: Result,
                                      preprocessed: String,
                                      target: SupportedLanguage,
                                      mode: PolishMode) -> String {
        if result.outcome == .success, let output = result.engineOutput {
            return output
        }
        guard mode != .auto else { return preprocessed }
        return PolishPostpass.decodeFromEngine(preprocessed, language: target)
    }

    // MARK: - Language detection + mode selection

    /// Default top-language confidence below which text is treated as gibberish
    /// and polish is skipped. ADR 0002 leaves the exact threshold open; 0.5 is a
    /// starting point tuned from logs.
    public static let defaultConfidenceThreshold: Double = 0.5

    /// Detect the dominant language as a raw `NLLanguage` code ("fr", "it",
    /// "zh-Hans", …), or `nil` when confidence is below `confidenceThreshold`
    /// (treated as gibberish → skip). Unlike `detectLanguage(in:)` this is NOT
    /// restricted to the four supported languages — Auto-detect mode (#239)
    /// needs the whole long tail, both for its gibberish gate and for the
    /// never-translate guardrail comparison.
    public static func detectLanguageCode(in text: String,
                                          confidenceThreshold: Double = defaultConfidenceThreshold) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let top = hypotheses.max(by: { $0.value < $1.value }),
              top.value >= confidenceThreshold else {
            return nil
        }
        return top.key.rawValue
    }

    /// Detect the dominant language, or `nil` when confidence is below
    /// `confidenceThreshold` (treated as gibberish → skip) OR when the detected
    /// language is not one of the four supported ones (per-language prompt
    /// paths only make sense for those).
    public static func detectLanguage(in text: String,
                                      confidenceThreshold: Double = defaultConfidenceThreshold) -> SupportedLanguage? {
        detectLanguageCode(in: text, confidenceThreshold: confidenceThreshold)
            .flatMap(SupportedLanguage.init(rawValue:))
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
