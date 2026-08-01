// DictusCore/Tests/DictusCoreTests/SupportedLanguageActivationTests.swift
// Tests for SupportedLanguage.activate — the single place the keyboard language
// and its layout are written together (#241, coupling tracked by #272).
import XCTest
@testable import DictusCore

final class SupportedLanguageActivationTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    override func tearDown() {
        super.tearDown()
        defaults?.removeObject(forKey: SharedKeys.language)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
    }

    // MARK: - Language write

    func testActivateWritesLanguage() {
        SupportedLanguage.activate(.spanish)
        XCTAssertEqual(defaults?.string(forKey: SharedKeys.language), "es")
        XCTAssertEqual(SupportedLanguage.active, .spanish)
    }

    func testActivateIsIdempotent() {
        SupportedLanguage.activate(.german)
        SupportedLanguage.activate(.german)
        XCTAssertEqual(SupportedLanguage.active, .german)
        XCTAssertEqual(LayoutType.active, .qwerty)
    }

    // MARK: - Layout write (the #272 coupling)

    func testActivateFrenchWritesAzerty() {
        SupportedLanguage.activate(.english)
        SupportedLanguage.activate(.french)
        XCTAssertEqual(defaults?.string(forKey: SharedKeys.keyboardLayout), "azerty")
        XCTAssertEqual(LayoutType.active, .azerty)
    }

    func testActivateNonFrenchWritesQwerty() {
        SupportedLanguage.activate(.french)
        SupportedLanguage.activate(.english)
        XCTAssertEqual(defaults?.string(forKey: SharedKeys.keyboardLayout), "qwerty")
        XCTAssertEqual(LayoutType.active, .qwerty)
    }

    /// Every supported language must leave the pair consistent — a new language
    /// added to the enum is covered without editing this test.
    func testActivateWritesTheLanguagesOwnDefaultLayout() {
        for language in SupportedLanguage.allCases {
            SupportedLanguage.activate(language)
            XCTAssertEqual(SupportedLanguage.active, language)
            XCTAssertEqual(LayoutType.active, language.defaultLayout)
        }
    }
}
