// DictusCore/Tests/DictusCoreTests/AccentedCharacterTests.swift
import XCTest
@testable import DictusCore

final class AccentedCharacterTests: XCTestCase {

    func testEMapsToFourAccentedVariants() {
        let accents = AccentedCharacters.accents(for: "e")
        XCTAssertNotNil(accents)
        // e with acute, grave, circumflex, diaeresis
        XCTAssertEqual(accents?.count, 4)
        XCTAssertEqual(accents, ["\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}"])
    }

    func testAMapsTo3AccentedVariants() {
        let accents = AccentedCharacters.accents(for: "a")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents?.count, 3)
        XCTAssertEqual(accents, ["\u{00E0}", "\u{00E2}", "\u{00E4}"])
    }

    func testCMapsTo1Variant() {
        let accents = AccentedCharacters.accents(for: "c")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents?.count, 1)
        XCTAssertEqual(accents, ["\u{00E7}"])
    }

    func testZHasNoAccentedVariants() {
        let accents = AccentedCharacters.accents(for: "z")
        XCTAssertNil(accents)
    }

    func testLookupIsCaseInsensitive() {
        let lowercaseResult = AccentedCharacters.accents(for: "e")
        let uppercaseResult = AccentedCharacters.accents(for: "E")
        XCTAssertEqual(lowercaseResult, uppercaseResult)
    }

    func testUMapsTo3Variants() {
        let accents = AccentedCharacters.accents(for: "u")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents?.count, 3)
        XCTAssertEqual(accents, ["\u{00F9}", "\u{00FB}", "\u{00FC}"])
    }

    func testIMapsTo2Variants() {
        let accents = AccentedCharacters.accents(for: "i")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents?.count, 2)
        XCTAssertEqual(accents, ["\u{00EE}", "\u{00EF}"])
    }

    func testOMapsTo2Variants() {
        let accents = AccentedCharacters.accents(for: "o")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents?.count, 2)
        XCTAssertEqual(accents, ["\u{00F4}", "\u{00F6}"])
    }

    func testYMapsTo1Variant() {
        let accents = AccentedCharacters.accents(for: "y")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents, ["\u{00FF}"])
    }

    func testNMapsTo1Variant() {
        let accents = AccentedCharacters.accents(for: "n")
        XCTAssertNotNil(accents)
        XCTAssertEqual(accents, ["\u{00F1}"])
    }
}
