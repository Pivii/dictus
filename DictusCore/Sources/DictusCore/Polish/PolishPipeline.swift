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
    /// rejected), `nil` when the engine threw, was cancelled, or was never
    /// called at all (`.exceededContextBudget`).
    public struct Result: Sendable {
        public let engineOutput: String?
        public let outcome: PolishMetrics.Outcome
        /// Pure LLM call duration (`engine.polish`).
        public let engineMs: Int
        /// Marker decode + NBSP + guardrail, measured after the engine returned.
        public let postprocessMs: Int
        /// The engine's own name for what it threw (#315). Set on
        /// `.engineFailed` and only there: every other outcome either never
        /// reached the engine or came back from it normally. `nil` elsewhere,
        /// so a caller can key on the reason's presence.
        public let failureReason: PolishFailureReason?

        public init(engineOutput: String?,
                    outcome: PolishMetrics.Outcome,
                    engineMs: Int,
                    postprocessMs: Int,
                    failureReason: PolishFailureReason? = nil) {
            self.engineOutput = engineOutput
            self.outcome = outcome
            self.engineMs = engineMs
            self.postprocessMs = postprocessMs
            self.failureReason = failureReason
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
    ///
    /// `gate` (#315) is the caller's polish-availability state. It defaults to a
    /// fresh gate, which allows everything, so a caller with no such state — the
    /// off-device eval harness — is unaffected.
    public static func transform(preprocessed: String,
                                 engine: PolishEngineProtocol,
                                 target: SupportedLanguage,
                                 mode: PolishMode,
                                 gate: PolishAvailabilityGate = PolishAvailabilityGate()) async -> Result {
        // Polish is in its unavailable state for this engine (#315): two
        // consecutive `rateLimited` refusals said this process is on the wrong
        // side of Apple's background rate limit, and only a fresh process
        // changes that. Exit before the newline encode and before the context
        // guard — the point is to pay nothing at all — and let `resolvedOutput`
        // hand back the same deterministic floor a guardrail rejection gets.
        guard gate.allowsCall(engine: engine.identifier) else {
            return Result(engineOutput: nil, outcome: .engineUnavailable, engineMs: 0, postprocessMs: 0)
        }
        // Encode newlines as a marker so the model can't "naturalise" them into
        // ", " + capital — see `PolishPostpass`. Sub-millisecond, kept out of the
        // engine timing below.
        let engineInput = PolishPostpass.encodeForEngine(preprocessed)
        // Context guard (#270). The backend answers whether this exact input,
        // with the instructions it will resolve for `(mode, target)`, fits its
        // window. Engines with no ceiling answer `.fits` by default, so this is
        // a no-op for them. Deliberately placed BEFORE `engineStart`: it costs
        // a single pass over the strings (tens of microseconds), and folding it
        // into `engineMs` would pollute the one number that measures the LLM.
        if case .exceeds(let estimated, let budget) = engine.contextFit(
            input: engineInput, targetLanguage: target, mode: mode
        ) {
            // The engine is NOT called. `resolvedOutput` returns the
            // deterministic floor for this outcome exactly as it does for an
            // engine failure — the user's text is never at risk here, only
            // the polish is.
            PolishMetrics.logContextOverflow(estimatedTokens: estimated, budgetTokens: budget, mode: mode)
            return Result(engineOutput: nil, outcome: .exceededContextBudget, engineMs: 0, postprocessMs: 0)
        }
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
            // Ask the engine that threw what it threw (#315). Only the failing
            // backend can read its own SDK's error type; the transform records
            // the answer without ever knowing which backend it is talking to.
            // Nothing else in this `do` block throws, so the error is always the
            // engine's.
            return Result(engineOutput: nil, outcome: .engineFailed, engineMs: engineMs, postprocessMs: 0,
                          failureReason: engine.failureReason(for: error))
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
    /// rejection, cancellation, context overflow, polish unavailable) it's the
    /// deterministic floor —
    /// the pre-pass text with newline markers decoded and target-language
    /// typography applied.
    ///
    /// Crucially it is NEVER the literal `raw`: a non-success must not throw away
    /// the free, deterministic verbal-punctuation work (otherwise the user sees
    /// the spoken command words "virgule" / "point" left in the text). This
    /// matches what the coordinator's `< engineMinDuration` gate already returns.
    /// (#185)
    ///
    /// Auto mode (#239): the floor is `preprocessed` — the `autoPreprocess`
    /// output, i.e. the input with verbal-punctuation commands already
    /// converted when the detected language has rules, or the input unchanged
    /// otherwise. No target typography is applied: `target` is the engine
    /// placeholder and must not leak French NBSP (or any per-language rule)
    /// onto a language chosen by detection.
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

    /// Deterministic pre-pass for the auto path (#239 device-test fix).
    ///
    /// Device testing showed spoken punctuation/formatting commands ("point
    /// d'exclamation", "retour à la ligne") were left as literal words in
    /// auto mode while the per-language path converts them. The conversion
    /// lives in `VerbalPunctuationPrepass` — a regex layer that exists
    /// precisely because Apple FM cannot be prompted into applying French
    /// verbal punctuation reliably (see that type's doc) — so prompt-only
    /// parity is not achievable and the regex must run here too.
    ///
    /// The rules are keyed on the DETECTED language, never the keyboard one,
    /// preserving the auto contract: a language with no rules (it, zh, …
    /// today; also es/de until their step-7 rules land) passes through
    /// byte-identical, so CJK text is never touched. False-positive tolerance
    /// is exactly the per-language path's (same regexes, incl. the #185 bare
    /// "point"/"period" exclusion).
    public static func autoPreprocess(_ raw: String, detectedCode: String?) -> String {
        guard let detectedCode,
              let supported = SupportedLanguage(rawValue: detectedCode) else {
            return raw
        }
        return VerbalPunctuationPrepass.apply(raw, language: supported)
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
