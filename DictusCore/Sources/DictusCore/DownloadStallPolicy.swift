// DictusCore/Sources/DictusCore/DownloadStallPolicy.swift
// When a parked model download is worth telling the user about (#492).
import Foundation

/// Decides whether a model download that has stopped moving is a failure the user
/// should be shown, or a pause they have no reason to hear about.
///
/// WHY THIS EXISTS (issue #492). The transfer runs in a
/// `URLSessionConfiguration.background` session, and a background session waits for
/// connectivity by definition: lose the network mid-download and iOS parks the tasks
/// instead of failing them. Nothing is delivered, nothing is logged, and the progress
/// bar stops at the byte it reached. Measured on device on 2026-09-05: three minutes and
/// twelve seconds of airplane mode produced not one line from the download layer, and
/// the only way out was a force quit. `timeoutIntervalForRequest` does not cover it —
/// that is an IDLE timeout on a running task, and a parked task is not idling, it is
/// not running.
///
/// WHY NOT A WALL-CLOCK TIMEOUT. A plain "no progress for N seconds" detector is what
/// issue #449 removed, and for a good reason: it fired on a user who simply left Dictus
/// for a minute, and the retry it triggered restarted a 445 MB file from byte zero. The
/// same detector was, at the same time, the only thing that caught a real network loss.
/// Both went at once, which is how #492 was created by fixing #449.
///
/// WHAT SEPARATES THE TWO. Not the duration — the two look identical on a stopwatch.
/// Three clauses, all of which have to hold at the same time:
///
/// 1. **No progress** for the grace period. Necessary, and on its own worth nothing.
/// 2. **The app is foregrounded.** A backgrounded app has a user who is somewhere else;
///    there is nothing to show them and nothing they could do about it. This is the
///    clause a legitimate backgrounding fails.
/// 3. **There is no network path.** `NWPathMonitor` answers this, and it is the clause
///    that makes the report actionable: "check your connection" is only useful advice
///    when the connection is in fact gone.
///
/// WHY THE CLOCK STARTS AT THE LATEST ONSET. Each clause carries the moment it started
/// holding, and the grace period is measured from the last of them. Otherwise a clause
/// could be satisfied retroactively: a user who spent three minutes in another app with
/// the network off would come back to an error that fired the instant they looked at the
/// screen, having never been given the grace period while they could see it. The rule is
/// that all three must hold *continuously* for the whole grace period, and the maximum
/// of the three onsets is where that window can first have started.
/// The two conditions outside a transfer that `DownloadStallPolicy` reads, as one value.
///
/// Each field is the instant its condition started holding, and `nil` means it does not
/// hold — or has not been observed yet, which must answer the same way: an unread network
/// monitor may never look like an outage.
public struct DownloadStallConditions: Sendable, Equatable {
    /// When the app last reached the foreground, `nil` when it is backgrounded.
    public let foregroundSince: Date?
    /// When the device last lost every network path, `nil` when it has one.
    public let offlineSince: Date?

    public init(foregroundSince: Date?, offlineSince: Date?) {
        self.foregroundSince = foregroundSince
        self.offlineSince = offlineSince
    }

    /// Nothing observed yet — the state a watcher starts in and returns to when it stops.
    public static let unknown = DownloadStallConditions(foregroundSince: nil, offlineSince: nil)
}

public enum DownloadStallPolicy {

    /// Seconds all three clauses must hold before a parked transfer is reported.
    ///
    /// WHY 15 AND NOT 30. Thirty seconds was the old idle-byte timeout (#207), chosen to
    /// avoid killing a slow-but-live foreground transfer, and it has nothing to say about
    /// this predicate: a live transfer fails clause 3 whatever its speed. The only thing
    /// left for the grace period to absorb is a *transient* unsatisfied reading — a
    /// Wi-Fi to cellular handover, a lift, a router blink — all of which are a few
    /// seconds. Fifteen clears them with room to spare, and is short enough that a user
    /// who has just turned on airplane mode still connects the message to what they did.
    public static let offlineGrace: TimeInterval = 15

