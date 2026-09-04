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
    /// pre-pass): encode newlines → `engine.polish` → decode + typography →
    /// guardrails. Honours `Task.isCancelled` so a caller wrapping this in a
    /// cancellable `Task` gets `.cancelled` when a newer request supersedes it.
    ///
    /// `job` says what is being asked and in which languages — see `PolishJob`. The
    /// two languages on it are separate because they legitimately differ: the prompt
    /// is resolved for one, and the typography post-pass keys on the output's, which
    /// for a translation is the target rather than the input (#79). Where the output
    /// language is genuinely unknown — the auto path (#239) — `typographyLanguage` is
    /// nil, the decode restores newline markers only, and the language guardrail
    /// compares against the INPUT's detected language instead of a target.
    ///
    /// `gate` (#315) is the caller's polish-availability state. It defaults to a
    /// fresh gate, which allows everything, so a caller with no such state — the
    /// off-device eval harness — is unaffected.
    public static func transform(preprocessed: String,
                                 engine: PolishEngineProtocol,
                                 job: PolishJob,
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
            input: engineInput, targetLanguage: job.promptLanguage, task: job.task
        ) {
            // The engine is NOT called. For the free polish `resolvedOutput` returns
            // the deterministic floor exactly as it does for an engine failure — the
            // user's text is never at risk here, only the polish is. For a Smart
            // Mode it returns nothing, because the floor is not what was asked for.
            PolishMetrics.logContextOverflow(
                estimatedTokens: estimated, budgetTokens: budget, task: job.task
            )
            return Result(engineOutput: nil, outcome: .exceededContextBudget, engineMs: 0, postprocessMs: 0)
        }
        let engineStart = Date()
        do {
            let polishedRaw = try await engine.polish(
                raw: engineInput, targetLanguage: job.promptLanguage, task: job.task
            )
            let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
            let postStart = Date()
            // Restore newlines (+ output-language typography, when there is an
            // output language) BEFORE the guardrail so the char-ratio compares
            // apples to apples (both sides use `\n`).
            let polished = job.typographyLanguage.map {
                PolishPostpass.decodeFromEngine(polishedRaw, language: $0)
            } ?? PolishPostpass.decodeNewlines(polishedRaw)
            if Task.isCancelled {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                return Result(engineOutput: polished, outcome: .cancelled, engineMs: engineMs, postprocessMs: postMs)
            }
            // Guardrail baseline is the preprocessed text — what the engine
            // actually saw (modulo the newline marker the post-pass undid).
            guard PolishGuardrail.accepts(
                raw: preprocessed, polished: polished, contract: job.task.contract
            ) else {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                PolishMetrics.logGuardrailRejection(check: "length", task: job.task)
                return Result(engineOutput: polished, outcome: .rejectedGuardrail, engineMs: engineMs, postprocessMs: postMs)
            }
            guard languageGuardrailPasses(polished: polished, preprocessed: preprocessed, job: job) else {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                PolishMetrics.logGuardrailRejection(check: "language", task: job.task)
                return Result(engineOutput: polished, outcome: .rejectedGuardrail, engineMs: engineMs, postprocessMs: postMs)
            }
            guard groundingGuardrailPasses(polished: polished, preprocessed: preprocessed, job: job) else {
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                PolishMetrics.logGuardrailRejection(check: "grounding", task: job.task)
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

    /// Language guardrail dispatch, off the task's contract (#79).
    ///
    /// - `.polishTarget` — the historical per-language check: the output must read
    ///   as the language the prompt named, which catches Apple FM chat-reply
    ///   contamination.
    /// - `.sameAsInput` — the auto-mode check (#239): the output must read as the
    ///   same language the INPUT reads as, which catches translation drift. When the
    ///   input's own language cannot be detected confidently the check passes
    ///   through, same philosophy as the short/low-confidence pass-throughs inside
    ///   the guardrail.
    /// - `.fixed` — translation. Same machinery as `.polishTarget`, pointed at the
    ///   mode's target instead of the prompt's language, which is what turns this
    ///   check from the obstacle it would have been into the one that catches the
    ///   model forgetting to translate.
    private static func languageGuardrailPasses(polished: String,
                                                preprocessed: String,
                                                job: PolishJob) -> Bool {
        switch job.task.contract.outputLanguage {
        case .polishTarget:
            return PolishGuardrail.detectedLanguageMatches(
                polished: polished, target: job.promptLanguage
            )
        case .fixed(let language):
            return PolishGuardrail.detectedLanguageMatches(polished: polished, target: language)
        case .sameAsInput:
            guard let inputCode = detectLanguageCode(in: preprocessed) else { return true }
            return PolishGuardrail.detectedLanguageMatches(
                polished: polished, inputLanguageCode: inputCode
            )
        }
    }

    /// Grounding guardrail (#414): every person, place and organisation the output
    /// names must already appear in the input.
    ///
    /// Runs only where the task's contract says it is sound — see
    /// `PolishAcceptanceContract.requiresGroundedNames`, which is a field precisely
    /// so a mode has to answer the question rather than have it derived here.
    ///
    /// The language handed to `NLTagger` is a hint, not a filter, and it is the one
    /// the OUTPUT is expected to read as: the input's own for `.sameAsInput`, the
    /// prompt's for `.polishTarget`. `.fixed` never reaches this function, because
    /// a translation's contract answers `false` above — but it is handled rather
    /// than trapped, since a custom mode (#269) could answer `true` on a contract
    /// nobody here anticipated.
    private static func groundingGuardrailPasses(polished: String,
                                                 preprocessed: String,
                                                 job: PolishJob) -> Bool {
        guard job.task.contract.requiresGroundedNames else { return true }
        let outputCode: String?
        switch job.task.contract.outputLanguage {
        case .polishTarget: outputCode = job.promptLanguage.rawValue
        case .fixed(let language): outputCode = language.rawValue
        case .sameAsInput: outputCode = detectLanguageCode(in: preprocessed)
        }
        return PolishGrounding.ungroundedAnchors(
            in: polished, input: preprocessed, languageCode: outputCode
        ).isEmpty
    }

    /// The string the user actually receives, given a transform `Result` and the
    /// deterministic pre-pass output — or `nil` when nothing may be inserted.
    ///
    /// On `.success` it is the accepted engine output.
    ///
    /// ### The free polish falls back; a Smart Mode does not (#79)
    ///
    /// For polish, every other outcome (gibberish-skip, engine failure, guardrail
    /// rejection, cancellation, context overflow, polish unavailable) returns the
    /// deterministic floor — the pre-pass text with newline markers decoded and, when
    /// there is an output language, its typography applied. Crucially it is NEVER
    /// the literal `raw`: a non-success must not throw away the free, deterministic
    /// verbal-punctuation work, otherwise the user sees the spoken command words
    /// "virgule" / "point" left in the text (#185). On the auto path (#239) the floor
    /// is `preprocessed` unchanged, because there is no output language whose
    /// typography could be applied without leaking French NBSP onto a language
    /// chosen by detection.
    ///
    /// For a Smart Mode the floor is not a degraded version of what was asked for —
    /// it is the untransformed text, and inserting it is the worst outcome available:
    /// French sent to an American client, or two minutes of rambling pasted where
    /// three bullets were expected. So the answer is `nil`, and the caller inserts
    /// nothing.
    ///
    /// ### With one exception, and only one: a context overflow on a mode that says
    /// it may degrade
    ///
    /// `.exceededContextBudget` is decided *before* the engine is called, so no
    /// transformation was attempted and the wrong-transformation risk the rule
    /// guards against is absent by construction. Whether that licenses the floor is
    /// the mode's own answer — see `SmartModeOverflowBehaviour`, which explains why
    /// Notes says yes and Translate says no.
    ///
    /// **A caller cannot tell the two apart from this return value alone.** A
    /// degraded output is a `String` exactly like a success, so `PolishService`
    /// re-derives the distinction and packages it as `PolishOutcome.degraded`; the
    /// user is told either way, because refusing in silence and degrading in silence
    /// are the same failure.
    public static func resolvedOutput(_ result: Result,
                                      preprocessed: String,
                                      job: PolishJob) -> String? {
        if result.outcome == .success, let output = result.engineOutput {
            return output
        }
        if let mode = job.task.smartMode, !degradesToFloor(mode, outcome: result.outcome) {
            return nil
        }
        guard let typography = job.typographyLanguage else { return preprocessed }
        return PolishPostpass.decodeFromEngine(preprocessed, language: typography)
    }

    /// Whether an armed mode accepts the deterministic floor for this outcome.
    ///
    /// The outcome test is as narrow as the argument that justifies it: only
    /// `.exceededContextBudget` never reached the engine. `.engineFailed`,
    /// `.rejectedGuardrail`, `.cancelled` and `.engineUnavailable` all stay
    /// fail-closed for every mode, whatever it declares — the first three because a
    /// transformation was attempted and may have half-happened, the last because it
    /// describes a process that will not run the model again for its lifetime, which
    /// is a different conversation to have with the user (#315).
    public static func degradesToFloor(_ mode: SmartMode,
                                       outcome: PolishMetrics.Outcome) -> Bool {
        outcome == .exceededContextBudget && mode.overflowBehaviour == .insertRawText
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
