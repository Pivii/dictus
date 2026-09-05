// DictusCore/Tests/DictusCoreTests/PolishHandoffConclusionTests.swift
// Tests for the status a concluded keyboard hand-off leaves behind (#467).

import XCTest
@testable import DictusCore

final class PolishHandoffConclusionTests: XCTestCase {

    /// The state the device capture found: `.ready` written at hand-off, never taken
    /// back, so `MainTabView` kept the recording overlay mounted over the home screen.
    func testReadyIsTakenBack() {
        XCTAssertTrue(PolishHandoffConclusion.returnsToIdle(from: .ready))
    }

    /// A failure is a sentence the user still has to read, and it outlives the
    /// dictation that produced it.
    func testFailedIsLeftStanding() {
        XCTAssertFalse(PolishHandoffConclusion.returnsToIdle(from: .failed))
    }

    /// A dictation that has replaced this one owns the status now. Concluding the old
    /// hand-off must not tear the new one down.
    func testALiveDictationIsLeftStanding() {
        for status in [DictationStatus.requested, .recording, .transcribing, .processing] {
            XCTAssertFalse(
                PolishHandoffConclusion.returnsToIdle(from: status),
                "concluding a hand-off cleared \(status.rawValue)"
            )
        }
    }

    /// Nothing to take back, so nothing is written — this is what keeps the watchdog
    /// and the clean ending from logging a status change apiece for one dictation.
    func testIdleIsNotRewritten() {
        XCTAssertFalse(PolishHandoffConclusion.returnsToIdle(from: .idle))
    }

    /// `.ready` is the only status the hand-off itself produces, so it has to be the
    /// only one taken back. Swept over `allCases` so a status added later joins the
    /// assertion instead of slipping past a hand-written list.
    func testReadyIsTheOnlyStatusTakenBack() {
        for status in DictationStatus.allCases {
            XCTAssertEqual(
                PolishHandoffConclusion.returnsToIdle(from: status),
                status == .ready,
                "unclassified status \(status.rawValue)"
            )
        }
    }
}
