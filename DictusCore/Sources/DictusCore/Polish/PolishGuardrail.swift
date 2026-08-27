// DictusCore/Sources/DictusCore/Polish/PolishGuardrail.swift
import Foundation
import NaturalLanguage

/// The two numbers the per-segment language check needs (#413).
///
/// They travel together because neither means anything alone. The floor decides
/// what counts as a confident disagreement; the length decides which segments are
/// long enough for a confidence to be worth reading at all. Raising one without the
/// other either fires on noise or stops firing entirely.
///
/// Both were measured, not chosen. Scored over 253 segments of 124 hand-labelled
/// outputs — every output the #393 campaign committed, plus an adversarial set for
/// the cases it does not contain. Reproduce with
/// `swift run polish-harness guardrail docs/research/413-414-guardrail/*.json --sweep`,
/// which drives no model.
///
/// | | worst case measured |
/// |---|---|
/// | A **legitimate** segment read as the wrong language | `Checker le build sur GitHub Actions` — **en 0.504** |
/// | A genuinely **drifted** segment, weakest reading | `Total 3 major changes` — **en 0.927** |
///
/// Nothing lands in between, so the floor is set inside a band 0.42 wide, and set
/// near its top rather than its middle: a floor that is too high misses a drift,
/// which leaves today's behaviour; a floor that is too low refuses a good output,
/// which for a Smart Mode costs the user everything they said. Only 3 of 219
/// legitimate segments disagreed with their expected language at all.
public struct PolishLanguageSegmentThresholds: Equatable, Sendable {

    /// Shortest segment the check will read, in characters, after its list marker
    /// is stripped. Below it the segment passes untested.
    ///
    /// The same 12 the whole-output check has always used, so a segment is held to
    /// exactly the minimum the whole output is. The sweep gives identical results
    /// for every value from 12 to 40 at the floor below, so this costs nothing
    /// measured and catches a drifted list whose bullets are all short.
    public let minimumSegmentCharacters: Int

    /// Confidence at or above which a disagreeing segment rejects. Below it the
    /// segment passes.
    public let confidenceFloor: Double

    public init(minimumSegmentCharacters: Int, confidenceFloor: Double) {
        self.minimumSegmentCharacters = minimumSegmentCharacters
        self.confidenceFloor = confidenceFloor
    }

    /// The measured pair. See the type's doc for where the numbers come from.
    public static let `default` = PolishLanguageSegmentThresholds(
        minimumSegmentCharacters: 12, confidenceFloor: 0.85
    )
}

/// Runtime sanity check on every polish output.
///
/// Three complementary checks:
/// 1. `accepts(raw:polished:mode:)` — character-length ratio. Catches catastrophic
///    over- or under-generation (empty output, runaway generation).
/// 2. `detectedLanguageMatches(polished:target:)` — language detection on the
///    polished output, whole **and per segment**. Catches chat-reply contamination
///    where Apple FM responds conversationally in a different language (e.g. "I'll
///    polish it for you" when the user dictated French), and since #413 also a list
///    that drifts one item at a time.
/// 3. `PolishGrounding` — whether the output is *about* the input. Lives in its own
///    type because it answers a different question with a different tool, and
///    because #349 will ask that type a second question.
public enum PolishGuardrail {

    /// Returns `true` when `polished` is within the length band `contract` allows.
    /// Empty raw → only empty polished accepted.
    ///
    /// The band comes off the contract rather than off a table keyed by mode since
    /// #79: `[0.5, 2.0]` is the ADR 0003 band for faithful polish, and it rejects
    /// Notes — which condenses on purpose — by construction. Each task carries the
    /// band its own transformation can legitimately produce. See
    /// `PolishAcceptanceContract`.
    public static func accepts(raw: String,
                               polished: String,
                               contract: PolishAcceptanceContract) -> Bool {
        guard !raw.isEmpty else { return polished.isEmpty }
        let ratio = Double(polished.count) / Double(raw.count)
        return contract.lengthBand.contains(ratio)
    }

    /// Free-polish convenience. Natural: `[0.5, 2.0]`. Repair: `[0.3, 3.0]`. Auto
    /// (#239): same band as Natural — the auto prompt is light-corrections-only, so
    /// anything outside the Natural band is over/under-generation.
    public static func accepts(raw: String, polished: String, mode: PolishMode) -> Bool {
        accepts(raw: raw, polished: polished, contract: PolishTask.polish(mode).contract)
    }

