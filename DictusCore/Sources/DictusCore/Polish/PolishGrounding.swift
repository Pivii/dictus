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

/// The two numbers the worst-segment overlap check needs (#414).
///
/// They travel together because neither means anything alone. The floor decides how
/// little of a line may be the speaker's before the line is called invented; the
/// minimum decides which lines carry enough content words for a share to be a
/// measurement rather than a coin toss.
///
/// Measured, not chosen. Scored over the committed corpora with
/// `swift run polish-harness guardrail docs/research/413-414-guardrail/*.json --sweep`,
/// which drives no model. Table in `docs/research/413-414-guardrail-resolution.md` §8.
///
/// **The two populations touch, and that is the whole difficulty.** Over the 331
/// outputs the check reads a share on, the worst of 321 legitimate ones scores
/// **0.200** and the worst of 10 fabricated ones scores **0.200** as well. No floor
/// separates them strictly, so this one is set *below* both: it takes the 8
/// fabrications that score 0.000 — a line with no word of the speaker in it at all —
/// and leaves the two that score higher to the named-entity check, which catches one
/// of them. Raising it to 0.25 takes the third and costs a measured false rejection;
/// that trade was declined on 2026-09-07.
public struct PolishSegmentOverlapThresholds: Equatable, Sendable {

    /// Share of a segment's content words that must also appear in the input.
    /// Strictly below it the output is refused.
    public let floor: Double

    /// Fewest content words a segment must carry to be judged at all. Below it the
    /// segment passes untested, the way a short segment passes the language check
    /// untested.
    ///
    /// Three. A segment of one or two content words can only score 0, 0.5 or 1, so a
    /// single unmatched word would refuse a whole dictation — the shape a heading
    /// like `Actions :` has. The corpus scores identically at 1, 2 and 3, so this
    /// costs nothing measured; 4 costs a measured catch (`W2-nom-prefixe`, whose
    /// fabricated bullet carries exactly 3).
    public let minimumContentWords: Int

    /// `assert` rather than `precondition`, and no clamping, for the reasons
    /// `PolishPrefixAlignmentThresholds` gives at length: this code runs inside the
    /// keyboard extension, where a doubtful number must not become a crash
    /// mid-dictation, and the only caller that varies these is the harness's sweep,
    /// which must print the numbers it actually measured.
    public init(floor: Double, minimumContentWords: Int) {
        assert(floor.isFinite && floor >= 0 && floor <= 1,
               "floor must be a finite share in [0, 1]; got \(floor)")
        assert(minimumContentWords > 0,
               "minimumContentWords must be positive; got \(minimumContentWords)")
        self.floor = floor
        self.minimumContentWords = minimumContentWords
    }

    /// The measured pair. See the type's doc for where the numbers come from.
    public static let `default` = PolishSegmentOverlapThresholds(
        floor: 0.15, minimumContentWords: 3
    )
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
/// ### The second query, now written: worst-segment overlap
///
/// A fabrication carrying no name at all was invisible to the anchor check. The
/// paragraph this replaces predicted the shape of the answer — *"the other query
/// over the same tokens: how much of the output's vocabulary appears in the input at
/// all"* — and said it would wait for a fixture set. The set exists now, and
/// `worstSegmentOverlap(ofOutput:against:thresholds:)` below is that query, asked
/// **per segment** rather than over the whole output, for the reason #413 had to ask
/// the language question per segment: `N2-reunion-vrac` scores 0.739 over the whole
/// output and 0.000 on its fabricated bullet, because one invented line in an
/// otherwise sound list is diluted by the rest.
///
/// It is not #349's answer. #349's capture is a *repair* event, and repair turns
/// this whole family of checks off — see `PolishAcceptanceContract.repair`, and #466
/// for the measurement that shut that door for good. The two checks here run on the
/// same contract field and are complementary rather than redundant: over the
/// committed corpora the anchors catch 7 of 10 fabrications, overlap catches 8 of
/// 10, and between them they catch 9. Neither is a superset of the other.
///
/// ### What it still does not catch, stated plainly
///
/// `Z1-sophie-reoccurrence` — the same invented bullet as the measured defect with
/// one clause reworded — scores above the floor and is accepted. Closing it needs a
/// floor of 0.25, which costs a measured false rejection. That trade was declined on
/// 2026-09-07 and the miss ships knowingly open; if a user reports a fabricated line
/// in the field, 0.25 is the lever and its cost is already measured.
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
        let inputWords = normalisedWordList(in: input)
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

    // MARK: - Worst-segment overlap (#414)

