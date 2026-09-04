// DictusCore/Sources/DictusCore/Polish/PolishAcceptanceContract.swift
// What a polish output has to look like to be accepted (issue #79).
import Foundation

/// The language a polished output is required to read as.
///
/// WHY this is a type rather than a `SupportedLanguage?`: the pipeline has three
/// genuinely different expectations, and until #79 two of them were expressed by
/// branching on `mode == .auto` inside `PolishPipeline`. A Smart Mode adds a third
/// that neither branch covers — translation, where the required language is neither
/// the prompt target nor the input's — so the expectation becomes a value the
/// contract carries.
public enum PolishOutputLanguage: Equatable, Sendable, Codable {
    /// Must read as the resolved polish target, i.e. the language the prompt names.
    /// The historical per-language check: catches Apple FM answering in English on
    /// a French dictation.
    case polishTarget
    /// Must read as whatever the input reads as. The auto-mode check written for
    /// #239, which is also the right one for any Smart Mode that keeps the
    /// speaker's language: it is the runtime enforcement of "never translate".
    case sameAsInput
    /// Must read as this language and no other. Only translation uses it, and for
    /// translation the check flips from obstacle to asset — it catches the model
    /// forgetting to translate.
    case fixed(SupportedLanguage)

    // MARK: - Encoding

    /// One string rather than a synthesised nested container, for the reason
    /// `TranscriptionLanguageMode.storedValue` is one: the value crosses the App
    /// Group inside the per-dictation snapshot, and a flat marker is both readable
    /// in a capture and stable across refactors of the enum's shape.
    public var storedValue: String {
        switch self {
        case .polishTarget: return "polishTarget"
        case .sameAsInput: return "sameAsInput"
        case .fixed(let language): return language.rawValue
        }
    }

    /// Parse a `storedValue`. Unlike the language *mode*, an unrecognised value
    /// throws rather than degrading: the degradation would be a guess about which
    /// language the user's text is allowed to come back in, and on a translation
    /// mode a wrong guess accepts untranslated output.
    public init(storedValue: String) throws {
        switch storedValue {
        case "polishTarget": self = .polishTarget
        case "sameAsInput": self = .sameAsInput
        default:
            guard let language = SupportedLanguage(rawValue: storedValue) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "unrecognised output language '\(storedValue)'"
                ))
            }
            self = .fixed(language)
        }
    }

    public init(from decoder: Decoder) throws {
        try self.init(storedValue: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedValue)
    }
}

/// What one polish task will accept back from the engine.
///
/// ### Why this had to stop being a property of `PolishMode`
///
/// `PolishGuardrail` was bound to the faithful-polish contract of ADR 0003 and ran
/// on the output whatever prompt produced it. Two of its rules break a Smart Mode by
/// construction: the `0.5...2.0` length band rejects Notes, which condenses on
/// purpose, and the output-must-match-the-target language check rejects every
/// translation. So the contract travels with the task instead of being looked up
/// from a global table (#79).
///
/// ### The length band is a backstop, not a guard
///
/// It catches catastrophic over- and under-generation — an empty answer, a runaway.
/// It does not catch a bad transformation. Measured on the Email harness run
/// (PR #388): the Natural band of `0.5...2.0` rejected **nothing in 240 calls**,
/// including outputs carrying an invented greeting and signature that accounted for
/// roughly a quarter of the added length.
///
/// So do not size a new mode's band as though it were protecting anything, and do
/// not let a wide band read as a weakened contract — the check that actually guards
/// a mode is `outputLanguage`. If a mode needs a real guard, it has to be a real
/// one.
///
/// The bands below are judgement calls sized against what each transformation does
/// to length, not measurements. They are the first thing to revisit if the harness
/// shows a mode's own output being rejected.
public struct PolishAcceptanceContract: Equatable, Sendable, Codable {

    /// Smallest accepted `polished.count / raw.count`.
    public let minimumLengthRatio: Double
    /// Largest accepted `polished.count / raw.count`.
    public let maximumLengthRatio: Double
    /// The language the output has to read as.
    public let outputLanguage: PolishOutputLanguage

