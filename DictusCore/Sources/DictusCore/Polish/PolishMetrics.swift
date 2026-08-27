// DictusCore/Sources/DictusCore/Polish/PolishMetrics.swift
import Foundation
import os.log

/// Wall-clock breakdown of a single polish invocation. Added on the
/// `feature/141-polish-latency` branch to answer "where does the 3-6s go?".
///
/// The three components sum to roughly `latencyMs` (any gap is Swift `Task`
/// scheduling / actor hop overhead, which is itself worth seeing). The
/// hypothesis under test: `engineMs` (the LLM call) dominates, and
/// `preprocessMs` + `postprocessMs` (our deterministic regex passes) are
/// negligible — i.e. there is no hidden 3s outside the model.
public struct PolishTimings: Sendable, Codable {
    /// Pre-pass (verbal-punctuation regex) + language detection + newline-marker encode.
    public let preprocessMs: Int
    /// Pure engine call — `session.respond(...)` for Apple FM. This is the LLM cost.
    public let engineMs: Int
    /// Newline-marker decode + French NBSP typography + guardrail checks.
    public let postprocessMs: Int

    public init(preprocessMs: Int, engineMs: Int, postprocessMs: Int) {
        self.preprocessMs = preprocessMs
        self.engineMs = engineMs
        self.postprocessMs = postprocessMs
    }
}

/// One polish invocation, emitted to `os_log` and consumed by the in-memory
/// debug ring buffer in DictusApp. No disk persistence at round 1.
public struct PolishMetrics: Sendable, Codable {
    public enum Outcome: String, Sendable, Codable {
        case success
        case rejectedGuardrail
        case skipped
        /// LLM intentionally skipped because the recording was shorter than the
        /// engine-duration gate (#141). Deterministic passes still ran; the
        /// model never loaded. Distinct from `skipped` (gibberish / low language
        /// confidence) so the debug JSON shows *why* the engine was bypassed.
        case skippedShort
        /// LEGACY — no longer emitted since #239. Between #226 and #239 the
        /// whole polish layer was bypassed in Whisper Auto-detect mode and the
        /// bypass was recorded under this outcome. Auto mode now runs the
        /// engine with the language-agnostic auto prompt (`PolishMode.auto`)
        /// and records normal outcomes. The case is KEPT so events persisted
        /// in the 7-day debug ring by pre-#239 builds still decode.
        case skippedAutoMode
        case cancelled
        case engineFailed
        /// The engine was not called because polish is in its unavailable state
        /// (#315). Reached when two consecutive `rateLimited` refusals have shown
        /// that this process is on the wrong side of Apple's background rate
        /// limit; every dictation after that takes the deterministic floor
        /// without paying for a call that will be refused.
        ///
        /// Deliberately distinct from `engineFailed`: nothing failed here, we
        /// declined to ask. Keeping the two apart is what lets an export say how
        /// many dictations a single outage cost, rather than folding them into
        /// the failure count and inflating it.
        case engineUnavailable
        /// Refused BEFORE the engine call (#270): the estimated token cost of
        /// the resolved instructions + input + output reserve exceeds the
        /// backend's context window. Deliberately distinct from
        /// `engineFailed` — nothing failed and nothing was attempted, the input
        /// simply does not fit. Keeping the two apart is what lets a caller say
        /// "that was too long" instead of "something went wrong", and what lets
        /// the metrics tell a length problem from a backend problem.
        case exceededContextBudget
    }

