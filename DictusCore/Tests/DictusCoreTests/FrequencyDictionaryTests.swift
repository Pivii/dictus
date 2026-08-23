// DictusCore/Tests/DictusCoreTests/FrequencyDictionaryTests.swift
import XCTest
@testable import DictusCore

final class FrequencyDictionaryTests: XCTestCase {

    func testFrequencyCountReturnsCorrectValueForKnownWord() {
        var dict = FrequencyDictionary()
        let json = #"{"de": 1, "la": 2, "le": 3, "bonjour": 500}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.frequencyCount(of: "de"), 1)
        XCTAssertEqual(dict.frequencyCount(of: "bonjour"), 500)
    }

    func testFrequencyCountReturnsZeroForUnknownWord() {
        // `frequencyCount(of:)` returns the raw frequency count (higher = more
        // common), and 0 when the word is not in the dictionary.
        var dict = FrequencyDictionary()
        let json = #"{"de": 1}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.frequencyCount(of: "xylophone"), 0)
    }

    func testFrequencyCountIsCaseInsensitive() {
        var dict = FrequencyDictionary()
        let json = #"{"bonjour": 42}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.frequencyCount(of: "Bonjour"), 42)
        XCTAssertEqual(dict.frequencyCount(of: "BONJOUR"), 42)
    }

    func testLoadFromInvalidDataProducesEmptyDict() {
        var dict = FrequencyDictionary()
        dict.load(from: "not json".data(using: .utf8)!)
        // Empty dict → unknown words return 0.
        XCTAssertEqual(dict.frequencyCount(of: "de"), 0)
    }

    func testCommonWordsHaveHigherCountsThanUncommon() {
        var dict = FrequencyDictionary()
        let json = #"{"de": 1, "la": 2, "anticonstitutionnellement": 9999}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertTrue(dict.frequencyCount(of: "de") < dict.frequencyCount(of: "anticonstitutionnellement"))
    }

    func testLoadFromFixtureFile() {
        guard let url = Bundle.module.url(forResource: "fr_frequency_test", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("Test fixture fr_frequency_test.json not found in test bundle")
            return
        }
        var dict = FrequencyDictionary()
        dict.load(from: data)
        XCTAssertEqual(dict.frequencyCount(of: "de"), 1)
        XCTAssertTrue(dict.frequencyCount(of: "le") < dict.frequencyCount(of: "anticonstitutionnellement"))
    }

    // MARK: - Ordering

    func testSortedMostCommonFirstPutsTheMostCommonWordFirst() {
        // The suggestion bar's contract, pinned (#365): typing "le" must offer
        // "les" before "lesparre". UITextChecker hands its completions over in
        // alphabetical order, so this ordering is the whole value we add.
        var dict = FrequencyDictionary()
        let json = #"{"les": 9000, "lesparre": 3}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.sortedMostCommonFirst(["lesparre", "les"]), ["les", "lesparre"])
    }

    func testSortedMostCommonFirstSinksWordsTheDictionaryDoesNotKnow() {
        // Only the top 10K words are kept in memory, so a rare completion counts
        // 0 and must land last rather than wherever the caller passed it.
        var dict = FrequencyDictionary()
        let json = #"{"les": 9000, "lesparre": 3}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(
            dict.sortedMostCommonFirst(["lesquiller", "lesparre", "les"]),
            ["les", "lesparre", "lesquiller"]
        )
    }
}
