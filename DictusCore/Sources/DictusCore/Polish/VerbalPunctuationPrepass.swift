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
/// cassée") become substitutions. Accepted — the dictation use case is
/// dominant in practice.
///
/// EXCLUDED ON PURPOSE — the bare sentence-period word (#185): French "point"
/// and English "period" are NOT in the rules. Unlike every other command they
/// are extremely common ordinary words ("un point de vue", "faire le point", "à
/// quel point" / "a period of time", "period drama"), and being single short
/// tokens they offer no multi-word context to disambiguate. Converting them
/// silently corrupts the sentence ("un point final" → "un. final"). We accept
/// the cost of dropping them because the LLM already supplies the terminal
/// period at natural sentence boundaries on its own (observed on device). The
/// unambiguous multi-word marks that merely CONTAIN "point" ("point
/// d'interrogation", "point d'exclamation", "point virgule") stay. The same
/// principle pre-emptively bars Spanish "punto" and German "Punkt" when those
/// languages get rules. Revisit once the LLM owns punctuation contextually.
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
        // Not yet implemented. When adding rules, do NOT include the bare
        // period word ("punto" / "Punkt") — see the type doc-comment (#185).
        case .spanish, .german: return []
        }
    }

    /// Order matters: multi-word phrases before shorter substrings that would
    /// otherwise match a piece of them. `\b` enforces word boundaries.
    /// `['’]` matches both ASCII and typographic apostrophe. The bare "point"
    /// rule is intentionally absent — see the type doc-comment (#185).
    private static let frenchRules: [(pattern: String, replacement: String)] = [
        (#"\bretour à la ligne\b"#, "\n"),
        (#"\bnouvelle ligne\b"#, "\n"),
        (#"\bà la ligne\b"#, "\n"),
        (#"\bpoint d['’]interrogation\b"#, "?"),
        (#"\bpoint d['’]exclamation\b"#, "!"),
        (#"\bpoint virgule\b"#, ";"),
        (#"\bdeux points\b"#, ":"),
        (#"\bvirgule\b"#, ","),
    ]

    /// The bare "period" rule is intentionally absent — see the type
    /// doc-comment (#185). "full stop" stays: it is unambiguous.
    private static let englishRules: [(pattern: String, replacement: String)] = [
        (#"\bnew line\b"#, "\n"),
        (#"\bnewline\b"#, "\n"),
        (#"\bquestion mark\b"#, "?"),
        (#"\bexclamation (mark|point)\b"#, "!"),
        (#"\bfull stop\b"#, "."),
        (#"\bsemicolon\b"#, ";"),
        (#"\bcolon\b"#, ":"),
        (#"\bcomma\b"#, ","),
    ]

    // MARK: - Normalization

    /// Post-substitution cleanup.
    ///
    /// Parakeet routinely surrounds the verbal-punctuation keyword it transcribes
    /// with its own punctuation (`", virgule,"` instead of `"virgule"`, `"? Point
    /// d'interrogation."` instead of `"Point d'interrogation"`). Naive substitution
    /// leaves runs like `,,,` or `?.` or `\n.` in the output. With Apple FM active,
    /// the Light pass smooths these — but in Passthrough mode (and to give the LLM
    /// less work either way) we clean them here.
    ///
    /// Strategy: stronger punctuation absorbs adjacent weaker punctuation.
    /// Priority high-to-low: `\n` > `?` `!` `;` `:` > `.` `,`.
    private static func normalize(_ s: String) -> String {
        var out = s
        // All horizontal-whitespace classes use [ \t]* explicitly so newline
        // characters introduced by the verbal-punctuation substitution don't
        // accidentally get swallowed by greedy `\s*` matches that span them.

        // 1. Collapse runs of the same strong mark ("? ?" → "?", "!!" → "!").
        out = out.replacingOccurrences(of: #"([?!;:])[ \t]*\1+"#, with: "$1", options: [.regularExpression])
        // 2. Collapse runs of the same weak mark (",,," → ",", ".." → ".").
        out = out.replacingOccurrences(of: #"([,.])[ \t]*\1+"#, with: "$1", options: [.regularExpression])
        // 3. Strong absorbs leading weak ("., ?" → " ?").
        out = out.replacingOccurrences(of: #"[.,]+([ \t]*[?!;:])"#, with: "$1", options: [.regularExpression])
        // 4. Strong absorbs trailing weak ("?., " → "? ").
        out = out.replacingOccurrences(of: #"([?!;:])[ \t]*[.,]+"#, with: "$1", options: [.regularExpression])
        // 5. Newline absorbs only TRAILING weak punctuation ("\n.," → "\n").
        //    A period BEFORE a newline is usually Parakeet's legitimate sentence
        //    terminator that we want to preserve (`"bien.\nA bientôt"`), so we
        //    do not absorb it.
        out = out.replacingOccurrences(of: #"\n[ \t]*[.,]+"#, with: "\n", options: [.regularExpression])
        // 6. Standard whitespace + spacing normalization.
        out = out.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: [.regularExpression])
        out = out.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: [.regularExpression])
        out = out.replacingOccurrences(of: #" +([,.])"#, with: "$1", options: [.regularExpression])
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }
}
