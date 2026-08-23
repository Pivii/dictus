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

    public init(minimumLengthRatio: Double,
                maximumLengthRatio: Double,
                outputLanguage: PolishOutputLanguage) {
        self.minimumLengthRatio = minimumLengthRatio
        self.maximumLengthRatio = maximumLengthRatio
        self.outputLanguage = outputLanguage
    }

    /// The band as a range, for `PolishGuardrail.accepts(raw:polished:band:)`.
    public var lengthBand: ClosedRange<Double> {
        // `min` guards a contract authored with the bounds the wrong way round,
        // which would otherwise trap at runtime on an empty range.
        min(minimumLengthRatio, maximumLengthRatio)...maximumLengthRatio
    }

    // MARK: - The free-polish contracts (ADR 0003, unchanged)

    /// Natural polish. The ADR 0003 band, and the historical target-language check.
    public static let natural = PolishAcceptanceContract(
        minimumLengthRatio: 0.5, maximumLengthRatio: 2.0, outputLanguage: .polishTarget
    )

    /// Repair. Wider on both sides because reconstructing intent legitimately
    /// rewrites more of the text (ADR 0002).
    public static let repair = PolishAcceptanceContract(
        minimumLengthRatio: 0.3, maximumLengthRatio: 3.0, outputLanguage: .polishTarget
    )

    /// Auto-detect polish (#239): the Natural band, and the never-translate check
    /// against the input's own detected language.
    public static let auto = PolishAcceptanceContract(
        minimumLengthRatio: 0.5, maximumLengthRatio: 2.0, outputLanguage: .sameAsInput
    )
}
