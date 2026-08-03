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
    /// An active status with no heartbeat to judge by. Not evidence of death.
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
/// value written by the process that would have died: `UnifiedAudioEngine` writes it
/// from the audio thread every 1 s while recording and every 3 s while the engine is
/// warm but idle -- which covers `.transcribing` too (#106 Phase C). A stored active
/// status whose heartbeat stopped is therefore decidable without waiting for anything.
///
/// WHY an enum with statics (not a struct): there is no state to carry. The caller
/// owns the facts; this type only combines them. Same pattern as `IdleReleasePolicy`.
public enum DictationSessionLivenessPolicy {

    /// How stale the heartbeat must be before the writer is declared gone.
    ///
    /// WHY 8 s and not the watchdog's 5 s: the slowest legitimate cadence is the
    /// 3 s idle heartbeat, and a cross-process `UserDefaults` read can lag behind
    /// the write. 8 s clears both with margin, and is still roughly half the 15 s
    /// cold-start grace this check exists to bypass.
    public static let staleHeartbeatThreshold: TimeInterval = 8

    /// Whether `status` describes a dictation that some process should be driving.
    ///
    /// WHY an exhaustive switch and not a `Set`: adding a case to `DictationStatus`
    /// (`processing`, #267) must stop the compiler here rather than silently fall
    /// through to "nothing is in flight".
    public static func isActive(_ status: DictationStatus) -> Bool {
        switch status {
        case .requested, .recording, .transcribing:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    /// What the shared state says about the process behind it.
    ///
    /// - Parameters:
    ///   - status: the stored `SharedKeys.dictationStatus`, or nil when unset or
    ///     unrecognised.
    ///   - heartbeat: the stored `SharedKeys.recordingHeartbeat` as seconds since
    ///     1970, or nil when the key is absent.
    ///   - now: seconds since 1970.
    ///
    /// Fails **closed** in two places, deliberately. `.requested` is active but is
    /// never orphaned here: the keyboard writes it moments before launching the app
    /// for a cold start, so a heartbeat left over from an earlier session would
    /// condemn every cold-start dictation. And a missing heartbeat yields
    /// `.unproven` rather than `.orphaned` -- an absent value is not evidence, and
    /// the keyboard's own 5 s/15 s watchdog already covers that case. A clock that
    /// moved backwards reads as `.live` for the same reason: killing a live
    /// recording is the worse error.
    public static func evaluate(
        status: DictationStatus?,
        heartbeat: TimeInterval?,
        now: TimeInterval,
        threshold: TimeInterval = staleHeartbeatThreshold
    ) -> DictationSessionLiveness {
        guard let status, isActive(status) else { return .notActive }
        guard status != .requested else { return .unproven }
        guard let heartbeat, heartbeat > 0 else { return .unproven }
        let age = now - heartbeat
        guard age > threshold else { return .live }
        return .orphaned
    }
}