    /// The inputs that decided the polish target, captured per event (#332).
    ///
    /// WHY this exists: five facts decide which language the model is told to
    /// write in, and until #332 an export carried only two of them — under a
    /// name (`targetLanguage`) that in fact held a third. A reader looking at
    /// a German target on French speech could not tell a bug from a setting,
    /// and it took three deliberate device re-tests to establish which it was.
    /// Recorded together with `targetLanguage` and `detectedLanguage` above,
    /// these make that question answerable from the export alone.
    public struct LanguageResolution: Sendable, Codable, Equatable {
        /// The user's transcription-language mode, self-describing:
        /// `followKeyboard` / `autoDetect` / `explicit(fr)`. Distinct from the
        /// keyboard language, which is the whole point.
        public let transcriptionMode: String
        /// The keyboard language at dictation time.
        public let keyboardLanguage: String
        /// The language code handed to the STT engine, or "auto".
        public let sttLanguageCode: String
        /// Whether that engine honours the code. False for Parakeet, which
        /// auto-detects from audio and ignores the parameter — so `stt:de`
        /// there describes what was passed, never what was heard.
        public let sttLanguageIsEffective: Bool

        public init(transcriptionMode: String,
                    keyboardLanguage: String,
                    sttLanguageCode: String,
                    sttLanguageIsEffective: Bool) {
            self.transcriptionMode = transcriptionMode
            self.keyboardLanguage = keyboardLanguage
            self.sttLanguageCode = sttLanguageCode
            self.sttLanguageIsEffective = sttLanguageIsEffective
        }

        /// Read the trail off the per-dictation policy snapshot — the same
        /// snapshot the target was resolved from, so the two can never drift.
        public init(policy: TranscriptionLanguagePolicy) {
            self.init(
                transcriptionMode: policy.mode.telemetryDescription,
                keyboardLanguage: policy.keyboardLanguage.rawValue,
                sttLanguageCode: policy.sttLanguageCodeDescription,
                sttLanguageIsEffective: policy.sttLanguageIsEffective
            )
        }
    }

    public let engine: String              // polish engine id, e.g. "apple-fm"
    public let mode: PolishMode?           // nil when skipped (no mode chosen)
    /// The language the polish prompt instructs the model to write in — the
    /// resolved polish target, NOT the keyboard language. See
    /// `TranscriptionLanguagePolicy.polishPromptSelection(detectedLanguage:)`.
    ///
    /// `nil` on the auto path, where there is no target at all: the prompt is
    /// language-agnostic and the model writes in whatever language the input
    /// is in. It was previously recorded as the keyboard language "for session
    /// context", which put a language that had no influence under a field
    /// named for the one that does — the precise confusion #332 exists to end,
    /// and the reason three device reproductions were needed to prove the
    /// original bug. An absent target now means no target.
    ///
    /// Optional decoding is also what keeps the seven-day ring readable: every
    /// event written before #332 carries a value here, so a missing key can
    /// only mean the auto path on a build that has this fix. (Auto-path events
    /// from older builds still carry their keyboard language; they are
    /// recognisable by having no `languageResolution`.)
    public let targetLanguage: SupportedLanguage?
    public let detectedLanguage: String?   // BCP-47 ("fr","en",…) or nil for gibberish

    /// How the polish target was arrived at (#332). Optional for the reason
    /// `sttEngine` and `timings` are: the debug ring holds seven days of
    /// events written by whatever build was installed at the time, and those
    /// must keep decoding. A missing key means "written before this existed",
    /// never "unknown".
    public let languageResolution: LanguageResolution?

    public let rawCharCount: Int
    public let polishedCharCount: Int      // equals rawCharCount when not polished
    public let latencyMs: Int
    public let outcome: Outcome

    /// Speech-to-text engine that produced the raw text. Optional for
    /// backward compatibility with events persisted before this field landed.
    public let sttEngine: String?          // "WK" / "PK" (SpeechEngine.rawValue)
    /// Specific STT model identifier, e.g. "openai_whisper-small" or
    /// "parakeet-tdt-0.6b-v3". Lets the JSON export be self-describing
    /// without needing to cross-reference the app log.
    public let sttModelID: String?

    /// Wall-clock breakdown of `latencyMs`. Optional for backward compatibility
    /// with events persisted before the latency-investigation branch.
    public let timings: PolishTimings?

    /// Why the engine failed, when it did (#315). Set on `.engineFailed` and
    /// only there.
    ///
    /// Optional for the same reason `timings` is: the debug ring holds seven
    /// days of events written by whatever build was installed at the time, and
    /// those events must keep decoding after this field lands. A missing key
    /// decodes to `nil` — an event from before the reason existed, not an
    /// unclassified failure.
    public let failureReason: PolishFailureReason?

