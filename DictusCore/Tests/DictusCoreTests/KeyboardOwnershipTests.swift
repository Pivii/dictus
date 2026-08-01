// DictusCore/Tests/DictusCoreTests/KeyboardOwnershipTests.swift
// Contract tests for keyboard-area ownership (#260).
import XCTest
@testable import DictusCore

final class KeyboardOwnershipTests: XCTestCase {

    private let outgoing = "1D69EDFD"
    private let incoming = "85DE4A71"

    // MARK: - What each state reads as

    func testOnlyAnOwnedAreaHasAnOwnerAndIsVisible() {
        XCTAssertNil(KeyboardOwnership.none.controllerID)
        XCTAssertFalse(KeyboardOwnership.none.isVisible)

        XCTAssertEqual(KeyboardOwnership.owned(controllerID: outgoing).controllerID, outgoing)
        XCTAssertTrue(KeyboardOwnership.owned(controllerID: outgoing).isVisible)
    }

    /// The reclaim marker must be invisible to every consumer: a controller
    /// comparing its own id against ownership must never match a deallocated
    /// instance, and `isKeyboardVisible` must not report a keyboard nobody owns.
    func testAReclaimableAreaReadsAsOwnerlessAndNotVisible() {
        let orphaned = KeyboardOwnership.awaitingReclaim(previousControllerID: outgoing)
        XCTAssertNil(orphaned.controllerID)
        XCTAssertFalse(orphaned.isVisible)
        XCTAssertTrue(orphaned.isReclaimable)
    }

    func testOnlyTheReclaimStateIsReclaimable() {
        XCTAssertFalse(KeyboardOwnership.none.isReclaimable)
        XCTAssertFalse(KeyboardOwnership.owned(controllerID: outgoing).isReclaimable)
    }

    // MARK: - Handoff

    /// The successor registering is the ordinary path, and it wins from any state:
    /// the controller iOS just brought on screen is the keyboard.
    func testAppearingTakesOwnershipFromEveryState() {
        let states: [KeyboardOwnership] = [
            .none,
            .owned(controllerID: outgoing),
            .awaitingReclaim(previousControllerID: outgoing)
        ]
        for state in states {
            XCTAssertEqual(
                state.appearing(controllerID: incoming),
                .owned(controllerID: incoming),
                "appearing must take ownership from \(state.logDescription)"
            )
        }
    }

    /// The #260 shape: a controller that is not the owner must not be able to
    /// empty ownership on its way out.
    func testANonOwnerCannotReleaseOwnership() {
        let owned = KeyboardOwnership.owned(controllerID: incoming)
        XCTAssertEqual(owned.disappearing(controllerID: outgoing), owned)
        XCTAssertEqual(
            owned.deallocating(controllerID: outgoing, sessionOwnsKeyboardArea: true),
            owned
        )
        XCTAssertEqual(
            owned.deallocating(controllerID: outgoing, sessionOwnsKeyboardArea: false),
            owned
        )
    }

    func testTheOwnerReleasesOwnershipOnDisappearance() {
        XCTAssertEqual(
            KeyboardOwnership.owned(controllerID: outgoing).disappearing(controllerID: outgoing),
            .none
        )
    }

    /// A clean handoff: the successor registers before iOS deallocates the
    /// previous owner, so the dying controller is no longer the owner and
    /// changes nothing. This is the case that already worked and must keep
    /// working — the successor's ownership survives its predecessor's deinit.
    func testAHandoffCompletedBeforeDeallocationIsUntouchedByIt() {
        let afterHandoff = KeyboardOwnership.owned(controllerID: outgoing)
            .appearing(controllerID: incoming)
        XCTAssertEqual(
            afterHandoff.deallocating(controllerID: outgoing, sessionOwnsKeyboardArea: true),
            .owned(controllerID: incoming)
        )
    }

    // MARK: - Deallocation during a live dictation (#260)

    /// The defect this issue is about: the owner is deallocated mid-recording,
    /// before iOS builds the successor. Ownership must not be released as if the
    /// keyboard had been dismissed.
    func testDeallocatingDuringADictationLeavesTheAreaReclaimable() {
        XCTAssertEqual(
            KeyboardOwnership.owned(controllerID: outgoing)
                .deallocating(controllerID: outgoing, sessionOwnsKeyboardArea: true),
            .awaitingReclaim(previousControllerID: outgoing)
        )
    }

