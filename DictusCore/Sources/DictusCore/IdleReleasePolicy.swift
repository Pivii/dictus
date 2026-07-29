// DictusCore/Sources/DictusCore/IdleReleasePolicy.swift
// Extracted decision rules for releasing the warm audio engine after an idle period.
// Testable in isolation -- no AVFoundation dependency.

import Foundation

/// Decides whether the warm audio engine may be, and should be, torn down.
///
/// WHY extracted from `UnifiedAudioEngine` (issue #256):
/// `UnifiedAudioEngine` is `@MainActor` and owns a live `AVAudioEngine`, so none
/// of its lifecycle can be exercised from a unit test. The release decision
/// itself is pure — it reads four facts and returns a Bool — and it is exactly
/// where #256's second defect lived: the wall-clock backstop checked only the
/// elapsed idle time, never whether a recording was running, so a stale idle
/// anchor could tear the engine down mid-dictation. Moving the predicate into
/// DictusCore is what makes that rule assertable at all. Same pattern as
/// `LiveActivityStateMachine`.
///
/// WHY an enum with statics (not a struct): there is no state to carry. The
/// caller owns the facts; this type only combines them.
public enum IdleReleasePolicy {

    /// Whether tearing the warm state down is permissible *at all*, independent
    /// of how long the engine has been idle.
    ///
    /// - Parameters:
    ///   - isWarm: the engine is running, or the audio session is still
    ///     configured. When false there is nothing to release, and the caller
    ///     should no-op rather than emit a second `warmStateReleased` log line
    ///     and a redundant Darwin post.
    ///   - isRecording: a dictation is accumulating samples right now. Releasing
    ///     would kill it mid-sentence, so this always wins.
    /// - Returns: true when a release is allowed to proceed.
    public static func canRelease(isWarm: Bool, isRecording: Bool) -> Bool {
        isWarm && !isRecording
    }

    /// Whether the idle window has elapsed, measured on the wall clock.
    ///
    /// WHY re-check the wall clock instead of trusting the armed timer: the
    /// `DispatchQueue.main.asyncAfter` that arms the release can be delayed or
    /// coalesced while the app is backgrounded. Any code path that regains a
    /// reliable runloop re-derives the answer from timestamps.
    ///
    /// A nil `idleSince` means the engine is not in the warm-idle state — either
    /// nothing was ever armed, or a recording is in progress — so nothing is due.
    /// A clock that moved backwards yields a negative elapsed time and is treated
    /// as "not due", which keeps the engine warm rather than killing it early.
    public static func isIdleWindowElapsed(
        idleSince: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let idleSince else { return false }
        return now.timeIntervalSince(idleSince) >= interval
    }

    /// Composite used by the wall-clock backstop: release only if permitted AND due.
    public static func shouldRelease(
        isWarm: Bool,
        isRecording: Bool,
        idleSince: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        canRelease(isWarm: isWarm, isRecording: isRecording)
            && isIdleWindowElapsed(idleSince: idleSince, now: now, interval: interval)
    }
}
