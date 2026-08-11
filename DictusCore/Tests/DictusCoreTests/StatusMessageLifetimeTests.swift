// DictusCore/Tests/DictusCoreTests/StatusMessageLifetimeTests.swift
// Which pending clear is allowed to take the toolbar message down (#342).

import XCTest
@testable import DictusCore

/// Coverage for the rule that stops one status message's timeout from clearing the
/// message that replaced it.
///
/// The timer itself is unreachable from a test: it lives in `KeyboardState` in the
/// keyboard extension, a target with no test bundle, and reproducing it needs two
/// dictations failing seconds apart in front of a user. What is testable is the rule
/// the timer consults, and the rule is where the bug was -- there was no rule at all,
/// only an unconditional clear.
final class StatusMessageLifetimeTests: XCTestCase {

    // MARK: - The rule

    /// The ordinary case, which has to keep working: nothing happened during the
    /// three seconds, so the message clears itself on time.
    func testAMessageClearsItselfWhenNothingReplacedIt() {
        var lifetime = StatusMessageLifetime()
        let message = lifetime.advance()

        XCTAssertTrue(lifetime.mayClear(message))
    }

    /// The bug. A clear scheduled for the first message must not fire against the
    /// second.
    func testAClearScheduledForAReplacedMessageMayNotFire() {
        var lifetime = StatusMessageLifetime()
        let first = lifetime.advance()

        lifetime.advance()

        XCTAssertFalse(
            lifetime.mayClear(first),
            "the first message's timeout cleared the message that replaced it"
        )
    }

    /// The replacement keeps its own full duration -- which is the point of the fix,
    /// not just that the stale timer goes quiet.
    func testTheReplacingMessageOwnsItsOwnClear() {
        var lifetime = StatusMessageLifetime()
        lifetime.advance()
        let second = lifetime.advance()

        XCTAssertTrue(lifetime.mayClear(second))
    }

    /// A message taken down early -- by a cancel, an insertion or a watchdog reset --
    /// invalidates its own pending timeout too. Otherwise that timeout would survive
    /// to clear whatever came next.
    func testAMessageClearedEarlyInvalidatesItsOwnPendingTimeout() {
        var lifetime = StatusMessageLifetime()
        let message = lifetime.advance()

        // `forceResetToIdle` / `requestCancel` / `insertTranscription` all assign nil.
        lifetime.advance()

        XCTAssertFalse(lifetime.mayClear(message))
    }

    /// Once invalidated, always invalidated. A late timer must not come back to life
    /// because the token happened to move again.
    func testAnInvalidatedClearStaysInvalidatedAcrossFurtherMessages() {
        var lifetime = StatusMessageLifetime()
        let first = lifetime.advance()

        lifetime.advance()
        lifetime.advance()
        lifetime.advance()

        XCTAssertFalse(lifetime.mayClear(first))
    }

    /// A token is never reissued, so no two messages can ever answer to the same
    /// pending clear.
    func testEveryAssignmentGetsATokenOfItsOwn() {
        var lifetime = StatusMessageLifetime()
        let tokens = (0..<10).map { _ in lifetime.advance() }

        XCTAssertEqual(Set(tokens).count, tokens.count, "a token was handed out twice")
    }

    // MARK: - The device sequence

    /// The exact shape of the 2026-08-06 device report: the mic is tapped twice, two
    /// seconds apart, both recordings are too short to transcribe. Before the fix the
    /// second message lived one second and its `dictationMessageCleared` line carried
    /// `displayedCount=0`.
    func testASecondFailureTwoSecondsLaterKeepsItsOwnThreeSeconds() {
        var lifetime = StatusMessageLifetime()

        // t=0: first failure raises a message and schedules its clear for t=3.
        let firstFailure = lifetime.advance()

        // t=2: second failure replaces it and schedules its own clear for t=5.
        let secondFailure = lifetime.advance()

        // t=3: the first clear fires. It must find nothing of its own left to do.
        XCTAssertFalse(lifetime.mayClear(firstFailure), "the second message died at t=3")

        // t=5: the second clear fires, having had its full three seconds on screen.
        XCTAssertTrue(lifetime.mayClear(secondFailure))
    }

    /// The cross-source case named in the issue: the two sites that raise a message
    /// are `refreshFromDefaults` (`appError`) and `reconcileAbandonedDictation`
    /// (`reconciled`). They clear each other as readily as each clears itself, and the
    /// log then names the wrong `reason` on the clear line.
    func testAReconciledMessageIsNotTruncatedByAnEarlierAppError() {
        var lifetime = StatusMessageLifetime()
        let appError = lifetime.advance()
        let reconciled = lifetime.advance()

        XCTAssertFalse(lifetime.mayClear(appError), "appError-timeout cleared the reconciled message")
        XCTAssertTrue(lifetime.mayClear(reconciled))
    }

    /// And the other way round, since the ordering is not fixed: a dictation can be
    /// reconciled as abandoned and then fail, as readily as the reverse.
    func testAnAppErrorIsNotTruncatedByAnEarlierReconciledMessage() {
        var lifetime = StatusMessageLifetime()
        let reconciled = lifetime.advance()
        let appError = lifetime.advance()

        XCTAssertFalse(lifetime.mayClear(reconciled), "reconciled-timeout cleared the app error")
        XCTAssertTrue(lifetime.mayClear(appError))
    }

    // MARK: - The duration

    /// One constant, so the two sites cannot drift apart. Its value is #313's
    /// question; that there is exactly one of it is this issue's.
    func testTheDisplayDurationIsLongEnoughToBeRead() {
        XCTAssertEqual(StatusMessageLifetime.displayDuration, 3)
    }
}