    /// The instant at which a parked transfer becomes reportable, or `nil` when it never
    /// will under the state given.
    ///
    /// - Parameters:
    ///   - lastProgressAt: when a byte last arrived for this transfer.
    ///   - foregroundSince: when the app last reached the foreground, `nil` when it is
    ///     backgrounded or has not been observed yet.
    ///   - offlineSince: when the device last lost every network path, `nil` when a path
    ///     exists or has not been observed yet.
    ///   - grace: how long all three clauses must hold.
    /// - Returns: the deadline, or `nil` when a clause is not met at all.
    public static func deadline(
        lastProgressAt: Date,
        foregroundSince: Date?,
        offlineSince: Date?,
        grace: TimeInterval = offlineGrace
    ) -> Date? {
        guard let foregroundSince, let offlineSince else { return nil }
        let latestOnset = max(lastProgressAt, foregroundSince, offlineSince)
        return latestOnset.addingTimeInterval(max(0, grace))
    }

    /// Whether the transfer should be reported to the user as of `now`.
    ///
    /// `nil` for either onset means "not in that state, or not known yet", and both
    /// answer false — an unread `NWPathMonitor` must never look like an outage.
    public static func hasStalled(
        now: Date,
        lastProgressAt: Date,
        foregroundSince: Date?,
        offlineSince: Date?,
        grace: TimeInterval = offlineGrace
    ) -> Bool {
        guard let deadline = deadline(
            lastProgressAt: lastProgressAt,
            foregroundSince: foregroundSince,
            offlineSince: offlineSince,
            grace: grace
        ) else {
            return false
        }
        return now >= deadline
    }

    /// Whether the two conditions a watcher reported are still the ones holding now.
    ///
    /// WHY THIS EXISTS. A watcher reads the conditions on its own queue and whatever acts
    /// on that reading runs somewhere else, later — so the decision is always taken on a
    /// reading of the past. That gap is not theoretical here: the queue the decision runs
    /// on is the download session's delegate queue, and the moment the network comes back
    /// is exactly the moment it fills up, because every parked task resumes at once and
    /// starts delivering bytes. A reading taken while the device was offline can therefore
    /// arrive for judgement after the device is online again, and be judged against a
    /// clock that has meanwhile passed the grace period. Acting on it would cancel a
    /// download that is, at that instant, working — the false alarm issue #449 removed,
    /// reached through another door.
    ///
    /// WHY IDENTITY OF THE ONSETS AND NOT A TIME COMPARISON. Both fields are the instant
    /// a condition started holding, written once per transition and never edited. So the
    /// same value in both readings means the condition was never interrupted between
    /// them, and a different one means it stopped and started again — which restarts the
    /// grace period, whatever the two instants happen to be. `nil` in `current` means it
    /// simply stopped. All three are refused.
    ///
    /// Conditions that started holding only *after* the reading are refused too: `current`
    /// then carries an onset `observed` never had. Nothing is lost by that — the next tick
    /// reports them, two seconds later, on a reading of their own.
    public static func conditionsHeldContinuously(
        observed: DownloadStallConditions,
        current: DownloadStallConditions
    ) -> Bool {
        observed.foregroundSince != nil
            && observed.offlineSince != nil
            && observed == current
    }

    /// The whole decision one watcher tick makes: whether a transfer that has stopped
    /// moving should be reported to the user.
    ///
    /// The only entry point a caller acting on a tick should use. `observed` is what the
    /// watcher read when it raised the tick; `current` is what it says at the moment the
    /// decision is being taken, which is the one that governs — a reading of the past may
    /// raise the question but never answers it.
    public static func shouldReportStall(
        now: Date,
        lastProgressAt: Date,
        observed: DownloadStallConditions,
        current: DownloadStallConditions,
        grace: TimeInterval = offlineGrace
    ) -> Bool {
        guard conditionsHeldContinuously(observed: observed, current: current) else {
            return false
        }
        return hasStalled(
            now: now,
            lastProgressAt: lastProgressAt,
            foregroundSince: current.foregroundSince,
            offlineSince: current.offlineSince,
            grace: grace
        )
    }
}
