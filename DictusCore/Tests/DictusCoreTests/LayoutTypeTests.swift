// DictusCore/Tests/DictusCoreTests/LayoutTypeTests.swift
// The layout enum is persisted by raw value in App Group defaults and read by
// both targets, so the raw values and the fallback are pinned here (#151).
import XCTest
@testable import DictusCore

final class LayoutTypeTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    /// Since #272 the layout resolves through the per-language store, and the presence of
    /// that store is a migration stamp — a leftover from another test would decide what
    /// `LayoutType.active` returns here. Cleared both ways round.
    override func setUp() {
        super.setUp()
        clearStorage()
    }

    override func tearDown() {
        clearStorage()
        super.tearDown()
    }

    private func clearStorage() {
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
        defaults?.removeObject(forKey: SharedKeys.keyboardLayoutsByLanguage)
        defaults?.removeObject(forKey: SharedKeys.language)
        // The migration also treats a completed onboarding as "this install predates
        // #272", so a leftover flag decides the outcome of the tests below.
        defaults?.removeObject(forKey: SharedKeys.hasCompletedOnboarding)
    }

    // MARK: - Persisted raw values

    /// Renaming any of these renames what is already stored on installed devices,
    /// which would silently reset those users to AZERTY.
    func testRawValuesAreStable() {
        XCTAssertEqual(LayoutType.azerty.rawValue, "azerty")
        XCTAssertEqual(LayoutType.qwerty.rawValue, "qwerty")
        XCTAssertEqual(LayoutType.qwertz.rawValue, "qwertz")
    }

    func testAllCasesCoversTheThreeLayouts() {
        XCTAssertEqual(LayoutType.allCases, [.azerty, .qwerty, .qwertz])
    }

    // MARK: - Round-trip through App Group defaults

    /// Since #272 the stored value is per language (`KeyboardLayoutPreference`); the migration
    /// off the old single global key has its own coverage in `KeyboardLayoutPreferenceTests`.
    func testEveryLayoutRoundTripsThroughAppGroupDefaults() {
        for layout in LayoutType.allCases {
            KeyboardLayoutPreference.setLayout(layout, for: .active)
            XCTAssertEqual(LayoutType.active, layout, "\(layout.rawValue) did not round-trip")
        }
    }

    func testQwertzIsResolvedFromTheStoredRawValue() {
        KeyboardLayoutPreference.setLayout(.qwertz, for: .active)
        XCTAssertEqual(LayoutType.active, .qwertz)
    }

    // MARK: - Fallback

    func testUnknownStoredValueFallsBackToAzerty() {
        defaults?.set([SupportedLanguage.active.rawValue: "dvorak"], forKey: SharedKeys.keyboardLayoutsByLanguage)
        XCTAssertEqual(LayoutType.active, .azerty,
                       "An unrecognised stored layout must keep falling back to the default, AZERTY for French.")
    }

    func testMissingStoredValueFallsBackToAzerty() {
        XCTAssertEqual(LayoutType.active, .azerty,
                       "Nothing stored and no language stored: French, therefore AZERTY.")
    }

    // MARK: - Display names

    /// Settings and the keyboard panel both read this, so the label is pinned once.
    func testDisplayNames() {
        XCTAssertEqual(LayoutType.azerty.displayName, "AZERTY")
        XCTAssertEqual(LayoutType.qwerty.displayName, "QWERTY")
        XCTAssertEqual(LayoutType.qwertz.displayName, "QWERTZ")
    }
}
