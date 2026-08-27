// DictusCore/Sources/DictusCore/Polish/PolishGrounding.swift
// Is the output ABOUT the input? (issue #414)
import Foundation
import NaturalLanguage

/// One thing an output asserts that can be checked against the input.
///
/// Today there is exactly one kind — a named entity. `kind` exists anyway because
/// the measurement that chose it also scored a second candidate (bare figures) and
/// rejected it, and a reader of a rejection needs to know which rule fired.
public struct PolishAnchor: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        /// A person, place or organisation, as `NLTagger`'s `.nameType` scheme reads it.
        case name
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// Whether the model's output is about the text it was given.
///
/// ### The hole this closes
///
/// `SmartModeNotesPrompt` carries a worked example whose output contains
/// `- Appeler Sophie avant : elle a les données de décembre`. Measured on 2026-08-25
/// (#393, PR #412), that exact line appeared in an **accepted** Notes output on a
/// dictation naming neither Sophie nor December: a person and a fact the user never
/// said, inserted into their document as their own words.
///
/// Neither existing guardrail can see it. The length band cannot — a fabricated
/// bullet is the same size as a real one, and PR #388 already measured the band
/// rejecting nothing in 240 calls. `detectedLanguageMatches` cannot — the example is
/// in the target language. What was missing is any check that the output is *about*
/// the input, and this is it.
///
/// ### Why named entities, and not capitalised words
///
/// The obvious cheap heuristic — "a capitalised word mid-sentence is a proper noun"
/// — is not merely worse, it is unusable, and German is why. German capitalises
/// every noun, so on `Die Rechnung für das Büro muss bis Freitag bezahlt werden` the
/// heuristic proposes `Rechnung`, `Büro` and `Freitag` as names and refuses an
/// ordinary German note. `NLTagger` reads the same sentence and returns `Herr
/// Müller` and nothing else. The campaign that produced this issue measured no
/// German at all, so the primitive had to be one that is safe there by construction
/// rather than by measurement.
///
/// ### Why not figures
///
/// Measured and rejected. ADR 0003 rule 3 *authorises* the polish to turn spoken
/// numbers into digits, and round 3 of the #393 campaign shows it doing exactly
/// that: `the build image is on eighteen` came back as `on 18`. A figure anchor
/// rejects that, which is a correct transformation being refused. Same for a
/// translation, where `alle undici` becomes `at 11`. See
/// `docs/research/413-414-guardrail-resolution.md` §6.
///
/// ### Where this must NOT run
///
/// Only where the output is expected in the input's own language and the
/// transformation is not licensed to replace words:
///
/// - **A translation localises names.** `Londres` becomes `London`, `mars` becomes
///   `March`. Surface identity is not expected, so the check would be measuring the
///   wrong thing.
/// - **Repair reconstructs words by design** (ADR 0002): its whole contract is
///   substituting what the speaker probably meant for what the STT emitted, which
///   can legitimately produce a name the raw does not contain.
///
/// The decision is a field on `PolishAcceptanceContract`, not a derivation — see
/// `requiresGroundedNames` for why.
///
/// ### What it does not catch, stated plainly
///
/// A fabrication carrying no name at all is invisible here. #349's measured case —
/// Apple FM answering *"Je suis désolé, mais je ne peux pas fournir une sortie
/// polie…"* in place of the user's dictation — contains no person, place or
/// organisation, so there is nothing for this check to look at. #349 needs the
/// *other* query over the same tokens: how much of the output's vocabulary appears
/// in the input at all. That is a second function on this type, not a different
/// mechanism, and it is deliberately not written until #349 has a fixture set to
/// size its threshold against.
public enum PolishGrounding {

    /// The anchors `output` asserts that `input` does not support.
    ///
    /// Empty means the output is grounded, which is the only answer that accepts.
    /// Every uncertainty resolves toward empty: an output the tagger finds no name
    /// in is grounded vacuously, because refusing on "I found nothing to check"
    /// would cost the user their dictation for the tagger's silence.
    ///
    /// - Parameter languageCode: the `NLLanguage` raw value the output is expected
    ///   to read as, when it is known. It is a hint to the tagger, not a filter.
    public static func ungroundedAnchors(in output: String,
                                         input: String,
                                         languageCode: String? = nil) -> [PolishAnchor] {
        let inputWords = normalisedWords(in: input)
        guard !inputWords.isEmpty else { return [] }
        return anchors(in: output, languageCode: languageCode).filter { anchor in
            !isGrounded(anchor.text, in: inputWords)
        }
    }

    /// Every anchor `output` carries, grounded or not. Exposed for the harness's
    /// scoring command and for tests; the pipeline only ever asks the question
    /// above.
    public static func anchors(in output: String, languageCode: String? = nil) -> [PolishAnchor] {
        // The tagger is run over the whole output AND over each segment, and the
        // results unioned, because its recall is context-sensitive in a way that
        // matters here: on the six-bullet list measured in round 1 it finds
        // `Thomas` when the bullet stands alone and misses it inside the block.
        // Two passes cost microseconds and the union can only find more.
        var seen = Set<String>()
        var found: [PolishAnchor] = []
        for text in [output] + PolishSegmentation.segments(of: output) {
            for name in names(in: text, languageCode: languageCode) {
                let key = normalise(name)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                found.append(PolishAnchor(text: name, kind: .name))
            }
        }
        return found
    }

    // MARK: - Extraction

    private static func names(in text: String, languageCode: String?) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        if let languageCode {
            tagger.setLanguage(NLLanguage(rawValue: languageCode),
                               range: text.startIndex..<text.endIndex)
        }
        var found: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if let tag, tag == .personalName || tag == .placeName || tag == .organizationName {
                found.append(String(text[range]))
            }
            return true
        }
        return found
    }

    // MARK: - Matching

    /// Whether every word of `anchor` is supported by some word of the input.
    ///
    /// Word-by-word rather than whole-anchor because `.joinNames` returns the
    /// nominative form of a multi-word name — `Herr Müller` — which a declined
    /// input (`Herrn Müller`) does not contain verbatim. Requiring every word to be
    /// supported keeps the check meaningful while surviving inflection.
    private static func isGrounded(_ anchor: String, in inputWords: Set<String>) -> Bool {
        let words = normalisedWords(in: anchor)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { word in
            // Prefix in either direction, so `herr` is supported by `herrn` and
            // `marion` by `marion`. NOT plain substring: `lea` is a substring of
            // `release`, and accepting that would ground a fabricated `Léa` on any
            // input mentioning a release.
            inputWords.contains { $0.hasPrefix(word) || word.hasPrefix($0) }
        }
    }

    /// Lowercased, diacritic-folded words. Both sides go through this, so `Müller`
    /// in the output is supported by `muller` in the input and `Léa` by `lea`.
    private static func normalisedWords(in text: String) -> Set<String> {
        Set(normalise(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty })
    }

    private static func normalise(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
