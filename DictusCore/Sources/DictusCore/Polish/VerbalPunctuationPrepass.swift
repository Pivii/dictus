// DictusCore/Sources/DictusCore/Polish/VerbalPunctuationPrepass.swift
import Foundation

/// Deterministic regex substitution of verbal punctuation commands.
///
/// Runs BEFORE the polish engine sees the text. Round 3 on-device testing showed
/// Apple FM applies verbal-punctuation rules reliably in English but never in
/// French — re-stating the rule as a "mandatory exception" in the prompt didn't
/// move the needle. The behavior is a floor of the model, not a prompt-tuning
/// problem.
///
/// Since verbal punctuation is a deterministic transformation anyway (no
/// language understanding required), doing it in regex bypasses Apple FM
/// entirely for this concern. Apple FM still handles the rest of Light:
/// capitalisation, typographic spacing, accents, glossary spelling.
///
/// Scope at round 1: French and English. Spanish/German added in step 7.
///
/// Known false positives: literal references to punctuation ("ma virgule est
/// cassée", "I had a period of doubt") become substitutions. Accepted — the
/// dictation use case is dominant in practice.
public enum VerbalPunctuationPrepass {

    /// Apply the language's verbal-punctuation rules to `raw`. Returns the
    /// input unchanged for languages without configured rules.
    public static func apply(_ raw: String, language: SupportedLanguage) -> String {
        let rules = self.rules(for: language)
        guard !rules.isEmpty else { return raw }
        var out = raw
        for rule in rules {
            out = out.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return normalize(out)
    }

    // MARK: - Rules

    private static func rules(for language: SupportedLanguage) -> [(pattern: String, replacement: String)] {
        switch language {
        case .french:  return frenchRules
        case .english: return englishRules
        case .spanish, .german: return []
        }
    }

    /// Order matters: multi-word phrases before shorter substrings that would
    /// otherwise match a piece of them. `\b` enforces word boundaries so
    /// "trois points" (plural) does NOT trigger the singular "point" rule.
    /// `['’]` matches both ASCII and typographic apostrophe.
    private static let frenchRules: [(pattern: String, replacement: String)] = [
        (#"\bretour à la ligne\b"#, "\n"),
        (#"\bnouvelle ligne\b"#, "\n"),
        (#"\bà la ligne\b"#, "\n"),
        (#"\bpoint d['’]interrogation\b"#, "?"),
        (#"\bpoint d['’]exclamation\b"#, "!"),
        (#"\bpoint virgule\b"#, ";"),
        (#"\bdeux points\b"#, ":"),
        (#"\bvirgule\b"#, ","),
        (#"\bpoint\b"#, "."),
    ]

    private static let englishRules: [(pattern: String, replacement: String)] = [
        (#"\bnew line\b"#, "\n"),
        (#"\bnewline\b"#, "\n"),
        (#"\bquestion mark\b"#, "?"),
        (#"\bexclamation (mark|point)\b"#, "!"),
        (#"\bfull stop\b"#, "."),
        (#"\bsemicolon\b"#, ";"),
        (#"\bcolon\b"#, ":"),
        (#"\bperiod\b"#, "."),
        (#"\bcomma\b"#, ","),
    ]

    // MARK: - Normalization

    /// Collapse horizontal whitespace, strip spaces around inserted newlines,
    /// and tighten spacing around `,` and `.`. `;` `:` `!` `?` are left alone —
    /// French typography wants a non-breaking space before them and the Light
    /// polish pass is responsible for that.
    private static func normalize(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: [.regularExpression])
        out = out.replacingOccurrences(of: #" *\n *"#, with: "\n", options: [.regularExpression])
        out = out.replacingOccurrences(of: #" +([,.])"#, with: "$1", options: [.regularExpression])
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }
}
