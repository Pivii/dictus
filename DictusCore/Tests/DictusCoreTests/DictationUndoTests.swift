// DictusCore/Tests/DictusCoreTests/DictationUndoTests.swift
// Tests for the dictation undo safety check (issue #266): the keyboard may only
// delete an insertion it can still prove is sitting at the caret.

import XCTest
@testable import DictusCore

final class DictationUndoTests: XCTestCase {

    /// A run of text comfortably longer than `minimumTruncatedMatch`, used by the
    /// truncated-window cases.
    private let longInsertion = "This is a fairly long dictation result that a bounded document context will not show in full. "

    // MARK: - Full verification

    func testInsertionAtEndOfEmptyFieldIsUndoable() {
        let result = DictationUndo.verify(context: "Bonjour. ", insertedText: "Bonjour. ")
        XCTAssertEqual(result, .ok(deleteCount: 9, verifiedCount: 9, windowTruncated: false))
    }

    func testInsertionAfterExistingTextIsUndoable() {
        let result = DictationUndo.verify(
            context: "Already typed: Bonjour. ",
            insertedText: "Bonjour. "
        )
        XCTAssertEqual(result, .ok(deleteCount: 9, verifiedCount: 9, windowTruncated: false))
    }

    func testSeparatorIsPartOfTheInsertionAndIsCounted() {
        // The pipeline appends ". " before writing to the App Group, so the
        // separator is inside the recorded string and must be deleted with it.
        let result = DictationUndo.verify(context: "je teste. ", insertedText: "je teste. ")
        XCTAssertEqual(result, .ok(deleteCount: 10, verifiedCount: 10, windowTruncated: false))
    }

    func testAutoDetectInsertionWithoutSeparatorIsUndoable() {
        // Whisper auto-detect inserts the transcription as-is (#226), no separator.
        let result = DictationUndo.verify(context: "你好世界", insertedText: "你好世界")
        XCTAssertEqual(result, .ok(deleteCount: 4, verifiedCount: 4, windowTruncated: false))
    }

    func testAccentsCountAsOneDeleteBackwardEach() {
        // "élève. " is 7 graphemes, and deleteBackward() removes one per call.
        let result = DictationUndo.verify(context: "un élève. ", insertedText: "élève. ")
        XCTAssertEqual(result, .ok(deleteCount: 7, verifiedCount: 7, windowTruncated: false))
    }

    func testDecomposedContextMatchesPrecomposedInsertion() {
        // Some hosts report decomposed Unicode (e + combining acute). Canonical
        // equivalence must still match, and the grapheme count is the same.
        let decomposedContext = "un e\u{0301}le\u{0300}ve. "
        let precomposedInsertion = "\u{00E9}l\u{00E8}ve. "
        let result = DictationUndo.verify(context: decomposedContext, insertedText: precomposedInsertion)
        XCTAssertEqual(result, .ok(deleteCount: 7, verifiedCount: 7, windowTruncated: false))
    }

    func testEmojiCountsAsOneGrapheme() {
        // A family emoji is several scalars but one deleteBackward().
        let result = DictationUndo.verify(context: "ok 👨‍👩‍👧‍👦", insertedText: "👨‍👩‍👧‍👦")
        XCTAssertEqual(result, .ok(deleteCount: 1, verifiedCount: 1, windowTruncated: false))
    }

    // MARK: - The user changed the field

    func testTypingAfterTheInsertionBreaksTheCheck() {
        let result = DictationUndo.verify(context: "Bonjour. et", insertedText: "Bonjour. ")
        XCTAssertEqual(result, .failed(reason: "suffix-mismatch"))
    }

    func testDeletingIntoTheInsertionBreaksTheCheck() {
        // The context is now SHORTER than the insertion, so this lands in the
        // truncated branch and is refused there for being too short to trust —
        // the reason differs from a plain mismatch, the refusal does not.
        let result = DictationUndo.verify(context: "Bonjour.", insertedText: "Bonjour. ")
        XCTAssertEqual(result, .failed(reason: "window-too-short"))
    }

