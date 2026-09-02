// DictusCore/Sources/DictusCore/Polish/PolishLexicon.swift
// The tokens an output-versus-input comparison is made of (#414, #466).
import Foundation

/// Cutting text into comparable words, and folding them so two spellings of the
/// same word compare equal.
///
/// ### Why this is its own type
///
/// Two guardrails ask questions about the same tokens. `PolishGrounding` (#414)
/// asks whether a named entity in the output appears in the input;
/// `PolishPrefixAlignment` (#466) asks where in the output the input's opening
/// words reappear. `PolishGrounding` shipped with this normalisation private, and
/// #414's own doc predicted the second query would arrive — *"that is a second
/// function on this type"*. It turned out to be a second type, because it answers a
/// different question with a different shape, but it must not be a second
/// normalisation: two checks that disagree on what a word is would disagree on
/// their answers for reasons no reader could trace.
///
/// The folding is deliberately blunt — case and diacritics only, no stemming and no
/// list of any kind. `Müller` in the output is supported by `muller` in the input
/// and `Léa` by `lea`, and nothing else is claimed.
enum PolishLexicon {

    /// The text's words, lowercased, diacritic-folded, **in order**.
    ///
    /// A word is a run of letters or numbers; everything else separates. Order is
    /// kept because both callers need it — one matches a contiguous sequence, the
    /// other measures where a sequence starts.
    static func words(in text: String) -> [String] {
        fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Case- and diacritic-folded text, without splitting it.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
