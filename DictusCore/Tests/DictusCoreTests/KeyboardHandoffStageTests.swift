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
            stored: .ready, drawing: .transcribing, handoff: .here
        ))
    }

    /// Same during the polish itself — every controller appearance refreshes, and iOS
    /// builds around nine per dictation.
    func testReadyIsNotDrawnOverProcessingWhileTheHandoffIsOutstanding() {
        XCTAssertFalse(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .processing, handoff: .here
        ))
    }

    // MARK: - What must still get through

    func testReadyIsDrawnOnceTheHandoffIsDone() {
        XCTAssertTrue(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .transcribing, handoff: .none
        ))
    }

    /// A dictation started inside DictusApp writes the same `.ready` and leaves no
    /// hand-off behind, so the keyboard treats it exactly as it did before #361.
    func testReadyIsDrawnFromIdle() {
        XCTAssertTrue(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .idle, handoff: .here
        ))
    }

    /// A failure has to reach the user whatever else is in flight — holding it is how
    /// an overlay outlives a dictation that is over (#260, #261).
    func testFailedIsAlwaysDrawn() {
        for current in DictationStatus.allCases {
            XCTAssertTrue(
                KeyboardHandoffStage.adopts(
                    stored: .failed, drawing: current, handoff: .here
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
                    stored: .idle, drawing: current, handoff: .here
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
                        stored: stored, drawing: current, handoff: .here
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
                        stored: stored, drawing: current, handoff: .none
                    ),
                    "stored \(stored.rawValue) drawing \(current.rawValue)"
                )
            }
        }
    }

    // MARK: - Somewhere else: drop the overlay, keep the dictation

    /// The keyboard followed the user into another host app. The wait it would draw
    /// there is for text that will not be typed there, so `.ready` is adopted and the
    /// overlay comes down.
    func testReadyIsDrawnWhenTheKeyboardIsInAnotherDocument() {
        XCTAssertTrue(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .processing, handoff: .elsewhere
        ))
    }

    func testEveryStatusIsDrawnWhenTheKeyboardIsElsewhere() {
        for stored in DictationStatus.allCases {
            for current in DictationStatus.allCases {
                XCTAssertTrue(
                    KeyboardHandoffStage.adopts(
                        stored: stored, drawing: current, handoff: .elsewhere
                    ),
                    "stored \(stored.rawValue) drawing \(current.rawValue)"
                )
            }
        }
    }

    // MARK: - The sequence that lost a dictation on 1bed468

    /// Claim in field X, iOS rebuilds the keyboard somewhere else while the user is in
    /// transit, the user comes straight back to field X. The text must land.
    ///
    /// The first attempt at the `elsewhere` rule cancelled the generation and cleared
    /// the pending record at step 2 — on device it fired 1.25 s after the claim, on a
    /// controller rebuilt while the maintainer was still on his way to the home
    /// screen, and nothing arrived when he came back a second later. Dropping the
    /// overlay and abandoning the dictation are different acts; this walks the two
    /// pure rules together to prove they stay different.
    func testLeavingAndReturningToTheSameFieldStillDelivers() {
        let fieldX = "1D6E6C1C-0000-0000-0000-00000000000A"
        let claimedAt: TimeInterval = 1_000
        let pending = PendingDictation(
            raw: "une dictée de trente secondes",
            policy: TranscriptionLanguagePolicy(
                mode: .followKeyboard,
                keyboardLanguage: .french,
                engine: .parakeet,
                modelIdentifier: "parakeet-tdt-0.6b-v3"
            ),
            recordingDuration: 30,
            documentIdentifier: fieldX,
            claimedAt: claimedAt
        )

        // 1. Claimed in field X, engine running, overlay up.
        XCTAssertFalse(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .processing, handoff: .here
        ), "the overlay stays up where the dictation belongs")

        // 2. iOS rebuilds the keyboard in transit: no document it can name.
        XCTAssertFalse(pending.mayInsert(into: nil))
        XCTAssertTrue(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .processing, handoff: .elsewhere
        ), "the overlay comes down")
        // And that is all it does — the record is still there to act on.
        XCTAssertTrue(pending.mayRecover(into: fieldX, now: claimedAt + 1.3))

        // 3. Back in field X a second later. Either route delivers: the generation
        //    still in flight inserts, or a rebuilt process recovers the raw.
        XCTAssertTrue(pending.mayInsert(into: fieldX), "the generation may insert")
        XCTAssertTrue(pending.mayRecover(into: fieldX, now: claimedAt + 2),
                      "and the recovery path is reachable")
        XCTAssertFalse(KeyboardHandoffStage.adopts(
            stored: .ready, drawing: .processing, handoff: .here
        ), "a keyboard still drawing the stage keeps it")
    }

    /// The same sequence, but the user takes longer than the recovery window to come
    /// back. The generation may still insert — the window bounds only the degraded
    /// path, never the identity check.
    func testReturningPastTheWindowStillLetsTheGenerationInsert() {
        let fieldX = "1D6E6C1C-0000-0000-0000-00000000000B"
        let pending = PendingDictation(
            raw: "texte",
            policy: TranscriptionLanguagePolicy(
                mode: .followKeyboard,
                keyboardLanguage: .french,
                engine: .whisperKit,
                modelIdentifier: "openai_whisper-small"
            ),
            recordingDuration: 5,
            documentIdentifier: fieldX,
            claimedAt: 1_000
        )
        XCTAssertFalse(pending.mayRecover(into: fieldX, now: 1_045))
        XCTAssertTrue(pending.mayInsert(into: fieldX))
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
            stored: .ready, drawing: .transcribing, handoff: .here
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
