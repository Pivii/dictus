// DictusCore/Tests/DictusCoreTests/SupportedLanguageActivationTests.swift
// Tests for SupportedLanguage.activate — the single place the keyboard language is
// written (#241). Since #272 it writes the language only: the layout is per language
// and activation no longer overrides it (see KeyboardLayoutPreferenceTests).
import XCTest
@testable import DictusCore

final class SupportedLanguageActivationTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    override func setUp() {
        super.setUp()
        clearStorage()
    }

    override func tearDown() {
        clearStorage()
        super.tearDown()
    }

    private func clearStorage() {
        defaults?.removeObject(forKey: SharedKeys.language)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayoutsByLanguage)
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
        XCTAssertEqual(LayoutType.active, .qwertz)
    }

    // MARK: - Resolved layout after activation
    //
    // The layout each language resolves to is unchanged for a user who never picked one:
    // it is that language's default. What changed in #272 is that a user who *did* pick one
    // keeps it — covered in KeyboardLayoutPreferenceTests. The assertions on
    // `SharedKeys.keyboardLayout` below read the legacy mirror, kept in step so a build
    // without #272 finds the same shape.

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

    func testActivateGermanWritesQwertz() {
        SupportedLanguage.activate(.english)
        SupportedLanguage.activate(.german)
        XCTAssertEqual(defaults?.string(forKey: SharedKeys.keyboardLayout), "qwertz")
        XCTAssertEqual(LayoutType.active, .qwertz)
    }

    /// No migration rewrites a stored layout (#151): a German user who installed before
    /// QWERTZ existed keeps QWERTY. Since #272 they keep it even across a re-selection of
    /// German — the stored value is that language's own choice, never re-derived from it.
    func testStoredLayoutSurvivesALanguageItNoLongerMatches() {
        defaults?.set(SupportedLanguage.german.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)
        XCTAssertEqual(SupportedLanguage.active, .german)
        XCTAssertEqual(LayoutType.active, .qwerty,
                       "Nobody's keyboard may change shape without them selecting the language again.")

        SupportedLanguage.activate(.french)
        SupportedLanguage.activate(.german)
        XCTAssertEqual(LayoutType.active, .qwerty,
                       "Re-selecting the language no longer overwrites the layout it is stored with.")
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