    /// Whether every person, place and organisation the output names has to appear
    /// in the input already (#414).
    ///
    /// ### Why a mode has to answer this
    ///
    /// The check is only sound where the output stays in the input's own language
    /// **and** the transformation is not licensed to replace words:
    ///
    /// - **A translation localises names.** `Londres` becomes `London`. Surface
    ///   identity is not expected, so the check would be measuring the wrong thing.
    /// - **Repair reconstructs words by design** (ADR 0002): its contract is
    ///   substituting what the speaker probably meant for what the STT emitted,
    ///   which can legitimately produce a name the raw does not carry.
    ///
    /// ### Why a field rather than a derivation
    ///
    /// `outputLanguage` happens to discriminate the translation case today, and
    /// deriving from it would work for this catalogue — the same argument
    /// `SmartModeOverflowBehaviour` answers, with the same conclusion. A custom mode
    /// (#269) must *answer* the question rather than inherit an answer from a
    /// property chosen for an unrelated reason, and a mode that condenses *and*
    /// reconstructs would break the derivation silently. It cannot break an answer
    /// someone had to write down.
    public let requiresGroundedNames: Bool

    public init(minimumLengthRatio: Double,
                maximumLengthRatio: Double,
                outputLanguage: PolishOutputLanguage,
                requiresGroundedNames: Bool) {
        self.minimumLengthRatio = minimumLengthRatio
        self.maximumLengthRatio = maximumLengthRatio
        self.outputLanguage = outputLanguage
        self.requiresGroundedNames = requiresGroundedNames
    }

    // MARK: - Decoding

    /// Hand-written so `requiresGroundedNames` can default rather than fail the
    /// whole record, for the reason `SmartMode.init(from:)` is hand-written: a
    /// contract crosses the App Group inside the per-dictation snapshot, and an app
    /// update can land between the write and the read.
    ///
    /// The default is **off**, which is the safe half here. A record written by a
    /// build that did not know about this check gets exactly today's behaviour for
    /// one dictation across one upgrade; the other default would turn a brand-new
    /// rejection on for a snapshot nobody measured, and a rejection on a Smart Mode
    /// costs the user everything they said.
    ///
    /// `encode(to:)` stays synthesised — it always writes every key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minimumLengthRatio = try container.decode(Double.self, forKey: .minimumLengthRatio)
        self.maximumLengthRatio = try container.decode(Double.self, forKey: .maximumLengthRatio)
        self.outputLanguage = try container.decode(PolishOutputLanguage.self, forKey: .outputLanguage)
        self.requiresGroundedNames = try container.decodeIfPresent(
            Bool.self, forKey: .requiresGroundedNames
        ) ?? false
    }

    /// The band as a range, for `PolishGuardrail.accepts(raw:polished:band:)`.
    public var lengthBand: ClosedRange<Double> {
        // `min` guards a contract authored with the bounds the wrong way round,
        // which would otherwise trap at runtime on an empty range.
        min(minimumLengthRatio, maximumLengthRatio)...maximumLengthRatio
    }

    // MARK: - The free-polish contracts (ADR 0003, unchanged)

    /// Natural polish. The ADR 0003 band, and the historical target-language check.
    ///
    /// Grounded because ADR 0003's forbidden list already says so — *"adding words
    /// or content that were not in the input"* — and this is the first runtime
    /// enforcement of that line. It is also the cheapest place in the codebase to
    /// be wrong: a rejection here hands back the deterministic floor, so the user
    /// keeps their words and loses only the polish.
    public static let natural = PolishAcceptanceContract(
        minimumLengthRatio: 0.5, maximumLengthRatio: 2.0,
        outputLanguage: .polishTarget, requiresGroundedNames: true
    )

    /// Repair. Wider on both sides because reconstructing intent legitimately
    /// rewrites more of the text (ADR 0002).
    ///
    /// **Not** grounded, and this is the one exclusion that is about the
    /// transformation rather than the language: repair's whole contract is
    /// substituting what the speaker probably meant for what Parakeet emitted, so a
    /// name it reconstructs need not appear in the raw. #349's refusal was recorded
    /// under this mode, and closing it needs the *other* query over
    /// `PolishGrounding` — how much of the output's vocabulary appears in the input
    /// at all — not this one.
    public static let repair = PolishAcceptanceContract(
        minimumLengthRatio: 0.3, maximumLengthRatio: 3.0,
        outputLanguage: .polishTarget, requiresGroundedNames: false
    )

    /// Auto-detect polish (#239): the Natural band, and the never-translate check
    /// against the input's own detected language. Same grounding answer as Natural,
    /// for the same reason — the auto prompt is light-corrections-only.
    public static let auto = PolishAcceptanceContract(
        minimumLengthRatio: 0.5, maximumLengthRatio: 2.0,
        outputLanguage: .sameAsInput, requiresGroundedNames: true
    )
}
