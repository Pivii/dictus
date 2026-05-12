// DictusCore/Sources/DictusCore/Polish/PolishGuardrail.swift
import Foundation
import NaturalLanguage

/// Runtime sanity check on every polish output.
///
/// Two complementary checks:
/// 1. `accepts(raw:polished:mode:)` — character-length ratio. Catches catastrophic
///    over- or under-generation (empty output, runaway generation).
/// 2. `detectedLanguageMatches(polished:target:)` — language detection on the
///    polished output. Catches chat-reply contamination where Apple FM responds
///    conversationally in a different language (e.g. "I'll polish it for you"
///    when the user dictated French).
public enum PolishGuardrail {

    /// Returns `true` when `polished` is within the allowed ratio band for `mode`.
    /// Light: `[0.5, 2.0]`. Repair: `[0.3, 3.0]`. Empty raw → only empty polished accepted.
    public static func accepts(raw: String, polished: String, mode: PolishMode) -> Bool {
        guard !raw.isEmpty else { return polished.isEmpty }
        let ratio = Double(polished.count) / Double(raw.count)
        switch mode {
        case .light:  return (0.5...2.0).contains(ratio)
        case .repair: return (0.3...3.0).contains(ratio)
        }
    }

    /// Returns `true` when the top language hypothesis of `polished` matches `target`
    /// with confidence ≥ 0.5. Short outputs (< 12 characters) and low-confidence
    /// detections pass through — `NLLanguageRecognizer` is unreliable on either.
    ///
    /// The intended failure to catch is the Apple FM chat-reply pattern: target=fr
    /// but the engine emitted English. The char-ratio guardrail misses this when
    /// the chat reply happens to be similar length to the raw input.
    public static func detectedLanguageMatches(polished: String,
                                                target: SupportedLanguage) -> Bool {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let top = hypotheses.max(by: { $0.value < $1.value }),
              top.value >= 0.5 else {
            return true
        }
        return top.key.rawValue == target.rawValue
    }
}
