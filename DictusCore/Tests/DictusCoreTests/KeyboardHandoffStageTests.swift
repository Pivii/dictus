// DictusCore/Tests/DictusCoreTests/KeyboardHandoffStageTests.swift
// Tests for the frame the keyboard must not draw between transcribing and
// processing (#361, device finding on eae6c68).

import XCTest
@testable import DictusCore

final class KeyboardHandoffStageTests: XCTestCase {

    // MARK: - The frame that was flashing

    /// The exact transition the device capture caught: the app writes `.ready` on
    /// hand-off, the keyboard is drawing `.transcribing`, and adopting it collapsed
    /// the keyboard to typing height and rebuilt the overlay one tick later.
    func testReadyIsNotDrawnOverTranscribingWhileTheHandoffIsOutstanding() {
        XCTAssertFalse(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .transcribing, handoffOutstanding: true
        ))
    }

    /// Same during the polish itself — every controller appearance refreshes, and iOS
    /// builds around nine per dictation.
    func testReadyIsNotDrawnOverProcessingWhileTheHandoffIsOutstanding() {
        XCTAssertFalse(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .processing, handoffOutstanding: true
        ))
    }

    // MARK: - What must still get through

    func testReadyIsDrawnOnceTheHandoffIsDone() {
        XCTAssertTrue(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .transcribing, handoffOutstanding: false
        ))
    }

    /// A dictation started inside DictusApp writes the same `.ready` and leaves no
    /// hand-off behind, so the keyboard treats it exactly as it did before #361.
    func testReadyIsDrawnFromIdle() {
        XCTAssertTrue(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .idle, handoffOutstanding: true
        ))
    }

    /// A failure has to reach the user whatever else is in flight — holding it is how
    /// an overlay outlives a dictation that is over (#260, #261).
    func testFailedIsAlwaysDrawn() {
        for current in DictationStatus.allCases {
            XCTAssertTrue(
                KeyboardHandoffStage.adopts(
                    stored: .failed, drawing: current, handoffOutstanding: true
                ),
                "drawing \(current.rawValue)"
            )
        }
    }

    /// And so does an `.idle`: a cancel, an interruption or a reconciliation all land
    /// there, and each of them ends the dictation the overlay belongs to.
    func testIdleIsAlwaysDrawn() {
        for current in DictationStatus.allCases {
            XCTAssertTrue(
                KeyboardHandoffStage.adopts(
                    stored: .idle, drawing: current, handoffOutstanding: true
                ),
                "drawing \(current.rawValue)"
            )
        }
    }

    /// Every non-terminal status describes work in progress and is never held.
    func testStagesAreAlwaysDrawn() {
        for stored in [DictationStatus.requested, .recording, .transcribing, .processing] {
            for current in DictationStatus.allCases {
                XCTAssertTrue(
                    KeyboardHandoffStage.adopts(
                        stored: stored, drawing: current, handoffOutstanding: true
                    ),
                    "stored \(stored.rawValue) drawing \(current.rawValue)"
                )
            }
        }
    }

    /// Nothing is ever held when no hand-off is outstanding, whatever the pair.
    func testWithoutAHandoffEveryStatusIsAdopted() {
        for stored in DictationStatus.allCases {
            for current in DictationStatus.allCases {
                XCTAssertTrue(
                    KeyboardHandoffStage.adopts(
                        stored: stored, drawing: current, handoffOutstanding: false
                    ),
                    "stored \(stored.rawValue) drawing \(current.rawValue)"
                )
            }
        }
    }

    // MARK: - #309's floor, which the flash was also costing

    /// The point of suppressing the `.ready` frame is that the keyboard then sees
    /// `transcribing -> processing`, which is the transition `TranscribingStageHold`
    /// holds. This asserts the two rules meet: a fast Parakeet transcription gets its
    /// 500 ms floor back.
    func testHoldingReadyRestoresTheTranscriptionFloor() {
        let start = Date()
        var hold = TranscribingStageHold(displayed: .transcribing, since: start)
        // 200 ms later the app hands over and the keyboard claims: `.ready` is held,
        // so it never reaches the stage hold at all.
        XCTAssertFalse(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .transcribing, handoffOutstanding: true
        ))
        // What reaches it is `.processing`, and the floor arms for the remainder.
        guard case .hold(let pending, let interval) = hold.apply(
            .processing, now: start.addingTimeInterval(0.2)
        ) else {
            return XCTFail("expected the transcription floor to arm")
        }
        XCTAssertEqual(pending, .processing)
        XCTAssertEqual(interval, 0.3, accuracy: 0.001)
    }

    /// The counterpart, which is what the device build actually did: `.ready` reaches
    /// the hold, is terminal, and the floor never arms.
    func testAdoptingReadyLosesTheTranscriptionFloor() {
        let start = Date()
        var hold = TranscribingStageHold(displayed: .transcribing, since: start)
        let outcome = hold.apply(.ready, now: start.addingTimeInterval(0.2))
        XCTAssertEqual(outcome, .draw(.ready), "regression guard: this is the flash")
    }
}
