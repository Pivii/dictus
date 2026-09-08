// DictusCore/Sources/DictusCore/Polish/PolishLanguageMix.swift
// How much of a transcript is in which language, by proportion (#456).
import Foundation
import NaturalLanguage

/// The two numbers deciding which sentences of a transcript get counted (#456).
///
/// They travel together for the reason `PolishLanguageSegmentThresholds`' pair does:
/// the length says which sentences are long enough for a reading to mean anything,
/// the floor says which readings are firm enough to attribute characters to. Move one
/// alone and the measurement either counts noise or counts almost nothing.
///
/// **Both are deliberately looser than the guardrail's pair, because this is a count
/// and that is a refusal.** A segment the guardrail misreads *rejects a whole polish*;
/// a sentence misread here contributes its characters to the wrong side of a ratio
/// that the rest of the text usually outweighs. So the floor is the pipeline's
/// ordinary detection floor (0.5) rather than the guardrail's 0.85.
public struct PolishLanguageMixThresholds: Equatable, Sendable {

    /// Shortest sentence whose reading is counted, in characters. Below it the
    /// sentence contributes nothing to either side — it is not evidence, and guessing
    /// at it would let a transcript of interjections decide what language to write in.
    public let minimumSentenceCharacters: Int

    /// Confidence at or above which a sentence's reading is counted.
    public let confidenceFloor: Double

    public init(minimumSentenceCharacters: Int, confidenceFloor: Double) {
        self.minimumSentenceCharacters = minimumSentenceCharacters
        self.confidenceFloor = confidenceFloor
    }

    /// The shipping pair. The 12 is the same minimum every other language check in
    /// this pipeline uses, so a sentence is held to exactly what a segment and a whole
    /// output are; the 0.5 is `PolishPipeline.defaultConfidenceThreshold`, i.e. the
    /// same bar the transcript as a whole has to clear to be polished at all.
    ///
    /// Both were checked against the committed corpus rather than assumed: `swift run
    /// polish-harness target docs/research/456-target-election/corpus.json` prints
    /// what each transcript is measured as under them, including the two cases they
    /// exist for — a transcript of one-word sentences, which counts nothing and takes
    /// the whole-string fallback, and a run-on dictation with no sentence punctuation
    /// at all, which counts as a single 201-character segment. It drives no model.
    public static let `default` = PolishLanguageMixThresholds(
        minimumSentenceCharacters: 12, confidenceFloor: PolishPipeline.defaultConfidenceThreshold
    )
}

/// What a transcript is *made of*, by language, measured as a proportion of its
/// characters (#456).
///
/// ### Why a proportion and not a detection
///
/// `NLLanguageRecognizer` is a classifier, not a counter. Asked about a whole
/// transcript it returns one hypothesis and a confidence, and that confidence is how
/// sure it is of its single answer — never how much of the text supports it. Nothing
/// in the pipeline had ever computed "the language most of this text is in", so the
/// rule the polish target actually needs was not a value the code could express.
///
/// It also weights the **opening** of the string. That is what produced `en 0.9995`
/// on the 471-character transcript captured in #456, whose French tail is 78 % of it:
///
/// | | reading |
/// |---|---|
/// | the full raw as shipped | **en 0.9995** |
/// | its English head alone (105 ch) | en 0.995 |
/// | its French tail alone (363 ch) | fr 1.000 |
///
/// Each part is read correctly on its own; concatenated, the head wins at full
/// confidence. That composes badly with Parakeet, which settles on a language *after*
/// the first sentences — so the region the recogniser trusts most is the region the
/// ASR gets wrong most. A confidence floor cannot help: 0.9995 is the ceiling.
///
/// ### The measurement
///
/// Cut into sentences (`PolishSegmentation.sentences`), read each one, and attribute
/// its **characters** to its reading. Character weight, not sentence count, is the
/// whole point — the captured transcript is two short English fragments against two
/// long French ones, and by count that is a tie while by characters it is 78/22.
///
/// This type only measures. It does not know what a target is, which language the
/// keyboard is on, or how large a share is large enough — those are
/// `TranscriptionLanguagePolicy`'s, so that the judgement lives next to the other
/// judgements about the user's intent rather than inside a counter.
public struct PolishLanguageMix: Equatable, Sendable, Codable {

    /// Share of the counted characters per `NLLanguage` raw code ("fr", "en",
    /// "zh-Hans", …). Sums to 1, or is empty when nothing at all was readable.
    public let shares: [String: Double]

    /// The code holding the largest share, `nil` when `shares` is empty.
    ///
    /// On an exact tie between two codes the lower code wins alphabetically. That is
    /// arbitrary and it is allowed to be: an exact tie is far below any dominance
    /// floor a target could be elected at, so the winner is never used as one.
    public let dominantCode: String?

    /// `dominantCode`'s share, 0 when there is none.
    public let dominantShare: Double

    /// Characters that carried a reading. Smaller than the transcript whenever a
    /// sentence was too short or too weakly read to count; 0 on the whole-blob
    /// fallback below, which measures no sentence.
    public let countedCharacters: Int

