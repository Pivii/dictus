import XCTest
@testable import DictusCore

/// Coverage for the post-interruption start rule (issue #515).
///
/// The rule is the only part of that fix that can be asserted anywhere: `startEngine` is
/// `@MainActor`, owns a live `AVAudioEngine`, and the situation needs a real phone call to
/// reach. Each test names the device attempt it encodes, so a capture that contradicts one
/// can be matched to the assertion it breaks.
final class AudioStartReadinessPolicyTests: XCTestCase {

    // MARK: - The three failures

    /// 14:46:36 and 14:47:18 (cellular), 14:57:19 (FaceTime Audio). The interruption left
    /// the route empty, the tap's own activation brought it back, and all three captured
    /// zero samples.
    func testAStartOnARouteAnInterruptionEmptiedRebuildsAfterWaiting() {
        XCTAssertEqual(
            AudioStartReadinessPolicy.decide(inputPortCount: 0, routeWentEmptySinceLastStart: true),
            .rebuildOnceInputRouteReturns(waitMilliseconds: 1000)
        )
    }

    /// The same attempt a moment later: the route has come back on its own, so there is
    /// nothing to wait for — but the node this engine holds still predates it.
    func testARouteThatHasAlreadyReturnedIsRebuiltWithoutWaiting() {
        XCTAssertEqual(
            AudioStartReadinessPolicy.decide(inputPortCount: 1, routeWentEmptySinceLastStart: true),
            .rebuildOnceInputRouteReturns(waitMilliseconds: 0)
        )
    }

    // MARK: - The six successes

    /// Every attempt in both captures whose activation did not have to re-establish the
    /// route captured between 24015 and 72045 samples. Nothing about those starts changes.
    func testAnOrdinaryStartIsUntouched() {
        XCTAssertEqual(
            AudioStartReadinessPolicy.decide(inputPortCount: 1, routeWentEmptySinceLastStart: false),
            .startNow
        )
    }

    /// The seventh activation, 14:54:20: the app's own `didBecomeActive` re-warm paid for
    /// the route, and the dictation two minutes later captured 35222 samples. Once a start
    /// has succeeded the flag is down, so that dictation takes the ordinary path — this is
    /// what stops the fix from firing on every start for the rest of the process.
    func testAStartAfterAnotherAttemptPaidForTheRouteIsOrdinary() {
        XCTAssertEqual(
            AudioStartReadinessPolicy.decide(inputPortCount: 2, routeWentEmptySinceLastStart: false),
            .startNow
        )
    }

    // MARK: - The edge the flag cannot describe

    /// An empty route with no interruption behind it is not this bug: it is #123, where the
    /// node latches `sr=0.0 ch=2` and `AudioInputFormatPolicy` already owns the answer.
    /// Waiting here would delay a start that has a different remedy.
    func testAnEmptyRouteWithNoInterruptionBehindItIsLeftToTheFormatGuards() {
        XCTAssertEqual(
            AudioStartReadinessPolicy.decide(inputPortCount: 0, routeWentEmptySinceLastStart: false),
            .startNow
        )
    }

    // MARK: - The bound

    /// The wait is bounded by what was observed, not chosen freely: the route returned
    /// inside the same log second as the activation in all three failures.
    func testTheWaitIsTheObservedUpperBound() {
        XCTAssertEqual(AudioStartReadinessPolicy.inputRouteWaitMilliseconds, 1000)
    }
}
