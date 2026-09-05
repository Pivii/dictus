// DictusCore/Sources/DictusCore/Polish/PolishLexicon.swift
// The tokens an output-versus-input comparison is made of (#414, #466).
import Foundation
import NaturalLanguage

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
            .flatMap(subdivide(_:))
    }

    /// One run of letters and digits, cut further **only if a tokeniser can cut it**.
    ///
    /// ### Why the split alone is not enough
    ///
    /// `split` separates on anything that is not a letter or a digit, which is every
    /// word boundary in a script that writes them — space, apostrophe, hyphen,
    /// punctuation. Chinese, Japanese, Thai and Khmer write none. A whole Chinese
    /// dictation is therefore **one token**, every check that counts words sees a
    /// length of 1, and `PolishPrefixAlignment` returns `.notApplicable` and accepts
    /// whatever the model returned. Measured: an authentic Chinese chat preamble was
    /// accepted, `caught 0/1`. Found by CodeRabbit reviewing PR #478; Auto mode
    /// (#239) is explicitly the language-agnostic route and `PolishPostpass` already
    /// anticipates CJK on it, so this is a live path (#409).
    ///
    /// ### Why the tokeniser only *refines*, and never replaces, the split
    ///
    /// `NLTokenizer` alone would be simpler and it changes French: it reads `j'ai`
    /// and `l'utilisateur` as single tokens, which fold to `jai` and `lutilisateur`.
    /// Both sides of a comparison go through this function, so the corpus does not
    /// notice — but `PolishGrounding` matches an output's anchor against the input's
    /// **words**, and an input saying `le rapport d'Alice` would then hold `dalice`
    /// while the output's anchor is `alice`. A real name, present in the dictation,
    /// would read as fabricated and cost the user their polish. No corpus entry has
    /// that shape, which is exactly why it must not be discovered later.
    ///
    /// So the split stays authoritative and the tokeniser is asked only about runs
    /// the split could not break. It is consulted when it finds **more than one**
    /// word inside such a run, which by construction can only happen where the run
    /// had no separators to begin with. A German compound comes back whole and is
    /// left alone; a Chinese sentence comes back as its words.
    private static func subdivide(_ run: Substring) -> [String] {
        // Cheap gate before allocating a tokeniser. No script in which words are
        // written without separators produces a run this short, and no Latin word
        // this short needs cutting — measured against German compounds, which the
        // tokeniser leaves whole anyway.
        guard run.count >= unsegmentedRunLength else { return [String(run)] }
        let text = String(run)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var found: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = text[range].filter { $0.isLetter || $0.isNumber }
            if !token.isEmpty { found.append(String(token)) }
            return true
        }
        return found.count > 1 ? found : [text]
    }

    /// Length at which a separator-free run is worth asking a tokeniser about.
    ///
    /// Eight. Long enough that the tokeniser is not consulted for ordinary words in
    /// a script that separates them, short enough to cover a two-word Chinese phrase.
    /// It cannot cause a wrong answer in either direction — below it the split's
    /// answer stands, above it the tokeniser only ever returns the same run when it
    /// finds no words inside.
    private static let unsegmentedRunLength = 8

    /// Case- and diacritic-folded text, without splitting it.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
