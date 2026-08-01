// DictusCore/Tests/DictusCoreTests/KeyboardOwnershipTests.swift
// Contract tests for keyboard-area ownership (#260).
import XCTest
@testable import DictusCore

/// Replays a keyboard-extension timeline against the ownership rules.
///
/// WHY a harness and not calls with hand-picked arguments: the first version of
/// this fix passed a `sessionOwnsKeyboardArea: true` premise into every test and
/// they all went green while the bug survived — the captured failure has the owner
/// deallocating while the status is still `.idle`, a second before the mic is
/// tapped. Driving the events in order, with the status carried along rather than
/// asserted into place, is what makes that case impossible to assume away.
///
/// `presents(_:)` mirrors what the two layers actually do with ownership:
/// `KeyboardRootView.presentedMode` and `KeyboardViewController.applyAreaMode`
/// both require the caller to be the owner before the recording overlay appears.
private struct KeyboardTimeline {
    private(set) var ownership: KeyboardOwnership = .none
    private(set) var status: DictationStatus = .idle

    mutating func appears(_ controllerID: String) {
        ownership = ownership.appearing(controllerID: controllerID)
    }

    mutating func disappears(_ controllerID: String) {
        ownership = ownership.disappearing(controllerID: controllerID)
    }

    mutating func deallocates(_ controllerID: String) {
        ownership = ownership.deallocating(controllerID: controllerID)
    }

    mutating func statusBecomes(_ status: DictationStatus) {
        self.status = status
    }

    /// The claim an on-screen controller makes when it sees a `.recording` mode it
    /// is not the owner of. Returns whether it now owns the area.
    @discardableResult
    mutating func claims(_ controllerID: String, isOnScreen: Bool) -> Bool {
        guard let next = ownership.claiming(controllerID: controllerID, isOnScreen: isOnScreen) else {
            return false
        }
        ownership = next
        return true
    }

    /// Whether `controllerID` may present the recording overlay right now.
    func presents(_ controllerID: String) -> Bool {
        status.ownsKeyboardArea
            && ownership.controllerID == controllerID
            && ownership.isVisible
    }
}

final class KeyboardOwnershipTests: XCTestCase {

    private let onScreen = "A49EED3D"
    private let doomed = "6C4DA89F"
    private let successor = "E9DE444D"

    // MARK: - What each state reads as

    func testOnlyAnOwnedAreaHasAnOwnerAndIsVisible() {
        XCTAssertNil(KeyboardOwnership.none.controllerID)
        XCTAssertFalse(KeyboardOwnership.none.isVisible)

        XCTAssertEqual(KeyboardOwnership.owned(controllerID: onScreen).controllerID, onScreen)
        XCTAssertTrue(KeyboardOwnership.owned(controllerID: onScreen).isVisible)
    }

    /// The reclaim marker must be invisible to every consumer: a controller
    /// comparing its own id against ownership must never match a deallocated
    /// instance, and `isKeyboardVisible` must not report a keyboard nobody owns.
    /// This is also why a marker that is never claimed is harmless — it reads
    /// exactly like the released state it replaced.
    func testAReclaimableAreaReadsAsOwnerlessAndNotVisible() {
        let orphaned = KeyboardOwnership.awaitingReclaim(previousControllerID: doomed)
        XCTAssertNil(orphaned.controllerID)
        XCTAssertFalse(orphaned.isVisible)
        XCTAssertTrue(orphaned.isReclaimable)
    }

    func testOnlyTheReclaimStateIsReclaimable() {
        XCTAssertFalse(KeyboardOwnership.none.isReclaimable)
        XCTAssertFalse(KeyboardOwnership.owned(controllerID: onScreen).isReclaimable)
    }

    // MARK: - The captured failure (#260, 14:14)

