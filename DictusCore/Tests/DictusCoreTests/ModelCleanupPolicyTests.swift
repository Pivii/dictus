import XCTest
@testable import DictusCore

/// Coverage for the "may a failed preparation delete the downloaded files?" rule
/// (issue #405).
///
/// These tests exist because `ModelManager` itself cannot be unit-tested: it is
/// `@MainActor`, drives WhisperKit/FluidAudio and lives in the DictusApp target.
/// The predicate below is the part of #405 that was actually wrong, so it is the
/// part worth pinning down.
final class ModelCleanupPolicyTests: XCTestCase {

    func testDownloadFailureKeepsTheFiles() {
        // Issue #210 resume policy: every file on disk is complete, a retry skips it.
        XCTAssertFalse(ModelCleanupPolicy.shouldCleanUpFiles(
            downloadPhaseCompleted: false,
            isPrewarmTimeout: false
        ))
    }

    func testPrewarmTimeoutKeepsTheFiles() {
        // The #405 regression: a Turbo compile that ran out of clock used to cost
        // the user a 1.05 GB re-download.
        XCTAssertFalse(ModelCleanupPolicy.shouldCleanUpFiles(
            downloadPhaseCompleted: true,
            isPrewarmTimeout: true
        ))
    }

    func testOtherPrewarmFailureStillCleansUp() {
        // Issue #104: an E5 bundle failure leaves an unusable Core ML cache that
        // makes every retry fail identically until it is cleared.
        XCTAssertTrue(ModelCleanupPolicy.shouldCleanUpFiles(
            downloadPhaseCompleted: true,
            isPrewarmTimeout: false
        ))
    }

    func testATimeoutBeforeTheDownloadCompletedIsStillAKeep() {
        // Not reachable today (the deadline guard only wraps the prewarm), but the
        // rule must not become "clean up" if a future timeout ever fires earlier.
        XCTAssertFalse(ModelCleanupPolicy.shouldCleanUpFiles(
            downloadPhaseCompleted: false,
            isPrewarmTimeout: true
        ))
    }

    func testCleanupIsTheSingleExceptionInTheTruthTable() {
        // One deleting case out of four -- stated as a whole so a future edit that
        // widens the deletion has to change this assertion on purpose.
        let deleting = [(true, false), (true, true), (false, true), (false, false)]
            .filter { ModelCleanupPolicy.shouldCleanUpFiles(
                downloadPhaseCompleted: $0.0,
                isPrewarmTimeout: $0.1
            ) }
        XCTAssertEqual(deleting.count, 1)
        XCTAssertTrue(deleting[0] == (true, false))
    }
}
