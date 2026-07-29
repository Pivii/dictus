// DictusCore/Tests/DictusCoreTests/LiveActivityLivenessTests.swift
// Unit tests for the "is this Live Activity still usable?" decision (issue #257).
//
// WHY these matter: the bug they encode takes 8 hours to reproduce on a device,
// because that is ActivityKit's ceiling before the system ends a Live Activity.
// The decision itself is pure, so it is verified here in milliseconds instead.

import XCTest
@testable import DictusCore

final class LiveActivityLivenessTests: XCTestCase {

    // MARK: - The #257 Decision

    func testEndedIsTreatedAsAbsent() {
        // The exact #257 state: the system ended the activity at the 8-hour ceiling,
        // but it still appears in Activity.activities, so an id-presence check
        // reports it as healthy forever.
        XCTAssertEqual(LiveActivityLiveness.ended.decision, .treatAsAbsent)
    }

    func testDismissedIsTreatedAsAbsent() {
        XCTAssertEqual(LiveActivityLiveness.dismissed.decision, .treatAsAbsent)
    }

    func testActiveIsKept() {
        XCTAssertEqual(LiveActivityLiveness.active.decision, .keep)
    }

    // MARK: - The .stale Judgement Call

    func testStaleIsRefreshedAndNotTreatedAsAbsent() {
        // A stale activity is still visible and still updatable -- only its content
        // is past staleDate. Dictus sets staleDate 30s ahead and never updates a
        // standby activity, so standby is stale by design. Treating stale as absent
        // would tear down every standby pill 30 seconds after it appeared.
        XCTAssertEqual(LiveActivityLiveness.stale.decision, .refresh)
        XCTAssertNotEqual(LiveActivityLiveness.stale.decision, .treatAsAbsent)
    }

    func testUnknownIsRefreshedRatherThanEnded() {
        // ActivityState is not frozen. An unrecognised state is not evidence of
        // death, and tearing down a live activity is the worse failure.
        XCTAssertEqual(LiveActivityLiveness.unknown.decision, .refresh)
    }

    // MARK: - Exhaustiveness

    func testOnlyEndedAndDismissedAreTreatedAsAbsent() {
        // Guards against a future case silently defaulting into a teardown.
        let absent = LiveActivityLiveness.allCases.filter { $0.decision == .treatAsAbsent }
        XCTAssertEqual(Set(absent), [.ended, .dismissed])
    }

    func testEveryStateHasANonTeardownOrTeardownDecision() {
        // Every case must resolve to a decision without trapping.
        for liveness in LiveActivityLiveness.allCases {
            let decision = liveness.decision
            XCTAssertTrue([.keep, .refresh, .treatAsAbsent].contains(decision),
                          "\(liveness) produced an unexpected decision")
        }
    }

    // MARK: - Log Stability

    func testRawValuesAreStableForExportedLogs() {
        // These strings land in the liveActivityStandbySkipped probe that a user
        // exports; renaming them silently breaks log triage.
        XCTAssertEqual(LiveActivityLiveness.active.rawValue, "active")
        XCTAssertEqual(LiveActivityLiveness.stale.rawValue, "stale")
        XCTAssertEqual(LiveActivityLiveness.ended.rawValue, "ended")
        XCTAssertEqual(LiveActivityLiveness.dismissed.rawValue, "dismissed")
        XCTAssertEqual(LiveActivityLiveness.unknown.rawValue, "unknown")
    }

    func testStandbySkippedProbeCarriesTheActivityState() {
        // The #257 log signature was "reason=ensureAlive-healthy-standby
        // isEnabled=true areActivitiesEnabled=true" -- both booleans true while the
        // activity was already dead. The state must now be part of that line.
        let event = LogEvent.liveActivityStandbySkipped(
            reason: "ensureAlive-clearedNotLive",
            isEnabled: true,
            activitiesEnabled: true,
            activityState: .ended
        )
        XCTAssertTrue(event.message.contains("activityState=ended"), event.message)
    }

    func testStandbySkippedProbeReportsNoneWhenNoActivityIsHeld() {
        let event = LogEvent.liveActivityStandbySkipped(
            reason: "ensureAlive-disabledInApp",
            isEnabled: false,
            activitiesEnabled: true,
            activityState: nil
        )
        XCTAssertTrue(event.message.contains("activityState=none"), event.message)
    }
}
