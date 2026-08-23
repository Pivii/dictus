// DictusCore/Tests/DictusCoreTests/Polish/SmartModeCatalogueTests.swift
// The Smart Mode catalogue and the record type it is made of (issue #79).
import XCTest
@testable import DictusCore

final class SmartModeCatalogueTests: XCTestCase {

    // MARK: - The rows

    func testCatalogueShipsNotesAndOneTranslateEntryPerSupportedLanguage() {
        XCTAssertEqual(SmartModeCatalogue.builtIns.count, 1 + SupportedLanguage.allCases.count)
        XCTAssertTrue(SmartModeCatalogue.builtIns.contains { $0.id == "notes" })
        for language in SupportedLanguage.allCases {
            XCTAssertTrue(
                SmartModeCatalogue.builtIns.contains { $0.id == "translate.\(language.rawValue)" },
                "no translate entry for \(language.rawValue)"
            )
        }
    }

    /// Email is conditional on harness validation and does not ship in this build.
    /// The assertion is here so that adding it is a deliberate act rather than a
    /// drive-by.
    func testEmailDoesNotShip() {
        XCTAssertFalse(SmartModeCatalogue.builtIns.contains { $0.id.contains("email") })
    }

    func testIdentifiersAreUnique() {
        let ids = SmartModeCatalogue.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryModeHasANameAnIconAndAPrompt() {
        for mode in SmartModeCatalogue.builtIns {
            XCTAssertFalse(mode.displayName.isEmpty, mode.id)
            XCTAssertFalse(mode.icon.isEmpty, mode.id)
            XCTAssertFalse(mode.prompt.instructions.isEmpty, mode.id)
            XCTAssertFalse(mode.prompt.userInstruction.isEmpty, mode.id)
            XCTAssertFalse(mode.prompt.outputMarker.isEmpty, mode.id)
        }
    }

    /// Translation targets are not filtered by keyboard language: the spoken
    /// language is unknown until the user speaks, so every target is always offered.
    func testTranslationTargetsAreNotFilteredByKeyboardLanguage() {
        AppGroup.defaults.set(SupportedLanguage.french.rawValue, forKey: SharedKeys.language)
        defer { AppGroup.defaults.removeObject(forKey: SharedKeys.language) }
        XCTAssertNotNil(SmartModeCatalogue.mode(withIdentifier: "translate.fr"))
    }

    // MARK: - Contracts

    /// The whole reason a mode carries its own contract: the ADR 0003 band starts at
    /// 0.5 and Notes condenses well below that.
    func testNotesWidensTheLengthFloorBelowTheFaithfulPolishBand() {
        let notes = SmartModeCatalogue.notes.contract
        XCTAssertLessThan(notes.minimumLengthRatio, PolishAcceptanceContract.natural.minimumLengthRatio)
        XCTAssertEqual(notes.outputLanguage, .sameAsInput)
    }

    func testEachTranslateModeExpectsItsOwnTargetLanguage() {
        for language in SupportedLanguage.allCases {
            let mode = SmartModeCatalogue.translate(to: language)
            XCTAssertEqual(mode.contract.outputLanguage, .fixed(language))
        }
    }

    /// The translate prompt names its target in English, and only its target: a
    /// prompt that named two languages would be one the model could choose between.
    func testTranslatePromptNamesItsTarget() {
        let english = SmartModeCatalogue.translate(to: .english)
        XCTAssertTrue(english.prompt.instructions.contains("English"))
        XCTAssertTrue(english.prompt.userInstruction.contains("English"))
        let german = SmartModeCatalogue.translate(to: .german)
        XCTAssertTrue(german.prompt.instructions.contains("German"))
        XCTAssertFalse(german.prompt.userInstruction.contains("English"))
    }

    /// One English-written prompt per mode, instructing the model to answer in the
    /// language of the input — the #239 pattern, not one prompt per language.
    func testNotesPromptIsWrittenOnceAndKeepsTheInputLanguage() {
        let instructions = SmartModeCatalogue.notes.prompt.instructions
        XCTAssertTrue(instructions.contains("OUTPUT LANGUAGE: the language of the input"))
        XCTAssertTrue(instructions.contains("NEVER translate"))
    }

    // MARK: - The record travels

    func testRecordSurvivesAJSONRoundTrip() throws {
        let original = SmartModeCatalogue.translate(to: .spanish).pinned(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SmartMode.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.contract.outputLanguage, .fixed(.spanish))
        XCTAssertTrue(decoded.isPinned)
    }

    func testOutputLanguageEncodesAsAFlatMarker() throws {
        func encoded(_ value: PolishOutputLanguage) throws -> String {
            String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        }
        XCTAssertEqual(try encoded(.polishTarget), "\"polishTarget\"")
        XCTAssertEqual(try encoded(.sameAsInput), "\"sameAsInput\"")
        XCTAssertEqual(try encoded(.fixed(.german)), "\"de\"")
    }

    func testUnrecognisedOutputLanguageThrowsRatherThanGuessing() {
        XCTAssertThrowsError(try PolishOutputLanguage(storedValue: "klingon"))
    }

    func testUnknownIdentifierResolvesToNoMode() {
        XCTAssertNil(SmartModeCatalogue.mode(withIdentifier: "translate.klingon"))
        XCTAssertNil(SmartModeCatalogue.mode(withIdentifier: ""))
    }
}
