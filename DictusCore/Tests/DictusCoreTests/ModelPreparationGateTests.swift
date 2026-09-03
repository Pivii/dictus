import XCTest
@testable import DictusCore

/// Issue #458: a model load that started while the user was already dictating raised the
/// preparation screen over the recording screen, mid-sentence. These tests hold the
/// display rule that replaced it.
final class ModelPreparationGateTests: XCTestCase {

    private let model = "openai_whisper-small"
    private let otherModel = "parakeet-tdt-0.6b-v3-coreml"

    // MARK: - The ordinary case, which must keep working

    /// Nothing else on screen: a live preparation is presented, exactly as before.
    func testPresentsWhenDictationIsIdle() {
        var gate = ModelPreparationGate()
        XCTAssertEqual(
            gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: false),
            model
        )
    }

    /// Nothing to present when nothing is preparing.
    func testPresentsNothingWithoutALivePreparation() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: nil, dictationStatus: .idle, isPresenting: false)
        )
    }

    /// The guard the call sites used to carry inline, kept: a screen already up is not
    /// re-raised over itself.
    func testDoesNotRaiseWhatIsAlreadyPresented() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: true)
        )
    }

    // MARK: - The bug

    /// Every status but `.idle` means the dictation screen is on screen, so every one of
    /// them refuses. Driven off `allCases` so a status added later joins the sweep on its
    /// own rather than silently defaulting to "go ahead".
    func testRefusesForEveryNonIdleStatus() {
        for status in DictationStatus.allCases where status != .idle {
            var gate = ModelPreparationGate()
            XCTAssertNil(
                gate.modelToPresent(liveModel: model, dictationStatus: status, isPresenting: false),
                "\(status.rawValue) must not raise a preparation screen"
            )
        }
    }

    /// The predicate on its own, since `MainTabView` uses it directly for its one-shot
    /// URL and notification handlers.
    func testDictationOwnsTheDisplayForEveryStatusButIdle() {
        XCTAssertFalse(ModelPreparationGate.dictationOwnsTheDisplay(.idle))
        for status in DictationStatus.allCases where status != .idle {
            XCTAssertTrue(ModelPreparationGate.dictationOwnsTheDisplay(status))
        }
    }

    // MARK: - No replay

    /// The second half of the rule. The load refused during the recording is still
    /// running when the dictation ends — and it stays off screen, because by then the
    /// user is reading their transcription.
    func testWithheldPreparationIsNotReplayedWhenTheDictationEnds() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .recording, isPresenting: false)
        )
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .transcribing, isPresenting: false)
        )
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: false),
            "the load withheld during the dictation must not pop after it"
        )
    }

    /// …and the suppression is scoped to that one load. Once it ends, the screen is free
    /// again — this is what keeps "tap a model in the Model Manager" working after a
    /// dictation that happened to overlap a load.
    func testANewPreparationAfterTheWithheldOneIsPresented() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .recording, isPresenting: false)
        )
        // The withheld load finishes.
        XCTAssertNil(
            gate.modelToPresent(liveModel: nil, dictationStatus: .idle, isPresenting: false)
        )
        // The user then asks for one themselves.
        XCTAssertEqual(
            gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: false),
            model
        )
    }

    /// Suppression follows the identifier, not the fact that something was once refused:
    /// a *different* model preparing after the dictation is a different event.
    func testADifferentModelIsPresentedAfterAWithheldOne() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .recording, isPresenting: false)
        )
        XCTAssertEqual(
            gate.modelToPresent(liveModel: otherModel, dictationStatus: .idle, isPresenting: false),
            otherModel
        )
    }

    // MARK: - Two preparations at once

    /// The review finding on PR #477, and the reason the gate remembers a set rather than
    /// the last refusal. `liveActivePrepModel` names one model but can alternate between
    /// two in flight — a download of B while A prewarms. Refusing A and then B must not
    /// forget A: A is still the load that started under the dictation.
    func testAWithheldModelIsNotForgottenByASecondRefusal() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .recording, isPresenting: false)
        )
        XCTAssertNil(
            gate.modelToPresent(liveModel: otherModel, dictationStatus: .recording, isPresenting: false)
        )
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: false),
            "the first refusal must survive the second one"
        )
        XCTAssertNil(
            gate.modelToPresent(liveModel: otherModel, dictationStatus: .idle, isPresenting: false),
            "and so must the second"
        )
    }

    /// Both refusals are dropped together, and only when nothing is preparing any more.
    /// Forgetting per model would clear a refusal whose load is still running, because
    /// the live one alternates while two are in flight.
    func testBothRefusalsAreClearedOnlyWhenNothingIsPreparing() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .recording, isPresenting: false)
        )
        XCTAssertNil(
            gate.modelToPresent(liveModel: otherModel, dictationStatus: .recording, isPresenting: false)
        )
        // Both preparations end.
        XCTAssertNil(
            gate.modelToPresent(liveModel: nil, dictationStatus: .idle, isPresenting: false)
        )
        // Either one asked for afresh is a new event.
        XCTAssertEqual(
            gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: false),
            model
        )
    }

    /// The `.onAppear` case the latch exists for: the user switches to the Models tab
    /// after the dictation, which re-asks the question about the same still-running load.
    func testTabSwitchAfterTheDictationDoesNotRaiseTheWithheldLoad() {
        var gate = ModelPreparationGate()
        XCTAssertNil(
            gate.modelToPresent(liveModel: model, dictationStatus: .recording, isPresenting: false)
        )
        for _ in 0..<3 {
            XCTAssertNil(
                gate.modelToPresent(liveModel: model, dictationStatus: .idle, isPresenting: false)
            )
        }
    }
}
