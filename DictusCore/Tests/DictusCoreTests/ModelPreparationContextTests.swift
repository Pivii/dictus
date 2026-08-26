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
