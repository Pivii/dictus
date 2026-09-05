// DictusCore/Sources/DictusCore/Polish/PolishPrefixAlignment.swift
// Is the output the user's own text, and does it OPEN as their own text? (#466, #349)
import Foundation

/// The two numbers this check needs, and the size of the text it declines to read.
///
/// They travel together because neither means anything alone. The window decides how
/// long a stretch of output has to be before "there is some of the speaker in here"
/// is worth believing; the floor decides what share of a stretch has to be the
/// speaker's words for it to count as theirs. One floor serves both tests below,
/// because both ask the same question — *what share of this text is the speaker's* —
/// of two different stretches.
///
/// Measured, not chosen. Scored over the committed corpora with
/// `swift run polish-harness guardrail docs/research/413-414-guardrail/*.json --sweep`,
/// which drives no model. Tables in `docs/research/466-preamble-guardrail.md` §6, §8
/// and §9.
///
/// **The separation is a 0.62-wide empty band.** Over 480 outputs: every legitimate
/// multi-line free-polish output has an opening line that is **100 %** the speaker's
/// words; every one of the 84 captured preambles and fabrications scores **0.38 or
/// less**. Nothing lands between.
public struct PolishPrefixAlignmentThresholds: Equatable, Sendable {

    /// How long a stretch of the output is judged at once when asking whether *any*
    /// of it is the speaker's, in words. About a clause.
    public let windowWords: Int

    /// Share of a stretch that has to be words the speaker actually said. Rounded
    /// up, so 0.70 over an 8-word window asks for 6 of them.
    public let supportFloor: Double

    /// Fewest words either side must carry for the question to be asked at all.
    /// Below it the check passes untested: a five-word dictation has no opening to
    /// judge, and guessing at one would refuse a good output for nothing.
    public let minimumWords: Int

    /// ### Why `assert` and not `precondition`, and why nothing is clamped here
    ///
    /// Raised in review of PR #478, which proposed `precondition` on all three.
    /// The technical analysis behind it is right — a non-positive `windowWords`
    /// makes an invalid `Range`, and a non-finite `supportFloor` traps the `Int`
    /// conversion — but a `precondition` is the wrong instrument in **this** type.
    ///
    /// This code runs inside the keyboard extension (#361). A `precondition` turns
    /// a doubtful number into a crash mid-dictation, which is the worst outcome
    /// available to a guardrail whose whole design rule is *every uncertainty
    /// resolves toward accepting, because a rejection costs the user words they
    /// said.* Nothing in the app can reach it — the only production value is
    /// `.default`, a compile-time constant — so it would trade a real user-facing
    /// risk for a hypothetical one. `DictusCore` has no `precondition` anywhere,
    /// and this is not the place to introduce the first.
    ///
    /// **Nor are the values clamped here**, which was the other suggestion. The one
    /// caller that varies them is the harness's threshold sweep, and a sweep that
    /// silently substituted 1.0 for a floor of 1.5 would print a table it did not
    /// measure. A measurement that misreports itself is the single failure this
    /// whole issue is organised against.
    ///
    /// So: the stored values are whatever the caller wrote, `assert` says so loudly
    /// in debug — which is where the sweep runs — and `alignment(ofOutput:against:)`
    /// makes the arithmetic unable to trap in release, following the precedent
    /// `PolishAcceptanceContract.lengthBand` sets for a contract authored with its
    /// bounds the wrong way round.
    public init(windowWords: Int, supportFloor: Double, minimumWords: Int) {
        assert(windowWords > 0, "windowWords must be positive; got \(windowWords)")
        assert(minimumWords > 0, "minimumWords must be positive; got \(minimumWords)")
        assert(supportFloor.isFinite && supportFloor > 0 && supportFloor <= 1,
               "supportFloor must be finite in (0, 1]; got \(supportFloor)")
        self.windowWords = windowWords
        self.supportFloor = supportFloor
        self.minimumWords = minimumWords
    }

    /// The measured set. See the type's doc for where the numbers come from.
    public static let `default` = PolishPrefixAlignmentThresholds(
        windowWords: 8, supportFloor: 0.70, minimumWords: 8
    )
}

