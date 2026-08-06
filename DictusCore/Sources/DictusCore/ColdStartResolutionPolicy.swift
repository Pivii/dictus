// DictusCore/Sources/DictusCore/ColdStartResolutionPolicy.swift
// Decides what to do with a cold-start dictation that was parked waiting for the
// app to become active, at the moment the app leaves the foreground instead.
// Testable in isolation -- no UIKit, no UserDefaults.

import Foundation

/// What a parked cold-start dictation gets when its last chance arrives.
public enum ColdStartResolution: String, Equatable, Sendable {
    /// Nothing was parked. The overwhelming majority of background transitions.
    case none
    /// Something was parked, but the keyboard has already stopped waiting for it.
    /// Reporting a failure here would raise an error banner for a request the user
    /// has moved on from.
    case dropped
    /// The parked start cannot be attempted -- the coordinator is busy with another
    /// dictation -- so the keyboard must be told, not left waiting.
    case report
    /// One last attempt to start the dictation. A failure inside it reports itself
    /// through the ordinary error path.
    case retry
}

/// Reads the facts around a parked cold start and says how it ends.
///
/// WHY this exists (issue #311): `DictationCoordinator` parks a URL-launched dictation
/// when the app is not yet `.active`, because `AVAudioEngine.start()` fails from a
/// non-active state (#73). The parked flag had exactly one consumer, the
/// `didBecomeActive` observer, and a user who swipes back to the host app before the
/// app settles never produces that event. The request then sat parked forever: the
/// keyboard's overlay held "Démarrage…", the Dynamic Island stayed in standby, and
/// nothing timed out. Four of twelve deliberately fast dictations were stranded that way.
///
/// The invariant this restores: **a parked start is never abandoned silently.** Every
/// path out of the park ends in a dictation that runs or a failure the user is told about.
///
/// WHY the decision lives here rather than in the coordinator: it is a three-fact rule
/// over two enums, and the coordinator can only be exercised on a device with a
/// microphone, an audio session and a keyboard extension. Same argument, and the same
/// shape, as `IdleReleasePolicy` and `DictationSessionLivenessPolicy`.
public enum ColdStartResolutionPolicy {

    /// Whether a new dictation may be started while the coordinator is in `status`.
    ///
    /// This is the entry guard `DictationCoordinator.startDictation` applies to its own
    /// `status`, expressed once so the last-chance path can ask the same question rather
    /// than restate the list and drift from it.
    ///
    /// WHY an exhaustive switch and not a `Set`: adding a case to `DictationStatus` must
    /// stop the compiler here rather than silently fall through to "go ahead" -- the
    /// permissive side is the dangerous one, since it would start a second recording
    /// over a live dictation.
    ///
    /// `.requested` is permitted: it is what the keyboard wrote moments before launching
    /// the app, so it describes *this* request, not a competing one.
    public static func canStartNewDictation(from status: DictationStatus) -> Bool {
        switch status {
        case .idle, .requested, .ready, .failed:
            return true
        case .recording, .transcribing, .processing:
            return false
        }
    }

    /// How a parked cold start ends.
    ///
    /// - Parameters:
    ///   - isPending: whether a cold start is currently parked.
    ///   - storedStatus: `SharedKeys.dictationStatus`, i.e. what the keyboard is still
    ///     waiting for. Nil when the key is unset or unrecognised.
    ///   - coordinatorStatus: the app's own dictation status.
    ///
    /// WHY `storedStatus` must still be `.requested` to act: anything else means the
    /// request was already resolved by someone -- the keyboard's watchdog reset it, a
    /// cancel wrote `.idle`, or a later dictation took over. This is the same guard the
    /// `didBecomeActive` retry has always applied, and it is what keeps a cancelled
    /// dictation from resurrecting.
    public static func resolution(
        isPending: Bool,
        storedStatus: DictationStatus?,
        coordinatorStatus: DictationStatus
    ) -> ColdStartResolution {
        guard isPending else { return .none }
        guard storedStatus == .requested else { return .dropped }
        guard canStartNewDictation(from: coordinatorStatus) else { return .report }
        return .retry
    }
}
