// DictusCore/Tests/DictusCoreTests/ProperNounGuardTests.swift
// Tests for the proper-noun preservation rules (issue #199): unknown
// capitalized mid-sentence words and acronyms must not be autocorrected,
// while sentence-start typos keep getting corrected.

import XCTest
@testable import DictusCore

final class ProperNounGuardTests: XCTestCase {

    // MARK: - isLikelyProperNoun — names mid-sentence (issue's example list)

    func testFirstNamesMidSentenceArePreserved() {
        for name in ["Mathilde", "Romain", "Pivi", "Sly"] {
            XCTAssertTrue(
                ProperNounGuard.isLikelyProperNoun(word: name, isAtSentenceStart: false),
                "\(name) mid-sentence should be preserved"
            )
        }
    }

    func testAccentedCapitalizedWordIsPreserved() {
        XCTAssertTrue(ProperNounGuard.isLikelyProperNoun(word: "Élodie", isAtSentenceStart: false))
    }

    // MARK: - isLikelyProperNoun — acronyms (position-independent)

    func testAllCapsAcronymsArePreservedAnywhere() {
        for acronym in ["SNCF", "EDF", "GPT"] {
            XCTAssertTrue(
                ProperNounGuard.isLikelyProperNoun(word: acronym, isAtSentenceStart: false),
                "\(acronym) mid-sentence should be preserved"
            )
            XCTAssertTrue(
                ProperNounGuard.isLikelyProperNoun(word: acronym, isAtSentenceStart: true),
                "\(acronym) at sentence start should be preserved"
            )
        }
    }

    // MARK: - isLikelyProperNoun — words that must stay correctable

    func testSentenceStartCapitalizedWordIsNotPreserved() {
        // "Jai faim" — sentence-start capitalization is autocap, not a name:
        // the contraction correction "Jai" -> "J'ai" must stay possible.
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "Jai", isAtSentenceStart: true))
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "Mathilde", isAtSentenceStart: true))
    }

    func testLowercaseWordIsNotPreserved() {
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "sui", isAtSentenceStart: false))
    }

    func testShortCapitalizedWordIsNotPreserved() {
        // 2-letter capitalized words ("Ca") stay correctable — the French
        // "Ca" -> "Ça" language override must keep working.
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "Ca", isAtSentenceStart: false))
    }

    func testWordWithDigitsIsNotPreserved() {
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "Test123", isAtSentenceStart: false))
    }

    func testWordWithApostropheIsNotPreserved() {
        // Contraction branches own apostrophe tokens ("J'ai", "C'est").
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "J'ai", isAtSentenceStart: false))
    }

    func testMixedCaseWordIsNotPreserved() {
        // Interior uppercase ("McDo", "MathildE") is outside the conservative
        // capitalized-word rule.
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "MathildE", isAtSentenceStart: false))
    }

    func testEmptyWordIsNotPreserved() {
        XCTAssertFalse(ProperNounGuard.isLikelyProperNoun(word: "", isAtSentenceStart: false))
    }

    // MARK: - isAtSentenceStart

    func testStartOfFieldIsSentenceStart() {
        XCTAssertTrue(ProperNounGuard.isAtSentenceStart(context: "Jai", word: "Jai"))
    }

    func testAfterSentencePunctuationIsSentenceStart() {
        XCTAssertTrue(ProperNounGuard.isAtSentenceStart(context: "Bonjour. Jai", word: "Jai"))
        XCTAssertTrue(ProperNounGuard.isAtSentenceStart(context: "Quoi ? Mathilde", word: "Mathilde"))
        XCTAssertTrue(ProperNounGuard.isAtSentenceStart(context: "Super ! Romain", word: "Romain"))
    }

    func testAfterNewlineIsSentenceStart() {
        XCTAssertTrue(ProperNounGuard.isAtSentenceStart(context: "Bonjour,\nMathilde", word: "Mathilde"))
    }

    func testMidSentenceIsNotSentenceStart() {
        XCTAssertFalse(ProperNounGuard.isAtSentenceStart(context: "J'ai vu Mathilde", word: "Mathilde"))
        XCTAssertFalse(ProperNounGuard.isAtSentenceStart(context: "on va chez Sly", word: "Sly"))
    }

    func testAfterCommaIsNotSentenceStart() {
        XCTAssertFalse(ProperNounGuard.isAtSentenceStart(context: "salut, Mathilde", word: "Mathilde"))
    }

    func testContextMismatchDefaultsToSentenceStart() {
        // Conservative fallback: when the context doesn't end with the word
        // (proxy desync), report sentence start so corrections stay enabled.
        XCTAssertTrue(ProperNounGuard.isAtSentenceStart(context: "je pense que", word: "Mathilde"))
    }
}