    /// The timeline of the capture in the issue body, in its own order:
    ///
    ///   14:14:3x  the keyboard is on screen, churn hands ownership to a doomed
    ///             instance, the status is idle
    ///   14:14:36  that instance deinits — ownership is emptied
    ///   14:14:37  the user taps the mic; the status becomes .requested
    ///
    /// The controller on screen never re-registers, because its viewWillAppear ran
    /// long before. Under the released-outright rule it could never present the
    /// overlay again, which is the reported bug: `activeID=none`, every status
    /// change skipped, the keyboard stuck in its typing layout.
    func testTheOnScreenControllerRecoversWhenItsOwnershipDiesBeforeTheDictation() {
        var timeline = KeyboardTimeline()
        timeline.appears(onScreen)
        timeline.appears(doomed)
        timeline.deallocates(doomed)

        XCTAssertFalse(timeline.presents(onScreen), "no dictation has started yet")

        timeline.statusBecomes(.requested)
        XCTAssertFalse(
            timeline.presents(onScreen),
            "the on-screen controller does not own the area — this is the bug"
        )

        XCTAssertTrue(timeline.claims(onScreen, isOnScreen: true))
        XCTAssertTrue(
            timeline.presents(onScreen),
            "the controller on screen must be able to present the dictation it was left out of"
        )
    }

    /// The same recovery when the owner dies *during* the dictation — the variant
    /// the root-cause comment describes. Both must work; conditioning the marker on
    /// the status at deallocation time only covers this one.
    func testTheOnScreenControllerRecoversWhenItsOwnershipDiesDuringTheDictation() {
        var timeline = KeyboardTimeline()
        timeline.appears(onScreen)
        timeline.appears(doomed)
        timeline.statusBecomes(.recording)
        timeline.deallocates(doomed)

        XCTAssertFalse(timeline.presents(onScreen))
        XCTAssertTrue(timeline.claims(onScreen, isOnScreen: true))
        XCTAssertTrue(timeline.presents(onScreen))
    }

    /// Every status a dictation passes through must be recoverable, so that the
    /// claim does not depend on catching one particular transition.
    func testRecoveryDoesNotDependOnWhichStatusTheDictationIsIn() {
        for status in [DictationStatus.idle, .requested, .recording, .transcribing] {
            var timeline = KeyboardTimeline()
            timeline.appears(onScreen)
            timeline.appears(doomed)
            timeline.statusBecomes(status)
            timeline.deallocates(doomed)
            XCTAssertTrue(
                timeline.claims(onScreen, isOnScreen: true),
                "an on-screen controller must be able to claim the area at status=\(status.rawValue)"
            )
        }
    }

    // MARK: - Who may claim

    /// The safety property. A cached instance iOS never told to disappear reaches
    /// the claim on exactly the same path as the live keyboard; only attachment
    /// separates them. If this were permissive, a stale controller would *acquire*
    /// the area — expanding its own hosting view while the on-screen tree still
    /// rendered the keys, the #116 shape — instead of merely being skipped.
    func testAControllerThatIsNotOnScreenCannotClaimTheArea() {
        var timeline = KeyboardTimeline()
        timeline.appears(onScreen)
        timeline.appears(doomed)
        timeline.statusBecomes(.recording)
        timeline.deallocates(doomed)

        XCTAssertFalse(timeline.claims("ZOMBIE01", isOnScreen: false))
        XCTAssertTrue(timeline.ownership.isReclaimable, "a refused claim must leave the area claimable")
        XCTAssertTrue(timeline.claims(onScreen, isOnScreen: true))
    }

    func testThereIsNothingToClaimWhileAControllerOwnsTheArea() {
        var timeline = KeyboardTimeline()
        timeline.appears(doomed)
        timeline.statusBecomes(.recording)

        XCTAssertFalse(
            timeline.claims(onScreen, isOnScreen: true),
            "a live owner's ownership must survive — #142 depends on it"
        )
        XCTAssertTrue(timeline.presents(doomed))
    }

