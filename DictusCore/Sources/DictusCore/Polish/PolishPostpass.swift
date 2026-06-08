// DictusCore/Sources/DictusCore/Polish/PolishPostpass.swift
import Foundation

/// Code-level corrections applied AFTER the polish engine returns.
///
/// Round 4 round-1 testing showed Apple Foundation Models has two
/// behavioural floors we cannot prompt-tune past:
///
/// 1. Raw `\n` characters in the input get "naturalised" into `, ` + capital
///    on output. The model interprets a newline as a sentence-boundary cue
///    and rewrites the boundary in prose form, no matter how the prompt
///    spells out "preserve newlines".
///
/// 2. The model never inserts the U+00A0 NO-BREAK SPACE before `?`, `!`,
///    `;`, `:` even when the rule line says so and the examples literally
///    contain NBSP bytes. ASCII space and NBSP are indistinguishable to
///    its sampling.
///
/// Both are deterministic transformations — handling them in code is more
/// reliable than coaxing the model. The pre-engine `encodeForEngine` step
/// hides newlines behind a multi-char ASCII marker that survives the
/// round-trip; the post-engine `decodeFromEngine` step restores the
/// newlines and applies the French typographic spacing.
public enum PolishPostpass {

    /// String the engine sees in place of `\n`. Apple FM treats this as
    /// opaque text and passes it through unaltered (round-1 testing).
    /// The marker is intentionally verbose so user speech won't accidentally
    /// transcribe to the same bytes.
    public static let newlineMarker = "<<NL>>"

    /// Encode `\n` characters as the engine-safe marker. Run on the pre-pass
    /// output before handing the string to Apple FM.
    public static func encodeForEngine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: newlineMarker)
    }

    /// Run on the engine's output. Restores newlines from markers and
    /// applies language-specific typography Apple FM is unreliable about.
    public static func decodeFromEngine(_ polished: String,
                                        language: SupportedLanguage) -> String {
        var out = polished
        out = out.replacingOccurrences(of: newlineMarker, with: "\n")

        switch language {
        case .french:
            // NBSP before ? ! ; :. Pattern matches ONE ASCII space (U+0020)
            // immediately preceding the mark; any existing NBSP (U+00A0)
            // stays untouched. `[ ]` is the literal space character class
            // — avoids `\s` which would also match `\n` and `\t`.
            out = out.replacingOccurrences(
                of: #"[ ]([?!;:])"#,
                with: "\u{00A0}$1",
                options: [.regularExpression]
            )
        case .english, .spanish, .german:
            break
        }
        return out
    }
}
