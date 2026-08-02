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

    func testPartiallyDeletedLongInsertionIsRefused() {
        // The user backspaced five characters off the end of a long dictation. The
        // window still shows text that came from the insertion, but it no longer
        // ENDS where the insertion ends, so it is not a suffix of it and the check
        // refuses. This is the case a truncated window is most often accused of
        // getting wrong; it does not reach the accepted-bound branch at all.
        let afterBackspaces = String(longInsertion.dropLast(5))
        XCTAssertEqual(
            DictationUndo.verify(context: String(afterBackspaces.suffix(60)), insertedText: longInsertion),
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

    // MARK: - The chunked deletion the caller performs
    //
    // `KeyboardState.deleteInsertedText` deletes in chunks and re-checks the part
    // still to go between them, stopping only on a refusal that PROVES the field
    // changed. These simulate that loop against both of the window behaviours a
    // host can have.

    /// How a host answers `documentContextBeforeInput` while text is deleted.
    private enum WindowBehaviour {
        /// The window slides back over the document, revealing text that was out of
        /// reach a moment ago. What the first design assumed of every host.
        case sliding(Int)
        /// The window is fetched once and merely trimmed as deletions consume it,
        /// so it runs dry and never refills. Measured in Notes on 2026-08-02: 491
        /// graphemes at the start of a burst, 11 after 480 were removed.
        case trimmedOnce(Int)
    }

    /// Mirrors `KeyboardState.deleteInsertedText`: delete a fixed chunk, then look
    /// at what is left and stop only if the document proves it is no longer ours.
    ///
    /// Returns the document as the loop leaves it and how much of the insertion it
    /// gave up on — zero when the undo completed.
    private func runUndoLoop(
        document startingDocument: String,
        insertion: String,
        behaviour: WindowBehaviour,
        chunkSize: Int = 40
    ) -> (document: String, abandoned: Int) {
        var document = startingDocument
        var deleted = 0
        let firstWindow: Int
        switch behaviour {
        case .sliding(let size), .trimmedOnce(let size):
            firstWindow = min(size, startingDocument.count)
        }

        func context() -> String {
            switch behaviour {
            case .sliding(let size):
                return String(document.suffix(size))
            case .trimmedOnce:
                return String(document.suffix(max(0, firstWindow - deleted)))
            }
        }

        var remaining = insertion.count
        // The check at the tap, which fails closed on anything short of a pass.
        guard case .ok = DictationUndo.verify(context: context(), insertedText: insertion) else {
            return (document, remaining)
        }

        while remaining > 0 {
            let batch = min(remaining, chunkSize)
            document = String(document.dropLast(batch))
            remaining -= batch
            deleted += batch
            guard remaining > 0 else { break }

            if case .failed(let reason) = DictationUndo.verify(
                context: context(),
                insertedText: String(insertion.prefix(remaining))
            ), DictationUndo.provesTheFieldChanged(reason) {
                return (document, remaining)
            }
        }
        return (document, 0)
    }

    func testALongUndoCompletesThroughASlidingWindow() {
        let existing = "A note the user wrote earlier. "
        let result = runUndoLoop(
            document: existing + longInsertion,
            insertion: longInsertion,
            behaviour: .sliding(50)
        )
        XCTAssertEqual(result.abandoned, 0, "the whole insertion should be removable")
        XCTAssertEqual(result.document, existing, "and the undo must land exactly on the earlier text")
    }

    func testALongUndoCompletesThroughAWindowTheHostNeverRefills() {
        // The device case. Requiring a fresh proof before each chunk made this stop
        // one window in, leaving most of the dictation in the field: 4752 graphemes
        // recorded, 480 removed, 4272 left. Absence of proof must not stop the burst.
        let existing = "A note the user wrote earlier. "
        let result = runUndoLoop(
            document: existing + longInsertion,
            insertion: longInsertion,
            behaviour: .trimmedOnce(50)
        )
        XCTAssertEqual(result.abandoned, 0, "a host that stops answering must not strand the undo")
        XCTAssertEqual(result.document, existing)
    }

    func testTheOfferIsRefusedWhenTheHostTruncatedTheInsertion() {
        // The host accepted only the first 50 graphemes of what it was handed, so
        // the recorded count reaches past what is actually in the field. The tail is
        // then the insertion's HEAD, which is not its tail, so the check at the tap
        // refuses and nothing is deleted at all.
        let existing = "A note the user wrote earlier. "
        let result = runUndoLoop(
            document: existing + String(longInsertion.prefix(50)),
            insertion: longInsertion,
            behaviour: .sliding(50)
        )
        XCTAssertEqual(result.abandoned, longInsertion.count, "nothing may be deleted")
        XCTAssertEqual(result.document, existing + String(longInsertion.prefix(50)))
    }

    func testTheBurstStopsWhenTheDocumentIsLegibleAndNoLongerOurs() {
        // A host that rewrites the field mid-burst. The window still answers, and
        // what it answers is not the remainder — that is proof, and proof stops the
        // deletion with the earlier text intact.
        let existing = "A note the user wrote earlier. "
        var document = existing + longInsertion
        var remaining = longInsertion.count
        var stopped = false

        while remaining > 0 {
            let batch = min(remaining, 40)
            document = String(document.dropLast(batch))
            remaining -= batch
            guard remaining > 0 else { break }
            // After the first chunk the host replaces the tail with foreign text.
            document = String(document.dropLast(30)) + "-- pasted by another app --"

            if case .failed(let reason) = DictationUndo.verify(
                context: String(document.suffix(50)),
                insertedText: String(longInsertion.prefix(remaining))
            ), DictationUndo.provesTheFieldChanged(reason) {
                stopped = true
                break
            }
        }

        XCTAssertTrue(stopped, "a legible mismatch must stop the burst")
        XCTAssertTrue(
            document.hasPrefix(existing),
            "text written before the dictation must survive the abandoned undo"
        )
    }

    func testFloorIsHonouredWhenTheCallerSuppliesOne() {
        // The floor is injectable so a caller with a different tolerance can set
        // one; the same window must be refused below it and accepted at it.
        let window = String(longInsertion.suffix(30))
        XCTAssertEqual(
            DictationUndo.verify(context: window, insertedText: longInsertion, minimumTruncatedMatch: 31),
            .failed(reason: "window-too-short")
        )
        XCTAssertEqual(
            DictationUndo.verify(context: window, insertedText: longInsertion, minimumTruncatedMatch: 30),
            .ok(deleteCount: longInsertion.count, verifiedCount: 30, windowTruncated: true)
        )
    }

    func testFloorDoesNotApplyToAFullMatch() {
        // A short insertion fully visible in the window is fully verified — the
        // floor exists only to make a PARTIAL match trustworthy.
        let result = DictationUndo.verify(context: "hi. ", insertedText: "hi. ")
        XCTAssertEqual(result, .ok(deleteCount: 4, verifiedCount: 4, windowTruncated: false))
    }
}
