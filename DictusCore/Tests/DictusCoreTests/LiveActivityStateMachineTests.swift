// DictusCore/Tests/DictusCoreTests/LiveActivityStateMachineTests.swift
// Unit tests for LiveActivityStateMachine transition validation and watchdog flag.

import XCTest
@testable import DictusCore

final class LiveActivityStateMachineTests: XCTestCase {

    // MARK: - Valid Transitions

    func testIdleToStandbySucceeds() {
        var sm = LiveActivityStateMachine()
        XCTAssertTrue(sm.transition(to: .standby))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testIdleToFailedSucceeds() {
        // Issue #261: the app relaunches after being terminated mid-recording,
        // receives the stop the keyboard sent into the void, collects zero samples
        // and reports a failure from `.idle`. Rejecting it left the Dynamic Island
        // unable to show an error in the one situation the user most needs one.
        var sm = LiveActivityStateMachine()
        XCTAssertTrue(sm.transition(to: .failed))
        XCTAssertEqual(sm.currentPhase, .failed)
    }

    func testStandbyToRecordingSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        XCTAssertTrue(sm.transition(to: .recording))
        XCTAssertEqual(sm.currentPhase, .recording)
    }

    func testRecordingToTranscribingSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        XCTAssertTrue(sm.transition(to: .transcribing))
        XCTAssertEqual(sm.currentPhase, .transcribing)
    }

    func testRecordingToStandbySucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        XCTAssertTrue(sm.transition(to: .standby))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testTranscribingToReadySucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        XCTAssertTrue(sm.transition(to: .ready))
        XCTAssertEqual(sm.currentPhase, .ready)
    }

    // MARK: - The LLM stage (#267)

    func testTranscribingToProcessingSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        XCTAssertTrue(sm.transition(to: .processing))
        XCTAssertEqual(sm.currentPhase, .processing)
    }

    func testProcessingToReadySucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processing)
        XCTAssertTrue(sm.transition(to: .ready))
        XCTAssertEqual(sm.currentPhase, .ready)
    }

    func testProcessingToFailedSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processing)
        XCTAssertTrue(sm.transition(to: .failed))
        XCTAssertEqual(sm.currentPhase, .failed)
    }

    /// The LLM stage is skipped on most dictations -- the polish toggle is off by
    /// default, the duration gate drops flash clips, and a device without Apple
    /// Foundation Models never reaches an engine worth announcing. Straight to
    /// `.ready` has to stay a first-class path, not a rejected transition.
    func testTranscribingStillGoesStraightToReadyWhenTheLLMStageIsSkipped() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        XCTAssertTrue(sm.transition(to: .ready))
    }

    /// The LLM stage runs on a transcript, so it can only follow transcription.
    func testRecordingToProcessingFails() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        XCTAssertFalse(sm.transition(to: .processing))
        XCTAssertEqual(sm.currentPhase, .recording)
    }

    /// A finished dictation must not be able to reopen the wait.
    func testProcessingCannotFollowReady() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .ready)
        XCTAssertFalse(sm.transition(to: .processing))
        XCTAssertEqual(sm.currentPhase, .ready)
    }

    // MARK: - A dictation abandoned inside a stage (#267 review)

    /// The property the whole recovery rests on. Before this edge existed, a
    /// dictation abandoned during transcription left the machine parked there, and
    /// the pill could never be walked back.
    func testAnAbandonedTranscriptionCanReturnToStandby() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        XCTAssertTrue(sm.transition(to: .standby))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testAnAbandonedProcessingStageCanReturnToStandby() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processing)
        XCTAssertTrue(sm.transition(to: .standby))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    /// The user-visible consequence, and the reason the edge above is not a
    /// cosmetic tidy-up: the next dictation has to be able to record.
    ///
    /// Without the recovery, the machine sat on the abandoned stage and this
    /// `.recording` transition was rejected -- so the Dynamic Island kept showing
    /// the stage of a dictation that had ended, while a new one recorded
    /// underneath it. That is the #42 / #257 desync, reached through the watchdog.
    func testTheNextDictationCanRecordAfterAnAbandonedStage() {
        for abandoned in [LiveActivityStateMachine.Phase.transcribing, .processing] {
            var sm = LiveActivityStateMachine()
            sm.transition(to: .standby)
            sm.transition(to: .recording)
            sm.transition(to: .transcribing)
            if abandoned == .processing {
                sm.transition(to: .processing)
            }
            XCTAssertEqual(sm.currentPhase, abandoned)

            XCTAssertTrue(
                sm.transition(to: .standby),
                "a dictation abandoned in \(abandoned.rawValue) must be able to come home"
            )
            XCTAssertTrue(
                sm.transition(to: .recording),
                "the dictation after one abandoned in \(abandoned.rawValue) must be able to record"
            )
        }
    }

    /// The recovery must not become a way for a finished dictation to reopen the
    /// wait: standby still leads forward, never back into a stage.
    func testRecoveringToStandbyDoesNotReopenAStage() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .standby)
        XCTAssertFalse(sm.transition(to: .transcribing))
        XCTAssertFalse(sm.transition(to: .processing))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testTranscribingToFailedSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        XCTAssertTrue(sm.transition(to: .failed))
        XCTAssertEqual(sm.currentPhase, .failed)
    }

    func testReadyToStandbySucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .ready)
        XCTAssertTrue(sm.transition(to: .standby))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testReadyToRecordingSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .ready)
        XCTAssertTrue(sm.transition(to: .recording))
        XCTAssertEqual(sm.currentPhase, .recording)
    }

    func testFailedToStandbySucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .failed)
        XCTAssertTrue(sm.transition(to: .standby))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testFailedToRecordingSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .failed)
        XCTAssertTrue(sm.transition(to: .recording))
        XCTAssertEqual(sm.currentPhase, .recording)
    }

    func testFailedToIdleSucceeds() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .failed)
        XCTAssertTrue(sm.transition(to: .idle))
        XCTAssertEqual(sm.currentPhase, .idle)
    }

    // MARK: - Invalid Transitions

    func testIdleToRecordingFails() {
        var sm = LiveActivityStateMachine()
        XCTAssertFalse(sm.transition(to: .recording))
        XCTAssertEqual(sm.currentPhase, .idle)
    }

    func testStandbyToTranscribingFails() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        XCTAssertFalse(sm.transition(to: .transcribing))
        XCTAssertEqual(sm.currentPhase, .standby)
    }

    func testRecordingToReadyFails() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        XCTAssertFalse(sm.transition(to: .ready))
        XCTAssertEqual(sm.currentPhase, .recording)
    }

    func testRecordingToFailedFails() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        XCTAssertFalse(sm.transition(to: .failed))
        XCTAssertEqual(sm.currentPhase, .recording)
    }

    // MARK: - Watchdog Flag

    func testNeedsWatchdogTrueOnlyWhenRecording() {
        var sm = LiveActivityStateMachine()
        XCTAssertFalse(sm.needsWatchdog, "idle should not need watchdog")

        sm.transition(to: .standby)
        XCTAssertFalse(sm.needsWatchdog, "standby should not need watchdog")

        sm.transition(to: .recording)
        XCTAssertTrue(sm.needsWatchdog, "recording should need watchdog")

        sm.transition(to: .transcribing)
        XCTAssertFalse(sm.needsWatchdog, "transcribing should not need watchdog")
    }

    // MARK: - Reset

    func testResetSetsPhaseToIdle() {
        var sm = LiveActivityStateMachine()
        sm.transition(to: .standby)
        sm.transition(to: .recording)
        sm.reset()
        XCTAssertEqual(sm.currentPhase, .idle)
    }

    // MARK: - No-Activity Cycle Suppression (#233)

    func testShouldLogRejectionTrueByDefault() {
        let sm = LiveActivityStateMachine()
        XCTAssertTrue(sm.shouldLogRejection, "rejections from idle must log when no cycle is declared")
    }

    func testBeginNoActivityCycleSuppressesIdleRejections() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        XCTAssertTrue(sm.isInNoActivityCycle)
        XCTAssertFalse(sm.shouldLogRejection, "idle rejections during a no-activity cycle must be suppressed")
    }

    func testSuppressionOnlyAppliesWhileIdle() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        sm.forcePhase(.standby)
        // forcePhase to non-idle means an activity exists -- #42 diagnostics must log
        XCTAssertTrue(sm.shouldLogRejection)
    }

    func testSuccessfulTransitionEndsNoActivityCycle() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        sm.transition(to: .standby)
        XCTAssertFalse(sm.isInNoActivityCycle)
        XCTAssertTrue(sm.shouldLogRejection)
    }

    func testFailedTransitionKeepsNoActivityCycle() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        // idle -> transcribing is invalid: the exact spam pattern from #233
        XCTAssertFalse(sm.transition(to: .transcribing))
        XCTAssertTrue(sm.isInNoActivityCycle)
        XCTAssertFalse(sm.shouldLogRejection)
    }

    func testForcePhaseToNonIdleEndsNoActivityCycle() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        sm.forcePhase(.recording)
        XCTAssertFalse(sm.isInNoActivityCycle)
    }

    func testForcePhaseToIdleKeepsNoActivityCycle() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        sm.forcePhase(.idle)
        XCTAssertTrue(sm.isInNoActivityCycle, "teardown to idle still has no activity -- keep suppressing")
        XCTAssertFalse(sm.shouldLogRejection)
    }

    func testEndNoActivityCycleRestoresLogging() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        sm.endNoActivityCycle()
        XCTAssertFalse(sm.isInNoActivityCycle)
        XCTAssertTrue(sm.shouldLogRejection)
    }

    func testResetEndsNoActivityCycle() {
        var sm = LiveActivityStateMachine()
        sm.beginNoActivityCycle()
        sm.reset()
        XCTAssertFalse(sm.isInNoActivityCycle)
        XCTAssertTrue(sm.shouldLogRejection)
    }
}
