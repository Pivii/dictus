// DictusCore/Tests/DictusCoreTests/FillerWordFilterTests.swift
import XCTest
@testable import DictusCore

final class FillerWordFilterTests: XCTestCase {

    // MARK: - French filler removal

    func testRemovesFrenchFillerAtStart() {
        XCTAssertEqual(FillerWordFilter.clean("euh bonjour"), "bonjour")
    }

    func testRemovesMidSentenceFiller() {
        XCTAssertEqual(
            FillerWordFilter.clean("bonjour euh comment allez-vous"),
            "bonjour comment allez-vous"
        )
    }

    func testRemovesAllFillersResultsInEmpty() {
        let result = FillerWordFilter.clean("hm bah ben voila")
        XCTAssertTrue(result.isEmpty, "Expected empty string, got: '\(result)'")
    }

    // MARK: - English filler removal

    func testRemovesEnglishFillers() {
        let result = FillerWordFilter.clean("um uh er")
        XCTAssertTrue(result.isEmpty, "Expected empty string, got: '\(result)'")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveMatching() {
        XCTAssertEqual(FillerWordFilter.clean("Euh Bonjour"), "Bonjour")
    }

    // MARK: - False positive protection (French words containing filler substrings)

    func testPreservesFrenchWordsWithFillerSubstrings() {
        XCTAssertEqual(
            FillerWordFilter.clean("l'humain est bénévole"),
            "l'humain est bénévole"
        )
    }

    func testPreservesWordErrer() {
        XCTAssertEqual(
            FillerWordFilter.clean("elle erre dans la forêt"),
            "elle erre dans la forêt"
        )
    }

    // MARK: - Whitespace and punctuation cleanup

    func testCollapsesDoubleSpaces() {
        XCTAssertEqual(
            FillerWordFilter.clean("Bonjour,  comment"),
            "Bonjour, comment"
        )
    }

    func testRemovesOrphanedPunctuation() {
        XCTAssertEqual(
            FillerWordFilter.clean("euh , bonjour"),
            "bonjour"
        )
    }

    func testPreservesPunctuationWhenNoFillers() {
        XCTAssertEqual(
            FillerWordFilter.clean("Bonjour. Comment allez-vous ?"),
            "Bonjour. Comment allez-vous ?"
        )
    }

    // MARK: - Edge cases

    func testEmptyString() {
        XCTAssertEqual(FillerWordFilter.clean(""), "")
    }

    func testNoFillersNoChange() {
        XCTAssertEqual(FillerWordFilter.clean("Bonjour"), "Bonjour")
    }
}
