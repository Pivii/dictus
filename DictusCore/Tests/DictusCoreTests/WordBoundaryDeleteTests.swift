// DictusCore/Tests/DictusCoreTests/WordBoundaryDeleteTests.swift
// Tests for the self-limiting replacement delete (issue #530): a delete count
// produced from a proxy read is a ceiling, and the loop stops at a word boundary
// whatever the count says.

import XCTest
@testable import DictusCore

final class WordBoundaryDeleteTests: XCTestCase {

    /// A stand-in for UITextDocumentProxy, modelling the two things that differ
    /// in the failure: the `document` the host really holds, and the `mirror`
    /// that `documentContextBeforeInput` reports.
    ///
    /// The mirror is a LOCAL optimistic buffer: it shrinks by one per
    /// deleteBackward() and is not re-fetched from the host in between. That is
    /// measured, not assumed — across the eight applies of the second #530
    /// capture, "every AUTOCORRECT-APPLY-AFTER-DELETE window slides left by
    /// exactly word.count". The delete loop is synchronous on the main thread,
    /// so no host round-trip can land between two iterations either.
    ///
    /// `mirrorPhantomSuffix` is the desync: characters the mirror claims and the
    /// document does not hold.
    private final class FakeProxy {
        /// The real document text before the cursor.
        private(set) var document: String
        /// What documentContextBeforeInput reports.
        private(set) var mirror: String

        init(document: String, mirrorPhantomSuffix: String = "") {
            self.document = document
            self.mirror = document + mirrorPhantomSuffix
        }

        var contextBeforeInput: String? { mirror.isEmpty ? nil : mirror }

        /// One deleteBackward(): the host loses a real character, and the local
        /// mirror loses one of its own — including a phantom one.
        func deleteBackward() {
            if !document.isEmpty { document.removeLast() }
            if !mirror.isEmpty { mirror.removeLast() }
        }

        func perform(deleteCount: Int) -> WordBoundaryDelete.Outcome {
            WordBoundaryDelete.perform(
                deleteCount: deleteCount,
                contextBeforeInput: { self.contextBeforeInput },
                deleteBackward: { self.deleteBackward() }
            )
        }
    }

    // MARK: - The measured failure

    func testOverCountByOneStopsAtTheSpaceAndYieldsTheCorrectWord() {
        // The capture: the document holds "Une fois ton", the proxy reports
        // "Une fois tonn", so the check hands out deleteCount 4 for a word that
        // has 3 characters. The blind loop removed n, o, t AND the space.
        let proxy = FakeProxy(document: "Une fois ton")
        let outcome = proxy.perform(deleteCount: 4)

        XCTAssertEqual(proxy.document, "Une fois ")
        XCTAssertEqual(outcome, .init(planned: 4, deleted: 3))
        XCTAssertTrue(outcome.wasClamped)

        // And the caller's insert then restores exactly the right text: the
        // over-count case comes out CORRECT, not merely non-destructive.
        XCTAssertEqual(proxy.document + "ton ", "Une fois ton ")
    }

    func testOverCountByFiveStopsAtTheSamePlace() {
        // The clamp is a boundary, not a fudge factor: the size of the desync
        // does not change where the delete stops.
        let proxy = FakeProxy(document: "Une fois ton")
        let outcome = proxy.perform(deleteCount: 8)

        XCTAssertEqual(proxy.document, "Une fois ")
        XCTAssertEqual(outcome, .init(planned: 8, deleted: 3))
    }

    // MARK: - The honest proxy: behaviour is unchanged

    func testExactCountBehavesExactlyAsBefore() {
        let proxy = FakeProxy(document: "je pense quee")
        let outcome = proxy.perform(deleteCount: 4)

        XCTAssertEqual(proxy.document, "je pense ")
        XCTAssertEqual(outcome, .init(planned: 4, deleted: 4))
        XCTAssertFalse(outcome.wasClamped)
    }

    func testUnderCountDeletesExactlyWhatItWasAsked() {
        // The opposite desync: the proxy reports FEWER characters than the
        // document holds. The loop spends its count and a stray character
        // survives — a typo one backspace clears, which is the trade #530 takes.
        let proxy = FakeProxy(document: "je pense quee")
        let outcome = proxy.perform(deleteCount: 3)

        XCTAssertEqual(proxy.document, "je pense q")
        XCTAssertFalse(outcome.wasClamped)
    }

    func testAccentedCharactersAreOneDeleteEach() {
        let proxy = FakeProxy(document: "la théorie")
        let outcome = proxy.perform(deleteCount: 7)

        XCTAssertEqual(proxy.document, "la ")
        XCTAssertEqual(outcome, .init(planned: 7, deleted: 7))
    }

    // MARK: - Termination

    func testWordAtStartOfFieldTerminates() {
        // Nothing precedes the word, so there is no boundary character to stop
        // on. The empty context must end the loop instead of spinning or
        // reaching into a document the replacement never owned.
        let proxy = FakeProxy(document: "ton")
        let outcome = proxy.perform(deleteCount: 4)

        XCTAssertEqual(proxy.document, "")
        XCTAssertEqual(outcome, .init(planned: 4, deleted: 3))
        XCTAssertTrue(outcome.wasClamped)
    }

