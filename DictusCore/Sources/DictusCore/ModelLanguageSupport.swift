// DictusCore/Sources/DictusCore/ModelLanguageSupport.swift
// Static curated per-model language metadata for the model manager UI (issue #240).
import Foundation

/// Curated description of which spoken languages a speech model supports,
/// shown in the model manager's per-model language detail view.
///
/// WHY static curated data instead of computed/fetched (#240 locked decision):
/// Language coverage is a property of the model family, documented by the
/// vendors (OpenAI/Argmax for Whisper, NVIDIA for Parakeet). It never changes
/// at runtime and benchmark-grade quality data is out of scope — a small
/// hand-curated set of entries with honest quality notes is more useful to
/// users than an exhaustive generated list.
///
/// WHY ISO 639-1 codes instead of display names:
/// The app layer localizes names via `Locale.localizedString(forLanguageCode:)`,
/// which yields correct French/English names for free and keeps DictusCore
/// free of UI strings (same split as `ModelInfo.description` vs the app's
/// `localizedDescription`).
public struct ModelLanguageSupport: Equatable, Sendable {

    /// The model's overall language coverage class. Drives the one-line
    /// summary in the detail view.
    public enum Coverage: Equatable, Sendable {
        /// Multilingual Whisper checkpoint: ≈99 languages, uneven quality.
        /// All Whisper models Dictus ships are the multilingual variants
        /// (no `.en` suffix), so they all share this coverage (#226 research).
        case whisperMultilingual
        /// Parakeet TDT v3: exactly the 25 European languages documented by
        /// NVIDIA. No Chinese or other non-European languages.
        case parakeetEuropean
    }

    /// A curated quality note attached to a highlighted language on a
    /// specific model tier. Kept as an enum so the app layer owns the
    /// localized wording (French + English) while the catalog stays data-only.
    public enum QualityNote: Equatable, Sendable {
        /// Usable but visibly rough on this model tier; a higher tier is a
        /// meaningfully better experience (e.g. Chinese on small-class
        /// Whisper: ~22-31% character error rate per #226 research).
        case impreciseUpgradeRecommended
        /// Meaningfully better on this tier than on the small class
        /// (e.g. Chinese on medium/turbo Whisper).
        case goodOnThisModel
    }

    /// One curated language row in the detail view.
    public struct Entry: Equatable, Sendable {
        /// ISO 639-1 language code (e.g. "fr", "zh").
        public let code: String
        /// Optional per-tier quality note; nil means no caveat worth surfacing.
        public let note: QualityNote?

        public init(code: String, note: QualityNote? = nil) {
            self.code = code
            self.note = note
        }
    }

    /// Coverage class for the summary line.
    public let coverage: Coverage

    /// Curated major languages, shown as individual rows. The four
    /// Dictus-tested languages (fr/en/es/de) always come first (#240 brief).
    public let highlights: [Entry]

    /// Remaining documented language codes beyond `highlights`, shown as a
    /// compact list. Populated for Parakeet (its 25-language list is finite
    /// and worth spelling out); empty for Whisper where the long tail
    /// (≈94 more languages) is conveyed by the coverage summary instead.
    public let additionalCodes: [String]

    public init(coverage: Coverage, highlights: [Entry], additionalCodes: [String] = []) {
        self.coverage = coverage
        self.highlights = highlights
        self.additionalCodes = additionalCodes
    }
}

// MARK: - Curated catalog data (issue #240)

extension ModelLanguageSupport {

    /// The four Dictus-tested languages, always listed first.
    private static let testedHighlights: [Entry] = [
        Entry(code: "fr"),
        Entry(code: "en"),
        Entry(code: "es"),
        Entry(code: "de")
    ]

    /// Small-class multilingual Whisper (tiny/base/small/small quantized):
    /// full ≈99-language coverage, but Chinese is rough at this size
    /// (~22-31% CER per the #226 research) — steer users to medium/turbo.
    static let whisperSmallClass = ModelLanguageSupport(
        coverage: .whisperMultilingual,
        highlights: testedHighlights + [
            Entry(code: "zh", note: .impreciseUpgradeRecommended)
        ]
    )

    /// High-accuracy multilingual Whisper (medium / large-v3 turbo):
    /// same ≈99-language coverage, meaningfully better Chinese quality.
    static let whisperHighAccuracy = ModelLanguageSupport(
        coverage: .whisperMultilingual,
        highlights: testedHighlights + [
            Entry(code: "zh", note: .goodOnThisModel)
        ]
    )

    /// Parakeet TDT 0.6b v3: exactly the 25 European languages documented by
    /// NVIDIA — nothing else. Chinese and other non-European languages are
    /// NOT supported (#226 research; surfaced explicitly in the detail view).
    /// The 21 codes below are the documented list minus the four tested
    /// languages already present in `highlights`.
    static let parakeetV3 = ModelLanguageSupport(
        coverage: .parakeetEuropean,
        highlights: testedHighlights,
        additionalCodes: [
            "bg", "hr", "cs", "da", "nl", "et", "fi", "el", "hu", "it",
            "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"
        ]
    )
}

// MARK: - ModelInfo accessor

extension ModelInfo {

    /// Curated language support for this model.
    ///
    /// WHY a computed lookup instead of a stored property:
    /// The support sets are shared per model tier (all small-class Whisper
    /// models have identical coverage), so a switch on identifier keeps the
    /// curated data in one reviewable block instead of repeating it across
    /// the seven catalog entries.
    public var languageSupport: ModelLanguageSupport {
        switch identifier {
        case "openai_whisper-medium", "openai_whisper-large-v3_turbo_954MB":
            return .whisperHighAccuracy
        case "parakeet-tdt-0.6b-v3":
            return .parakeetV3
        default:
            // tiny / base / small / small_216MB, plus any future Whisper
            // entry until it is explicitly classified above. Defaulting to
            // the small-class (most conservative quality claims) is the safe
            // direction for unclassified models.
            switch engine {
            case .whisperKit:
                return .whisperSmallClass
            case .parakeet:
                return .parakeetV3
            }
        }
    }
}
