import XCTest
@testable import DictusCore

final class ModelPreparationContextTests: XCTestCase {

    func testOnlyKeyboardColdStartUsesPrepareOnlyFlow() {
        XCTAssertFalse(ModelPreparationContext.onboarding.isPrepareOnly)
        XCTAssertFalse(ModelPreparationContext.modelSelection.isPrepareOnly)
        XCTAssertTrue(ModelPreparationContext.keyboardColdStart.isPrepareOnly)
    }

    // MARK: - Escape hatch (#428)

    /// The two flows that can hide the whole app behind a compile that may never finish
    /// must both be escapable. Both are reachable with a model already on disk: the
    /// keyboard cold start replaces the tab bar outright, and model selection covers the
    /// Models tab. Neither had any way out before #428.
    func testTheFlowsThatCanLockTheAppOfferAnEscape() {
        XCTAssertTrue(ModelPreparationContext.keyboardColdStart.allowsEscape)
        XCTAssertTrue(ModelPreparationContext.modelSelection.allowsEscape)
    }

    /// Onboarding is the exception, and not out of politeness: there is no second model
    /// on disk to switch to and no tab bar behind the screen, so an escape would dismiss
    /// the flow into nothing.
    func testOnboardingOffersNoEscape() {
        XCTAssertFalse(ModelPreparationContext.onboarding.allowsEscape)
    }

    // MARK: - Gave up vs finished (#428, third review finding D)

    /// Both outcomes write `.idle`, so a screen that cannot tell them apart congratulates
    /// the user on a model that is not loaded — on the keyboard cold start this issue
    /// exists for. These are the two reasons that mean the app stopped waiting.
    func testTheGaveUpReasonsAreTheTwoWaysTheAppStopsWaiting() {
        XCTAssertTrue(ModelPreparationEscape.reasonMeansGaveUp(
            ModelPreparationEscape.deadlineExpiredReason))
        XCTAssertTrue(ModelPreparationEscape.reasonMeansGaveUp(
            ModelPreparationEscape.userLeftScreenReason))
        XCTAssertEqual(ModelPreparationEscape.gaveUpReasons.count, 2)
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
                ModelPreparationEscape.reasonMeansGaveUp(reason),
                "\(reason) is a resolved load, not the app giving up on one"
            )
        }
    }

    /// The strings are shared constants precisely so the writer and the reader cannot
    /// drift. If someone retypes one at a call site, this is what notices.
    func testTheReasonsAreTheLiteralsTheCoordinatorWrites() {
        XCTAssertEqual(ModelPreparationEscape.deadlineExpiredReason, "init-preload-deadline")
        XCTAssertEqual(ModelPreparationEscape.userLeftScreenReason, "user-left-preparation-screen")
    }

    /// A context added later has to make this choice deliberately rather than inherit
    /// whichever answer the `!=` happens to give it.
    func testEveryContextAnswersTheEscapeQuestion() {
        for context in ModelPreparationContext.allCases {
            switch context {
            case .onboarding:
                XCTAssertFalse(context.allowsEscape)
            case .modelSelection, .keyboardColdStart:
                XCTAssertTrue(context.allowsEscape)
            }
        }
    }
}