    /// Returns `true` when the top language hypothesis of `polished` matches `target`
    /// with confidence ≥ 0.5. Short outputs (< 12 characters) and low-confidence
    /// detections pass through — `NLLanguageRecognizer` is unreliable on either.
    ///
    /// The intended failure to catch is the Apple FM chat-reply pattern: target=fr
    /// but the engine emitted English. The char-ratio guardrail misses this when
    /// the chat reply happens to be similar length to the raw input.
    public static func detectedLanguageMatches(polished: String,
                                               target: SupportedLanguage,
                                               thresholds: PolishLanguageSegmentThresholds = .default) -> Bool {
        matches(polished: polished, expectedCode: target.rawValue, thresholds: thresholds)
    }

    /// Auto-mode variant (#239): there is no target language, but the INPUT's
    /// detected language is known — the polished output must be in the same
    /// one. This is the runtime enforcement of the auto prompt's
    /// never-translate contract: it catches translation drift (e.g. English
    /// speech polished into the keyboard language) that the char-ratio check
    /// cannot see. `inputLanguageCode` is an `NLLanguage` raw value (BCP-47ish:
    /// "en", "it", "zh-Hans", …) from `PolishPipeline.detectLanguageCode`,
    /// compared against the same recognizer's verdict on the output — so both
    /// sides share one namespace.
    public static func detectedLanguageMatches(polished: String,
                                               inputLanguageCode: String,
                                               thresholds: PolishLanguageSegmentThresholds = .default) -> Bool {
        matches(polished: polished, expectedCode: inputLanguageCode, thresholds: thresholds)
    }

    /// Shared core: `true` when the output reads as `expectedCode` **as a whole and
    /// segment by segment** — or when the check cannot be trusted (short output,
    /// short segment, low confidence), which passes through.
    ///
    /// ### Why the per-segment pass had to be added (#413)
    ///
    /// The whole-output pass alone asks `NLLanguageRecognizer` *"what is the
    /// dominant language of this text"*, and a list that drifts one item at a time
    /// keeps its aggregate reading. Measured on 2026-08-25 (#393, PR #412), on the
    /// same French fixture and one bullet apart:
    ///
    /// | output | whole-output reading | verdict then |
    /// |---|---|---|
    /// | 6 bullets, wholly English | English, 0.607 | rejected ✅ |
    /// | 5 English bullets + 1 French | **French, 0.789** | **accepted** ❌ |
    ///
    /// The second is the more broken of the two for a French user and it is the one
    /// that got through, because the single French bullet, the proper nouns and the
    /// word "euros" carried the aggregate. Read line by line the same text is
    /// unambiguous: `fr 1.000`, then `en 0.992`, `en 0.988`, `en 0.908`, `en 0.961`,
    /// `en 0.999`.
    ///
    /// **Raising the confidence floor was never the fix**, and is recorded here so
    /// nobody re-proposes it: 0.789 is a *confident wrong* answer, so any floor low
    /// enough to be useful still accepts it.
    ///
    /// ### Both passes stay
    ///
    /// The whole-output pass is what catches a wholly-wrong single passage — the
    /// Apple FM chat reply this guardrail was written for — which has no segment
    /// structure to inspect. The per-segment pass only ever adds rejections; free
    /// polish, which returns one continuous passage, sees no change.
    private static func matches(polished: String,
                                expectedCode: String,
                                thresholds: PolishLanguageSegmentThresholds) -> Bool {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return true }
        guard reads(trimmed, as: expectedCode, confidenceFloor: 0.5) else { return false }
        let segments = PolishSegmentation.segments(of: trimmed)
        guard segments.count > 1 else { return true }
        return segments.allSatisfy { segment in
            // A segment too short for the recogniser is not evidence of anything, so
            // it passes untested rather than being guessed at. Every uncertainty in
            // this check resolves toward accepting: a wrong rejection costs a Smart
            // Mode user the whole dictation.
            guard segment.count >= thresholds.minimumSegmentCharacters else { return true }
            return reads(segment, as: expectedCode, confidenceFloor: thresholds.confidenceFloor)
        }
    }

    /// `true` when `text` reads as `expectedCode`, or when the reading is too weak
    /// to act on. Only a confident disagreement returns `false`.
    private static func reads(_ text: String, as expectedCode: String, confidenceFloor: Double) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let top = hypotheses.max(by: { $0.value < $1.value }),
              top.value >= confidenceFloor else {
            return true
        }
        return top.key.rawValue == expectedCode
    }
}
