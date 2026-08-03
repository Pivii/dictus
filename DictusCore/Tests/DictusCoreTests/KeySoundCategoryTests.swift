// DictusCore/Tests/DictusCoreTests/KeySoundCategoryTests.swift
// Contract tests pinning the three key-click identifiers (#286).
import XCTest
@testable import DictusCore

final class KeySoundCategoryTests: XCTestCase {

    // MARK: - Cases

    func testEnumHasExactlyThreeCases() {
        XCTAssertEqual(KeySoundCategory.allCases.count, 3)
    }

    // MARK: - System sound identifiers

    /// Moving the click to touchDown (#286) must not change WHICH sound plays.
    /// These are the identifiers the bridge handlers used before the move, and the
    /// same ones giellakbd-ios and Apple's keyboard use.
    func testSystemSoundIdentifiersAreUnchanged() {
        XCTAssertEqual(KeySoundCategory.letter.systemSoundID, 1104)
        XCTAssertEqual(KeySoundCategory.delete.systemSoundID, 1155)
        XCTAssertEqual(KeySoundCategory.modifier.systemSoundID, 1156)
    }

    func testEachCategoryHasItsOwnSound() {
        let ids = Set(KeySoundCategory.allCases.map(\.systemSoundID))
        XCTAssertEqual(ids.count, KeySoundCategory.allCases.count)
    }
}
