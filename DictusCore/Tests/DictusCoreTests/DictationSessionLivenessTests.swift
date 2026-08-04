// DictusCore/Tests/DictusCoreTests/DictationSessionLivenessTests.swift
// Unit tests for the orphaned-dictation predicate (issue #261).

import XCTest
@testable import DictusCore

/// Coverage for the decision that tells a phantom dictation from a live one.
///
/// These tests exist because neither side of #261 can be exercised end to end:
/// `KeyboardState` is a singleton in an extension target with no test bundle, the
/// failure it reacts to is iOS terminating another process, and a simulator cannot
/// even enable the Dictus keyboard. The predicate is the whole of the decision.
///
/// The device-scenario cases below carry the real timestamps from the 2026-08-03
/// capture on build 25, because that run is what proved the first design wrong in
/// both directions at once.
final class DictationSessionLivenessTests: XCTestCase {

    private let now: TimeInterval = 1_700_000_000
    private var recordingThreshold: TimeInterval {
        DictationSessionLivenessPolicy.recordingStaleThreshold
    }
    private var transcribingThreshold: TimeInterval {
        DictationSessionLivenessPolicy.transcribingStaleThreshold
    }

    private func evaluate(
        _ status: DictationStatus?,
        heartbeat: TimeInterval?,
        localSessionStartedAt: TimeInterval? = nil
    ) -> DictationSessionLiveness {
        DictationSessionLivenessPolicy.evaluate(
            status: status,
            heartbeat: heartbeat,
            localSessionStartedAt: localSessionStartedAt,
            now: now
        )
    }

    // MARK: - isActive

