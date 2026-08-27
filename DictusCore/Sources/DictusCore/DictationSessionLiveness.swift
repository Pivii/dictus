// DictusCore/Sources/DictusCore/DictationSessionLiveness.swift
// Decides whether an active dictation status in the App Group still has a live
// process behind it. Testable in isolation -- no UserDefaults, no AVFoundation.

import Foundation

/// What the shared dictation state says about the process that wrote it.
public enum DictationSessionLiveness: String, Equatable, Sendable {
    /// The stored status describes no dictation in flight. Nothing to reconcile.
    case notActive
    /// An active status backed by a heartbeat fresh enough to prove the writer is alive.
    case live
    /// An active status with no heartbeat that can speak about it. Not evidence of death.
    case unproven
    /// An active status whose heartbeat stopped. The writing process is gone.
    case orphaned
}

/// Reads the shared dictation state and says whether a process still owns it.
///
/// WHY this exists (issue #261): when iOS terminates DictusApp mid-dictation,
/// `SharedKeys.dictationStatus` keeps saying `recording` and nothing audits it.
/// A keyboard extension rebuilt afterwards faithfully restores a recording overlay
/// for a session no process is running, the user keeps talking into nothing, and
/// their stop taps reach a dead listener.
///
/// WHY the heartbeat is the evidence and the session id is not: there is no session
/// id in the App Group at all. `KeyboardState.activeSessionID` is in-memory in the
/// extension process, so `sessionID=none` is what *every* rebuilt keyboard reports,
/// whether or not the app is healthy. `SharedKeys.recordingHeartbeat` is the only
/// value written by the process that would have died -- `UnifiedAudioEngine` writes
/// it from the audio thread.
///
/// WHY an enum with statics (not a struct): there is no state to carry. The caller
/// owns the facts; this type only combines them. Same pattern as `IdleReleasePolicy`.
public enum DictationSessionLivenessPolicy {

    /// How stale the heartbeat must be, while the stored status is `recording`,
    /// before the writer is declared gone.
    ///
    /// WHY 4 s: the audio thread writes the heartbeat at 1 Hz while recording, and
    /// that path `synchronize()`s every 200 ms, so four missed beats is a wide margin
    /// over both the cadence and cross-process lag.
    ///
    /// WHY it has to be under 5 s, which is the constraint that actually fixes #261's
    /// first device failure: `KeyboardState`'s watchdog resets the status once waveform
    /// data is 5 s stale, and both ages start ticking from the same instant -- the app
    /// dies and stops writing waveform and heartbeat together. A threshold above 5 s is
    /// therefore unreachable by construction: the watchdog resets to `.idle` first and
    /// its own guard then stops the timer. The first shipped version used 8 s for both
    /// states and, on device, never fired once for exactly that reason.
    public static let recordingStaleThreshold: TimeInterval = 4

    /// The same, while the stored status is `transcribing` or `processing`.
    ///
    /// WHY 8 s and not 4 s: recording has stopped, so the audio thread has fallen back
    /// to its warm-idle path, which writes only every 3 s (#106 Phase C, sized to stay
    /// under the watchdog's 5 s threshold). Judging that cadence by the recording
    /// threshold would condemn every transcription that runs longer than four seconds.
    ///
    /// WHY `processing` shares it rather than getting a longer one of its own (#267):
    /// this threshold judges the heartbeat's *cadence*, not the stage's length. Both
    /// post-recording stages run against the same 3 s warm-idle writer, so an LLM stage
    /// that takes a minute is no more suspicious at second 50 than at second 5 -- what
    /// would be suspicious is the same three missed beats.
    public static let transcribingStaleThreshold: TimeInterval = 8

    /// Whether `status` describes a dictation that some process should be driving.
    ///
    /// WHY an exhaustive switch and not a `Set`: adding a case to `DictationStatus`
    /// must stop the compiler here rather than silently fall through to "nothing is
    /// in flight". That is how `processing` (#267) got here instead of being missed.
    public static func isActive(_ status: DictationStatus) -> Bool {
        switch status {
        case .requested, .recording, .transcribing, .processing:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    /// How long the heartbeat may go quiet, for a given stored status, before the
    /// writer is declared gone. Nil for statuses that are never judged this way.
    public static func staleThreshold(for status: DictationStatus) -> TimeInterval? {
        switch status {
        case .recording:
            return recordingStaleThreshold
        case .transcribing, .processing:
            return transcribingStaleThreshold
        case .requested, .idle, .ready, .failed:
            return nil
        }
    }

    /// What the shared state says about the process behind it.
    ///
    /// - Parameters:
    ///   - status: the stored `SharedKeys.dictationStatus`, or nil when unset or
    ///     unrecognised.
    ///   - heartbeat: the stored `SharedKeys.recordingHeartbeat` as seconds since
    ///     1970, or nil when the key is absent.
    ///   - localSessionStartedAt: when *this* process started the dictation it
    ///     currently owns, as seconds since 1970. Nil when it owns none.
    ///   - now: seconds since 1970.
    ///
    /// ### The rule that carries this
    ///
    /// **A heartbeat can only speak about a session it postdates.** One older than the
    /// moment this process started its current session belongs to an earlier session
    /// and says nothing about this one, however stale it looks.
    ///
    /// That is not a refinement, it is the load-bearing clause. Without it, on device
    /// (2026-08-03, build 25): a watchdog reset left a corpse heartbeat behind at
    /// 14:36:51, the user tapped the mic at 14:37:02, the app cold-started and wrote
    /// `recording` at 14:37:03, and the keyboard judged that one-second-old session by
    /// the eleven-second-old heartbeat, declared it orphaned and killed it. The keyboard
    /// was holding the proof it should not have -- its own session id, set a second
    /// earlier -- and the predicate was not looking at it.
    ///
    /// ### Fails closed, in three more places
    ///
    /// `.requested` is active but is never orphaned here: the keyboard writes it moments
    /// before launching the app for a cold start, so a leftover heartbeat would condemn
    /// every cold-start dictation. A missing heartbeat yields `.unproven` -- an absent
    /// value is not evidence, and the keyboard's own watchdog still covers it. A clock
    /// that moved backwards reads as `.live`, because killing a live recording is the
    /// worse error.
    public static func evaluate(
        status: DictationStatus?,
        heartbeat: TimeInterval?,
        localSessionStartedAt: TimeInterval? = nil,
        now: TimeInterval
    ) -> DictationSessionLiveness {
        guard let status, isActive(status) else { return .notActive }
        guard let threshold = staleThreshold(for: status) else { return .unproven }
        guard let heartbeat, heartbeat > 0 else { return .unproven }
        if let localSessionStartedAt, heartbeat <= localSessionStartedAt {
            return .unproven
        }
        guard now - heartbeat > threshold else { return .live }
        return .orphaned
    }
}
