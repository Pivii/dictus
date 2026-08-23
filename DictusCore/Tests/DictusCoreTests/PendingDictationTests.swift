// DictusCore/Tests/DictusCoreTests/PendingDictationTests.swift
// Tests for the record that keeps a raw transcription durable while the keyboard
// polishes it, and for the identity rule that decides whether the result may be
// typed (#361 decision 7).

import XCTest
@testable import DictusCore

final class PendingDictationTests: XCTestCase {

    private let fieldA = "1D6E6C1C-0000-0000-0000-000000000001"
    private let fieldB = "1D6E6C1C-0000-0000-0000-000000000002"

    private let policy = TranscriptionLanguagePolicy(
        mode: .explicit(.german),
        keyboardLanguage: .french,
        engine: .parakeet,
        modelIdentifier: "parakeet-tdt-0.6b-v3"
    )

    private func pending(
        documentIdentifier: String?,
        claimedAt: TimeInterval = 1_000
    ) -> PendingDictation {
        PendingDictation(
            raw: "bonjour tout le monde",
            policy: policy,
            recordingDuration: 4.2,
            documentIdentifier: documentIdentifier,
            claimedAt: claimedAt
        )
    }

    // MARK: - May this generation be typed

    func testSameDocumentMayBeInsertedInto() {
        XCTAssertTrue(pending(documentIdentifier: fieldA).mayInsert(into: fieldA, keyboardIsAttached: true))
    }

    func testDifferentDocumentIsRefused() {
        XCTAssertFalse(pending(documentIdentifier: fieldA).mayInsert(into: fieldB, keyboardIsAttached: true))
    }

    /// The suspended-generation case from #357 Q4: the keyboard came back somewhere
    /// else, and the host will not name the field it is now editing.
    func testUnknownCurrentDocumentIsRefused() {
        XCTAssertFalse(pending(documentIdentifier: fieldA).mayInsert(into: nil, keyboardIsAttached: true))
    }

    /// And the mirror image: the host would not name the field when the dictation was
    /// claimed, so there is nothing to compare against later.
    func testUnknownClaimedDocumentIsRefused() {
        XCTAssertFalse(pending(documentIdentifier: nil).mayInsert(into: fieldA, keyboardIsAttached: true))
    }

    /// Two unknowns are not a match. "We could not tell" must never read as "yes" on
    /// the path that types into somebody's message.
    func testTwoUnknownsAreNotAMatch() {
        XCTAssertFalse(pending(documentIdentifier: nil).mayInsert(into: nil, keyboardIsAttached: true))
    }

    // MARK: - Off screen, which identity alone could not see

    /// The `fe8223c` loss: `viewDidDisappear` at :39, `deinit` at :43, and an
    /// insertion at :41 into a keyboard that had already gone. The proxy went on
    /// answering with the same identifier throughout, so identity said yes.
    func testAKeyboardThatIsNoLongerOnScreenMayNotInsert() {
        XCTAssertFalse(
            pending(documentIdentifier: fieldA).mayInsert(into: fieldA, keyboardIsAttached: false)
        )
    }

    /// Attachment does not weaken the identity rule; it is an extra condition on top.
    func testAttachmentDoesNotExcuseTheWrongDocument() {
        XCTAssertFalse(
            pending(documentIdentifier: fieldA).mayInsert(into: fieldB, keyboardIsAttached: true)
        )
    }

    func testRecoveryAlsoRequiresAnAttachedKeyboard() {
        let record = pending(documentIdentifier: fieldA, claimedAt: 1_000)
        XCTAssertFalse(record.mayRecover(into: fieldA, keyboardIsAttached: false, now: 1_001))
    }

    /// The stage rule keeps asking about identity alone, deliberately: it is decided
    /// from `viewWillAppear`, before the view is reliably in a window, and folding
    /// attachment in there would drop the overlay on every controller rebuild.
    func testIdentityIsAvailableWithoutTheAttachmentQuestion() {
        XCTAssertTrue(pending(documentIdentifier: fieldA).addressesSameDocument(as: fieldA))
        XCTAssertFalse(pending(documentIdentifier: fieldA).addressesSameDocument(as: fieldB))
    }

    // MARK: - May a stranded raw still be recovered

    func testRecoveryInsideTheWindowIsAllowed() {
        let record = pending(documentIdentifier: fieldA, claimedAt: 1_000)
        XCTAssertTrue(record.mayRecover(into: fieldA, keyboardIsAttached: true, now: 1_000 + 29))
    }

    func testRecoveryAtTheWindowBoundaryIsAllowed() {
        let record = pending(documentIdentifier: fieldA, claimedAt: 1_000)
        XCTAssertTrue(record.mayRecover(into: fieldA, keyboardIsAttached: true, now: 1_000 + PendingDictation.recoveryWindow))
    }

    func testRecoveryPastTheWindowIsRefused() {
        let record = pending(documentIdentifier: fieldA, claimedAt: 1_000)
        XCTAssertFalse(record.mayRecover(into: fieldA, keyboardIsAttached: true, now: 1_000 + 31))
    }

    /// The window does not soften the identity rule — it is an extra condition on top
    /// of it, not an alternative to it.
    func testRecoveryIntoAnotherFieldIsRefusedEvenImmediately() {
        let record = pending(documentIdentifier: fieldA, claimedAt: 1_000)
        XCTAssertFalse(record.mayRecover(into: fieldB, keyboardIsAttached: true, now: 1_001))
    }

    func testExpiryFollowsTheSameWindow() {
        let record = pending(documentIdentifier: fieldA, claimedAt: 1_000)
        XCTAssertFalse(record.isExpired(now: 1_000 + PendingDictation.recoveryWindow))
        XCTAssertTrue(record.isExpired(now: 1_000 + PendingDictation.recoveryWindow + 1))
    }

    // MARK: - Crossing the App Group

    func testRecordSurvivesEncodingIntact() throws {
        let original = pending(documentIdentifier: fieldA, claimedAt: 1_724_400_000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingDictation.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// The policy is the part that must not be re-derived on the far side: the
    /// keyboard toolbar is where a mid-transcription language change comes from, and
    /// re-reading the live setting there is the #226 bug returning.
    func testPolicySurvivesTheCrossingWithItsExplicitMode() throws {
        let data = try JSONEncoder().encode(pending(documentIdentifier: fieldA))
        let decoded = try JSONDecoder().decode(PendingDictation.self, from: data)
        XCTAssertEqual(decoded.policy.mode, .explicit(.german))
        XCTAssertEqual(decoded.policy.keyboardLanguage, .french)
        XCTAssertEqual(decoded.policy.engine, .parakeet)
        XCTAssertEqual(decoded.policy.modelIdentifier, "parakeet-tdt-0.6b-v3")
    }

    func testRecordWithNoDocumentIdentifierRoundTrips() throws {
        let data = try JSONEncoder().encode(pending(documentIdentifier: nil))
        let decoded = try JSONDecoder().decode(PendingDictation.self, from: data)
        XCTAssertNil(decoded.documentIdentifier)
    }
}