    /// `true` when no segment of `polished` is too foreign to `raw` to have come from
    /// it, as far as this check is concerned.
    ///
    /// Every uncertainty resolves toward `true`, for the reason it does everywhere
    /// else in this family: a rejection costs a Smart Mode user everything they said.
    /// An output with no judgeable segment, or an empty input, passes untested.
    public static func acceptsSegmentOverlap(polished: String,
                                             raw: String,
                                             thresholds: PolishSegmentOverlapThresholds = .default) -> Bool {
        guard let worst = worstSegmentOverlap(ofOutput: polished, against: raw, thresholds: thresholds) else {
            return true
        }
        return worst >= thresholds.floor
    }

    /// The share of content words the *least* supported segment of `output` shares
    /// with `input`, or `nil` when no segment is long enough to judge.
    ///
    /// The measurement behind `acceptsSegmentOverlap`, exposed for the harness's
    /// sweep and for tests — a sweep needs the reading, not the verdict, the same
    /// reason `anchors(in:languageCode:)` is public.
    ///
    /// ### Content words, and why the list is one-sided
    ///
    /// A segment's function words are dropped before the share is taken, because
    /// they are shared by every sentence in a language and would drown the signal:
    /// `Appeler Sophie avant : elle a les données de décembre` is 60 % French
    /// grammar, and counting it whole scores an invented bullet at 0.4 against a
    /// dictation it has nothing to do with. Dropping them scores it 0.000. Measured:
    /// with no list at all the check catches 2 of 9 instead of 7 of 9 on the two
    /// corpora #414 replays.
    ///
    /// `functionWords` covers the four languages the polish prompts are written in.
    /// A language it does not list simply keeps all its words, which **raises** every
    /// share and so can only make the check accept more — the safe direction, and the
    /// same direction every other uncertainty in this file resolves toward. That is
    /// why an incomplete list is a tolerable artefact and a wrong threshold is not.
    public static func worstSegmentOverlap(ofOutput output: String,
                                           against input: String,
                                           thresholds: PolishSegmentOverlapThresholds = .default) -> Double? {
        let spoken = Set(PolishLexicon.words(in: input))
        guard !spoken.isEmpty else { return nil }
        var worst: Double?
        for segment in PolishSegmentation.segments(of: output) {
            let content = contentWords(in: segment)
            guard content.count >= thresholds.minimumContentWords else { continue }
            let share = Double(content.count { spoken.contains($0) }) / Double(content.count)
            worst = worst.map { Swift.min($0, share) } ?? share
        }
        return worst
    }

    /// The text's words with the function words of the four supported languages
    /// removed.
    ///
    /// Tokenised by `PolishLexicon`, never by a second tokeniser: two checks that
    /// disagree about what a word is would disagree about their answers for reasons
    /// no reader could trace. The list is applied here rather than in `PolishLexicon`
    /// because that type is deliberately list-free — the anchor check below matches
    /// names and must not have `de` or `von` removed from an input under it.
    private static func contentWords(in text: String) -> [String] {
        PolishLexicon.words(in: text).filter { !functionWords.contains($0) }
    }

    /// Closed-class words plus the handful of adverbs and light verbs that carry no
    /// reference, for the four languages the polish prompts are written in
    /// (`SupportedLanguage`), already lowercased and diacritic-folded so they compare
    /// equal to what `PolishLexicon.fold` produces.
    ///
    /// ### It is load-bearing, and its edges were measured
    ///
    /// The list is not decoration. `avant` is on it, and the flagship defect —
    /// `Appeler Sophie avant : elle a les données de décembre` against a dictation
    /// that says `avant la réunion` — scores 0.000 with it and 0.200 without, which
    /// is the difference between catching that bullet and missing it. A list trimmed
    /// to determiners, pronouns, prepositions and auxiliaries alone catches 5 of 9
    /// instead of 7 of 9. Both variants are in
    /// `docs/research/413-414-guardrail-resolution.md` §8.
    ///
    /// It is written as a literal rather than loaded from the frequency dictionaries
    /// this repo already ships (`FrequencyDictionary`): those are 10 000-word bundle
    /// resources loaded one language at a time, and this check runs inside the
    /// keyboard extension (#361), where the budget is ~50 MB.
    private static let functionWords: Set<String> = {
        let list = """
        le la les un une des du de d au aux et ou ni mais donc or car que qui quoi dont a en y
        il elle ils elles on nous vous je tu me te se ce cet cette ces son sa ses leur leurs
        mon ma mes ton ta tes notre nos votre vos pour par avec sans sur sous dans chez vers entre
        pas ne plus tres bien tout tous toute toutes meme aussi comme si quand alors depuis apres
        avant encore deja etre avoir fait faire est sont etait ete suis es sommes etes ont as ai
        avons avez peut peux pouvoir doit dois devoir va vais aller

        the a an of to in on at for with by from as is are was were be been being and or but not no
        so if then than that this these those it its he she they we you i him her them us my your
        our their his hers do does did done have has had will would can could should may might must
        there here what which who whom when where how all any some more most very just also into
        out up down over under about

        el los las lo unos unas y o pero del al por para con sin sobre se es son era eran ser estar
        esta estan su sus mi mis tus este esto esos esas cuando donde muy mas ya tambien todo todos
        toda todas

        der die das den dem des ein eine einen einem einer eines und oder aber nicht kein keine von
        zu mit auf im am an fur uber unter bei nach aus vor durch ist sind war waren sein haben hat
        habe hatte werden wird wurde ich du er wir ihr mich dich sich uns euch mein dein ihre unser
        dass wenn als auch noch nur schon sehr mehr alle alles
        """
        return Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
    }()

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

