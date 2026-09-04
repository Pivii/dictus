// DictusCore/Sources/DictusCore/DetachedDeadline.swift
// A deadline the caller can actually honour, for work that cannot be cancelled (#427).
import Foundation

/// Thrown by `withDetachedDeadline` when the budget runs out before the operation
/// finishes. It says the work was late, never that it failed: at the moment this is
/// thrown the operation is by definition still running.
public struct DeadlineExpired: Error, Equatable {
    /// The budget that was applied, so the caller can put the same number in its log
    /// line and its message rather than remembering it separately.
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }
}

/// Runs `operation` under a deadline, and stops waiting on it when the deadline
/// expires — without pretending the operation stopped.
///
/// WHY THIS EXISTS, and why it is not a task group (issue #427):
/// the obvious spelling is `withThrowingTaskGroup` with the work in one child and a
/// `Task.sleep` in the other, first-to-finish wins, `cancelAll()` on the way out. That
/// was the shipped implementation and it does not work, because **a task group cannot
/// return until every child task has finished**. `cancelAll()` is a cooperative
/// request; a child that never checks `Task.isCancelled` and never reaches a
/// cancellation-aware suspension point simply keeps running, and the group's implicit
/// drain waits for it. A Core ML compile is exactly such a child.
///
/// Measured on device on 2026-08-26: a **5 second** budget on a Turbo compile produced
/// its timeout error **212 seconds** later — approximately the full cost of the compile
/// it was supposed to cut short, which had by then completed and warmed the cache. The
/// budget was not a budget. It was a stopwatch reporting, after the fact, that the work
/// had taken longer than a number.
///
/// WHAT THIS DOES INSTEAD: the operation runs in an unstructured `Task.detached` that
/// nothing here ever awaits. The awaiting side waits on a one-shot latch that either
/// the operation or the deadline resolves, whichever gets there first. When the
/// deadline wins, this function throws and returns control to the caller *at the
/// deadline*, and the operation keeps running to completion on its own.
///
/// WHAT IT STILL CANNOT DO: stop the work. Nothing can stop a Core ML compile once it
/// has begun — it neither polls a cancellation flag nor offers a suspension point where
/// it could notice one. So the operation keeps burning CPU, and whatever hardware it
/// holds stays held. That is not a defect of this function, it is the shape of the
/// problem; what expiry buys is the only thing ever on offer, which is that the app
/// stops waiting.
///
/// WHAT NOBODY OWNS, THE OPERATION ALSO LOSES: an abandoned operation has no owner by
/// construction, so nothing keeps its process alive for it. On iOS that means the host
/// app leaving the foreground can suspend it or take it away entirely, and whatever the
/// operation was going to leave behind is lost with it. Observed on 2026-08-30 for a
/// Core ML compile; `ModelManager.downloadWhisperKitModel` carries the full reasoning
/// and the reasons nothing here tries to prevent it.
///
/// WHAT THE CALLER OWES: `onLateCompletion` fires, on the main actor, if and only if
/// the operation lands after the deadline already won. It is where anything the
/// abandoned work still owns gets handed back. A caller that holds a resource for the
/// duration of the operation MUST release it there rather than on the way out of the
/// throw, because on the way out of the throw the operation is still using it.
///
/// - Parameters:
///   - seconds: the budget. A non-positive value expires immediately rather than
///     trapping, so a bad catalogue entry cannot crash a download.
///   - operation: the work. Runs off the main actor at `.userInitiated`, which is the
///     priority the task-group child it replaces inherited.
///   - onLateCompletion: called only when the operation finishes after the deadline
///     expired, with whatever the operation produced.
/// - Returns: the operation's value, when it beats the deadline.
/// - Throws: `DeadlineExpired` when the deadline wins, or whatever the operation threw
///   when the operation wins.
@MainActor
public func withDetachedDeadline<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T,
    onLateCompletion: @escaping @MainActor @Sendable (Result<T, Error>) -> Void = { _ in }
) async throws -> T {
    let race = DeadlineRace<T>()

    // Deliberately not stored and deliberately never cancelled: cancelling it would do
    // nothing to the compile inside (see above), and holding a handle to it would only
    // invite a later reader to `await` it, which is the bug this function exists to fix.
    Task.detached(priority: .userInitiated) {
        let result: Result<T, Error>
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        if await race.settle(result) == false {
            // The deadline already won and the caller is long gone. This is the only
            // notification anyone gets that the abandoned work has actually landed.
            await onLateCompletion(result)
        }
    }

    let deadline = Task { @MainActor in
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds)) * 1_000_000_000)
        } catch {
            // Cancelled because the operation already won. Nothing to declare.
            return
        }
        _ = race.settle(.failure(DeadlineExpired(seconds: seconds)))
    }
    defer { deadline.cancel() }

    return try await race.value()
}

/// One-shot latch deciding which of the two arms above gets to answer the caller.
///
/// WHY MAIN-ACTOR ISOLATED rather than lock-guarded: both arms already end on the main
/// actor — the deadline runs there, and the detached arm hops there to settle — so the
/// isolation is free and it removes the `@unchecked Sendable` a lock would need. The
/// only work done under it is a nil check and a resume.
@MainActor
private final class DeadlineRace<T: Sendable> {
    private var outcome: Result<T, Error>?
    private var waiter: CheckedContinuation<T, Error>?

    /// Records the first result offered and wakes the caller if it is already waiting.
    /// Returns `true` to exactly one caller, ever: the arm that won.
    func settle(_ result: Result<T, Error>) -> Bool {
        guard outcome == nil else { return false }
        outcome = result
        if let waiter {
            self.waiter = nil
            waiter.resume(with: result)
        }
        return true
    }

    /// Waits for the winner. Call once; a second call would strand the first waiter.
    func value() async throws -> T {
        if let outcome { return try outcome.get() }
        return try await withCheckedThrowingContinuation { continuation in
            // No suspension point between the check and the store, so a result that
            // arrives in between is impossible and the continuation cannot be lost.
            if let outcome {
                continuation.resume(with: outcome)
            } else {
                waiter = continuation
            }
        }
    }
}
