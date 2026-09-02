// DictusCore/Sources/DictusCore/Polish/PolishPrefixAlignment.swift
// Does the output START with the user's words? (issues #466, #349)
import Foundation

/// The three numbers the prefix-alignment check needs, and the size of the text it
/// declines to read.
///
/// They travel together because none of them means anything alone. The window
/// decides how much of the input's opening is the reference; the floor decides how
/// much of that reference a candidate window has to carry; the offset decides how
/// far into the output the reference may legitimately have moved. Change one and
/// the other two are measuring something else.
///
/// Measured, not chosen. Scored over the committed corpus with
/// `swift run polish-harness guardrail docs/research/413-414-guardrail/*.json --sweep`,
/// which drives no model. The table it prints is in
/// `docs/research/466-preamble-guardrail.md` §6.
public struct PolishPrefixAlignmentThresholds: Equatable, Sendable {

    /// How many of the input's opening words form the reference the output is
    /// searched for.
    ///
    /// Long enough that a couple of substituted words cannot sink it — ADR 0003
    /// licenses removing fillers and stutters and substituting spoken punctuation,
    /// all of which land in the opening — and short enough to fit inside a short
    /// dictation. It is clamped to the length of the shorter side, so a six-word
    /// dictation compares six words.
    public let windowWords: Int

    /// Share of the reference's **distinct** words a window of the output has to
    /// carry to count as the same passage. Rounded up, so a floor of 0.4 over a
    /// 12-word reference asks for 5 words.
    public let overlapFloor: Double

    /// How many words of the output may precede the reference. Above it the output
    /// opens with something that is not the user's opening, which is the defect.
    ///
    /// Not zero: the contract lets the model delete an opening filler run, and every
    /// word it deletes from the input's head is a word of *input* the reference
    /// window slides past, not a word of output — but a spoken-punctuation
    /// substitution ("virgule" → ",") and a rule 8 repair both leave the output's
    /// own head shifted. The sweep sizes the tolerance.
    public let maximumOffsetWords: Int

    /// Fewest words either side must carry for the question to be asked at all.
    /// Below it the check passes untested: a five-word dictation has no prefix to
    /// align, and guessing at one would refuse a good output for nothing.
    public let minimumWords: Int

    public init(windowWords: Int, overlapFloor: Double, maximumOffsetWords: Int, minimumWords: Int) {
        self.windowWords = windowWords
        self.overlapFloor = overlapFloor
        self.maximumOffsetWords = maximumOffsetWords
        self.minimumWords = minimumWords
    }

    /// The measured set. See the type's doc for where the numbers come from.
    public static let `default` = PolishPrefixAlignmentThresholds(
        windowWords: 12, overlapFloor: 0.4, maximumOffsetWords: 4, minimumWords: 8
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
/// A model that talks about its own task *after* the user's text, or in the middle
/// of it, aligns at offset 0 and passes. This closes the measured shape, not the
/// class.
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
    /// Takes the input's first `windowWords` words as a reference, slides a window
    /// of the same size along the output, and returns the **earliest** offset whose
    /// distinct words cover `overlapFloor` of the reference's. Earliest, because the
    /// question is where the output *starts* tracking the input; a later, better
    /// match says nothing about its head.
    public static func alignment(ofOutput output: String,
                                 against input: String,
                                 thresholds: PolishPrefixAlignmentThresholds = .default) -> Alignment {
        let inputWords = PolishLexicon.words(in: input)
        let outputWords = PolishLexicon.words(in: output)
        guard inputWords.count >= thresholds.minimumWords,
              outputWords.count >= thresholds.minimumWords else {
            return .notApplicable
        }
        // Clamped to the shorter side so a dictation shorter than the window is
        // compared on all of itself rather than on a window padded with nothing.
        let window = min(thresholds.windowWords, inputWords.count, outputWords.count)
        let reference = Set(inputWords.prefix(window))
        guard !reference.isEmpty else { return .notApplicable }
        // Rounded up: a floor is a floor. Over a reference of 12 distinct words,
        // 0.4 asks for 5 of them, not 4.
        let required = Int((Double(reference.count) * thresholds.overlapFloor).rounded(.up))
        for offset in 0...(outputWords.count - window) {
            let candidate = Set(outputWords[offset..<(offset + window)])
            if reference.intersection(candidate).count >= required {
                return .aligned(offset: offset)
            }
        }
        return .unaligned
    }
}
