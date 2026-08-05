import XCTest
@testable import DictusCore

/// Coverage for how a parked cold-start dictation ends (issue #311).
///
/// These tests exist because `DictationCoordinator` cannot be unit-tested: it is
/// `@MainActor`, owns a live `AVAudioEngine` and an `AVAudioSession`, reads
/// `UIApplication.applicationState` and lives in the DictusApp target. The rule
/// below is the part of #311 that decides whether the user is left staring at
/// "Démarrage…" forever, so it is the part worth pinning down.
final class ColdStartResolutionPolicyTests: XCTestCase {

    // MARK: - canStartNewDictation

    func testStatusesThatAcceptANewDictation() {
        // These four are `startDictation`'s own entry guard. `.requested` belongs
        // here because it is what the keyboard wrote moments before launching the
        // app: it describes this request, not a competing one.
        for status in [DictationStatus.idle, .requested, .ready, .failed] {
            XCTAssertTrue(
                ColdStartResolutionPolicy.canStartNewDictation(from: status),
                "\(status.rawValue) should accept a new dictation"
            )
        }
    }

    func testStatusesThatRefuseANewDictation() {
        // A dictation is in flight. Starting a second one over it is the failure
        // this predicate exists to refuse.
        for status in [DictationStatus.recording, .transcribing, .processing] {
            XCTAssertFalse(
                ColdStartResolutionPolicy.canStartNewDictation(from: status),
                "\(status.rawValue) should refuse a new dictation"
            )
        }
    }

    func testTheTwoListsAboveCoverEveryStatus() {
        // Guards the two tests above against a case added to `DictationStatus` later
        // and named in neither list -- which would leave it untested while both
        // still passed.
        XCTAssertEqual(DictationStatus.allCases.count, 7)
    }

    // MARK: - resolution

    func testNothingParkedResolvesToNone() {
        XCTAssertEqual(
            ColdStartResolutionPolicy.resolution(
                isPending: false,
                storedStatus: .requested,
                coordinatorStatus: .idle
            ),
            .none
        )
    }

    func testParkedStartIsRetriedWhileTheKeyboardStillWaits() {
        // The case the issue was filed for: the keyboard is holding "Démarrage…"
        // and the app is about to lose its last chance to honour it.
        XCTAssertEqual(
            ColdStartResolutionPolicy.resolution(
                isPending: true,
                storedStatus: .requested,
                coordinatorStatus: .idle
            ),
            .retry
        )
    }

    func testParkedStartIsDroppedOnceTheKeyboardHasGivenUp() {
        // Anything but `.requested` means somebody already resolved the request --
        // the keyboard's watchdog, a cancel, or a later dictation. Reporting a
        // failure here would raise a banner for a request the user has moved on from.
        for stored in DictationStatus.allCases where stored != .requested {
            XCTAssertEqual(
                ColdStartResolutionPolicy.resolution(
                    isPending: true,
                    storedStatus: stored,
                    coordinatorStatus: .idle
                ),
                .dropped,
                "stored=\(stored.rawValue) should be dropped"
            )
        }
    }

    func testParkedStartIsDroppedWhenTheStoredStatusIsUnreadable() {
        // An absent or unrecognised key is not a request to honour.
        XCTAssertEqual(
            ColdStartResolutionPolicy.resolution(
                isPending: true,
                storedStatus: nil,
                coordinatorStatus: .idle
            ),
            .dropped
        )
    }

    func testParkedStartIsReportedWhenTheCoordinatorIsBusy() {
        // No attempt is possible, so the keyboard has to be told rather than left
        // waiting -- which is the whole point of #311.
        for busy in [DictationStatus.recording, .transcribing, .processing] {
            XCTAssertEqual(
                ColdStartResolutionPolicy.resolution(
                    isPending: true,
                    storedStatus: .requested,
                    coordinatorStatus: busy
                ),
                .report,
                "coordinator=\(busy.rawValue) should report"
            )
        }
    }

    func testAParkedStartIsNeverAbandonedSilently() {
        // The invariant, stated as a sweep: while the keyboard is still waiting,
        // every coordinator status resolves to an outcome that either starts the
        // dictation or tells the user. `.none` and `.dropped` are unreachable here.
        for status in DictationStatus.allCases {
            let resolution = ColdStartResolutionPolicy.resolution(
                isPending: true,
                storedStatus: .requested,
                coordinatorStatus: status
            )
            XCTAssertTrue(
                resolution == .retry || resolution == .report,
                "coordinator=\(status.rawValue) resolved to \(resolution.rawValue), which says nothing to the user"
            )
        }
    }
}