    func testMovingTheCaretBeforeTheInsertionBreaksTheCheck() {
        // Caret moved into the middle of the insertion: same shape as above, the
        // text before it is a prefix of what we inserted, never the whole of it.
        let result = DictationUndo.verify(context: "Bonjour", insertedText: "Bonjour. ")
        XCTAssertEqual(result, .failed(reason: "window-too-short"))
    }

    func testHostRewroteTheTextBreaksTheCheck() {
        let result = DictationUndo.verify(
            context: "Something else entirely, rewritten by the host app.",
            insertedText: "Bonjour. "
        )
        XCTAssertEqual(result, .failed(reason: "suffix-mismatch"))
    }

    // MARK: - Nothing to prove with

    func testNilContextFailsClosed() {
        // Secure fields report no context at all.
        XCTAssertEqual(
            DictationUndo.verify(context: nil, insertedText: "Bonjour. "),
            .failed(reason: "no-context")
        )
    }

    func testEmptyContextFailsClosed() {
        XCTAssertEqual(
            DictationUndo.verify(context: "", insertedText: "Bonjour. "),
            .failed(reason: "no-context")
        )
    }

    func testEmptyInsertionFailsClosed() {
        XCTAssertEqual(
            DictationUndo.verify(context: "Bonjour. ", insertedText: ""),
            .failed(reason: "empty-insertion")
        )
    }

    // MARK: - Bounded proxy window

    func testTruncatedWindowMatchingTheTailIsUndoableInFull() {
        let window = String(longInsertion.suffix(60))
        let result = DictationUndo.verify(context: window, insertedText: longInsertion)
        // Verified 60, but the delete count is the whole insertion: undoing half a
        // dictation is not an undo.
        XCTAssertEqual(
            result,
            .ok(deleteCount: longInsertion.count, verifiedCount: 60, windowTruncated: true)
        )
    }

    func testTruncatedWindowIsFlaggedSoPartialIsNeverReadAsFull() {
        let window = String(longInsertion.suffix(40))
        guard case .ok(let deleteCount, let verifiedCount, let windowTruncated) =
                DictationUndo.verify(context: window, insertedText: longInsertion) else {
            return XCTFail("expected the truncated window to verify")
        }
        XCTAssertTrue(windowTruncated)
        XCTAssertLessThan(verifiedCount, deleteCount)
    }

    func testTruncatedWindowWithTypedTextIsRefused() {
        let window = String(longInsertion.suffix(60)) + "and then I typed"
        XCTAssertEqual(
            DictationUndo.verify(context: window, insertedText: longInsertion),
            .failed(reason: "truncated-mismatch")
        )
    }

    func testTruncatedWindowFromAnotherFieldIsRefused() {
        let window = "a completely different field's trailing text"
        XCTAssertEqual(
            DictationUndo.verify(context: window, insertedText: longInsertion),
            .failed(reason: "truncated-mismatch")
        )
    }

    func testShortWindowIsRefusedEvenWhenItMatches() {
        // 12 graphemes of match is too little to distinguish "our insertion" from
        // "a field that happens to end the same way".
        let window = String(longInsertion.suffix(12))
        XCTAssertEqual(
            DictationUndo.verify(context: window, insertedText: longInsertion),
            .failed(reason: "window-too-short")
        )
    }

    func testWindowExactlyAtTheFloorIsAccepted() {
        let window = String(longInsertion.suffix(DictationUndo.minimumTruncatedMatch))
        guard case .ok(let deleteCount, let verifiedCount, let windowTruncated) =
                DictationUndo.verify(context: window, insertedText: longInsertion) else {
            return XCTFail("expected a window at the floor to verify")
        }
        XCTAssertEqual(verifiedCount, DictationUndo.minimumTruncatedMatch)
        XCTAssertEqual(deleteCount, longInsertion.count)
        XCTAssertTrue(windowTruncated)
    }

    func testFloorDoesNotApplyToAFullMatch() {
        // A short insertion fully visible in the window is fully verified — the
        // floor exists only to make a PARTIAL match trustworthy.
        let result = DictationUndo.verify(context: "hi. ", insertedText: "hi. ")
        XCTAssertEqual(result, .ok(deleteCount: 4, verifiedCount: 4, windowTruncated: false))
    }
}
