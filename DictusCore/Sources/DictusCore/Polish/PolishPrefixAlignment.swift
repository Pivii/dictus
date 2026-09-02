// DictusCore/Sources/DictusCore/Polish/PolishPrefixAlignment.swift
// Does the output START with the user's words? (issues #466, #349)
import Foundation

/// The three numbers the prefix-alignment check needs, and the size of the text it
/// declines to read.
///
/// They travel together because none of them means anything alone. The window
/// decides how long a stretch of output is judged at once; the floor decides how
/// much of that stretch has to be the speaker's own words; the offset decides how
/// far into the output the speaker's words may legitimately start. Change one and
/// the other two are measuring something else.
///
/// Measured, not chosen. Scored over the committed corpus with
/// `swift run polish-harness guardrail docs/research/413-414-guardrail/*.json --sweep`,
/// which drives no model. The tables it prints are in
/// `docs/research/466-preamble-guardrail.md` §6 and §8.
///
/// **The separation these sit in is wide and empty.** Over the corpus: every one of
/// the 102 legitimate free-polish outputs starts being supported at word 0, except
/// one at word 2. The two captured preambles start at word 6 and word 16, and the
/// three captured refusals never start at all. The offset threshold is the midpoint
/// of that gap.
public struct PolishPrefixAlignmentThresholds: Equatable, Sendable {

    /// How long a stretch of the output is examined at once, in words.
    ///
    /// About a clause. Short enough to sit inside a six-word preamble rather than
    /// straddle it — **the first version of this check used a 12-word window and a
    /// six-word preamble slipped past it on device**, because the window spanned the
    /// preamble and reached into the real text behind it. Long enough that two or
    /// three substituted words cannot swing it. Clamped to the output's length.
    public let windowWords: Int

    /// Share of that stretch which has to be words the speaker actually said.
    /// Rounded up, so 0.70 over an 8-word window asks for 6 of them.
    public let supportFloor: Double

    /// How many words of the output may precede the first supported stretch. Above
    /// it, the output opens with something that is not the user's text, which is the
    /// defect.
    ///
    /// Not zero: ADR 0003 licenses deleting an opening filler run and substituting a
    /// spoken punctuation command, and both leave the output's head shifted by a
    /// word or two.
    public let maximumOffsetWords: Int

    /// Fewest words either side must carry for the question to be asked at all.
    /// Below it the check passes untested: a five-word dictation has no prefix to
    /// align, and guessing at one would refuse a good output for nothing.
    public let minimumWords: Int

    public init(windowWords: Int, supportFloor: Double, maximumOffsetWords: Int, minimumWords: Int) {
        self.windowWords = windowWords
        self.supportFloor = supportFloor
        self.maximumOffsetWords = maximumOffsetWords
        self.minimumWords = minimumWords
    }

    /// The measured set. See the type's doc for where the numbers come from.
    public static let `default` = PolishPrefixAlignmentThresholds(
        windowWords: 8, supportFloor: 0.70, maximumOffsetWords: 4, minimumWords: 8
    )
}

