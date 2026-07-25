// DictusCore/Tests/DictusCoreTests/AutocorrectReplacementTests.swift
// Tests for the boundary-safe replacement check (issue #191): autocorrect must
// never delete the space (or other boundary) before the word it replaces.

import XCTest
@testable import DictusCore

final class AutocorrectReplacementTests: XCTestCase {

    // MARK: - Happy path: live context matches the word

    func testWordAfterSpaceIsSafe() {
        // Repro A from the issue: "pense quee" + space, correcting "quee".
        let result = AutocorrectReplacement.check(context: "je pense quee", word: "quee")
        XCTAssertEqual(result, .ok(deleteCount: 4))
    }

    func testWordAtStartOfFieldIsSafe() {
        let result = AutocorrectReplacement.check(context: "quee", word: "quee")
        XCTAssertEqual(result, .ok(deleteCount: 4))
    }

    func testAccentedWordIsSafeWithGraphemeCount() {
        // Repro B: "la théori" — é must count as ONE deleteBackward call.
        let result = AutocorrectReplacement.check(context: "la théori", word: "théori")
        XCTAssertEqual(result, .ok(deleteCount: 6))
    }

    func testDecomposedAccentMatchesPrecomposedWord() {
        // Some hosts report decomposed Unicode (e + combining acute).
        // Swift's canonical equivalence must still match, and the grapheme
        // count (5) is identical in both normalization forms.
        let decomposedContext = "la the\u{0301}ori"      // "théori" decomposed, 9 graphemes
        let precomposedWord = "th\u{00E9}ori"            // "théori" precomposed
        let result = AutocorrectReplacement.check(context: decomposedContext, word: precomposedWord)
        XCTAssertEqual(result, .ok(deleteCount: 6))
    }

    func testWordAfterApostropheIsSafe() {
        // "l'ami": word extraction yields "ami", preceded by an apostrophe —
        // a legitimate intra-token boundary, replacement stays within "ami".
        let result = AutocorrectReplacement.check(context: "l'ami", word: "ami")
        XCTAssertEqual(result, .ok(deleteCount: 3))
    }

    func testWordAfterNewlineIsSafe() {
        let result = AutocorrectReplacement.check(context: "Bonjour,\nquee", word: "quee")
        XCTAssertEqual(result, .ok(deleteCount: 4))
    }

    // MARK: - Desync: context no longer ends with the word

    func testStaleWordLongerThanContextSuffixIsRejected() {
        // Captured "quee" but the document actually ends with "que"
        // (the phantom duplicated letter never landed in the host).
        let result = AutocorrectReplacement.check(context: "je pense que", word: "quee")
        XCTAssertEqual(result, .failed(reason: "suffix-mismatch"))
    }

    func testStaleWordShorterThanContextSuffixIsRejected() {
        // Captured "que" but the user typed one more letter since.
        let result = AutocorrectReplacement.check(context: "je pense quee", word: "que")
        XCTAssertEqual(result, .failed(reason: "suffix-mismatch"))
    }

    func testCompletelyDifferentSuffixIsRejected() {
        let result = AutocorrectReplacement.check(context: "je pense donc", word: "quee")
        XCTAssertEqual(result, .failed(reason: "suffix-mismatch"))
    }

    // MARK: - Boundary violations: word glued to previous token

    func testWordGluedToPreviousWordIsRejected() {
        // The document already lost its space ("penseque"): word extraction
        // may still claim the last word is "que", but deleting 3 chars and
        // reinserting would silently ratify the merge. Reject.
        let result = AutocorrectReplacement.check(context: "je penseque", word: "que")
        XCTAssertEqual(result, .failed(reason: "no-boundary-before"))
    }

    func testWordPrecededByDigitIsRejected() {
        let result = AutocorrectReplacement.check(context: "abc123que", word: "que")
        XCTAssertEqual(result, .failed(reason: "no-boundary-before"))
    }

    // MARK: - Degenerate inputs

    func testEmptyWordIsRejected() {
        let result = AutocorrectReplacement.check(context: "je pense", word: "")
        XCTAssertEqual(result, .failed(reason: "empty-word"))
    }

    func testNilContextIsRejected() {
        let result = AutocorrectReplacement.check(context: nil, word: "que")
        XCTAssertEqual(result, .failed(reason: "no-context"))
    }

    func testEmptyContextIsRejected() {
        let result = AutocorrectReplacement.check(context: "", word: "que")
        XCTAssertEqual(result, .failed(reason: "no-context"))
    }
}
