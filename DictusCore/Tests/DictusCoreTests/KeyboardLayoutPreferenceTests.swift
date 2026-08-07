// DictusCore/Tests/DictusCoreTests/KeyboardLayoutPreferenceTests.swift
// Per-language layout storage, the inherited/explicit distinction, and the one-time
// migration off the single global layout key (#272).
//
// This is the part of #272 that can be proven without a device, and the migration is the
// part that cannot be fixed after the fact — an update that reshapes a keyboard has
// already reshaped it. Hence the coverage here.
import XCTest
@testable import DictusCore

final class KeyboardLayoutPreferenceTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    /// Both keys AND the language are cleared on the way in and out: the migration stamp is
    /// sticky by design, so a leftover from another test would hide every migration case.
    override func setUp() {
        super.setUp()
        clearStorage()
    }

    override func tearDown() {
        clearStorage()
        super.tearDown()
    }

    private func clearStorage() {
        defaults?.removeObject(forKey: SharedKeys.keyboardLayoutsByLanguage)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
        defaults?.removeObject(forKey: SharedKeys.language)
        defaults?.removeObject(forKey: SharedKeys.hasCompletedOnboarding)
    }

    // MARK: - Inherited (no explicit choice)

    func testEveryLanguageStartsAtItsDefaultLayout() {
        for language in SupportedLanguage.allCases {
            XCTAssertEqual(KeyboardLayoutPreference.layout(for: language), language.defaultLayout)
            XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: language))
            XCTAssertNil(KeyboardLayoutPreference.explicitLayout(for: language))
        }
    }

    /// The point of "inherited": a language nobody chose a layout for still follows the
    /// default, so shipping a new default (QWERTZ for German, #151) reaches those users.
    func testAnInheritedLanguageTracksItsDefault() {
        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .german), .qwertz)
        XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: .german))
    }

    // MARK: - Explicit choice

    func testAnExplicitChoiceIsStoredAndReported() {
        KeyboardLayoutPreference.setLayout(.azerty, for: .english)

        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .english), .azerty)
        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .english), .azerty)
        XCTAssertFalse(KeyboardLayoutPreference.isInherited(for: .english))
    }

    /// The case in the issue: English autocorrect on the AZERTY the user's fingers know,
    /// without French losing AZERTY or English losing its own remembered layout.
    func testLanguagesRememberTheirLayoutsIndependently() {
        KeyboardLayoutPreference.setLayout(.azerty, for: .english)

        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .english), .azerty)
        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .french), .azerty, "French keeps its default")
        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .german), .qwertz, "German is untouched")
        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .spanish), .qwerty, "Spanish is untouched")
    }

    func testSwitchingLanguageDoesNotRewriteAnyStoredLayout() {
        KeyboardLayoutPreference.setLayout(.azerty, for: .english)

        SupportedLanguage.activate(.english)
        XCTAssertEqual(LayoutType.active, .azerty, "Picking English must not force QWERTY back")

        SupportedLanguage.activate(.french)
        SupportedLanguage.activate(.english)
        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .english), .azerty,
                       "A round trip through another language must not clear the choice")
    }

    /// A pick that happens to equal the default is still a pick: it must survive a later
    /// change of that language's default, exactly like any other explicit choice.
    func testChoosingTheDefaultLayoutIsStillExplicit() {
        KeyboardLayoutPreference.setLayout(.qwertz, for: .german)

        XCTAssertFalse(KeyboardLayoutPreference.isInherited(for: .german))
        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .german), .qwertz)
    }

    func testLastChoiceWinsForTheSameLanguage() {
        KeyboardLayoutPreference.setLayout(.azerty, for: .english)
        KeyboardLayoutPreference.setLayout(.qwertz, for: .english)

        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .english), .qwertz)
    }

    func testAnUnreadableStoredEntryFallsBackToTheLanguageDefault() {
        defaults?.set(["de": "dvorak"], forKey: SharedKeys.keyboardLayoutsByLanguage)

        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .german), .qwertz,
                       "A layout we cannot parse must behave as no choice at all, not as AZERTY")
        XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: .german))
    }

    // MARK: - LayoutType.active resolves through the active language

    func testActiveLayoutFollowsTheActiveLanguage() {
        KeyboardLayoutPreference.setLayout(.azerty, for: .english)

        SupportedLanguage.activate(.english)
        XCTAssertEqual(LayoutType.active, .azerty)

        SupportedLanguage.activate(.german)
        XCTAssertEqual(LayoutType.active, .qwertz, "German never got a choice, so it uses its default")
    }

    // MARK: - Migration (spec §6)

    /// The common upgrade: one stored layout, matching the active language's default.
    func testMigrationFreezesTheStoredLayoutOfTheActiveLanguage() {
        defaults?.set(SupportedLanguage.french.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.azerty.rawValue, forKey: SharedKeys.keyboardLayout)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .french), .azerty,
                       "The active language's layout is frozen as explicit, not recomputed")
    }

    /// The reason the value is frozen instead of recomputed: the pre-#272 Settings picker
    /// let a layout diverge from the active language's default, so some installs already
    /// hold a combination `defaultLayout` would not produce.
    func testMigrationPreservesALayoutThatDivergesFromTheLanguageDefault() {
        defaults?.set(SupportedLanguage.german.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)

        XCTAssertEqual(LayoutType.active, .qwerty,
                       "Nobody's keyboard may change shape on update — not even to the new default")
        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .german), .qwerty)
    }

    func testMigrationLeavesTheOtherLanguagesInherited() {
        defaults?.set(SupportedLanguage.german.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        for language in SupportedLanguage.allCases where language != .german {
            XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: language),
                          "\(language.rawValue) never had a visible value, so it seeds at its default")
            XCTAssertEqual(KeyboardLayoutPreference.layout(for: language), language.defaultLayout)
        }
    }

    /// An unreadable legacy value used to resolve to AZERTY — that is the shape the user
    /// is looking at, so that is what gets frozen.
    func testMigrationFreezesAzertyForAnUnreadableLegacyValue() {
        defaults?.set(SupportedLanguage.spanish.rawValue, forKey: SharedKeys.language)
        defaults?.set("dvorak", forKey: SharedKeys.keyboardLayout)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .spanish), .azerty)
    }

    /// No stored layout but onboarding is behind them: they have been typing on the AZERTY
    /// fallback, and must keep it.
    func testMigrationFreezesAzertyForAnOnboardedInstallWithNoStoredLayout() {
        defaults?.set(true, forKey: SharedKeys.hasCompletedOnboarding)
        defaults?.set(SupportedLanguage.english.rawValue, forKey: SharedKeys.language)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .english), .azerty)
    }

    /// A fresh install has no shape to preserve: everything stays inherited, so a new
    /// install that picks German gets QWERTZ rather than the AZERTY fallback.
    func testMigrationFreezesNothingOnAFreshInstall() {
        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        for language in SupportedLanguage.allCases {
            XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: language))
        }
        XCTAssertEqual(defaults?.dictionary(forKey: SharedKeys.keyboardLayoutsByLanguage) as? [String: String], [:],
                       "The empty dictionary is the stamp that says migration already ran")
    }

    /// The stamp is what makes a *later* language change safe: without it, this install
    /// would look like an upgrade sitting on German and be frozen to AZERTY.
    func testAFreshInstallThatPicksGermanAfterMigrationStillInheritsQwertz() {
        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        SupportedLanguage.activate(.german)

        XCTAssertEqual(LayoutType.active, .qwertz)
        XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: .german))
    }

    func testMigrationIsIdempotentAndNeverOverwritesAChoice() {
        defaults?.set(SupportedLanguage.french.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.azerty.rawValue, forKey: SharedKeys.keyboardLayout)

        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()
        KeyboardLayoutPreference.setLayout(.qwerty, for: .french)
        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        XCTAssertEqual(KeyboardLayoutPreference.layout(for: .french), .qwerty,
                       "A second migration must not reinstate the legacy value")
    }

    /// Migration runs from whichever entry point is reached first, in whichever process —
    /// the keyboard extension can run before DictusApp is ever launched again.
    func testMigrationRunsFromAPlainRead() {
        defaults?.set(SupportedLanguage.german.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)

        _ = KeyboardLayoutPreference.layout(for: .french)

        XCTAssertEqual(defaults?.dictionary(forKey: SharedKeys.keyboardLayoutsByLanguage) as? [String: String],
                       ["de": "qwerty"])
    }

    func testMigrationRunsBeforeALanguageSwitchCanMoveTheActiveLanguage() {
        defaults?.set(SupportedLanguage.french.rawValue, forKey: SharedKeys.language)
        defaults?.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)

        SupportedLanguage.activate(.english)

        XCTAssertEqual(KeyboardLayoutPreference.explicitLayout(for: .french), .qwerty,
                       "The frozen value belongs to the language the user was typing on")
        XCTAssertTrue(KeyboardLayoutPreference.isInherited(for: .english),
                      "The language they switched to must not inherit the other one's frozen value")
        XCTAssertEqual(LayoutType.active, .qwerty, "English still had no choice, so it uses its own default")
    }

    // MARK: - Legacy mirror (rollback safety)

    func testTheLegacyKeyMirrorsTheActiveLanguageLayout() {
        SupportedLanguage.activate(.german)
        XCTAssertEqual(defaults?.string(forKey: SharedKeys.keyboardLayout), "qwertz")

        KeyboardLayoutPreference.setLayout(.azerty, for: .german)
        XCTAssertEqual(defaults?.string(forKey: SharedKeys.keyboardLayout), "azerty",
                       "A build without #272 must find the shape the user is actually on")
    }

    func testChoosingALayoutForAnotherLanguageLeavesTheMirrorAlone() {
        SupportedLanguage.activate(.french)
        KeyboardLayoutPreference.setLayout(.qwerty, for: .english)

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.keyboardLayout), "azerty",
                       "The mirror describes the active language, not the one being configured")
    }
}