/// Whether the output opens with the words the user actually dictated.
///
/// ### The hole this closes
///
/// Apple FM answered the polish prompt like a chatbot and the keyboard typed the
/// answer. Captured on device 2026-09-01 (#466), `natural` mode, target `fr`:
///
/// ```
/// raw       Okay donc là je refait les tests que j'ai fait parce que j'étais en…
/// polished  Bien sûr, je vais vous aider à polir votre texte. Voici la version polie :
///           Je vais donc faire de nouveau les tests que j'ai faits, car je suis en…
/// ```
///
/// Every guardrail passed it. The length ratio was 1.60, inside Natural's
/// `[0.5, 2.0]`. `detectedLanguageMatches` passed whole and per segment, because a
/// model instructed to write French writes its chat reply in French too.
/// `PolishGrounding` passed because the preamble names no person, place or
/// organisation. What was missing is any check that the output *starts where the
/// input starts*.
///
/// #349 is the same phenomenon from the other end — Apple FM refusing
/// (*"Je suis désolé, mais je ne peux pas fournir une sortie polie pour ce texte…"*)
/// and the refusal being inserted as the user's dictation, also with
/// `outcome = success`. Same engine, same blind spot, one detector: a preamble reads
/// as alignment starting late, a refusal as no alignment anywhere.
///
/// ### What it measures
///
/// Not "does the input's opening reappear in the output" — that was the first
/// version and **a device test falsified it**. It slid a 12-word window along the
/// output looking for the input's opening words, which cannot see a preamble
/// shorter than the window: a six-word one leaves the window straddling it, half in
/// the junk and half in the real text, still carrying enough of the input's opening
/// to pass. That is a limit of the shape, not a mis-set number, and no threshold in
/// the sweep recovered it.
///
/// What it measures instead is **where the output starts being made of the user's
/// words.** Slide a short window along the output and find the earliest position
/// where `supportFloor` of it is vocabulary the speaker actually used. A faithful
/// polish is supported from word 0; a preamble is a stretch of the model's own
/// words in front of the user's, so support starts late; a refusal is never
/// supported at all.
///
/// | | reads as |
/// |---|---|
/// | ordinary polish | supported from word 0 |
/// | **#466**, a preamble | support starts late |
/// | **#349**, a refusal | never supported |
///
/// The measurement is still comparative and still between two texts the same
/// dictation produced. What changed is which side is scanned: the output's head is
/// now the thing being judged, rather than the thing being searched.
///
/// ### Why comparative, and not a list of phrases
///
/// A per-language list of meta-discourse openers ("Bien sûr", "Voici", "Sure,
/// here's") was weighed and rejected. The test here is between two texts the same
/// dictation produced, so nothing is maintained per language and nothing rots as
/// Apple FM's phrasing changes. `PolishNaturalPromptFR.swift:24` already names five
/// such formulas as forbidden and the captured output opens with two of them, which
/// is the measured evidence that naming the words does not work.
///
/// ### It rejects, it never repairs
///
/// The preamble arrives as its own line and is mechanically separable, and cutting
/// it is still not what happens. A post-pass that cuts the head of an output can cut
/// a real sentence of the user's — ADR 0003 forbids that and #441 banned it
/// explicitly — and a wrong cut is permanent where a missing polish is not. The
/// property `PolishGuardrail` already has, *when it refuses, the user keeps their
/// own words*, is worth more than recovering a polish that was 90 % good.
///
/// ### Where this must NOT run
///
/// Only where the output is expected to reuse the input's own words in the input's
/// own order, which the task's contract answers with
/// `PolishAcceptanceContract.requiresAlignedPrefix`: **Natural and Auto**. Three
/// tasks answer no, and the third was a measurement rather than a judgement:
///
/// - **List restructures.** It condenses a rambling dictation into bullets that
///   synthesise, so the first bullet need not come from the first sentence.
/// - **Translation keeps no word of the input**, so there is nothing to align
///   anywhere, let alone at the head.
/// - **Repair reconstructs in a different language.** `PolishPipeline.mode` selects
///   it precisely when the detected language differs from the target, so a repair
///   output is a translation in all but name and shares no vocabulary with its
///   input. #466's scope section put repair in scope; the corpus said otherwise —
///   **10 of 10 legitimate repair outputs are refused, at every threshold pair in
///   the sweep.** See `docs/research/466-preamble-guardrail.md` §6.3.
///
/// ### Two accepted holes, stated on purpose
///
/// **A preamble inside a List or a Translate output is invisible here.** It is seen
/// only by `PolishGrounding`, and only if it invents a named entity — which a
/// preamble about the act of polishing does not.
///
/// **And so is one inside a Repair output**, which is where #349's own capture was
/// recorded. The same string IS refused when it arrives on the Natural or Auto path,
/// and repair is the mode where nothing can look at it: no lexical measure separates
/// a refusal from a legitimate cross-lingual reconstruction, because both share
/// nothing with the input by construction. #349 therefore does not close on the
/// strength of this type alone, and that is written here rather than discovered
/// later.
///
/// ### What it does not catch, stated plainly
///
/// **A preamble of about four words or fewer.** `maximumOffsetWords` is 4 because
/// ADR 0003 licenses deleting an opening filler run, and the corpus holds a
/// legitimate output whose own words start at word 2. A preamble that fits inside
/// that tolerance is arithmetically the same event as a deleted filler run, so no
/// setting separates them: closing this hole means refusing a polish that opened by
/// dropping `euh alors donc en fait`. The two captured preambles are six and fifteen
/// words. Pinned by a test that asserts the miss.
///
/// **A model that talks about its own task after the user's text, or in the middle
/// of it.** It is supported from word 0 and passes. This closes the measured shape,
/// not the class.
public enum PolishPrefixAlignment {

