// DictusCore/Tests/DictusCoreTests/MicAvailabilityPolicyTests.swift
import XCTest
@testable import DictusCore

/// Issue #250 — the mic button reflects a model load before the tap.
/// These cover the two traps: flicker on fast loads, and a `loading` value
/// stranded in the App Group by a force-quit disabling the button forever.
final class MicAvailabilityPolicyTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func availability(
        _ state: ModelLoadState,
        startedAt: Date?,
        after seconds: TimeInterval
    ) -> MicAvailability {
        MicAvailabilityPolicy.availability(
            state: state,
            loadStartedAt: startedAt,
            now: start.addingTimeInterval(seconds)
        )
    }

    // MARK: - Non-loading states never dim the button

    func testIdleStateIsAvailable() {
        XCTAssertEqual(availability(.idle, startedAt: start, after: 10), .available)
    }

    func testReadyStateIsAvailable() {
        XCTAssertEqual(availability(.ready, startedAt: start, after: 10), .available)
    }

    // MARK: - Flicker guard

    func testLoadingIsNotSurfacedImmediately() {
        XCTAssertEqual(availability(.loading, startedAt: start, after: 0), .available)
    }

    func testFastLoadNeverSurfaces() {
        // Parakeet / warm-app path: resolves well inside the surface delay.
        let justBefore = MicAvailabilityPolicy.surfaceDelay - 0.01
        XCTAssertEqual(availability(.loading, startedAt: start, after: justBefore), .available)
    }

    func testSlowLoadSurfacesOncePastTheDelay() {
        XCTAssertEqual(
            availability(.loading, startedAt: start, after: MicAvailabilityPolicy.surfaceDelay),
            .modelLoading
        )
    }

    func testWhisperMediumWindowStaysSurfaced() {
        // ~10s was the window measured on whisper-medium in the #250 report.
        XCTAssertEqual(availability(.loading, startedAt: start, after: 10), .modelLoading)
    }

    // MARK: - Stale `loading` bound

    func testStaleLoadingStopsDimmingAtCutoff() {
        XCTAssertEqual(
            availability(.loading, startedAt: start, after: MicAvailabilityPolicy.staleLoadCutoff),
            .available
        )
    }

    func testLoadingStrandedByForceQuitNeverDisablesTheButton() {
        // Force-quit mid-load an hour ago: the value is still `loading` and
        // nothing is left to move it on. The button must be normal.
        XCTAssertEqual(availability(.loading, startedAt: start, after: 3600), .available)
    }

    func testUnknownAgeIsTreatedAsUntrustworthy() {
        XCTAssertEqual(availability(.loading, startedAt: nil, after: 10), .available)
    }

    func testClockMovedBackwardsDoesNotDimTheButton() {
        // A negative elapsed means the write timestamp is in the future — we
        // cannot age it, so we must not dim.
        let inTheFuture = start.addingTimeInterval(120)
        XCTAssertEqual(availability(.loading, startedAt: inTheFuture, after: 0), .available)
    }

    // MARK: - Re-evaluation window

    func testReevaluationRunsWhileALoadIsYoung() {
        XCTAssertTrue(MicAvailabilityPolicy.needsReevaluation(
            state: .loading,
            loadStartedAt: start,
            now: start.addingTimeInterval(1)
        ))
    }

    func testReevaluationStopsOnceLoadingIsStale() {
        XCTAssertFalse(MicAvailabilityPolicy.needsReevaluation(
            state: .loading,
            loadStartedAt: start,
            now: start.addingTimeInterval(MicAvailabilityPolicy.staleLoadCutoff)
        ))
    }

    func testReevaluationStopsWhenNotLoading() {
        XCTAssertFalse(MicAvailabilityPolicy.needsReevaluation(
            state: .ready,
            loadStartedAt: start,
            now: start.addingTimeInterval(1)
        ))
    }

    // MARK: - Thresholds are the documented values

    func testThresholdValues() {
        XCTAssertEqual(MicAvailabilityPolicy.surfaceDelay, 0.6)
        XCTAssertEqual(MicAvailabilityPolicy.staleLoadCutoff, 30)
    }
}