    func testDeallocatingWithNoDictationReleasesOwnership() {
        XCTAssertEqual(
            KeyboardOwnership.owned(controllerID: outgoing)
                .deallocating(controllerID: outgoing, sessionOwnsKeyboardArea: false),
            .none
        )
    }

    func testAnAttachedControllerCanReclaimTheSession() {
        let orphaned = KeyboardOwnership.awaitingReclaim(previousControllerID: outgoing)
        XCTAssertEqual(orphaned.reclaiming(controllerID: incoming), .owned(controllerID: incoming))
    }

    /// Reclaim is single-shot: once a controller has claimed the area, a second
    /// one reacting to the same status change finds nothing to claim and falls
    /// back to the ordinary ownership guard (#128).
    func testOnlyTheFirstClaimantReclaims() {
        let orphaned = KeyboardOwnership.awaitingReclaim(previousControllerID: outgoing)
        guard let claimed = orphaned.reclaiming(controllerID: incoming) else {
            return XCTFail("the first claimant must be able to reclaim")
        }
        XCTAssertNil(claimed.reclaiming(controllerID: "C295CB1A"))
    }

    func testThereIsNothingToReclaimWhenTheKeyboardWasDismissed() {
        XCTAssertNil(KeyboardOwnership.none.reclaiming(controllerID: incoming))
    }

    // MARK: - Genuine dismissal mid-recording

    /// The case the deinit safety net was written for, and the acceptance
    /// criterion that a dismissed keyboard must not leave ownership stuck: the
    /// keyboard is dismissed during a recording, no successor ever registers, and
    /// the session then ends. The marker is dropped with it.
    func testADismissedKeyboardEndsWithOwnershipReleased() {
        let orphaned = KeyboardOwnership.owned(controllerID: outgoing)
            .deallocating(controllerID: outgoing, sessionOwnsKeyboardArea: true)
        XCTAssertEqual(orphaned.resolving(sessionOwnsKeyboardArea: true), orphaned)

        let afterSession = orphaned.resolving(sessionOwnsKeyboardArea: false)
        XCTAssertEqual(afterSession, .none)
        XCTAssertFalse(afterSession.isVisible)
        XCTAssertNil(afterSession.controllerID)
    }

    /// Resolving is about the reclaim marker only — it must never take ownership
    /// away from a live controller just because a dictation ended.
    func testResolvingLeavesALiveOwnerAlone() {
        let owned = KeyboardOwnership.owned(controllerID: incoming)
        XCTAssertEqual(owned.resolving(sessionOwnsKeyboardArea: false), owned)
        XCTAssertEqual(owned.resolving(sessionOwnsKeyboardArea: true), owned)
        XCTAssertEqual(KeyboardOwnership.none.resolving(sessionOwnsKeyboardArea: false), .none)
    }

    func testResolvingIsIdempotent() {
        let states: [KeyboardOwnership] = [
            .none,
            .owned(controllerID: incoming),
            .awaitingReclaim(previousControllerID: outgoing)
        ]
        for state in states {
            for sessionOwnsKeyboardArea in [true, false] {
                let once = state.resolving(sessionOwnsKeyboardArea: sessionOwnsKeyboardArea)
                let twice = once.resolving(sessionOwnsKeyboardArea: sessionOwnsKeyboardArea)
                XCTAssertEqual(once, twice, "\(state.logDescription) owns=\(sessionOwnsKeyboardArea)")
            }
        }
    }

    // MARK: - Logging

    func testLogDescriptionNamesTheStateAndTheController() {
        XCTAssertEqual(KeyboardOwnership.none.logDescription, "none")
        XCTAssertEqual(
            KeyboardOwnership.owned(controllerID: incoming).logDescription,
            "owned(\(incoming))"
        )
        XCTAssertEqual(
            KeyboardOwnership.awaitingReclaim(previousControllerID: outgoing).logDescription,
            "awaitingReclaim(\(outgoing))"
        )
    }
}
