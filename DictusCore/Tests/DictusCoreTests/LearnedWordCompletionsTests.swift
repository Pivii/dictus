// DictusCore/Tests/DictusCoreTests/LearnedWordCompletionsTests.swift
// Covers the merge that gives a learned word the first completion slot (#346).
import XCTest
@testable import DictusCore

final class LearnedWordCompletionsTests: XCTestCase {

    /// Timestamps are epoch seconds. These only need to be ordered.
    private let older = 1_700_000_000
    private let newer = 1_700_000_100

    // MARK: - No learned match

    func testAnEmptyDictionaryLeavesTheSystemCompletionsUntouched() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: [:],
            systemCompletions: ["zone", "zoo", "zodiaque", "zoom"]
        )
        XCTAssertEqual(result, ["zone", "zoo", "zodiaque"])
    }

    func testAWordThatDoesNotExtendThePrefixIsNotOffered() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["mathilde": newer],
            systemCompletions: ["zone", "zoo"]
        )
        XCTAssertEqual(result, ["zone", "zoo"])
    }

    // MARK: - Exact match dropped (decision 3)

    func testAFullyTypedLearnedWordIsNotEchoedBack() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zorglub",
            learnedWords: ["zorglub": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, [], "A match equal to what was typed spends a slot on a tap that changes nothing")
    }

    func testTheExactMatchIsDroppedEvenWhenTheCasingDiffers() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "Zorglub",
            learnedWords: ["zorglub": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, [])
    }

    func testALongerLearnedWordStillWinsWhenAShorterOneMatchesExactly() {
        // "zorglub" is fully typed and dropped; "zorglubien" still extends it.
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zorglub",
            learnedWords: ["zorglub": newer, "zorglubien": older],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["zorglubien"])
    }

    // MARK: - Several matches resolved by lastUsed (decision 4)

    func testTheMostRecentlyUsedMatchWins() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": older, "zorbax": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["zorbax"])
    }

    func testRecencyBeatsPrefixLengthAndAlphabet() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "z",
            learnedWords: ["zabu": newer, "zorglub": older, "zzz": older],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["zabu"])
    }

    func testMatchesStampedInTheSameSecondResolveDeterministically() {
        // Second resolution means ties are ordinary, and Dictionary iteration
        // order is not stable — the same store must always offer the same word.
        let learned = ["zorglub": newer, "zorbax": newer, "zumba": newer]
        let results = (0..<20).map { _ in
            LearnedWordCompletions.merge(
                typedPrefix: "z", learnedWords: learned, systemCompletions: []
            )
        }
        XCTAssertEqual(Set(results.map { $0.first }), ["zorbax"])
    }

    // MARK: - First slot, one word maximum

    func testTheLearnedWordTakesTheFirstSlotAndTheRestFollowInOrder() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": newer],
            systemCompletions: ["zone", "zoo", "zodiaque"]
        )
        XCTAssertEqual(result, ["zorglub", "zone", "zoo"])
    }

    func testAtMostOneLearnedWordIsOfferedEvenWithManyMatches() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": newer, "zorbax": older, "zoltan": older],
            systemCompletions: ["zone", "zoo"]
        )
        XCTAssertEqual(result, ["zorglub", "zone", "zoo"])
    }

    func testTheListNeverExceedsTheLimit() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": newer],
            systemCompletions: ["zone", "zoo", "zodiaque", "zoom", "zorro"]
        )
        XCTAssertEqual(result.count, 3)
    }

    func testALearnedWordTheSystemAlsoKnowsIsOfferedOnlyOnce() {
        // Learning gates on the trie, not on UITextChecker, so the two sources
        // can genuinely produce the same word.
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zone": newer],
            systemCompletions: ["zone", "zoo", "zodiaque"]
        )
        XCTAssertEqual(result, ["zone", "zoo", "zodiaque"])
    }

    // MARK: - Casing reconstructed from the typed prefix (decision 6)

    func testALowercasePrefixOffersTheWordLowercased() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["zorglub"])
    }

    func testACapitalizedPrefixOffersTheWordCapitalized() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "Zo",
            learnedWords: ["zorglub": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["Zorglub"])
    }

    func testAnAllCapsPrefixStillMatchesAndFollowsTheCapitalizationRule() {
        // The shift key fixes the rest; the store has no display form to restore.
        let result = LearnedWordCompletions.merge(
            typedPrefix: "ZO",
            learnedWords: ["zorglub": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["Zorglub"])
    }

    // MARK: - Prefix rules

    func testASingleLetterPrefixAlreadyOffersTheWord() {
        // No minimum prefix length (decision 5).
        let result = LearnedWordCompletions.merge(
            typedPrefix: "z",
            learnedWords: ["zorglub": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["zorglub"])
    }

    func testAnEmptyPrefixOffersNothingLearned() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "",
            learnedWords: ["zorglub": newer],
            systemCompletions: ["zone"]
        )
        XCTAssertEqual(result, ["zone"])
    }

    func testAStoredWordWithUnexpectedCasingStillMatches() {
        // The store lowercases its keys; the merge must not depend on that.
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["ZorGluB": newer],
            systemCompletions: []
        )
        XCTAssertEqual(result, ["zorglub"])
    }

    func testAZeroLimitReturnsNothing() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": newer],
            systemCompletions: ["zone"],
            limit: 0
        )
        XCTAssertEqual(result, [])
    }

    func testALimitOfOneLeavesRoomForTheLearnedWordOnly() {
        let result = LearnedWordCompletions.merge(
            typedPrefix: "zo",
            learnedWords: ["zorglub": newer],
            systemCompletions: ["zone", "zoo"],
            limit: 1
        )
        XCTAssertEqual(result, ["zorglub"])
    }

    // MARK: - The corrections row

    func testTheLearnedWordTakesTheThirdSlotFromTheAlternative() {
        // The device case: typing "Zor" proposes "Air", and "Zorglub" had no
        // slot at all before this.
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "Zor",
            correction: "Air",
            alternative: "Aire",
            learnedWords: ["zorglub": newer]
        )
        XCTAssertEqual(row, ["Zor", "Air", "Zorglub"])
    }

    func testTheCorrectionSlotIsNeverTheLearnedWord() {
        // Slot 1 is what space applies on its own. A learned word there is L3,
        // which is #114's — see ADR 0004.
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "Zor",
            correction: "Air",
            alternative: nil,
            learnedWords: ["zorglub": newer]
        )
        XCTAssertEqual(row[1], "Air")
    }

    func testTheAlternativeKeepsTheThirdSlotWhenNoLearnedWordMatches() {
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "Zor",
            correction: "Air",
            alternative: "Aire",
            learnedWords: ["mathilde": newer]
        )
        XCTAssertEqual(row, ["Zor", "Air", "Aire"])
    }

    func testTheRowIsTwoSlotsWhenThereIsNeitherAnAlternativeNorALearnedWord() {
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "Zor",
            correction: "Air",
            alternative: nil,
            learnedWords: [:]
        )
        XCTAssertEqual(row, ["Zor", "Air"])
    }

    func testALearnedWordFillsTheThirdSlotEvenWithNoAlternative() {
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "Zorgl",
            correction: "Sorti",
            alternative: nil,
            learnedWords: ["zorglub": newer]
        )
        XCTAssertEqual(row, ["Zorgl", "Sorti", "Zorglub"])
    }

    func testAtMostOneLearnedWordReachesTheCorrectionsRow() {
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "zo",
            correction: "ai",
            alternative: nil,
            learnedWords: ["zorglub": newer, "zorbax": older, "zoltan": older]
        )
        XCTAssertEqual(row, ["zo", "ai", "zorglub"])
    }

    func testTheMostRecentlyUsedLearnedWordTakesTheCorrectionsSlot() {
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "zo",
            correction: "ai",
            alternative: nil,
            learnedWords: ["zorglub": older, "zorbax": newer]
        )
        XCTAssertEqual(row.last, "zorbax")
    }

    func testTheCorrectionsSlotFollowsTheCasingOfTheTypedPrefix() {
        let lower = LearnedWordCompletions.correctionsRow(
            typedWord: "zorg", correction: "sort", alternative: nil,
            learnedWords: ["zorglub": newer]
        )
        let upper = LearnedWordCompletions.correctionsRow(
            typedWord: "Zorg", correction: "Sort", alternative: nil,
            learnedWords: ["zorglub": newer]
        )
        XCTAssertEqual(lower.last, "zorglub")
        XCTAssertEqual(upper.last, "Zorglub")
    }

    func testAFullyTypedLearnedWordDoesNotClaimTheCorrectionsSlot() {
        // Same strictness as the completions merge: nothing left to complete.
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "zorglub",
            correction: "zorglube",
            alternative: "zorglubs",
            learnedWords: ["zorglub": newer]
        )
        XCTAssertEqual(row, ["zorglub", "zorglube", "zorglubs"])
    }

    func testALearnedWordEqualToTheCorrectionYieldsToTheAlternative() {
        // The two come from different sources and nothing stops them agreeing;
        // the same string twice in one bar is a bug either way.
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "zorg",
            correction: "Zorglub",
            alternative: "sortie",
            learnedWords: ["zorglub": newer]
        )
        XCTAssertEqual(row, ["zorg", "Zorglub", "sortie"])
    }

    func testTheCorrectionsRowNeverExceedsThreeSlots() {
        let row = LearnedWordCompletions.correctionsRow(
            typedWord: "zo",
            correction: "ai",
            alternative: "air",
            learnedWords: ["zorglub": newer, "zorbax": older]
        )
        XCTAssertEqual(row.count, 3)
    }
}
