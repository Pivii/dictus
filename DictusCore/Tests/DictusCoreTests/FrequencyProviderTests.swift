// DictusCore/Tests/DictusCoreTests/FrequencyProviderTests.swift
// Tests for FrequencyProvider.knowsWord — the shape of the question #287 asks.
import XCTest
@testable import DictusCore

/// WHY these exist: `knowsWord` is the single rule two things now depend on —
/// the word-boundary learning gate in the keyboard extension and the duplicate
/// prune in `UserDictionary`. If it disagrees with the split
/// `TextPredictionEngine.spellCheck` makes before its `already-valid` skip, the
/// gate and the corrector stop describing the same dictionary.
final class FrequencyProviderTests: XCTestCase {

    private let provider = MockFrequencyProvider(frequencies: [
        "chat": 900, "ai": 8000, "est": 7000
    ])

    func testKnowsWordIsCaseInsensitive() {
        XCTAssertTrue(provider.knowsWord("Chat"))
        XCTAssertTrue(provider.knowsWord("CHAT"))
    }

    func testKnowsWordIsFalseForAWordTheDictionaryDoesNotHave() {
        XCTAssertFalse(provider.knowsWord("zorglub"))
    }

    /// The trie stores "j'ai" as "ai", so a contraction is judged on the part
    /// after the last apostrophe — the same way the corrector looks it up.
    func testKnowsWordJudgesAContractionOnThePartAfterTheApostrophe() {
        XCTAssertTrue(provider.knowsWord("j'ai"))
        XCTAssertTrue(provider.knowsWord("C'est"))
        XCTAssertFalse(provider.knowsWord("qu'zorglub"))
    }

    /// A trailing apostrophe leaves nothing to look up. Reporting "known" would
    /// be the dangerous answer: the boundary site would decline to learn a word
    /// nothing had actually vetted.
    func testKnowsWordIsFalseWhenTheApostropheLeavesNothingToCheck() {
        XCTAssertFalse(provider.knowsWord("chat'"))
    }
}
