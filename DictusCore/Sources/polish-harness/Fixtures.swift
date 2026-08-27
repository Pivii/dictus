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

    /// Evaluate against the polished output and the original raw. Returns nil on
    /// pass, or a human-readable failure reason.
    func failure(polished: String, raw: String) -> String? {
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
        let ratio = raw.isEmpty ? 1 : Double(polished.count) / Double(raw.count)
        if let lo = lengthRatioMin, ratio < lo {
            return String(format: "length ratio %.2f < %.2f", ratio, lo)
        }
        if let hi = lengthRatioMax, ratio > hi {
            return String(format: "length ratio %.2f > %.2f", ratio, hi)
        }
        return nil
    }
}

enum FixtureLoader {
    static func load(_ path: String) throws -> [Fixture] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Fixture].self, from: data)
    }
}