    func testEmptyDocumentDeletesNothing() {
        let proxy = FakeProxy(document: "")
        let outcome = proxy.perform(deleteCount: 3)

        XCTAssertEqual(proxy.document, "")
        XCTAssertEqual(outcome, .init(planned: 3, deleted: 0))
    }

    func testZeroCountDeletesNothing() {
        let proxy = FakeProxy(document: "je pense quee")
        let outcome = proxy.perform(deleteCount: 0)

        XCTAssertEqual(proxy.document, "je pense quee")
        XCTAssertEqual(outcome, .init(planned: 0, deleted: 0))
        XCTAssertFalse(outcome.wasClamped)
    }

    func testCursorAlreadyOnASpaceDeletesNothing() {
        let proxy = FakeProxy(document: "je pense ")
        let outcome = proxy.perform(deleteCount: 4)

        XCTAssertEqual(proxy.document, "je pense ")
        XCTAssertEqual(outcome, .init(planned: 4, deleted: 0))
    }

    // MARK: - Which characters are boundaries

    func testNewlineIsABoundary() {
        let proxy = FakeProxy(document: "Bonjour,\nquee")
        let outcome = proxy.perform(deleteCount: 6)

        XCTAssertEqual(proxy.document, "Bonjour,\n")
        XCTAssertEqual(outcome, .init(planned: 6, deleted: 4))
    }

    func testApostropheIsNotABoundary() {
        // "l'ami": the apostrophe is a legitimate intra-token boundary that
        // AutocorrectReplacement.check already allows, so replacing "ami" must
        // still work. Clamping on punctuation would break it.
        let proxy = FakeProxy(document: "l'ami")
        let outcome = proxy.perform(deleteCount: 3)

        XCTAssertEqual(proxy.document, "l'")
        XCTAssertFalse(outcome.wasClamped)
    }

    func testHyphenIsNotABoundary() {
        let proxy = FakeProxy(document: "peut-etre")
        let outcome = proxy.perform(deleteCount: 4)

        XCTAssertEqual(proxy.document, "peut-")
        XCTAssertFalse(outcome.wasClamped)
    }

    func testNonBreakingSpaceIsABoundary() {
        // French typography puts U+00A0 before ":" and "!". It is whitespace,
        // so a replacement must not cross it either.
        let proxy = FakeProxy(document: "bonjour\u{00A0}quee")
        let outcome = proxy.perform(deleteCount: 6)

        XCTAssertEqual(proxy.document, "bonjour\u{00A0}")
        XCTAssertEqual(outcome, .init(planned: 6, deleted: 4))
    }

    // MARK: - Reporting

    func testClampInvokesTheReportCallbackOnce() {
        let proxy = FakeProxy(document: "Une fois ton")
        var reported: [WordBoundaryDelete.Outcome] = []

        WordBoundaryDelete.perform(
            deleteCount: 4,
            contextBeforeInput: { proxy.contextBeforeInput },
            deleteBackward: { proxy.deleteBackward() },
            onClamped: { reported.append($0) }
        )

        XCTAssertEqual(reported, [.init(planned: 4, deleted: 3)])
    }

    func testFullSpendDoesNotInvokeTheReportCallback() {
        let proxy = FakeProxy(document: "je pense quee")
        var reported: [WordBoundaryDelete.Outcome] = []

        WordBoundaryDelete.perform(
            deleteCount: 4,
            contextBeforeInput: { proxy.contextBeforeInput },
            deleteBackward: { proxy.deleteBackward() },
            onClamped: { reported.append($0) }
        )

        XCTAssertTrue(reported.isEmpty)
    }

    // MARK: - The desync end to end

    func testClampDoesNotFireOnTheMeasuredDesyncAndTheTextIsStillDestroyed() {
        // FALSIFICATION of the fix design decided in #530. Reported, not worked
        // around: this test documents what the clamp does NOT do, so the next
        // reader does not have to rediscover it.
        //
        // The capture: the mirror reports "Une fois tonn", the host holds
        // "Une fois ton". AutocorrectReplacement.check reads the mirror and
        // returns .ok(deleteCount: 4) — as it must, the mirror is its only input.
        let proxy = FakeProxy(document: "Une fois ton", mirrorPhantomSuffix: "n")
        XCTAssertEqual(
            AutocorrectReplacement.check(context: proxy.contextBeforeInput, word: "tonn"),
            .ok(deleteCount: 4)
        )

        let outcome = proxy.perform(deleteCount: 4)

        // The loop re-reads the tail four times and sees "n", "n", "o", "t" —
        // never a boundary, because the mirror is offset by exactly the phantom.
        // So the clamp never fires and the host still loses its space.
        XCTAssertFalse(outcome.wasClamped)
        XCTAssertEqual(outcome, .init(planned: 4, deleted: 4))
        XCTAssertEqual(proxy.document, "Une fois")
        XCTAssertEqual(proxy.document + "ton ", "Une foiston ")   // the reported damage

        // Why it can never fire downstream of the check: the check has already
        // confirmed the mirror's last `deleteCount` characters ARE the word, and
        // a word carries no whitespace. The mirror cannot change under the loop
        // except by the loop's own deletes. The two conditions are exclusive.
        XCTAssertEqual(proxy.mirror, "Une fois ")                 // still lying, by one
    }
}
