// DictusCore/Tests/DictusCoreTests/DictationSessionGenerationTests.swift
// Which in-flight work is still allowed to report (#267).

import XCTest
@testable import DictusCore

/// Coverage for the rule that stops an abandoned dictation's transcription task
/// from reporting after the session is over.
///
/// The task itself is unreachable from a test: it lives in `DictationCoordinator`
/// in DictusApp, a target with no test bundle, and the race it loses needs a real
/// WhisperKit call that ignores cancellation for a second or two. What is testable
/// is the rule it consults, and the rule is where the bug was -- the counter that
/// existed before moved for one of the two reasons a session can end.
final class DictationSessionGenerationTests: XCTestCase {

    // MARK: - The rule

    func testWorkMayReportWhileItsSessionIsStillTheCurrentOne() {
        let generation = DictationSessionGeneration()
        XCTAssertTrue(generation.mayReport(from: generation.current))
    }

    /// The gap that caused the bug. A dictation that is cancelled, watchdog-reset
    /// or interrupted ends with no successor, and the counter has to move for that
    /// too -- not only when a new dictation starts.
    func testAbandoningASessionStopsItsOutstandingWorkFromReporting() {
        var generation = DictationSessionGeneration()
        let inFlight = generation.current

        generation.abandonSession()

        XCTAssertFalse(
            generation.mayReport(from: inFlight),
            "a task from an abandoned dictation must not write status or insert text"
        )
    }

    /// The #60 case, which the counter already covered: a newer dictation
    /// supersedes the previous one's outstanding work.
    func testStartingANewSessionStopsThePreviousOnesWorkFromReporting() {
        var generation = DictationSessionGeneration()
        let inFlight = generation.current

        generation.beginSession()

        XCTAssertFalse(generation.mayReport(from: inFlight))
        XCTAssertTrue(generation.mayReport(from: generation.current))
    }

    /// Both reasons a session stops being current have to invalidate outstanding
    /// work. Spelled out as one table so a third reason added later has an obvious
    /// place to prove itself.
    func testEveryWayASessionEndsInvalidatesOutstandingWork() {
        let endings: [(String, (inout DictationSessionGeneration) -> Void)] = [
            ("abandoned", { $0.abandonSession() }),
            ("superseded", { $0.beginSession() })
        ]

        for (label, end) in endings {
            var generation = DictationSessionGeneration()
            let inFlight = generation.current
            end(&generation)
            XCTAssertFalse(generation.mayReport(from: inFlight), "\(label) work still reported")
        }
    }

    /// A dictation that is simply progressing must keep its own work valid --
    /// otherwise the gate would drop every ordinary transcription result.
    func testWorkStaysValidAcrossTheLifeOfItsOwnSession() {
        var generation = DictationSessionGeneration()
        generation.beginSession()
        let inFlight = generation.current

        XCTAssertTrue(generation.mayReport(from: inFlight))
        XCTAssertTrue(generation.mayReport(from: inFlight), "nothing but an ending may invalidate work")
    }

    // MARK: - The device sequence

    /// The exact shape of the 2026-08-04 device failure: a dictation is stopped,
    /// its task is still running, the user abandons the session, and the task then
    /// finishes. Before the fix the task wrote `.failed` and the recording screen
    /// came back for half a second; on the success path it would have inserted text
    /// into the user's document.
    func testATaskFinishingAfterTheUserAbandonedItReportsNothing() {
        var generation = DictationSessionGeneration()
        generation.beginSession()
        let transcriptionTask = generation.current

        // The user taps the close button; the coordinator tears the session down.
        generation.abandonSession()

        // WhisperKit returns a second later, one way or the other.
        XCTAssertFalse(generation.mayReport(from: transcriptionTask), "late failure re-presented the screen")
        XCTAssertFalse(generation.mayReport(from: transcriptionTask), "late success inserted text")
    }

    /// Abandoning twice must not resurrect anything -- the watchdog and the user
    /// can both tear the same session down.
    func testAbandoningTwiceKeepsOutstandingWorkInvalid() {
        var generation = DictationSessionGeneration()
        let inFlight = generation.current

        generation.abandonSession()
        generation.abandonSession()

        XCTAssertFalse(generation.mayReport(from: inFlight))
    }
}
