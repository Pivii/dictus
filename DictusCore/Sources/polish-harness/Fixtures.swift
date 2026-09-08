// DictusCore/Sources/polish-harness/Fixtures.swift
import Foundation
import DictusCore

/// One eval case: a raw STT transcript + the target language + optional
/// contract expectations. `raw` is exactly the `raw` field from a device JSON
/// export — the polish input is text, so no audio is needed.
struct Fixture: Codable {
    let id: String
    let raw: String
    /// BCP-47-ish: "fr" / "en" / "es" / "de" runs the per-language path.
    /// Anything else ("auto", "zh", "it", …) runs the Auto-detect path (#239)
    /// — mirroring the app, where languages without a dedicated prompt only
    /// ever reach polish through auto mode.
    let lang: String
    /// "PK" (Parakeet) or "WK" (WhisperKit). Defaults to Parakeet.
    let sttEngine: String?
    /// Declarative contract checks (eval mode). Each entry sets ONE predicate.
    let expect: [Expectation]?

    /// `nil` routes the fixture through the Auto-detect path.
    var language: SupportedLanguage? { SupportedLanguage(rawValue: lang) }
    var speechEngine: SpeechEngine { sttEngine == "WK" ? .whisperKit : .parakeet }

    /// The same case routed through another path (`--lang`, #439).
    ///
    /// A dictation reaches polish through the per-language prompt or through the
    /// Auto one depending on a SETTING, not on the text: the six #439 fixtures were
    /// captured under `autoDetect` and so took `PolishAutoPrompt`, while their `lang:
    /// "fr"` runs them under `PolishNaturalPromptFR`. Both prompts have to hold, so
    /// both get measured — and the alternative to this two-line override is a second
    /// fixture file holding a second copy of the same six transcripts, which is a
    /// copy that can drift from the device export it is supposed to be.
    func routed(through lang: String) -> Fixture {
        Fixture(id: id, raw: raw, lang: lang, sttEngine: sttEngine, expect: expect)
    }
}

/// A single tolerant assertion on the polished output. LLM output is
/// non-deterministic, so these check *properties* (the contract), not an exact
/// string. Exactly one field is expected to be set per entry.
struct Expectation: Codable {
    /// Output must contain this substring (case-insensitive).
    var contains: String?
    /// Output must NOT contain this substring (case-insensitive).
    var notContains: String?
    /// No match for this regex (e.g. `\n\n\n` for stray newlines, `<<NL>>` leak).
    var regexAbsent: String?
    /// polishedCount / rawCount must be ≥ this (guards against truncation).
    var lengthRatioMin: Double?
    /// polishedCount / rawCount must be ≤ this (guards against invention).
    var lengthRatioMax: Double?
    /// Every `<<NL>>` the engine was handed comes back as a line break.
    ///
    /// WHY this is not `regexAbsent: "<<NL>>"`, which `seed.json` already carries:
    /// that assertion passes both when the marker is CONVERTED to a newline and when
    /// it is DELETED outright, and those are opposite results. The absence check was
    /// green through the whole #518 campaign while a device session was losing three
    /// markers out of three and printing no line break at all. Counting is what tells
    /// the two apart, and the count has to be taken against the text the engine
    /// received — the marker only exists after the pre-pass.
    ///
    /// The bar is "at least as many", not "exactly as many". Normal polish is
    /// allowed to ADD whitespace and never to REMOVE words, so an extra paragraph
    /// break is within contract while a lost marker is not. Both counts are printed
    /// on failure, so a reader sees which of the two happened.
    ///
    /// It is judged on the ENGINE's output, not on what would reach the document.
    /// Those differ exactly where this check matters: on any non-success the free
    /// polish falls back to the deterministic floor, and the floor is the pre-passed
    /// text — which still carries every line break. Asserting on the inserted text
    /// would therefore pass a run in which the model deleted all of them, which is
    /// the very hole this check was added to close, one level further down.
    var lineBreaksPreserved: Bool?

    /// The run's outcome must be this `PolishMetrics.Outcome` raw value.
    ///
    /// A run-level assertion rather than a text one: a fixture that exists to prove
    /// a REFUSAL has no text to inspect, and `refusal-cs.json` was committed with an
    /// empty expectation list for that reason — which asserted nothing at all, so a
    /// Czech translate that started succeeding would have passed it silently.
    var outcome: String?

    /// The engine failure's slug must be this `PolishFailureReason`.
    ///
    /// Paired with `outcome` rather than folded into it, because `engineFailed` alone
    /// would be satisfied by a refusal for any other reason and a negative control has
    /// to name the one it is about.
    ///
    /// `refusal-cs.json` was that control and no longer carries this half (#490): its
    /// refusal is now the local pre-flight's, `unsupportedInputLanguage` with nothing
    /// thrown, because the pipeline asks which languages the backend reads before
    /// calling it. The field stays for any fixture that does assert on a throw.
    var failureReason: String?

