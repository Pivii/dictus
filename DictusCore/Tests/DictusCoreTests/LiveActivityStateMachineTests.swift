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