    /// Nothing readable — gibberish, or an empty string.
    public static let undetermined = PolishLanguageMix(
        shares: [:], dominantCode: nil, dominantShare: 0, countedCharacters: 0
    )

    public init(shares: [String: Double],
                dominantCode: String?,
                dominantShare: Double,
                countedCharacters: Int) {
        self.shares = shares
        self.dominantCode = dominantCode
        self.dominantShare = dominantShare
        self.countedCharacters = countedCharacters
    }

    /// True when more than one language was counted. The one fact a debug reader needs
    /// to tell "detection was mixed" from "detection was confident" at a glance.
    public var isMixed: Bool { shares.count > 1 }

    /// Every language the transcript was counted as containing, as `NLLanguage` raw
    /// codes. Empty when nothing was readable.
    ///
    /// The whole mix rather than the leader, because the one question asked of it —
    /// can the polish backend read any of this? (#490) — is answered wrong by the
    /// leader alone on a bilingual transcript.
    public var countedCodes: Set<String> { Set(shares.keys) }

    // MARK: - Measurement

    /// Measure `text`.
    ///
    /// ### The whole-blob fallback, and why it is not a shortcut
    ///
    /// When no sentence clears the thresholds — a transcript of interjections, a
    /// language whose sentences the tokenizer cannot find, a single fragment — the
    /// result is the whole-string reading at share 1, exactly what
    /// `PolishPipeline.detectLanguageCode` would have returned before this existed.
    /// Without it, a text of short sentences would suddenly have no detected language
    /// and the gibberish gate would stop polishing text it polishes today. **This
    /// measurement is only ever allowed to add information, never to remove any**: a
    /// dominance rule that silently turns polish off on short speech would be a worse
    /// bug than the one it was written for.
    ///
    /// `countedCharacters == 0` is how a reader tells that fallback from a real
    /// single-language measurement.
    public static func measure(
        _ text: String,
        thresholds: PolishLanguageMixThresholds = .default
    ) -> PolishLanguageMix {
        var characters: [String: Int] = [:]
        var counted = 0
        for sentence in PolishSegmentation.sentences(of: text) {
            guard sentence.count >= thresholds.minimumSentenceCharacters,
                  let code = topReading(of: sentence, floor: thresholds.confidenceFloor) else {
                continue
            }
            characters[code, default: 0] += sentence.count
            counted += sentence.count
        }
        guard counted > 0 else {
            return wholeStringFallback(text, thresholds: thresholds)
        }
        let shares = characters.mapValues { Double($0) / Double(counted) }
        // `max(by:)` on a dictionary is unordered on ties, and this value reaches a
        // debug export — so ties break on the code to keep the same input producing
        // the same event.
        let dominant = shares.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }
        return PolishLanguageMix(
            shares: shares,
            dominantCode: dominant?.key,
            dominantShare: dominant?.value ?? 0,
            countedCharacters: counted
        )
    }

    private static func wholeStringFallback(
        _ text: String, thresholds: PolishLanguageMixThresholds
    ) -> PolishLanguageMix {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let code = topReading(of: trimmed, floor: thresholds.confidenceFloor) else {
            return .undetermined
        }
        return PolishLanguageMix(
            shares: [code: 1], dominantCode: code, dominantShare: 1, countedCharacters: 0
        )
    }

    /// The top hypothesis for `text`, or `nil` when it is below `floor`.
    private static func topReading(of text: String, floor: Double) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let top = recognizer.languageHypotheses(withMaximum: 1)
            .max(by: { $0.value < $1.value }), top.value >= floor else {
            return nil
        }
        return top.key.rawValue
    }

    // MARK: - Reading the measurement

    /// The dominant language narrowed to the four the per-language polish prompts
    /// exist for, whatever its share. `nil` when nothing was read, or when what was
    /// read is outside that set.
    ///
    /// This is the pipeline's answer to *"did we read a language we can polish in"* —
    /// the question the gibberish gate asks. It deliberately ignores the dominance
    /// floor: a genuinely bilingual transcript is not gibberish, and skipping polish
    /// on it would take the user's punctuation away for a reason that has nothing to
    /// do with them.
    public var dominantSupportedLanguage: SupportedLanguage? {
        dominantCode.flatMap(SupportedLanguage.init(rawValue:))
    }

    /// The language a polish target may be elected from: the dominant one, narrowed to
    /// the supported four, **and holding at least `floor` of the counted characters**.
    /// `nil` when no language holds enough of the transcript for one to be named.
    public func electedLanguage(floor: Double) -> SupportedLanguage? {
        guard dominantShare >= floor else { return nil }
        return dominantSupportedLanguage
    }

    /// Shares rounded for a debug event, so the JSON is readable and a re-export of
    /// the same event is byte-stable.
    public var roundedShares: [String: Double] {
        shares.mapValues { (($0 * 1000).rounded() / 1000) }
    }
}