/// Whether the output is the user's own text, and whether it *opens* as their own
/// text.
///
/// ### The hole this closes
///
/// Apple FM answers the polish prompt like a chatbot and the keyboard types the
/// answer. Captured on device (#466), `natural` mode, target `fr`:
///
/// ```
/// raw       Okay donc là je refait les tests que j'ai fait parce que j'étais en…
/// polished  Bien sûr, je vais vous aider à polir votre texte. Voici la version polie :
///           Je vais donc faire de nouveau les tests que j'ai faits, car je suis en…
/// ```
///
/// Every other guardrail passes it. The length ratio is 1.60, inside Natural's
/// `[0.5, 2.0]`. `detectedLanguageMatches` passes whole and per segment, because a
/// model instructed to write French writes its chat reply in French too.
/// `PolishGrounding` passes because the preamble names no person, place or
/// organisation. Measured on 200 real Apple FM runs of that dictation, **23.5 % came
/// back with a preamble of this family**, in 24 distinct formulations.
///
/// #349 is the same phenomenon from the other end — Apple FM refusing
/// (*"Je suis désolé, mais je ne peux pas fournir une sortie polie pour ce texte…"*)
/// and the refusal being inserted as the user's dictation, also with
/// `outcome = success`.
///
/// ### What it measures: two questions, one floor
///
/// **1. Is any of this the speaker's?** Slide a short window along the output and
/// look for one stretch where `supportFloor` of the words are vocabulary the input
/// contains. None anywhere means the model wrote about something else entirely —
/// #349's refusal, or an invented paragraph.
///
/// **2. Does it OPEN as the speaker's?** If the output has more than one line, its
/// first line has to be the speaker's words by the same floor. A chat preamble
/// arrives as its own line — measured on **81 of 81** captured preambles across two
/// device corpora — which is what makes it separable without a lexical list.
///
/// ### Two mechanisms were measured before this one, and both failed
///
/// **Searching the output for the input's opening** (the first version, shipped and
/// device-tested). A sliding window looking for the input's opening words cannot see
/// a preamble shorter than the window: a six-word one leaves the window straddling
/// it, half in the junk and half in the real text, still carrying enough to pass.
/// Falsified on device.
///
/// **Where support starts, measured as an offset with a tolerance** (the second).
/// It reads a legitimately *translated* opening as a preamble, because both are an
/// unsupported head. Measured on 50 real runs of the #456 transcript — a dictation
/// whose opening is mistranscribed as English and polished into French — it refused
/// **14 faithful polishes out of 14**. A tolerance wide enough to admit them is
/// wider than the preambles it had to catch: the faithful heads ran 21 to 41 words,
/// the preambles began at 5. **The offset is not a separator and no value of it is**,
/// which is why this version has no offset threshold at all.
///
/// The line boundary is what separates them: a translated opening is the *same*
/// line as the body, a preamble is a line of its own.
///
/// ### Why comparative, and not a list of phrases
///
/// A per-language list of meta-discourse openers ("Bien sûr", "Voici", "Sure,
/// here's") was weighed and rejected. The test here is between two texts the same
/// dictation produced, so nothing is maintained per language and nothing rots as
/// Apple FM's phrasing changes. `PolishNaturalPromptFR.swift:24` already names five
/// such formulas as forbidden, and the captured output opens with two of them — the
/// measured evidence that naming the words does not work.
///
/// ### It rejects, it never repairs
///
/// The preamble is its own line and is therefore mechanically separable, and cutting
/// it is still not what happens. A post-pass that cuts the head of an output can cut
/// a real sentence of the user's — ADR 0003 forbids that and #441 banned it
/// explicitly — and a wrong cut is permanent where a missing polish is not. The
/// property `PolishGuardrail` already has, *when it refuses, the user keeps their own
/// words*, is worth more than recovering a polish that was 90 % good.
///
/// ### Where this must NOT run
///
/// Only where the output is expected to reuse the input's own words, which the task's
/// contract answers with `PolishAcceptanceContract.requiresAlignedPrefix`: **Natural
/// and Auto**. Three tasks answer no:
///
/// - **List restructures**, and is licensed to synthesise bullets that name
///   conclusions rather than reuse sentences.
/// - **Translation keeps no word of the input**, so nothing is ever supported.
/// - **Repair reconstructs in another language.** `PolishPipeline.mode` selects it
///   exactly when the detected language differs from the target, so its output
///   shares no vocabulary with its input: **10 of 10 legitimate repair outputs are
///   refused, at every threshold pair swept, under all three mechanisms.** See
///   `docs/research/466-preamble-guardrail.md` §6.3.
///
/// ### Accepted holes, stated on purpose
///
/// **A preamble that is not on its own line.** Question 2 is a per-line test, so a
/// model that writes `Voici la version polie : Okay donc là je refais…` on one line
/// is invisible. Measured at **0 of 81** captured preambles, across 250 real Apple FM
/// runs — but it is a property of the output's shape and not a law, and it is the
/// price of not refusing a legitimately translated opening.
///
/// **A preamble inside a List, a Translate or a Repair output**, per the contract
/// above. Those are seen only by `PolishGrounding`, and only if they invent a named
/// entity — which a sentence about the act of polishing does not.
///
/// **A model that talks about its own task after the user's text, or in the middle
/// of it.** The opening line is the speaker's, so it passes. This closes the
/// measured shape, not the class.
///
/// ### Scripts that write no word separators are covered, and were not
///
/// Chinese, Japanese and Thai reached this check as a single token, because
/// splitting on "not a letter or a digit" finds no boundary in them — so the
/// word-count floor was never met and every output was accepted. Found by CodeRabbit
/// reviewing PR #478 and measured at `caught 0/1` on an authentic Chinese preamble.
/// `PolishLexicon` now refines a run the split could not break, and the fixture is
/// committed as `P4-preamble-zh`. Auto mode (#239) is the language-agnostic route
/// and real users reach it (#409).
public enum PolishPrefixAlignment {