    /// Whether the input contains this anchor as a **contiguous, ordered** run of
    /// words.
    ///
    /// ### Why a sequence and not a bag of words
    ///
    /// The first version asked only that every word of the anchor appear somewhere
    /// in the input, which let two fabrications through and was caught in review:
    ///
    /// - `Alice Smith` was grounded by an input mentioning an unrelated `Alice` and
    ///   an unrelated `Smith` in different sentences. The model can compose a person
    ///   who was never named out of two who were.
    /// - `Paul` was grounded by an input containing only `Pauline`, because the
    ///   match allowed a prefix in either direction. A fabricated name that happens
    ///   to be a prefix of a real one is exactly the shape this check exists to
    ///   catch.
    ///
    /// Requiring the words in order and adjacent closes both: a name is grounded
    /// only when the input actually names that person.
    ///
    /// ### The one inflection allowance, and its bounds
    ///
    /// A non-final anchor word may match an input word carrying **one** extra
    /// trailing letter, and only in a multi-word anchor. That is there for German
    /// declension — an output writing `Herr Müller` where the input said
    /// `Herrn Müller` — and it is deliberately too narrow to reopen the hole above:
    /// `Paul` is a single-word anchor, so it gets no allowance at all, and the
    /// anchor's last word (the surname, the part that identifies) must always match
    /// exactly.
    ///
    /// What it still admits: a two-word anchor whose *first* word is a one-letter
    /// variant of the input's, e.g. `Martin Dupont` against `Martine Dupont`. That
    /// is an alteration of a named person rather than an invention of one, it needs
    /// the surname to match exactly and adjacently, and no German-free alternative
    /// covers the declension case. Stated rather than hidden.
    /// Testing seam for the matching rule alone.
    ///
    /// It exists because `NLTagger`'s recall is a *separate* limitation, documented
    /// on this type and pinned by its own tests: the French tagger does not fire on
    /// `Paul` or `Paul Durand` in an ordinary bullet, so a test of the matching that
    /// went through extraction would pass while asserting nothing. This lets the
    /// prefix and split-name rules be tested on their own terms.
    static func isGrounded(_ anchor: String, in input: String) -> Bool {
        isGrounded(anchor, in: normalisedWordList(in: input))
    }

    private static func isGrounded(_ anchor: String, in inputWords: [String]) -> Bool {
        let words = normalisedWordList(in: anchor)
        guard !words.isEmpty else { return true }
        guard words.count <= inputWords.count else { return false }
        for start in 0...(inputWords.count - words.count) {
            let matches = words.indices.allSatisfy { offset in
                token(words[offset],
                      matches: inputWords[start + offset],
                      allowInflection: words.count > 1 && offset < words.count - 1)
            }
            if matches { return true }
        }
        return false
    }

    /// One anchor word against one input word.
    private static func token(_ anchorWord: String,
                              matches inputWord: String,
                              allowInflection: Bool) -> Bool {
        if anchorWord == inputWord { return true }
        guard allowInflection, inputWord.count == anchorWord.count + 1 else { return false }
        return inputWord.hasPrefix(anchorWord)
    }

    /// Lowercased, diacritic-folded words, **in order**. Both sides go through this,
    /// so `Müller` in the output is supported by `muller` in the input and `Léa` by
    /// `lea`. Order is kept because the match is a sequence, not a set.
    ///
    /// Shared with `PolishPrefixAlignment` since #466 — see `PolishLexicon` for why
    /// two checks that compare an output to its input must not disagree about what
    /// a word is.
    private static func normalisedWordList(in text: String) -> [String] {
        PolishLexicon.words(in: text)
    }

    private static func normalise(_ text: String) -> String {
        PolishLexicon.fold(text)
    }
}
