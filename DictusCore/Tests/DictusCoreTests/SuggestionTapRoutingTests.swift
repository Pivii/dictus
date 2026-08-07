// DictusCore/Tests/DictusCoreTests/SuggestionTapRoutingTests.swift
// Tests for the suggestion-tap routing table (issue #335): a tap must replace
// the word in progress when the cursor is mid-word, and insert only when the
// document really ends on a boundary — mode and `currentWord` alone lie.

import XCTest
@testable import DictusCore

final class SuggestionTapRoutingTests: XCTestCase {

    // MARK: - Mid-word: the tap replaces

    func testMidWordWithMatchingCurrentWordReplaces() {
        // The reported repro: bar in .undoAvailable, "concerne" typed after an
        // autocorrect, tapping "concerné" used to append instead of replacing.
        let decision = SuggestionTapRouting.decide(
            context: "Mais j'avais des clients concerne",
            currentWord: "concerne"
        )
        XCTAssertEqual(decision, .replace(deleteCount: 8))
    }

    func testMidWordAtStartOfFieldReplaces() {
        let decision = SuggestionTapRouting.decide(context: "concerne", currentWord: "concerne")
        XCTAssertEqual(decision, .replace(deleteCount: 8))
    }

    func testAccentedCurrentWordReplacesWithGraphemeCount() {
        // é is ONE grapheme, so ONE deleteBackward call.
        let decision = SuggestionTapRouting.decide(context: "la théori", currentWord: "théori")
        XCTAssertEqual(decision, .replace(deleteCount: 6))
    }

    func testDecomposedContextMatchesPrecomposedCurrentWord() {
        // Some hosts report decomposed Unicode (e + combining acute). Canonical
        // equivalence must still match, with the same grapheme count.
        let decomposedContext = "la the\u{0301}ori"      // "théori" decomposed
        let precomposedWord = "th\u{00E9}ori"            // "théori" precomposed
        let decision = SuggestionTapRouting.decide(
            context: decomposedContext,
            currentWord: precomposedWord
        )
        XCTAssertEqual(decision, .replace(deleteCount: 6))
    }

    // MARK: - Mid-word with a stale word: the tap does nothing

    func testMidWordWithStaleCurrentWordAborts() {
        // The user typed one more letter between the bar's async computation
        // and the tap. Deleting a blind count would eat into the previous word.
        let decision = SuggestionTapRouting.decide(
            context: "des clients concernee",
            currentWord: "concerne"
        )
        XCTAssertEqual(decision, .abort(reason: "suffix-mismatch"))
    }

    func testMidWordWithEmptyCurrentWordAborts() {
        let decision = SuggestionTapRouting.decide(context: "des clients", currentWord: "")
        XCTAssertEqual(decision, .abort(reason: "empty-word"))
    }

    func testMidWordGluedToPreviousWordAborts() {
        let decision = SuggestionTapRouting.decide(context: "je penseque", currentWord: "que")
        XCTAssertEqual(decision, .abort(reason: "no-boundary-before"))
    }

    // MARK: - Boundary: the tap inserts, whatever `currentWord` holds

    func testContextEndingInSpaceInsertsDespiteStaleCurrentWord() {
        // updateAsync early-returns on a whitespace-terminated context WITHOUT
        // clearing currentWord in .predictions/.undoAvailable mode: type a word
        // after an autocorrect then backspace it away, and currentWord survives.
        // Inserting is right here — aborting would swallow the tap.
        let decision = SuggestionTapRouting.decide(
            context: "des clients ",
            currentWord: "concerne"
        )
        XCTAssertEqual(decision, .insert)
    }

    func testContextEndingInNewlineInserts() {
        let decision = SuggestionTapRouting.decide(
            context: "Bonjour,\n",
            currentWord: "concerne"
        )
        XCTAssertEqual(decision, .insert)
    }

    func testEmptyContextInserts() {
        let decision = SuggestionTapRouting.decide(context: "", currentWord: "concerne")
        XCTAssertEqual(decision, .insert)
    }

    func testNilContextInserts() {
        let decision = SuggestionTapRouting.decide(context: nil, currentWord: "concerne")
        XCTAssertEqual(decision, .insert)
    }
}
