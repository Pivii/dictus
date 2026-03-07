// DictusCore/Tests/DictusCoreTests/SharedKeysExtensionTests.swift
// Tests for SharedKeys extensions: language, hapticsEnabled, hasCompletedOnboarding.
import XCTest
@testable import DictusCore

final class SharedKeysExtensionTests: XCTestCase {

    func testLanguageKeyExists() {
        XCTAssertEqual(SharedKeys.language, "dictus.language")
    }

    func testHapticsEnabledKeyExists() {
        XCTAssertEqual(SharedKeys.hapticsEnabled, "dictus.hapticsEnabled")
    }

    func testHasCompletedOnboardingKeyExists() {
        XCTAssertEqual(SharedKeys.hasCompletedOnboarding, "dictus.hasCompletedOnboarding")
    }

    func testNewKeysAreUnique() {
        let newKeys = [
            SharedKeys.language,
            SharedKeys.hapticsEnabled,
            SharedKeys.hasCompletedOnboarding,
        ]
        XCTAssertEqual(newKeys.count, Set(newKeys).count, "SharedKeys must be unique")
    }

    func testNewKeysHaveDictusPrefix() {
        XCTAssertTrue(SharedKeys.language.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hapticsEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hasCompletedOnboarding.hasPrefix("dictus."))
    }
}
