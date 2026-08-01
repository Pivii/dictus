// DictusCore/Tests/DictusCoreTests/UserDictionaryTests.swift
// Tests for UserDictionary.recordUsage — the repetition-learning counter path.
import XCTest
@testable import DictusCore

/// WHY these tests exist: `recordUsage` is called from the keyboard extension on
/// every word boundary and is the only place the pending → learned promotion
/// happens. Its two counter branches (bump an already-learned word, increment a
/// pending word and promote it at the threshold) had no coverage.
///
/// WHY they drive the shared singleton: `UserDictionary` has a private init and
/// reads App Group UserDefaults directly, so there is no seam to inject storage.
/// `resetAll()` in tearDown restores a clean slate, matching the approach in
/// KeyboardModeTests and SupportedLanguageActivationTests.
final class UserDictionaryTests: XCTestCase {

    override func tearDown() {
        UserDictionary.shared.resetAll()
        super.tearDown()
    }

    // MARK: - Promotion from pending to learned

    func testRecordUsageLearnsAWordOnceTheThresholdIsReached() {
        let word = "zorglub"
        var crossedThreshold = false
        for _ in 0..<UserDictionary.repetitionThreshold {
            crossedThreshold = UserDictionary.shared.recordUsage(word)
        }

        XCTAssertTrue(crossedThreshold, "The call reaching the threshold must report the word as just learned")
        XCTAssertTrue(UserDictionary.shared.isLearned(word))
        // The promoted word carries the pending count it accumulated, not a reset to 1.
        XCTAssertEqual(UserDictionary.shared.allLearnedWords[word], UserDictionary.repetitionThreshold)
    }

    func testRecordUsageBelowTheThresholdDoesNotLearnTheWord() throws {
        try XCTSkipIf(
            UserDictionary.repetitionThreshold < 2,
            "Threshold is 1, so there is no below-threshold call to observe"
        )
        let word = "zorglub"
        XCTAssertFalse(UserDictionary.shared.recordUsage(word))
        XCTAssertFalse(UserDictionary.shared.isLearned(word))
    }

    // MARK: - Bumping an already-learned word

    func testRecordUsageBumpsTheCountOfAnAlreadyLearnedWord() {
        let word = "zorglub"
        UserDictionary.shared.learn(word)
        XCTAssertEqual(UserDictionary.shared.allLearnedWords[word], 1)

        let crossedThreshold = UserDictionary.shared.recordUsage(word)

        XCTAssertFalse(crossedThreshold, "An already-learned word must not report as newly learned")
        XCTAssertEqual(UserDictionary.shared.allLearnedWords[word], 2)
    }

    func testRecordUsageMatchesAnAlreadyLearnedWordRegardlessOfCase() {
        UserDictionary.shared.learn("zorglub")

        XCTAssertFalse(UserDictionary.shared.recordUsage("ZorGluB"))

        // Case-folded onto the same key rather than creating a second entry.
        XCTAssertEqual(UserDictionary.shared.allLearnedWords["zorglub"], 2)
        XCTAssertNil(UserDictionary.shared.allLearnedWords["ZorGluB"])
    }

    // MARK: - Guards

    func testRecordUsageIgnoresEmptyAndSingleCharacterWords() {
        XCTAssertFalse(UserDictionary.shared.recordUsage(""))
        XCTAssertFalse(UserDictionary.shared.recordUsage("a"))
        XCTAssertEqual(UserDictionary.shared.count, 0)
    }
}
