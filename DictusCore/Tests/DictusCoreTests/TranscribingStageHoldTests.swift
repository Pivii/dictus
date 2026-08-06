import XCTest
@testable import DictusCore

/// Coverage for the display floor under the transcription stage (#309).
///
/// These tests exist because neither surface that runs the rule can be exercised:
/// the keyboard extension target has no test bundle, and `RecordingView` needs a
/// running app. The preemption invariant is the part of #309 that can be wrong in a
/// way the user pays for -- a hold that outlives a terminal state would add latency
/// to the fastest path in the product -- so it is the part pinned down here.
final class TranscribingStageHoldTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var floor: TimeInterval { TranscribingStageHold.minimumDisplayDuration }

    /// A hold sitting on `.transcribing`, drawn at `start`.
    private func transcribing() -> TranscribingStageHold {
        TranscribingStageHold(displayed: .transcribing, since: start)
    }

    /// Asserts an outcome is a hold for `status` lasting `interval`.
    ///
    /// The interval is a `TimeInterval` subtraction, so it carries the usual
    /// floating-point residue and cannot be compared by `==`.
    private func assertHold(
        _ outcome: TranscribingStageHold.Outcome,
        _ status: DictationStatus,
        _ interval: TimeInterval,
        line: UInt = #line
    ) {
        guard case .hold(let held, let remaining) = outcome else {
            return XCTFail("expected a hold, got \(outcome)", line: line)
        }
        XCTAssertEqual(held, status, line: line)
        XCTAssertEqual(remaining, interval, accuracy: 0.0001, line: line)
    }

    // MARK: - The defect: Parakeet + polish, a stage that flashes

    func testProcessingArrivingInsideTheWindowIsHeldForTheRemainder() {
        var hold = transcribing()
        // The measured Parakeet case: transcription returns after 154 ms.
        let outcome = hold.apply(.processing, now: start.addingTimeInterval(0.154))

        assertHold(outcome, .processing, floor - 0.154)
        XCTAssertEqual(hold.displayed, .transcribing)
        XCTAssertEqual(hold.pending, .processing)
    }

    func testReleasingTheHoldDrawsTheStageThatWasWaiting() {
        var hold = transcribing()
        _ = hold.apply(.processing, now: start.addingTimeInterval(0.154))

        let outcome = hold.release(now: start.addingTimeInterval(floor))

        XCTAssertEqual(outcome, .draw(.processing))
        XCTAssertEqual(hold.displayed, .processing)
        XCTAssertNil(hold.pending)
    }

    func testReleasingWithNothingPendingDrawsNothing() {
        // A timer that outlived its decision, e.g. a terminal status preempted the
        // hold before it elapsed. It must draw nothing at all.
        var hold = transcribing()
        XCTAssertEqual(hold.release(now: start.addingTimeInterval(floor)), .unchanged)
        XCTAssertEqual(hold.displayed, .transcribing)
    }

    // MARK: - Preemption: the invariant that keeps added latency at zero

    func testReadyPreemptsTheStageImmediately() {
        // Polish OFF, the default. The 154 ms is not an aborted stage, it is the whole
        // tail of the interaction: the user validated and their text is here. Holding
        // anything would deliberately slow the fastest path in the product.
        var hold = transcribing()
        XCTAssertEqual(hold.apply(.ready, now: start.addingTimeInterval(0.154)), .draw(.ready))
        XCTAssertEqual(hold.displayed, .ready)
    }

    func testFailurePreemptsTheStageImmediately() {
        var hold = transcribing()
        XCTAssertEqual(hold.apply(.failed, now: start.addingTimeInterval(0.05)), .draw(.failed))
    }

    func testCancellationPreemptsTheStageImmediately() {
        // `.idle` is what a cancel, a watchdog reset and `forceResetToIdle` all write.
        var hold = transcribing()
        XCTAssertEqual(hold.apply(.idle, now: start.addingTimeInterval(0.05)), .draw(.idle))
    }

    func testATerminalStatusArrivingMidHoldClearsThePendingStage() {
        var hold = transcribing()
        _ = hold.apply(.processing, now: start.addingTimeInterval(0.1))

        XCTAssertEqual(hold.apply(.ready, now: start.addingTimeInterval(0.2)), .draw(.ready))
        XCTAssertNil(hold.pending)
        // And the timer that is still in flight draws nothing when it fires.
        XCTAssertEqual(hold.release(now: start.addingTimeInterval(floor)), .unchanged)
        XCTAssertEqual(hold.displayed, .ready)
    }

    func testANewDictationIsNeverDelayed() {
        // `.requested` is the one moment the user needs immediate truth: the mic is
        // about to go live. Holding it would be the only place this rule cost real
        // perceived latency.
        for next in [DictationStatus.requested, .recording] {
            var hold = transcribing()
            XCTAssertEqual(hold.apply(next, now: start.addingTimeInterval(0.05)), .draw(next))
        }
    }

    // MARK: - Where the rule must never fire

    func testTheRuleNeverFiresOnceTheStageHasBeenReadable() {
        // Whisper medium transcribes in 2.9-5 s measured on device.
        var hold = transcribing()
        XCTAssertEqual(hold.apply(.processing, now: start.addingTimeInterval(3.0)), .draw(.processing))
        XCTAssertNil(hold.pending)
    }

    func testExactlyAtTheFloorTheStageIsDrawnImmediately() {
        var hold = transcribing()
        XCTAssertEqual(hold.apply(.processing, now: start.addingTimeInterval(floor)), .draw(.processing))
    }

    func testJustInsideTheFloorTheStageIsHeld() {
        var hold = transcribing()
        assertHold(hold.apply(.processing, now: start.addingTimeInterval(floor - 0.001)), .processing, 0.001)
    }

    func testAClockThatMovedBackwardsCannotLengthenTheHold() {
        // `now` is wall-clock on both surfaces, so an NTP correction landing between
        // the two reads makes the elapsed time negative. Unclamped it flowed into the
        // remainder and returned the floor *plus* the size of the jump -- an hour-long
        // correction would have stranded the overlay on "Transcription..." for the rest
        // of the dictation.
        var hold = transcribing()
        assertHold(hold.apply(.processing, now: start.addingTimeInterval(-3600)), .processing, floor)
    }

    func testTheHoldNeverExceedsTheFloor() {
        // The ceiling the clamp buys, stated as an invariant rather than as one case:
        // whatever the clock does, no surface is ever asked to wait longer than the
        // floor it was given.
        for offset in [-3600.0, -1.0, -0.001, 0.0, 0.1, 0.499] {
            var hold = transcribing()
            guard case .hold(_, let remaining) = hold.apply(
                .processing, now: start.addingTimeInterval(offset)
            ) else {
                return XCTFail("expected a hold at offset \(offset)")
            }
            XCTAssertLessThanOrEqual(remaining, floor, "offset \(offset)")
            XCTAssertGreaterThan(remaining, 0, "offset \(offset)")
        }
    }

    func testAStageMissedEntirelyIsDrawnAtOnceAndNothingIsSynthesised() {
        // Darwin notifications coalesce: the keyboard can go straight from `.recording`
        // to `.processing` without ever seeing `.transcribing`. There is nothing on
        // screen to hold and no flash either, so no stage is invented to fill the gap.
        var hold = TranscribingStageHold(displayed: .recording, since: start)
        XCTAssertEqual(hold.apply(.processing, now: start.addingTimeInterval(0.01)), .draw(.processing))
        XCTAssertNil(hold.pending)
    }

    func testASurfaceRecreatedMidHoldDrawsProcessingImmediately() {
        // iOS rebuilds the keyboard extension constantly (#281). A fresh instance
        // starts at `.idle`, reads `.processing` from the App Group, and draws it.
        var hold = TranscribingStageHold(displayed: .idle, since: start)
        XCTAssertEqual(hold.apply(.processing, now: start), .draw(.processing))
    }

    func testEnteringTranscriptionIsNeverDelayed() {
        var hold = TranscribingStageHold(displayed: .recording, since: start)
        XCTAssertEqual(hold.apply(.transcribing, now: start.addingTimeInterval(4)), .draw(.transcribing))
    }

    func testProcessingItselfCarriesNoFloor() {
        // Its next state is always terminal, so "hold when another stage follows"
        // can never fire for it.
        var hold = TranscribingStageHold(displayed: .processing, since: start)
        XCTAssertEqual(hold.apply(.ready, now: start.addingTimeInterval(0.01)), .draw(.ready))
    }

    func testOnlyTranscriptionHasAFloor() {
        // Sweeps the whole enum: from any other displayed status, every incoming
        // status is drawn at once. A status added later joins this sweep on its own.
        for displayed in DictationStatus.allCases where displayed != .transcribing {
            for incoming in DictationStatus.allCases where incoming != displayed {
                var hold = TranscribingStageHold(displayed: displayed, since: start)
                XCTAssertEqual(
                    hold.apply(incoming, now: start.addingTimeInterval(0.01)),
                    .draw(incoming),
                    "\(displayed) -> \(incoming) must not be held"
                )
            }
        }
    }

    // MARK: - Repeated writes of the same status

    func testRedrawingTheSameStatusChangesNothing() {
        // The keyboard re-adopts the stored status on every Darwin refresh and every
        // keyboard appearance. If those restarted the floor, a stage already half spent
        // would be held from scratch each time.
        var hold = transcribing()
        XCTAssertEqual(hold.apply(.transcribing, now: start.addingTimeInterval(0.3)), .unchanged)
        assertHold(hold.apply(.processing, now: start.addingTimeInterval(0.3)), .processing, 0.2)
    }

    func testRepeatingTheStatusUnderHoldKeepsTheDecision() {
        // A re-affirmation of what is already on screen must not throw away a decision
        // already taken -- that would strand the overlay on `.transcribing` until the
        // next status arrived.
        var hold = transcribing()
        _ = hold.apply(.processing, now: start.addingTimeInterval(0.1))

        XCTAssertEqual(hold.apply(.transcribing, now: start.addingTimeInterval(0.2)), .unchanged)
        XCTAssertEqual(hold.pending, .processing)
        XCTAssertEqual(hold.release(now: start.addingTimeInterval(floor)), .draw(.processing))
    }

    func testRepeatingThePendingStatusIsNotASecondHold() {
        var hold = transcribing()
        _ = hold.apply(.processing, now: start.addingTimeInterval(0.1))
        XCTAssertEqual(hold.apply(.processing, now: start.addingTimeInterval(0.2)), .unchanged)
    }

    // MARK: - The constant

    func testTheFloorSitsInsideTheLegibleBand() {
        // Lower bound: reading a one-word label in one fixation (~250 ms) plus
        // perceiving the state change (~300-400 ms). Upper bound: no full crossing of
        // the transcription sine, which takes 2.00 s.
        XCTAssertGreaterThanOrEqual(TranscribingStageHold.minimumDisplayDuration, 0.35)
        XCTAssertLessThanOrEqual(TranscribingStageHold.minimumDisplayDuration, 0.6)
    }
}