    /// Limit this assertion to one prompt route: `"perLanguage"` or `"auto"`.
    /// Absent means it holds on both, which is the default and the common case.
    ///
    /// Needed because the two prompts disagree about one shape on purpose. An
    /// off-language fragment inside otherwise-French speech is a rule-8 repair
    /// target under `PolishNaturalPromptFR`, and under `PolishAutoPrompt` it is
    /// PRESERVED by name (*"Mixed-language input keeps every part in its original
    /// language"*). Asserting its absence on both routes marks the auto prompt's
    /// own contract as a failure, which is measuring the fixture rather than the
    /// prompt. Everything else here holds on both routes and carries no value.
    var onlyOnRoute: String?

    /// The route name a fixture runs under, for `onlyOnRoute`.
    static func routeName(perLanguage: Bool) -> String {
        perLanguage ? "perLanguage" : "auto"
    }

    /// Whether this assertion applies on `route`.
    func applies(to route: String) -> Bool {
        onlyOnRoute == nil || onlyOnRoute == route
    }

    /// Whether this assertion reads the text that would reach the document.
    ///
    /// Used by `eval` to decide whether "the mode inserted nothing" is a failure:
    /// for a fixture asserting on the run (`outcome`, `failureReason`) it is the
    /// expected result, and for one asserting on the text it is the absence of the
    /// thing under test.
    var inspectsInsertedText: Bool {
        contains != nil || notContains != nil || regexAbsent != nil
            || lengthRatioMin != nil || lengthRatioMax != nil
    }

    /// Evaluate against everything one run produced. Returns nil on pass, or a
    /// human-readable reason.
    func failure(_ run: RunEvidence) -> String? {
        if let expected = outcome, run.outcome != expected {
            return "outcome \(run.outcome), expected \(expected)"
        }
        if let expected = failureReason, run.failureReason != expected {
            return "failure reason \(run.failureReason ?? "none"), expected \(expected)"
        }
        if lineBreaksPreserved == true {
            // `preprocessed` is the pre-pass output, not `raw`: the marker only
            // exists once `VerbalPunctuationPrepass` has turned spoken "retour à la
            // ligne" into a newline. It is encoded here the way `PolishPipeline`
            // encodes it, so what is counted is what the engine was sent rather than
            // a stand-in for it. The engine's own output comes back already decoded
            // (`PolishPipeline.transform`), so the other side counts real newlines.
            let markers = PolishPostpass.encodeForEngine(run.preprocessed)
                .components(separatedBy: PolishPostpass.newlineMarker).count - 1
            guard let engineOutput = run.engineOutput else {
                return markers == 0
                    ? nil
                    : "\(markers) line-break marker(s) in, and the engine produced "
                        + "no output to check (\(run.outcome))"
            }
            let breaks = engineOutput.filter(\.isNewline).count
            if breaks < markers {
                return "\(markers) line-break marker(s) in, \(breaks) line break(s) out"
            }
        }
        // Everything below reads the text that would reach the document. When there
        // is none, `eval` says so once rather than once per assertion.
        guard let polished = run.polished else { return nil }
        if let needle = contains,
           polished.range(of: needle, options: .caseInsensitive) == nil {
            return "missing \"\(needle)\""
        }
        if let needle = notContains,
           polished.range(of: needle, options: .caseInsensitive) != nil {
            return "contains forbidden \"\(needle)\""
        }
        if let pattern = regexAbsent,
           polished.range(of: pattern, options: .regularExpression) != nil {
            return "matched forbidden /\(pattern)/"
        }
        let ratio = run.raw.isEmpty ? 1 : Double(polished.count) / Double(run.raw.count)
        if let lo = lengthRatioMin, ratio < lo {
            return String(format: "length ratio %.2f < %.2f", ratio, lo)
        }
        if let hi = lengthRatioMax, ratio > hi {
            return String(format: "length ratio %.2f > %.2f", ratio, hi)
        }
        return nil
    }
}

/// Everything one run produced, as the expectations see it.
///
/// Grouped rather than passed loose because the assertions no longer all read the
/// same string: `lineBreaksPreserved` judges the ENGINE's output, `outcome` and
/// `failureReason` judge the run, and the rest judge what would reach the document.
/// Passing five arguments in a fixed order is how the first two got asserted against
/// the wrong one.
struct RunEvidence {
    /// What would reach the document, nil when nothing would (a Smart Mode refusal).
    let polished: String?
    /// The fixture's verbatim transcript.
    let raw: String
    /// The pre-pass output — the text the engine was handed, before marker encoding.
    let preprocessed: String
    /// The model's own output, already decoded; nil when it never produced one.
    let engineOutput: String?
    /// `PolishMetrics.Outcome` raw value.
    let outcome: String
    /// `PolishFailureReason` slug, when the engine threw.
    let failureReason: String?
}

enum FixtureLoader {
    static func load(_ path: String) throws -> [Fixture] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Fixture].self, from: data)
    }
}
