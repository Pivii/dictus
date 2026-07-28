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

    private let highAccuracyWhisperIDs = [
        "openai_whisper-medium",
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

    func testWhisperTierGroupsCoverFullTokenizerSet() {
        // Every Whisper model must carry the complete tokenizer language
        // set: 100 unique codes (99 classic + Cantonese `yue`), grouped
        // good -> fair -> limited.
        for model in ModelInfo.allIncludingDeprecated where model.engine == .whisperKit {
            let groups = model.languageSupport.tierGroups
            XCTAssertEqual(groups.map(\.tier), [.good, .fair, .limited],
                           "\(model.identifier) tiers out of order")
            let allCodes = groups.flatMap(\.codes)
            XCTAssertEqual(allCodes.count, 100,
                           "\(model.identifier) must cover the full tokenizer set")
            XCTAssertEqual(Set(allCodes).count, allCodes.count,
                           "\(model.identifier) has duplicate codes across tiers")
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
