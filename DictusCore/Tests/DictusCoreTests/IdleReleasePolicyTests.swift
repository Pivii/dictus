import XCTest
@testable import DictusCore

/// Coverage for the warm-engine idle-release decision (issue #256).
///
/// These tests exist because `UnifiedAudioEngine` itself cannot be unit-tested:
/// it is `@MainActor`, owns a live `AVAudioEngine` and lives in the DictusApp
/// target. The predicate below is the part of #256 that was actually wrong, so
/// it is the part worth pinning down.
final class IdleReleasePolicyTests: XCTestCase {

    private let tenMinutes: TimeInterval = 10 * 60
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - canRelease

    func testCanReleaseWhenWarmAndNotRecording() {
        XCTAssertTrue(IdleReleasePolicy.canRelease(isWarm: true, isRecording: false))
    }

    func testCannotReleaseWhileRecording() {
        // The regression this whole guard exists for: a release during an active
        // dictation would tear the engine down mid-sentence.
        XCTAssertFalse(IdleReleasePolicy.canRelease(isWarm: true, isRecording: true))
    }

    func testCannotReleaseWhenNotWarm() {
        XCTAssertFalse(IdleReleasePolicy.canRelease(isWarm: false, isRecording: false))
    }

    func testRecordingWinsOverEveryOtherSignal() {
        XCTAssertFalse(IdleReleasePolicy.canRelease(isWarm: false, isRecording: true))
    }

    // MARK: - isIdleWindowElapsed

    func testWindowNotElapsedWithoutAnAnchor() {
        // Nil anchor means "not warm-idle" — nothing was ever armed, or a
        // recording is in progress.
        XCTAssertFalse(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: nil, now: now, interval: tenMinutes
        ))
    }

    func testWindowNotElapsedJustBeforeTheDeadline() {
        XCTAssertFalse(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: now.addingTimeInterval(-(tenMinutes - 1)),
            now: now,
            interval: tenMinutes
        ))
    }

    func testWindowElapsedExactlyAtTheDeadline() {
        XCTAssertTrue(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: now.addingTimeInterval(-tenMinutes),
            now: now,
            interval: tenMinutes
        ))
    }

    func testWindowElapsedLongAfterTheDeadline() {
        // The 8h18m overnight case from the device log.
        XCTAssertTrue(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: now.addingTimeInterval(-(8 * 3600 + 18 * 60)),
            now: now,
            interval: tenMinutes
        ))
    }

    func testBackwardsClockKeepsTheEngineWarm() {
        // A negative elapsed time must not be read as "overdue".
        XCTAssertFalse(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: now.addingTimeInterval(60),
            now: now,
            interval: tenMinutes
        ))
    }

    func testShorterWindowIsHonoured() {
        // The warm-up window is a separate constant that the maintainer may
        // shorten; the policy must measure against whatever it is handed.
        let fiveMinutes: TimeInterval = 5 * 60
        XCTAssertTrue(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: now.addingTimeInterval(-fiveMinutes),
            now: now,
            interval: fiveMinutes
        ))
        XCTAssertFalse(IdleReleasePolicy.isIdleWindowElapsed(
            idleSince: now.addingTimeInterval(-fiveMinutes),
            now: now,
            interval: tenMinutes
        ))
    }

    // MARK: - shouldRelease (composite, used by the wall-clock backstop)

    func testShouldReleaseWhenWarmIdleAndOverdue() {
        XCTAssertTrue(IdleReleasePolicy.shouldRelease(
            isWarm: true,
            isRecording: false,
            idleSince: now.addingTimeInterval(-tenMinutes - 1),
            now: now,
            interval: tenMinutes
        ))
    }

    func testShouldNotReleaseWhileRecordingEvenWhenOverdue() {
        // The exact hole #256 describes: a stale idle anchor plus a foreground
        // transition during a recording.
        XCTAssertFalse(IdleReleasePolicy.shouldRelease(
            isWarm: true,
            isRecording: true,
            idleSince: now.addingTimeInterval(-3600),
            now: now,
            interval: tenMinutes
        ))
    }

    func testShouldNotReleaseWhenNotYetDue() {
        XCTAssertFalse(IdleReleasePolicy.shouldRelease(
            isWarm: true,
            isRecording: false,
            idleSince: now.addingTimeInterval(-60),
            now: now,
            interval: tenMinutes
        ))
    }

    func testShouldNotReleaseWhenAlreadyCold() {
        XCTAssertFalse(IdleReleasePolicy.shouldRelease(
            isWarm: false,
            isRecording: false,
            idleSince: now.addingTimeInterval(-3600),
            now: now,
            interval: tenMinutes
        ))
    }

    func testShouldNotReleaseWithoutAnAnchor() {
        XCTAssertFalse(IdleReleasePolicy.shouldRelease(
            isWarm: true,
            isRecording: false,
            idleSince: nil,
            now: now,
            interval: tenMinutes
        ))
    }
}
