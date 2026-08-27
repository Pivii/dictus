import XCTest
@testable import DictusCore

final class ModelPreparationContextTests: XCTestCase {

    func testOnlyKeyboardColdStartUsesPrepareOnlyFlow() {
        XCTAssertFalse(ModelPreparationContext.onboarding.isPrepareOnly)
        XCTAssertFalse(ModelPreparationContext.modelSelection.isPrepareOnly)
        XCTAssertTrue(ModelPreparationContext.keyboardColdStart.isPrepareOnly)
    }

    // MARK: - Gave up vs finished (#428, third review finding D)

    /// Both outcomes write `.idle`, so a screen that cannot tell them apart congratulates
    /// the user on a model that is not loaded — on the keyboard cold start this issue
    /// exists for. One reason means the app stopped waiting: the launch deadline.
    func testTheDeadlineIsTheWayTheAppStopsWaiting() {
        XCTAssertTrue(ModelPreparationOutcome.reasonMeansGaveUp(
            ModelPreparationOutcome.deadlineExpiredReason))
        XCTAssertEqual(ModelPreparationOutcome.gaveUpReasons.count, 1)
    }

    /// Every reason that means the load actually resolved must NOT be treated as giving
    /// up, or a finished load would stop showing its completion.
    func testAFinishedLoadIsNotGivingUp() {
        let finished = [
            "init-preload-success",
            "init-preload-failed",
            "didBecomeActive-success",
            "didBecomeActive-failed",
            "selectModel-proactive-success",
            "selectModel-proactive-failed",
            "init-preload",
            "stale-loading-cleared-at-launch"
        ]
        for reason in finished {
            XCTAssertFalse(
                ModelPreparationOutcome.reasonMeansGaveUp(reason),
                "\(reason) is a resolved load, not the app giving up on one"
            )
        }
    }

    /// The strings are shared constants precisely so the writer and the reader cannot
    /// drift. If someone retypes one at a call site, this is what notices.
    func testTheReasonsAreTheLiteralsTheCoordinatorWrites() {
        XCTAssertEqual(ModelPreparationOutcome.deadlineExpiredReason, "init-preload-deadline")
    }

}
