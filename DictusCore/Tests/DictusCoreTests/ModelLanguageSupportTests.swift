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

    // MARK: - Whisper long tail

    func testWhisperModelsHaveNoAdditionalCodesList() {
        // The ≈94-language long tail is conveyed by the coverage summary,
        // not an exhaustive list (#240 plan).
        for model in ModelInfo.allIncludingDeprecated where model.engine == .whisperKit {
            XCTAssertTrue(model.languageSupport.additionalCodes.isEmpty,
                          "\(model.identifier) should not list additional codes")
        }
    }
}