    /// Where the input's opening reappears in the output.
    public enum Alignment: Equatable, Sendable {
        /// One side was too short to carry a prefix. Passes untested.
        case notApplicable
        /// The input's opening was found this many words into the output. Zero is
        /// the ordinary case.
        case aligned(offset: Int)
        /// The input's opening appears nowhere in the output — #349's shape.
        case unaligned
    }

    /// `true` when the output may be shown to the user, as far as this check is
    /// concerned.
    ///
    /// Every uncertainty resolves toward `true`, for the reason it does in
    /// `PolishGuardrail` and `PolishGrounding`: a rejection costs a user something
    /// they said.
    public static func accepts(polished: String,
                               raw: String,
                               thresholds: PolishPrefixAlignmentThresholds = .default) -> Bool {
        switch alignment(ofOutput: polished, against: raw, thresholds: thresholds) {
        case .notApplicable:
            return true
        case .aligned(let offset):
            return offset <= thresholds.maximumOffsetWords
        case .unaligned:
            return false
        }
    }

    /// The measurement behind `accepts`, exposed for the harness's scoring command
    /// and for tests — a sweep needs the offset, not the verdict.
    ///
    /// Slides a `windowWords` window along the output and returns the **earliest**
    /// offset at which `supportFloor` of the window is vocabulary the input
    /// contains. Earliest, because the question is where the output *starts* being
    /// the user's text; a well-supported stretch further in says nothing about its
    /// head.
    ///
    /// The support set is the whole input rather than its opening. Restricting it to
    /// the input's first 18, 24 or 30 words was measured and scores identically on
    /// this corpus, so the narrower rule would be a knob bought with no evidence.
    /// What it would additionally catch — an output that opens with the user's own
    /// words taken from the *end* of their dictation — is reordering, which ADR 0003
    /// forbids but which nothing in the field has produced.
    public static func alignment(ofOutput output: String,
                                 against input: String,
                                 thresholds: PolishPrefixAlignmentThresholds = .default) -> Alignment {
        let inputWords = PolishLexicon.words(in: input)
        let outputWords = PolishLexicon.words(in: output)
        guard inputWords.count >= thresholds.minimumWords,
              outputWords.count >= thresholds.minimumWords else {
            return .notApplicable
        }
        // Clamped to the output so a dictation shorter than the window is judged on
        // all of itself rather than on a window padded with nothing.
        let window = min(thresholds.windowWords, outputWords.count)
        let spoken = Set(inputWords)
        // Rounded up: a floor is a floor. Over an 8-word window, 0.70 asks for 6.
        let required = Int((Double(window) * thresholds.supportFloor).rounded(.up))
        for offset in 0...(outputWords.count - window) {
            let supported = outputWords[offset..<(offset + window)].count { spoken.contains($0) }
            if supported >= required { return .aligned(offset: offset) }
        }
        return .unaligned
    }
}
