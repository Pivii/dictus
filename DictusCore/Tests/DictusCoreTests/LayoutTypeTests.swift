// DictusCore/Tests/DictusCoreTests/LayoutTypeTests.swift
// The layout enum is persisted by raw value in App Group defaults and read by
// both targets, so the raw values and the fallback are pinned here (#151).
import XCTest
@testable import DictusCore

final class LayoutTypeTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    override func tearDown() {
        super.tearDown()
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
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

    func testEveryLayoutRoundTripsThroughAppGroupDefaults() {
        for layout in LayoutType.allCases {
            defaults?.set(layout.rawValue, forKey: SharedKeys.keyboardLayout)
            XCTAssertEqual(LayoutType.active, layout, "\(layout.rawValue) did not round-trip")
        }
    }

    func testQwertzIsResolvedFromTheStoredRawValue() {
        defaults?.set("qwertz", forKey: SharedKeys.keyboardLayout)
        XCTAssertEqual(LayoutType.active, .qwertz)
    }

    // MARK: - Fallback

    func testUnknownStoredValueFallsBackToAzerty() {
        defaults?.set("dvorak", forKey: SharedKeys.keyboardLayout)
        XCTAssertEqual(LayoutType.active, .azerty,
                       "An unrecognised stored layout must keep falling back to AZERTY.")
    }

    func testMissingStoredValueFallsBackToAzerty() {
        defaults?.removeObject(forKey: SharedKeys.keyboardLayout)
        XCTAssertEqual(LayoutType.active, .azerty)
    }

    // MARK: - Display names

    /// Settings and the keyboard panel both read this, so the label is pinned once.
    func testDisplayNames() {
        XCTAssertEqual(LayoutType.azerty.displayName, "AZERTY")
        XCTAssertEqual(LayoutType.qwerty.displayName, "QWERTY")
        XCTAssertEqual(LayoutType.qwertz.displayName, "QWERTZ")
    }
}
