// DictusCore/Sources/polish-harness/Fixtures.swift
import Foundation
import DictusCore

/// One eval case: a raw STT transcript + the target language + optional
/// contract expectations. `raw` is exactly the `raw` field from a device JSON
/// export — the polish input is text, so no audio is needed.
struct Fixture: Codable {
    let id: String
    let raw: String
    /// BCP-47-ish: "fr" / "en" / "es" / "de". Maps to SupportedLanguage.
    let lang: String
    /// "PK" (Parakeet) or "WK" (WhisperKit). Defaults to Parakeet.
    let sttEngine: String?
    /// Declarative contract checks (eval mode). Each entry sets ONE predicate.
    let expect: [Expectation]?

    var language: SupportedLanguage { SupportedLanguage(rawValue: lang) ?? .french }
    var speechEngine: SpeechEngine { sttEngine == "WK" ? .whisperKit : .parakeet }
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