    func testActiveStatesAreTheOnesThatOwnADictation() {
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.requested))
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.recording))
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.transcribing))
        XCTAssertTrue(DictationSessionLivenessPolicy.isActive(.processing))
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
        XCTAssertEqual(evaluate(.recording, heartbeat: now - 23), .orphaned)
    }

    func testTranscribingWithADeadHeartbeatIsOrphaned() {
        // The engine keeps writing a 3 s idle heartbeat through transcription
        // (#106 Phase C), so silence here means the same thing.
        XCTAssertEqual(evaluate(.transcribing, heartbeat: now - 23), .orphaned)
    }

    func testARebuiltKeyboardOwnsNoSessionAndStillReachesAVerdict() {
        // The originally reported incident: the extension is a fresh process, so it
        // has no session of its own, and the App Group is all it has to go on.
        XCTAssertEqual(evaluate(.recording, heartbeat: now - 23, localSessionStartedAt: nil), .orphaned)
    }

    // MARK: - A live app must never be declared dead

    func testFreshHeartbeatIsLive() {
        XCTAssertEqual(evaluate(.recording, heartbeat: now - 1), .live)
    }

    func testIdleCadenceHeartbeatIsLiveDuringTranscription() {
        // The slowest legitimate write is every 3 s, and it must not read as death.
        XCTAssertEqual(evaluate(.transcribing, heartbeat: now - 3), .live)
    }

    func testHeartbeatInTheFutureIsLive() {
        // A clock that moved backwards is not evidence of anything. Killing a live
        // recording is the worse error.
        XCTAssertEqual(evaluate(.recording, heartbeat: now + 60), .live)
    }

    // MARK: - Thresholds track the writer's cadence

    func testRecordingUsesTheShorterThreshold() {
        XCTAssertEqual(recordingThreshold, 4)
        XCTAssertEqual(evaluate(.recording, heartbeat: now - recordingThreshold), .live)
        XCTAssertEqual(evaluate(.recording, heartbeat: now - recordingThreshold - 0.01), .orphaned)
    }

    func testTranscribingUsesTheLongerThreshold() {
        XCTAssertEqual(transcribingThreshold, 8)
        XCTAssertEqual(evaluate(.transcribing, heartbeat: now - transcribingThreshold), .live)
        XCTAssertEqual(evaluate(.transcribing, heartbeat: now - transcribingThreshold - 0.01), .orphaned)
    }

    /// The LLM stage (#267) is judged by the same threshold as transcription, and
    /// deliberately so: what the threshold measures is the heartbeat's cadence, and
    /// both post-recording stages run against the same 3 s warm-idle writer. A
    /// longer one for `processing` would only delay noticing a dead app.
    func testProcessingIsJudgedByTheSameThresholdAsTranscribing() {
        XCTAssertEqual(
            DictationSessionLivenessPolicy.staleThreshold(for: .processing),
            DictationSessionLivenessPolicy.staleThreshold(for: .transcribing)
        )
        XCTAssertEqual(evaluate(.processing, heartbeat: now - transcribingThreshold), .live)
        XCTAssertEqual(evaluate(.processing, heartbeat: now - transcribingThreshold - 0.01), .orphaned)
    }

    /// A long LLM stage is not a suspicious one. Six minutes into a Smart Mode with
    /// a heartbeat two seconds old, the session is alive -- the stage's length must
    /// never be the thing that condemns it.
    func testALongProcessingStageWithAFreshHeartbeatStaysLive() {
        XCTAssertEqual(evaluate(.processing, heartbeat: now - 2, localSessionStartedAt: now - 360), .live)
    }

    func testTheRecordingThresholdIsUnderTheKeyboardWatchdogWindow() {
        // Defect 1 of the 2026-08-03 device run, pinned as a rule rather than a
        // comment. `KeyboardState`'s watchdog resets a stale dictation once waveform
        // data is 5 s old, and both ages start at the same instant, so a predicate
        // threshold at or above 5 s can never fire: the watchdog resets to `.idle`
        // first and its own guard then stops the timer. The first shipped version
        // used 8 s and never once fired on device.
        XCTAssertLessThan(
            recordingThreshold, 5,
            "a threshold at or above the watchdog's 5 s window is unreachable by construction"
        )
    }

    func testTranscribingKeepsRoomForTheThreeSecondIdleCadence() {
        XCTAssertGreaterThan(
            transcribingThreshold, 3 * 2,
            "the warm-idle heartbeat writes every 3 s; the threshold must clear two of them"
        )
    }

    // MARK: - A heartbeat can only speak about a session it postdates

    func testHeartbeatFromBeforeOurSessionProvesNothing() {
        // Defect 2 of the 2026-08-03 device run, with its real numbers. A watchdog
        // reset left a corpse heartbeat at 14:36:51. The user tapped the mic at
        // 14:37:02 and the app wrote `recording` at 14:37:03. Judging that
        // one-second-old session by the eleven-second-old heartbeat declared it
        // orphaned and killed a healthy cold start.
        let corpseHeartbeat = now - 11.609
        let sessionStarted = now - 1
        XCTAssertEqual(
            evaluate(.recording, heartbeat: corpseHeartbeat, localSessionStartedAt: sessionStarted),
            .unproven
        )
    }

    func testHeartbeatFromDuringOurSessionCanStillBeOrphaned() {
        // The mirror image, and the reason the rule is "postdates" rather than
        // "we hold a session": the app died in the middle of a dictation this
        // keyboard started, so its heartbeat is younger than the session and its
        // silence does mean something.
        let sessionStarted = now - 20
        XCTAssertEqual(
            evaluate(.recording, heartbeat: now - 8, localSessionStartedAt: sessionStarted),
            .orphaned
        )
    }

    func testHeartbeatExactlyAtOurSessionStartProvesNothing() {
        // Ambiguous by construction, so it fails closed.
        let sessionStarted = now - 30
        XCTAssertEqual(
            evaluate(.recording, heartbeat: sessionStarted, localSessionStartedAt: sessionStarted),
            .unproven
        )
    }

    func testALiveSessionOfOurOwnDoesNotSuppressAFreshVerdict() {
        // Owning a session must not make the keyboard blind: a fresh heartbeat from
        // within it still reads as live.
        XCTAssertEqual(
            evaluate(.recording, heartbeat: now - 1, localSessionStartedAt: now - 10),
            .live
        )
    }

    // MARK: - Fail closed

    func testRequestedIsNeverOrphaned() {
        // The keyboard writes `.requested` moments before launching the app for a
        // cold start. A heartbeat left over from an earlier session would otherwise
        // condemn every cold-start dictation before the app had written one.
        XCTAssertEqual(evaluate(.requested, heartbeat: now - 3600), .unproven)
    }

    func testRequestedIsNeverOrphanedEvenWithNoSessionOfOurOwn() {
        XCTAssertEqual(
            evaluate(.requested, heartbeat: now - 3600, localSessionStartedAt: nil),
            .unproven
        )
    }

    func testMissingHeartbeatIsUnprovenNotOrphaned() {
        // An absent value is not evidence. The keyboard's own watchdog still covers
        // this case.
        XCTAssertEqual(evaluate(.recording, heartbeat: nil), .unproven)
    }

    func testZeroHeartbeatIsUnproven() {
        // `UserDefaults.double(forKey:)` returns 0 for a missing key, which is how
        // the absence actually reaches the policy.
        XCTAssertEqual(evaluate(.recording, heartbeat: 0), .unproven)
    }

    // MARK: - Local and stored state disagreeing, exhaustively

    func testLocalAndStoredDisagreementMatrix() {
        // Every combination of "do we own a session, and when did it start" against
        // "what does the App Group say", for the statuses that can be orphaned.
        // The failure this suite exists for lived in one cell of this table and was
        // invisible to a simulator run that only ever seeded one of the two.
        let cases: [(DictationStatus, TimeInterval, TimeInterval?, DictationSessionLiveness, String)] = [
            (.recording, now - 20, nil, .orphaned, "rebuilt keyboard, dead app"),
            (.recording, now - 20, now - 1, .unproven, "corpse heartbeat, session we just started"),
            (.recording, now - 20, now - 60, .orphaned, "our session, app died inside it"),
            (.recording, now - 1, now - 60, .live, "our session, app alive"),
            (.recording, now - 1, nil, .live, "rebuilt keyboard, app alive"),
            (.transcribing, now - 20, now - 1, .unproven, "corpse heartbeat during transcription"),
            (.transcribing, now - 5, now - 60, .live, "idle cadence inside our session"),
            (.transcribing, now - 20, nil, .orphaned, "rebuilt keyboard, dead app, transcribing"),
            (.processing, now - 20, now - 1, .unproven, "corpse heartbeat during the LLM stage"),
            (.processing, now - 5, now - 60, .live, "idle cadence inside our session, LLM stage"),
            (.processing, now - 20, nil, .orphaned, "rebuilt keyboard, dead app, LLM stage")
        ]
        for (status, heartbeat, sessionStart, expected, label) in cases {
            XCTAssertEqual(
                evaluate(status, heartbeat: heartbeat, localSessionStartedAt: sessionStart),
                expected,
                label
            )
        }
    }
}
