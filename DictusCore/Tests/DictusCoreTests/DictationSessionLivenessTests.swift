// DictusCore/Tests/DictusCoreTests/DictationSessionLivenessTests.swift
// Unit tests for the orphaned-dictation predicate (issue #261).

import XCTest
@testable import DictusCore

/// Coverage for the decision that tells a phantom dictation from a live one.
///
/// These tests exist because neither side of #261 can be exercised end to end:
/// `KeyboardState` is a singleton in an extension target with no test bundle, and
/// the failure it reacts to is iOS terminating another process. The predicate is
/// the whole of the decision, so it is the part worth pinning down — and the two
/// fail-closed clauses below are the ones that would break cold-start dictation if
/// they ever regressed.
final class DictationSessionLivenessTests: XCTestCase {

    private let now: TimeInterval = 1_700_000_000
    private var threshold: TimeInterval { DictationSessionLivenessPolicy.staleHeartbeatThreshold }

    private func evaluate(
        _ status: DictationStatus?,
        heartbeat: TimeInterval?
    ) -> DictationSessionLiveness {
        DictationSessionLivenessPolicy.evaluate(status: status, heartbeat: heartbeat, now: now)
    }

    // MARK: - isActive

    func testActiveStatesAreTheOnesThatOwnADictation() {
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.requested))
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.recording))
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.transcribing))
        XCTAssertFalse(DictationSessionLivenessPolicy.isActive(.idle))
        XCTAssertFalse(DictationSessionLivenessPolicy.isActive(.ready))
        XCTAssertFalse(DictationSessionLivenessPolicy.isActive(.failed))
    }

    // MARK: - Nothing to reconcile

    func testUnsetStatusIsNotActive() {
        XCTAssertEqual(evaluate(nil, heartbeat: now - 3600), .notActive)
    }

    func testTerminalStatusesAreNotActive() {
        for status: DictationStatus in [.idle, .ready, .failed] {
            XCTAssertEqual(evaluate(status, heartbeat: now - 3600), .notActive, "\(status.rawValue)")
        }
    }

    // MARK: - The reported failure

    func testRecordingWithADeadHeartbeatIsOrphaned() {
        // The #261 capture: the app stopped emitting at 15:08:10, the rebuilt
        // keyboard read the state at 15:08:33.
        XCTAssertEqual(evaluate(.recording, heartbeat: now - 23), .orphaned)
    }

    func testTranscribingWithADeadHeartbeatIsOrphaned() {
        // The engine keeps writing a 3 s idle heartbeat through transcription
        // (#106 Phase C), so silence here means the same thing.
        XCTAssertEqual(evaluate(.transcribing, heartbeat: now - 23), .orphaned)
    }

    // MARK: - A live app must never be declared dead

    func testFreshHeartbeatIsLive() {
        XCTAssertEqual(evaluate(.recording, heartbeat: now - 1), .live)
    }

    func testIdleCadenceHeartbeatIsLive() {
        // The slowest legitimate write is every 3 s, and it must not read as death.
        XCTAssertEqual(evaluate(.transcribing, heartbeat: now - 3), .live)
    }

    func testHeartbeatExactlyAtTheThresholdIsLive() {
        XCTAssertEqual(evaluate(.recording, heartbeat: now - threshold), .live)
    }

    func testHeartbeatJustPastTheThresholdIsOrphaned() {
        XCTAssertEqual(evaluate(.recording, heartbeat: now - threshold - 0.01), .orphaned)
    }

    func testHeartbeatInTheFutureIsLive() {
        // A clock that moved backwards is not evidence of anything. Killing a live
        // recording is the worse error.
        XCTAssertEqual(evaluate(.recording, heartbeat: now + 60), .live)
    }

    // MARK: - Fail closed

    func testRequestedIsNeverOrphaned() {
        // The keyboard writes `.requested` moments before launching the app for a
        // cold start. A heartbeat left over from an earlier session would otherwise
        // condemn every cold-start dictation before the app had a chance to write one.
        XCTAssertEqual(evaluate(.requested, heartbeat: now - 3600), .unproven)
    }

    func testMissingHeartbeatIsUnprovenNotOrphaned() {
        // An absent value is not evidence. The keyboard's own 5 s/15 s watchdog
        // still covers this case.
        XCTAssertEqual(evaluate(.recording, heartbeat: nil), .unproven)
    }

    func testZeroHeartbeatIsUnproven() {
        // `UserDefaults.double(forKey:)` returns 0 for a missing key, which is how
        // the absence actually reaches the policy.
        XCTAssertEqual(evaluate(.recording, heartbeat: 0), .unproven)
    }
}
