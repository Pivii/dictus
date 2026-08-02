// DictusCore/Tests/DictusCoreTests/AppScenePhaseProbeTests.swift
// Tests for AppScenePhaseProbe — the App Group contract the keyboard extension reads
// to state, on its own log line, whether DictusApp had already backgrounded when iOS
// tore its controllers down (issue #281).
import XCTest
@testable import DictusCore

final class AppScenePhaseProbeTests: XCTestCase {

    /// A suite of its own: these tests write the same keys the app writes, and the
    /// shared App Group suite is live state on a developer machine.
    private let suiteName = "dictus.tests.appScenePhaseProbe"
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Markers

    func testMarkerRawValuesAreTheStringsTheLogCarries() {
        XCTAssertEqual(AppScenePhaseMarker.active.rawValue, "active")
        XCTAssertEqual(AppScenePhaseMarker.inactive.rawValue, "inactive")
        XCTAssertEqual(AppScenePhaseMarker.background.rawValue, "background")
        XCTAssertEqual(AppScenePhaseMarker.unknown.rawValue, "unknown")
    }

    // MARK: - Round trip

    func testRecordedPhaseIsReadBack() {
        AppScenePhaseProbe.record(.background, at: Date(), into: defaults)

        XCTAssertTrue(
            AppScenePhaseProbe.describe(from: defaults).contains("appPhase=background"),
            "The phase the app publishes is the phase the keyboard reports"
        )
    }

    func testAgeIsMeasuredFromTheRecordedTimestamp() {
        let written = Date(timeIntervalSince1970: 1_000)
        AppScenePhaseProbe.record(.active, at: written, into: defaults)

        let description = AppScenePhaseProbe.describe(
            at: Date(timeIntervalSince1970: 1_002.5),
            from: defaults
        )

        XCTAssertTrue(description.contains("appPhaseAgeMs=2500"), description)
    }

    func testALaterRecordReplacesTheEarlierOne() {
        AppScenePhaseProbe.record(.background, at: Date(timeIntervalSince1970: 1_000), into: defaults)
        AppScenePhaseProbe.record(.active, at: Date(timeIntervalSince1970: 1_001), into: defaults)

        let description = AppScenePhaseProbe.describe(
            at: Date(timeIntervalSince1970: 1_001),
            from: defaults
        )

        XCTAssertTrue(description.contains("appPhase=active"), description)
        XCTAssertTrue(description.contains("appPhaseAgeMs=0"), description)
    }

    // MARK: - Nothing published

    /// The keyboard can be torn down in an install where the app has never run since
    /// the probe shipped. It must say so rather than invent a phase, since the whole
    /// point of the field is to be trusted about ordering.
    func testUnwrittenPhaseReadsUnknownWithASentinelAge() {
        let description = AppScenePhaseProbe.describe(from: defaults)

        XCTAssertTrue(description.contains("appPhase=unknown"), description)
        XCTAssertTrue(description.contains("appPhaseAgeMs=-1"), description)
    }

    /// A value written by a build whose marker set differs — or corrupted by hand —
    /// is reported as unknown rather than echoed into the log.
    func testUnrecognisedPhaseReadsUnknown() {
        defaults.set("hibernating", forKey: SharedKeys.appScenePhase)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.appScenePhaseTimestamp)

        XCTAssertTrue(
            AppScenePhaseProbe.describe(from: defaults).contains("appPhase=unknown"),
            "An unrecognised marker must not reach the log verbatim"
        )
    }

    /// An `unknown` the app actually reported keeps its age, and must not be collapsed
    /// into the never-published case: "the app moved to a phase this build cannot name,
    /// 500 ms ago" and "the app has never published anything" are different answers to
    /// the ordering question the probe exists to settle.
    func testReportedUnknownKeepsItsAge() {
        AppScenePhaseProbe.record(.unknown, at: Date(timeIntervalSince1970: 1_000), into: defaults)

        let description = AppScenePhaseProbe.describe(
            at: Date(timeIntervalSince1970: 1_000.5),
            from: defaults
        )

        XCTAssertTrue(description.contains("appPhase=unknown"), description)
        XCTAssertTrue(description.contains("appPhaseAgeMs=500"), description)
    }

    /// A phase with no timestamp cannot be aged, so it cannot be trusted, so it is
    /// unknown — and the sentinel age keeps that unambiguous with a real measurement.
    func testPhaseWithoutTimestampReadsUnknown() {
        defaults.set(AppScenePhaseMarker.background.rawValue, forKey: SharedKeys.appScenePhase)

        let description = AppScenePhaseProbe.describe(from: defaults)

        XCTAssertTrue(description.contains("appPhase=unknown"), description)
        XCTAssertTrue(description.contains("appPhaseAgeMs=-1"), description)
    }

    // MARK: - Cold start flag

    func testColdStartFlagIsCarriedOnTheSameLine() {
        AppScenePhaseProbe.record(.background, into: defaults)
        defaults.set(true, forKey: SharedKeys.coldStartActive)

        XCTAssertTrue(
            AppScenePhaseProbe.describe(from: defaults).contains("coldStart=true"),
            "The #281 window only opens during a cold-start handoff"
        )
    }

    func testColdStartFlagIsReportedEvenWithNoPhasePublished() {
        defaults.set(true, forKey: SharedKeys.coldStartActive)

        XCTAssertTrue(
            AppScenePhaseProbe.describe(from: defaults).contains("coldStart=true"),
            "The two halves of the line are independent"
        )
    }
}