    func testThereIsNothingToClaimAfterAPlainDismissal() {
        var timeline = KeyboardTimeline()
        timeline.appears(onScreen)
        timeline.disappears(onScreen)

        XCTAssertFalse(timeline.claims(onScreen, isOnScreen: true))
    }

    /// Single-shot: once a controller has claimed the area, a second one reacting
    /// to the same status change finds nothing to claim and falls back to the
    /// ordinary ownership guard (#128).
    func testOnlyTheFirstClaimantWins() {
        var timeline = KeyboardTimeline()
        timeline.appears(doomed)
        timeline.statusBecomes(.recording)
        timeline.deallocates(doomed)

        XCTAssertTrue(timeline.claims(onScreen, isOnScreen: true))
        XCTAssertFalse(timeline.claims(successor, isOnScreen: true))
        XCTAssertTrue(timeline.presents(onScreen))
    }

    // MARK: - Handoff

    /// The successor registering is the ordinary path, and it wins from any state:
    /// the controller iOS just brought on screen is the keyboard.
    func testAppearingTakesOwnershipFromEveryState() {
        let states: [KeyboardOwnership] = [
            .none,
            .owned(controllerID: doomed),
            .awaitingReclaim(previousControllerID: doomed)
        ]
        for state in states {
            XCTAssertEqual(
                state.appearing(controllerID: successor),
                .owned(controllerID: successor),
                "appearing must take ownership from \(state.logDescription)"
            )
        }
    }

    /// The #260 shape at its narrowest: a controller that is not the owner must not
    /// be able to empty ownership on its way out.
    func testANonOwnerCannotReleaseOwnership() {
        let owned = KeyboardOwnership.owned(controllerID: successor)
        XCTAssertEqual(owned.disappearing(controllerID: doomed), owned)
        XCTAssertEqual(owned.deallocating(controllerID: doomed), owned)
    }

    func testTheOwnerReleasesOwnershipOnDisappearance() {
        XCTAssertEqual(
            KeyboardOwnership.owned(controllerID: doomed).disappearing(controllerID: doomed),
            .none
        )
    }

    /// A clean handoff: the successor registers before iOS deallocates the previous
    /// owner, so the dying controller is no longer the owner and changes nothing.
    /// This is the case that already worked and must keep working.
    func testAHandoffCompletedBeforeDeallocationIsUntouchedByIt() {
        var timeline = KeyboardTimeline()
        timeline.appears(doomed)
        timeline.statusBecomes(.recording)
        timeline.appears(successor)
        timeline.deallocates(doomed)

        XCTAssertEqual(timeline.ownership, .owned(controllerID: successor))
        XCTAssertTrue(timeline.presents(successor))
    }

    /// A keyboard dismissed mid-recording, where no successor ever registers: the
    /// acceptance criterion is that ownership does not stay stuck. It cannot — the
    /// marker reports no owner and no visibility, exactly like the release it
    /// replaced — and a fresh keyboard later takes the area normally.
    func testADismissedKeyboardLeavesNothingStuck() {
        var timeline = KeyboardTimeline()
        timeline.appears(doomed)
        timeline.statusBecomes(.recording)
        timeline.deallocates(doomed)
        timeline.statusBecomes(.idle)

        XCTAssertNil(timeline.ownership.controllerID)
        XCTAssertFalse(timeline.ownership.isVisible)
        XCTAssertFalse(timeline.claims("OFFSCREEN", isOnScreen: false))

        timeline.appears(successor)
        timeline.statusBecomes(.recording)
        XCTAssertTrue(timeline.presents(successor))
    }

    // MARK: - Logging

    func testLogDescriptionNamesTheStateAndTheController() {
        XCTAssertEqual(KeyboardOwnership.none.logDescription, "none")
        XCTAssertEqual(
            KeyboardOwnership.owned(controllerID: successor).logDescription,
            "owned(\(successor))"
        )
        XCTAssertEqual(
            KeyboardOwnership.awaitingReclaim(previousControllerID: doomed).logDescription,
            "awaitingReclaim(\(doomed))"
        )
    }
}
