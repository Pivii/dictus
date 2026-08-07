// DictusCore/Tests/DictusCoreTests/NumberRowPreferenceTests.swift
// The number row flag: its default, its round trip, and its independence from the
// per-language layout store it sits next to (#331).
//
// The default is the part that cannot be fixed after the fact — a release that turns the
// row on for existing users has already made every keyboard on every device taller.
import XCTest
@testable import DictusCore

final class NumberRowPreferenceTests: XCTestCase {

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

    /// The layout keys go too: the migration stamp is sticky, and a leftover from another
    /// test would hide the migration cases below.
    private func clearStorage() {
        defaults?.removeObject(forKey: SharedKeys.numberRowEnabled)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayoutsByLanguage)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
        defaults?.removeObject(forKey: SharedKeys.language)
        defaults?.removeObject(forKey: SharedKeys.hasCompletedOnboarding)
    }

    // MARK: - Default

    func testTheRowIsOffOnAFreshAppGroup() {
        XCTAssertFalse(NumberRowPreference.isEnabled,
                       "Existing installs must see no change: absence of the key means off")
    }

    /// Absence, not a stored `false`. Anything that wrote a default on first launch would make
    /// the flag look chosen, and would be one more thing to keep in step across two processes.
    func testTheDefaultIsAbsenceRatherThanAStoredFalse() {
        _ = NumberRowPreference.isEnabled

        XCTAssertNil(defaults?.object(forKey: SharedKeys.numberRowEnabled),
                     "Reading the preference must not write one")
    }

    // MARK: - Round trip

    func testTheChoiceRoundTrips() {
        NumberRowPreference.setEnabled(true)
        XCTAssertTrue(NumberRowPreference.isEnabled)

        NumberRowPreference.setEnabled(false)
        XCTAssertFalse(NumberRowPreference.isEnabled)
    }

    /// The Settings toggle writes the raw key through @AppStorage rather than through
    /// `setEnabled`, so the two writers have to mean the same thing.
    func testARawWriteToTheSharedKeyIsReadBack() {
        defaults?.set(true, forKey: SharedKeys.numberRowEnabled)

        XCTAssertTrue(NumberRowPreference.isEnabled)
    }

    // MARK: - Independence from the layout store (#272)

    func testTheLayoutMigrationLeavesTheFlagAlone() {
        NumberRowPreference.setEnabled(true)
        defaults?.set(SupportedLanguage.german.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        XCTAssertTrue(NumberRowPreference.isEnabled,
                      "An upgrade that migrates the layout store must not disturb the row")
    }

    func testTheLayoutMigrationDoesNotTurnTheRowOn() {
        defaults?.set(true, forKey: SharedKeys.hasCompletedOnboarding)
        defaults?.set(SupportedLanguage.french.rawValue, forKey: SharedKeys.language)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        XCTAssertFalse(NumberRowPreference.isEnabled)
    }

    func testChoosingALayoutLeavesTheFlagAlone() {
        NumberRowPreference.setEnabled(true)

        KeyboardLayoutPreference.setLayout(.qwertz, for: .german)

        XCTAssertTrue(NumberRowPreference.isEnabled)
    }

    func testTheFlagIsGlobalAndNotPerLanguage() {
        NumberRowPreference.setEnabled(true)

        for language in SupportedLanguage.allCases {
            SupportedLanguage.activate(language)
            XCTAssertTrue(NumberRowPreference.isEnabled,
                          "\(language.rawValue) must see the same row setting as every other language")
        }
    }
}