    /// What the output looks like against its input.
    public enum Alignment: Equatable, Sendable {
        /// One side was too short to judge. Passes untested.
        case notApplicable
        /// The output is the speaker's text and opens as their text.
        case aligned
        /// The output's first line carries almost none of the speaker's words while
        /// more text follows it — a preamble (#466). Carries the share it measured,
        /// so a rejection can be checked rather than trusted.
        case openingLineNotTheSpeakers(supportedShare: Double)
        /// No stretch of the output is the speaker's at all — a refusal, or an
        /// invented answer (#349).
        case neverSupported
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
        case .notApplicable, .aligned:
            return true
        case .openingLineNotTheSpeakers, .neverSupported:
            return false
        }
    }

    /// The measurement behind `accepts`, exposed for the harness's scoring command
    /// and for tests — a sweep needs the reading, not the verdict.
    ///
    /// The support set is the whole input rather than its opening. Restricting it to
    /// the input's first 18, 24 or 30 words was measured and scores identically, so
    /// the narrower rule would be a knob bought with no evidence.
    public static func alignment(ofOutput output: String,
                                 against input: String,
                                 thresholds: PolishPrefixAlignmentThresholds = .default) -> Alignment {
        let inputWords = PolishLexicon.words(in: input)
        let outputWords = PolishLexicon.words(in: output)
        guard inputWords.count >= thresholds.minimumWords,
              outputWords.count >= thresholds.minimumWords else {
            return .notApplicable
        }
        let spoken = Set(inputWords)
        guard isAnythingSupported(outputWords, by: spoken, thresholds: thresholds) else {
            return .neverSupported
        }
        // The opening line is only evidence when something follows it. A single-line
        // output has no line that is *only* a preamble, and judging the whole output
        // by this floor would refuse a polish that legitimately reconstructs a
        // mistranscribed opening — 14 of 14 on the #456 transcript, measured.
        let lines = PolishSegmentation.segments(of: output)
            .map { PolishLexicon.words(in: $0) }
            .filter { !$0.isEmpty }
        guard lines.count > 1, let opening = lines.first else { return .aligned }
        let share = Double(opening.count { spoken.contains($0) }) / Double(opening.count)
        return share < thresholds.supportFloor
            ? .openingLineNotTheSpeakers(supportedShare: share)
            : .aligned
    }

    /// What share of the output's opening line is the speaker's own words, or `nil`
    /// when the output is a single line and so has no opening line to judge apart
    /// from its body.
    ///
    /// Exposed for the harness's scoring command, which prints the band the floor
    /// sits in — the same reason `PolishGrounding.anchors` is public. The pipeline
    /// only ever asks `accepts`.
    public static func openingLineSupport(ofOutput output: String,
                                          against input: String) -> Double? {
        let lines = PolishSegmentation.segments(of: output)
            .map { PolishLexicon.words(in: $0) }
            .filter { !$0.isEmpty }
        guard lines.count > 1, let opening = lines.first else { return nil }
        let spoken = Set(PolishLexicon.words(in: input))
        return Double(opening.count { spoken.contains($0) }) / Double(opening.count)
    }

    /// Whether any window-long stretch of the output is the speaker's words.
    ///
    /// A window rather than the whole output, because a faithful polish of a
    /// bilingual dictation is only *partly* the speaker's vocabulary — the
    /// mistranscribed part is reconstructed — and judging the whole blob by one
    /// ratio would refuse it. One clause that is clearly theirs is enough to say the
    /// model was working on their text.
    private static func isAnythingSupported(_ outputWords: [String],
                                            by spoken: Set<String>,
                                            thresholds: PolishPrefixAlignmentThresholds) -> Bool {
        // Both clamps guard a threshold set authored out of domain, the way
        // `PolishAcceptanceContract.lengthBand` guards bounds written the wrong way
        // round: without them a non-positive window builds an invalid `Range` and a
        // non-finite floor traps the `Int` conversion — inside the keyboard
        // extension. The `assert` on the initialiser is what stops this being
        // silent; this is what stops it being fatal.
        let window = max(1, min(thresholds.windowWords, outputWords.count))
        let floor = thresholds.supportFloor.isFinite ? min(max(thresholds.supportFloor, 0), 1) : 1
        let required = Int((Double(window) * floor).rounded(.up))
        // `window` is clamped up to 1, so it can exceed a zero-length output — which
        // only a non-positive `minimumWords` lets through the guard above. Reached
        // only in release, where the `assert` is inert.
        guard outputWords.count >= window else { return false }
        for offset in 0...(outputWords.count - window)
        where outputWords[offset..<(offset + window)].count(where: { spoken.contains($0) }) >= required {
            return true
        }
        return false
    }
}
