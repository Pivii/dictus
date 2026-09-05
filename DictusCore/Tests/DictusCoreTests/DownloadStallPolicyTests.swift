// DictusCore/Tests/DictusCoreTests/DownloadStallPolicyTests.swift
// The three clauses that tell a network loss from a backgrounding (#492).
import XCTest
@testable import DictusCore

final class DownloadStallPolicyTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_757_000_000)
    private let grace: TimeInterval = 15

    private func at(_ seconds: TimeInterval) -> Date {
        epoch.addingTimeInterval(seconds)
    }

    // MARK: - The case the issue is about

    /// Airplane mode, user watching: all three clauses hold, and the grace period runs out.
    func testReportsWhenForegroundedAndOfflineWithNoProgress() {
        XCTAssertTrue(DownloadStallPolicy.hasStalled(
            now: at(20),
            lastProgressAt: at(0),
            foregroundSince: at(0),
            offlineSince: at(2),
            grace: grace
        ))
    }

    // MARK: - The case #449 removed, which must not come back

    /// A plain backgrounding: the network is fine and nobody is looking. This is the
    /// false alarm the old wall-clock detector produced, and the whole reason the
    /// predicate has three clauses.
    func testSilentWhenBackgroundedWithANetworkPath() {
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(600),
            lastProgressAt: at(0),
            foregroundSince: nil,
            offlineSince: nil,
            grace: grace
        ))
    }

    /// Backgrounded AND offline: still nothing to say, because there is nobody to say
    /// it to and nothing they could do from another app.
    func testSilentWhenBackgroundedEvenWithNoNetworkPath() {
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(600),
            lastProgressAt: at(0),
            foregroundSince: nil,
            offlineSince: at(5),
            grace: grace
        ))
    }

    /// Foregrounded, no bytes for ten minutes, but the device has a route: a slow or
    /// wedged server is not this predicate's business, and reporting it would be the
    /// wall-clock timeout again under another name.
    func testSilentWhenForegroundedWithANetworkPath() {
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(600),
            lastProgressAt: at(0),
            foregroundSince: at(0),
            offlineSince: nil,
            grace: grace
        ))
    }

    // MARK: - The clock starts at the latest onset

    /// Three minutes in another app with the network off, then a return: the grace
    /// period starts at the return, not at the last byte. Firing on the first frame
    /// would give the user an error for a window they never saw.
    func testGracePeriodRestartsOnReturningToTheForeground() {
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(181),
            lastProgressAt: at(0),
            foregroundSince: at(180),
            offlineSince: at(1),
            grace: grace
        ))
        XCTAssertTrue(DownloadStallPolicy.hasStalled(
            now: at(195),
            lastProgressAt: at(0),
            foregroundSince: at(180),
            offlineSince: at(1),
            grace: grace
        ))
    }

    /// The same rule for the path: a download that was running fine and lost the
    /// network a second ago gets the full grace period from the loss.
    func testGracePeriodRestartsWhenTheNetworkDrops() {
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(101),
            lastProgressAt: at(95),
            foregroundSince: at(0),
            offlineSince: at(100),
            grace: grace
        ))
        XCTAssertTrue(DownloadStallPolicy.hasStalled(
            now: at(115),
            lastProgressAt: at(95),
            foregroundSince: at(0),
            offlineSince: at(100),
            grace: grace
        ))
    }

    /// A byte that arrives after the network reading is the latest onset, and it is the
    /// one that matters: bytes are proof the transfer is alive whatever a monitor says.
    func testProgressResetsTheGracePeriod() {
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(110),
            lastProgressAt: at(100),
            foregroundSince: at(0),
            offlineSince: at(50),
            grace: grace
        ))
    }

    // MARK: - Boundary and shape

    func testFiresExactlyAtTheDeadlineAndNotOneInstantBefore() {
        let arguments = (
            lastProgressAt: at(0),
            foregroundSince: at(0),
            offlineSince: at(0)
        )
        XCTAssertFalse(DownloadStallPolicy.hasStalled(
            now: at(grace - 0.001),
            lastProgressAt: arguments.lastProgressAt,
            foregroundSince: arguments.foregroundSince,
            offlineSince: arguments.offlineSince,
            grace: grace
        ))
        XCTAssertTrue(DownloadStallPolicy.hasStalled(
            now: at(grace),
            lastProgressAt: arguments.lastProgressAt,
            foregroundSince: arguments.foregroundSince,
            offlineSince: arguments.offlineSince,
            grace: grace
        ))
    }

    func testDeadlineIsTheLatestOnsetPlusTheGracePeriod() {
        XCTAssertEqual(
            DownloadStallPolicy.deadline(
                lastProgressAt: at(10),
                foregroundSince: at(40),
                offlineSince: at(25),
                grace: grace
            ),
            at(55)
        )
    }

    /// An unread `NWPathMonitor` reports `nil`, not an outage: nothing may fire before
    /// the first real reading of either clause.
    func testNoDeadlineWhileEitherClauseIsUnknown() {
        XCTAssertNil(DownloadStallPolicy.deadline(
            lastProgressAt: at(0),
            foregroundSince: nil,
            offlineSince: at(0),
            grace: grace
        ))
        XCTAssertNil(DownloadStallPolicy.deadline(
            lastProgressAt: at(0),
            foregroundSince: at(0),
            offlineSince: nil,
            grace: grace
        ))
    }

    /// The shipped grace period, asserted so a change to it is a deliberate edit to a
    /// test and not a silent one-character change to a constant.
    func testShippedGracePeriodIsFifteenSeconds() {
        XCTAssertEqual(DownloadStallPolicy.offlineGrace, 15)
    }
}
