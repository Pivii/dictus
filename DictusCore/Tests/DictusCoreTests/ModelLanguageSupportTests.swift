// DictusCore/Tests/DictusCoreTests/ModelLanguageSupportTests.swift
// Curated per-model language metadata invariants (issue #240).
import XCTest
@testable import DictusCore

final class ModelLanguageSupportTests: XCTestCase {

    private let testedCodes = ["fr", "en", "es", "de"]

    /// Small-class Whisper identifiers: full multilingual coverage but rough
    /// Chinese quality (#226 research, ~22-31% CER).
    private let smallClassWhisperIDs = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-small_216MB"
    ]

    /// Both quantized Turbo variants belong here. `_954MB` is deprecated since #408
    /// but still installed on devices, so it must keep the claims it shipped with
    /// rather than falling through to the small-class default.
    private let highAccuracyWhisperIDs = [
        "openai_whisper-medium",
        "openai_whisper-large-v3-v20240930_turbo_632MB",
        "openai_whisper-large-v3_turbo_954MB"
    ]

    // MARK: - Coverage classes

    func testEveryWhisperModelIsMultilingual() {
        for model in ModelInfo.allIncludingDeprecated where model.engine == .whisperKit {
            XCTAssertEqual(model.languageSupport.coverage, .whisperMultilingual,
                           "\(model.identifier) should report multilingual Whisper coverage")
        }
    }

    func testParakeetIsEuropeanOnly() {
        let parakeet = ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3")
        XCTAssertEqual(parakeet?.languageSupport.coverage, .parakeetEuropean)
    }

    // MARK: - Tested languages ordering

    func testTestedLanguagesComeFirstOnEveryModel() {
        // The four Dictus-tested languages must open the highlights list,
        // in fr/en/es/de order (#240 brief).
        for model in ModelInfo.allIncludingDeprecated {
            let firstFour = model.languageSupport.highlights.prefix(4).map(\.code)
            XCTAssertEqual(Array(firstFour), testedCodes,
                           "\(model.identifier) must list the tested languages first")
        }
    }

    // MARK: - Chinese quality notes per tier

    func testSmallClassWhisperFlagsChineseAsImprecise() {
        for id in smallClassWhisperIDs {
            guard let model = ModelInfo.forIdentifier(id) else {
                XCTFail("\(id) missing from catalog")
                continue
            }
            let zh = model.languageSupport.highlights.first { $0.code == "zh" }
            XCTAssertEqual(zh?.note, .impreciseUpgradeRecommended,
                           "\(id) must carry the imprecise-Chinese note")
        }
    }

    func testHighAccuracyWhisperMarksChineseAsGood() {
        for id in highAccuracyWhisperIDs {
            guard let model = ModelInfo.forIdentifier(id) else {
                XCTFail("\(id) missing from catalog")
                continue
            }
            let zh = model.languageSupport.highlights.first { $0.code == "zh" }
            XCTAssertEqual(zh?.note, .goodOnThisModel,
                           "\(id) must carry the good-Chinese note")
        }
    }

    // MARK: - Issue #408: the Turbo swap must not change tier

    /// The acceptance criterion the swap could silently fail: `languageSupport`
    /// switches on the identifier, and an unclassified Whisper entry falls through to
    /// the small-class default. A new Turbo landing in that branch would tell its
    /// users their model is imprecise on Chinese and to upgrade — away from the
    /// highest-accuracy variant the app ships.
    func testBothTurboVariantsResolveToHighAccuracyNotTheSmallClassDefault() {
        for id in ["openai_whisper-large-v3-v20240930_turbo_632MB",
                   "openai_whisper-large-v3_turbo_954MB"] {
            guard let model = ModelInfo.forIdentifier(id) else {
                XCTFail("\(id) missing from catalog")
                continue
            }
            let zh = model.languageSupport.highlights.first { $0.code == "zh" }
            XCTAssertEqual(zh?.note, .goodOnThisModel, "\(id) fell through to the small class")
            guard let medium = ModelInfo.forIdentifier("openai_whisper-medium") else {
                XCTFail("medium missing from catalog")
                return
            }
            XCTAssertEqual(model.languageSupport.highlights.map(\.code),
                           medium.languageSupport.highlights.map(\.code),
                           "\(id) does not share Medium's high-accuracy highlights")
        }
    }

    // MARK: - Parakeet documented list

    func testParakeetListsExactly25UniqueLanguagesWithoutChinese() {
        guard let parakeet = ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3") else {
            XCTFail("Parakeet missing from catalog")
            return
        }
        let support = parakeet.languageSupport
        let allCodes = support.highlights.map(\.code) + support.additionalCodes
        // NVIDIA documents exactly 25 European languages for TDT 0.6b v3.
        XCTAssertEqual(allCodes.count, 25)
        XCTAssertEqual(Set(allCodes).count, 25, "language codes must be unique")
        XCTAssertFalse(allCodes.contains("zh"), "Parakeet does not support Chinese")
        for code in testedCodes {
            XCTAssertTrue(allCodes.contains(code), "\(code) missing from Parakeet list")
        }
        // No quality caveats curated on Parakeet's highlighted languages.
        XCTAssertTrue(support.highlights.allSatisfy { $0.note == nil })
    }

    func testParakeetCodesAreValidISO639_1() {
        guard let parakeet = ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3") else {
            XCTFail("Parakeet missing from catalog")
            return
        }
        let allCodes = parakeet.languageSupport.highlights.map(\.code)
            + parakeet.languageSupport.additionalCodes
        for code in allCodes {
            XCTAssertEqual(code.count, 2, "\(code) is not a two-letter ISO 639-1 code")
            // The English locale must be able to name every documented code —
            // guards against typos like "cz" (Czech is "cs").
            let name = Locale(identifier: "en").localizedString(forLanguageCode: code)
            XCTAssertNotNil(name, "\(code) is not a language code the OS can name")
            XCTAssertNotEqual(name, code, "\(code) resolved to itself — likely invalid")
        }
    }

    // MARK: - Whisper full list with quality tiers (#240 design round)

    func testWhisperModelsHaveNoAdditionalCodesList() {
        // Whisper's full list lives in tierGroups; additionalCodes stays
        // Parakeet-only.
        for model in ModelInfo.allIncludingDeprecated where model.engine == .whisperKit {
            XCTAssertTrue(model.languageSupport.additionalCodes.isEmpty,
                          "\(model.identifier) should not list additional codes")
        }
    }

    func testParakeetHasNoTierGroups() {
        // Parakeet's finite documented list needs no tier breakdown.
        let parakeet = ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3")
        XCTAssertEqual(parakeet?.languageSupport.tierGroups.isEmpty, true)
    }

    /// Golden copy of WhisperKit's tokenizer language map (Constants in
    /// Core/Models.swift, 99 classic codes + Cantonese `yue`), with the same
    /// jw -> jv Javanese normalization the production data applies. Kept as an
    /// independent literal so a missing or substituted code in the production
    /// tiers fails the comparison, not just a count check.
    private static let whisperTokenizerCodes: Set<String> = [
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
        "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
        "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
        "jv", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
        "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
        "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
        "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh"
    ]

    func testWhisperTierGroupsCoverFullTokenizerSet() {
        // Every Whisper model must carry the complete tokenizer language
        // set, grouped good -> fair -> limited, matching the golden copy
        // code-for-code (not just by count).
        for model in ModelInfo.allIncludingDeprecated where model.engine == .whisperKit {
            let groups = model.languageSupport.tierGroups
            XCTAssertEqual(groups.map(\.tier), [.good, .fair, .limited],
                           "\(model.identifier) tiers out of order")
            let allCodes = groups.flatMap(\.codes)
            XCTAssertEqual(Set(allCodes).count, allCodes.count,
                           "\(model.identifier) has duplicate codes across tiers")
            XCTAssertEqual(Set(allCodes), Self.whisperTokenizerCodes,
                           "\(model.identifier) must match the tokenizer set exactly")
        }
    }

    func testWhisperTierAssignmentsMatchPublishedAnchors() {
        // Spot-check the FLEURS-grounded assignments (OpenAI large-v3
        // language-breakdown data): the four tested languages and Chinese
        // are good-tier; Czech/Hindi are fair; Bengali and the unbenchmarked
        // long tail (Cantonese, Hawaiian) are limited.
        guard let support = ModelInfo.forIdentifier("openai_whisper-small")?.languageSupport,
              let good = support.tierGroups.first(where: { $0.tier == .good }),
              let fair = support.tierGroups.first(where: { $0.tier == .fair }),
              let limited = support.tierGroups.first(where: { $0.tier == .limited }) else {
            XCTFail("Whisper small missing tier groups")
            return
        }
        for code in testedCodes + ["zh"] {
            XCTAssertTrue(good.codes.contains(code), "\(code) should be good-tier")
        }
        XCTAssertTrue(fair.codes.contains("cs"))
        XCTAssertTrue(fair.codes.contains("hi"))
        XCTAssertTrue(limited.codes.contains("bn"))
        XCTAssertTrue(limited.codes.contains("yue"))
        XCTAssertTrue(limited.codes.contains("haw"))
        // Whisper's legacy "jw" must be normalized to ISO "jv" for display.
        XCTAssertTrue(limited.codes.contains("jv"))
        XCTAssertFalse(limited.codes.contains("jw"))
    }

    func testWhisperTierCodesAreNameableByTheOS() {
        // Every tier code must resolve to a real language name via Locale
        // (guards against typos across the 100-code list). Codes may be
        // 2-letter ISO 639-1 or 3-letter ISO 639-2/3 (haw, yue).
        guard let support = ModelInfo.forIdentifier("openai_whisper-small")?.languageSupport else {
            XCTFail("Whisper small missing language support")
            return
        }
        for code in support.tierGroups.flatMap(\.codes) {
            XCTAssertTrue((2...3).contains(code.count), "\(code) has unexpected length")
            let name = Locale(identifier: "en").localizedString(forLanguageCode: code)
            XCTAssertNotNil(name, "\(code) is not a language code the OS can name")
            XCTAssertNotEqual(name, code, "\(code) resolved to itself — likely invalid")
        }
    }
}