    public init(engine: String,
                mode: PolishMode?,
                targetLanguage: SupportedLanguage?,
                detectedLanguage: String?,
                rawCharCount: Int,
                polishedCharCount: Int,
                latencyMs: Int,
                outcome: Outcome,
                sttEngine: String? = nil,
                sttModelID: String? = nil,
                timings: PolishTimings? = nil,
                failureReason: PolishFailureReason? = nil,
                languageResolution: LanguageResolution? = nil) {
        self.engine = engine
        self.mode = mode
        self.targetLanguage = targetLanguage
        self.detectedLanguage = detectedLanguage
        self.languageResolution = languageResolution
        self.rawCharCount = rawCharCount
        self.polishedCharCount = polishedCharCount
        self.latencyMs = latencyMs
        self.outcome = outcome
        self.sttEngine = sttEngine
        self.sttModelID = sttModelID
        self.timings = timings
        self.failureReason = failureReason
    }

    /// Emit one line for a pre-call context refusal (#270). The metrics event
    /// that follows records the outcome but not the arithmetic behind it, and
    /// the arithmetic is what tells "one genuinely enormous dictation" apart
    /// from "our safety margin is mis-tuned" when reading a debug log.
    public static func logContextOverflow(estimatedTokens: Int,
                                          budgetTokens: Int,
                                          mode: PolishMode) {
        if #available(iOS 14.0, macOS 11.0, *) {
            PolishLog.logger.info(
                "📊 polish context-overflow mode=\(mode.rawValue, privacy: .public) estimatedTokens=\(estimatedTokens, privacy: .public) budgetTokens=\(budgetTokens, privacy: .public) — engine not called"
            )
        }
    }

    /// Emit one line to the `polish` os_log category. Prefixed with `📊 polish`
    /// so debug log readers can grep for the polish stream.
    public static func log(_ m: PolishMetrics) {
        if #available(iOS 14.0, macOS 11.0, *) {
            let t = m.timings
            let breakdown = t.map { " timings=pre:\($0.preprocessMs)/engine:\($0.engineMs)/post:\($0.postprocessMs)" } ?? ""
            // Appended only on a failure (#315): the reason is nil on the ~80% of
            // events that succeed, and a `reason=-` on every one of them would
            // pay for nothing.
            let reason = m.failureReason.map { " reason=\($0.slug)" } ?? ""
            // How the target was arrived at (#332), appended only when the
            // event carries the trail so pre-#332 events keep their old shape.
            // `inert` marks a code the engine ignores — Parakeet auto-detects
            // from audio, so `stt:de` there says nothing about what was heard.
            let resolution = m.languageResolution.map { r in
                let inert = r.sttLanguageIsEffective ? "" : "(inert)"
                return " resolution=tx:\(r.transcriptionMode)/kbd:\(r.keyboardLanguage)"
                    + "/stt:\(r.sttLanguageCode)\(inert)"
            } ?? ""
            PolishLog.logger.info(
                "📊 polish outcome=\(m.outcome.rawValue, privacy: .public) engine=\(m.engine, privacy: .public) mode=\(m.mode?.rawValue ?? "-", privacy: .public) target=\(m.targetLanguage?.rawValue ?? "none", privacy: .public) detected=\(m.detectedLanguage ?? "-", privacy: .public)\(resolution, privacy: .public) stt=\(m.sttEngine ?? "-", privacy: .public)/\(m.sttModelID ?? "-", privacy: .public) chars=\(m.rawCharCount, privacy: .public)→\(m.polishedCharCount, privacy: .public) latencyMs=\(m.latencyMs, privacy: .public)\(breakdown, privacy: .public)\(reason, privacy: .public)"
            )
        }
    }
}

private enum PolishLog {
    @available(iOS 14.0, macOS 11.0, *)
    static let logger = Logger(subsystem: "com.pivi.dictus", category: "polish")
}
