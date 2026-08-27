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

    /// Quality tier for the full-list breakdown of a multilingual model
    /// (issue #240 design round).
    ///
    /// Tiers are grounded in OpenAI's published per-language large-v3
    /// results on the FLEURS benchmark (the `language-breakdown.svg` chart
    /// in the openai/whisper repository, extracted 2026-07-28):
    /// - `good`: WER/CER <= ~10% (25 languages, Spanish 2.8% .. Arabic 9.6%)
    /// - `fair`: ~10-25% (19 languages, Czech 10.1% .. Lithuanian 23.7%)
    /// - `limited`: > 25% (Hebrew 26.1% .. Bengali 50.0%) or no published
    ///   FLEURS number at all (low-resource long tail).
    /// Numbers are for the LARGE models; smaller checkpoints degrade
    /// further — the UI surfaces that caveat alongside the tiers.
    public enum QualityTier: Equatable, Sendable {
        case good
        case fair
        case limited
    }

    /// A quality tier together with the language codes assigned to it.
    public struct TierGroup: Equatable, Sendable {
        public let tier: QualityTier
        /// Language codes in published-benchmark order (best WER first,
        /// unbenchmarked codes appended); the UI re-sorts alphabetically
        /// by localized name for scanning.
        public let codes: [String]

        public init(tier: QualityTier, codes: [String]) {
            self.tier = tier
            self.codes = codes
        }
    }

    /// Coverage class for the summary line.
    public let coverage: Coverage

    /// Curated major languages, shown as individual rows. The four
    /// Dictus-tested languages (fr/en/es/de) always come first (#240 brief).
    public let highlights: [Entry]

    /// Remaining documented language codes beyond `highlights`, shown as a
    /// compact list. Populated for Parakeet (its 25-language list is finite
    /// and worth spelling out); empty for Whisper, which uses `tierGroups`
    /// for its full breakdown instead.
    public let additionalCodes: [String]

    /// Complete supported-language list grouped by published quality tier
    /// (issue #240 design round). Populated for Whisper models (the full
    /// tokenizer language set, ~100 codes); empty for Parakeet, whose
    /// finite documented list lives in `highlights` + `additionalCodes`.
    public let tierGroups: [TierGroup]

    public init(coverage: Coverage,
                highlights: [Entry],
                additionalCodes: [String] = [],
                tierGroups: [TierGroup] = []) {
        self.coverage = coverage
        self.highlights = highlights
        self.additionalCodes = additionalCodes
        self.tierGroups = tierGroups
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

    /// The complete Whisper tokenizer language set (~100 codes, including
    /// Cantonese `yue` added with large-v3), grouped by quality tier.
    ///
    /// SOURCE OF TRUTH for the code list: WhisperKit's `Constants.languages`
    /// map (Sources/WhisperKit/Core/Models.swift), which mirrors OpenAI's
    /// whisper tokenizer. One normalization: Whisper's legacy "jw" code for
    /// Javanese is stored here as the valid ISO 639-1 "jv" so `Locale` can
    /// name it (this data is display-only, never fed to the tokenizer).
    ///
    /// SOURCE OF TRUTH for tier assignment: OpenAI's published large-v3
    /// per-language FLEURS results (language-breakdown.svg in the
    /// openai/whisper repo; WER, or CER for zh/ja/ko/th). Codes without a
    /// published FLEURS number default to `limited` — the honest claim for
    /// the low-resource long tail. See `QualityTier` for thresholds.
    static let whisperTierGroups: [TierGroup] = [
        // <= ~10% WER/CER on FLEURS with large-v3 (best first):
        // es 2.8, it 3.0, ko 3.1, pt 4.1, en 4.1, pl 4.6, ca 4.8, ja 4.9,
        // de 4.9, ru 5.0, nl 5.2, fr 5.3, id 6.1, uk 6.4, tr 6.7, ms 7.3,
        // sv 7.6, zh 7.7, fi 7.7, no 7.8, ro 8.2, th 8.4, vi 8.6, sk 9.2,
        // ar 9.6
        TierGroup(tier: .good, codes: [
            "es", "it", "ko", "pt", "en", "pl", "ca", "ja", "de", "ru",
            "nl", "fr", "id", "uk", "tr", "ms", "sv", "zh", "fi", "no",
            "ro", "th", "vi", "sk", "ar"
        ]),
        // ~10-25% WER on FLEURS with large-v3:
        // cs 10.1, hr 10.8, el 10.9, sr 11.6, da 12.0, bg 12.5, hu 12.9,
        // tl 13.0, bs 13.0, gl 13.1, mk 14.7, hi 17.0, et 18.1, sl 18.3,
        // ta 18.3, lv 19.4, az 19.7, ur 20.6, lt 23.7
        TierGroup(tier: .fair, codes: [
            "cs", "hr", "el", "sr", "da", "bg", "hu", "tl", "bs", "gl",
            "mk", "hi", "et", "sl", "ta", "lv", "az", "ur", "lt"
        ]),
        // > 25% WER on FLEURS with large-v3 (he 26.1 .. bn 50.0), followed
        // by every remaining tokenizer language without a published FLEURS
        // number (low-resource long tail, alphabetical).
        TierGroup(tier: .limited, codes: [
            "he", "cy", "fa", "is", "kk", "af", "kn", "mr", "sw", "te",
            "mi", "ne", "hy", "be", "gu", "pa", "bn",
            "am", "as", "ba", "bo", "br", "eu", "fo", "ha", "haw", "ht",
            "jv", "ka", "km", "la", "lb", "ln", "lo", "mg", "ml", "mn",
            "mt", "my", "nn", "oc", "ps", "sa", "sd", "si", "sn", "so",
            "sq", "su", "tg", "tk", "tt", "uz", "yi", "yo", "yue"
        ])
    ]

    /// Small-class multilingual Whisper (tiny/base/small/small quantized):
    /// full ≈99-language coverage, but Chinese is rough at this size
    /// (~22-31% CER per the #226 research) — steer users to medium/turbo.
    static let whisperSmallClass = ModelLanguageSupport(
        coverage: .whisperMultilingual,
        highlights: testedHighlights + [
            Entry(code: "zh", note: .impreciseUpgradeRecommended)
        ],
        tierGroups: whisperTierGroups
    )

    /// High-accuracy multilingual Whisper (medium / large-v3 turbo):
    /// same ≈99-language coverage, meaningfully better Chinese quality.
    static let whisperHighAccuracy = ModelLanguageSupport(
        coverage: .whisperMultilingual,
        highlights: testedHighlights + [
            Entry(code: "zh", note: .goodOnThisModel)
        ],
        tierGroups: whisperTierGroups
    )

    /// Parakeet TDT 0.6b v3: exactly the 25 European languages documented by
    /// NVIDIA — nothing else; Chinese and other non-European languages are
    /// NOT supported (#226 research). The detail view conveys the limit via
    /// the "25 European languages" summary plus the exhaustive list (design
    /// round dropped the extra warning row as redundant).
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
