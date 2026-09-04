import XCTest
@testable import DictusCore

/// What `withDetachedDeadline` promises, tested against the one property the primitive
/// it replaces did not have: that the caller gets control back **at** the deadline,
/// while the operation is still running (issue #427).
///
/// WHY THIS SUITE CAN EXIST AT ALL: the thing under test is the concurrency shape, not
/// Core ML. A `Task.sleep` is an operation that outlives its budget just as well as a
/// compile does, and it needs no ANE — which is what makes the fix testable on the Mac
/// when the failure it fixes is device-only.
///
/// Budgets are whole seconds because the catalogue is, so every test here pays about a
/// second of wall clock. That is the price of testing a deadline.
final class DetachedDeadlineTests: XCTestCase {

    /// The whole point. The old task-group implementation failed exactly here: it
    /// returned only once the operation had finished, so a 5s budget reported failure
    /// after 212s on device.
    @MainActor
    func testTheCallerGetsControlBackAtTheDeadlineNotAtTheEndOfTheOperation() async {
        let operationFinished = Flag()
        let started = Date()

        do {
            _ = try await withDetachedDeadline(seconds: 1) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await operationFinished.raise()
                return 42
            }
            XCTFail("the deadline should have won against a 4s operation")
        } catch let expiry as DeadlineExpired {
            XCTAssertEqual(expiry.seconds, 1)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let waited = Date().timeIntervalSince(started)
        XCTAssertLessThan(waited, 2.5, "the caller waited \(waited)s on a 1s budget")
        XCTAssertFalse(
            operationFinished.isRaised,
            "the operation must still be running when the caller is released"
        )
    }

    /// The operation is abandoned, not cancelled. This is what makes the outcome
    /// acceptable on device: the compile runs on and leaves a warm Core ML cache, so
    /// the retry the user is invited to make is the cheap one.
    @MainActor
    func testAnAbandonedOperationRunsToCompletionAfterTheDeadline() async {
        let operationFinished = Flag()

        _ = try? await withDetachedDeadline(seconds: 1) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await operationFinished.raise()
            return 42
        }
        XCTAssertFalse(operationFinished.isRaised)

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertTrue(
            operationFinished.isRaised,
            "expiry must not stop the operation, only stop waiting on it"
        )
    }

    /// The late hook is the seam a caller needs to hand back anything the abandoned
    /// work still holds — in `ModelManager` that is the Neural Engine, which an
    /// abandoned compile is still sitting on and must keep until it lands.
    @MainActor
    func testLateCompletionFiresOnceWithTheOperationsRealResult() async {
        let landings = Counter()

        _ = try? await withDetachedDeadline(seconds: 1) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return 42
        } onLateCompletion: { result in
            landings.record(try? result.get())
        }

        XCTAssertEqual(landings.count, 0, "nothing has landed yet at the deadline")

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertEqual(landings.count, 1)
        XCTAssertEqual(landings.lastValue, 42)
    }

    /// An operation that beats its budget behaves like a plain `await`: its value comes
    /// straight back and nothing is reported as abandoned.
    @MainActor
    func testAnOperationThatBeatsItsBudgetReturnsNormally() async throws {
        let landings = Counter()

        let value = try await withDetachedDeadline(seconds: 5) {
            42
        } onLateCompletion: { result in
            landings.record(try? result.get())
        }

        XCTAssertEqual(value, 42)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(landings.count, 0, "a winning operation never counts as late")
    }

    /// A real failure must reach the caller as itself. `ModelManager` routes on this:
    /// an E5 bundle error deletes the downloaded files, a deadline keeps them (#405).
    /// Collapsing the two into one error would delete a gigabyte on every timeout.
    @MainActor
    func testTheOperationsOwnErrorSurvivesInsteadOfBecomingADeadline() async {
        do {
            _ = try await withDetachedDeadline(seconds: 5) { () async throws -> Int in
                throw CompileFailure()
            }
            XCTFail("the operation's failure should have propagated")
        } catch is DeadlineExpired {
            XCTFail("a failing operation was reported as a deadline expiry")
        } catch {
            XCTAssertTrue(error is CompileFailure)
        }
    }

    /// A catalogue entry with a nonsensical budget must fail the download, not trap the
    /// process. `ModelInfoTests` keeps every shipped entry positive; this covers the
    /// identifier that came from an older build and resolved to something odd.
    @MainActor
    func testANonPositiveBudgetExpiresInsteadOfTrapping() async {
        do {
            _ = try await withDetachedDeadline(seconds: 0) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return 42
            }
            XCTFail("a zero budget cannot be survived")
        } catch let expiry as DeadlineExpired {
            XCTAssertEqual(expiry.seconds, 0)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

/// The failure an operation raises on its own, as opposed to a deadline expiring.
private struct CompileFailure: Error {}

/// Set once from the detached operation, read from the test. Main-actor isolation is
/// what makes it safe to share across that boundary without a lock.
@MainActor
private final class Flag {
    private(set) var isRaised = false

    func raise() {
        isRaised = true
    }
}

/// Records what the late-completion hook was handed, and how often.
@MainActor
private final class Counter {
    private(set) var count = 0
    private(set) var lastValue: Int?

    func record(_ value: Int?) {
        count += 1
        lastValue = value
    }
}
