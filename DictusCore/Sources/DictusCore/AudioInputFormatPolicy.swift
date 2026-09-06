// DictusCore/Sources/DictusCore/AudioInputFormatPolicy.swift
// What to do with the format an audio input node reports, before anything is built on it.
import Foundation

/// Why a dictation was refused after the input node reported an unusable format.
///
/// The two cases exist to be told apart in a log, not to be shown to anyone. They
/// carry no user-facing text — #313 owns that layer, and both of these end up
/// behind the same sentence there, because from the user's side they are the same
/// event: the microphone is not available.
public enum AudioInputFormatFailure: String, Equatable, Sendable {
    /// The node reported no channels at all. Until #123 this threw the phone-call
    /// error, which told the user a call held the microphone when nothing said so —
    /// a zero-channel format means the hardware is unavailable for any reason.
    case zeroChannelCount
    /// The node reported channels but no sample rate. This is the signature #123 was
    /// filed on, `sr=0.0 ch=2`: the format the node latches when it is read while the
    /// session momentarily has no input at all.
    case zeroSampleRate
}

/// What a caller should do with the format its audio input node just reported.
public enum AudioInputFormatDecision: Equatable, Sendable {
    /// The format is usable. Install the tap on that node — since #417 the tap takes the
    /// bus's own format rather than this one, which is kept as the converter's first guess.
    case proceed
    /// The format is dead. Throw the whole engine away, build a new one, and read the
    /// format again from the new node. Returned at most once per start attempt — see
    /// `AudioInputFormatPolicy.decide`.
    case rebuildEngine
    /// The format is dead and a fresh node reported it too. The hardware genuinely is
    /// not there; give up and say which half of the format was missing.
    case fail(AudioInputFormatFailure)
}

/// Decides whether an audio input format can be recorded from (issue #123).
///
/// ### Why this is in DictusCore and not next to the engine
///
/// Same reason as `IdleReleasePolicy`: `UnifiedAudioEngine` is `@MainActor` and owns a
/// live `AVAudioEngine`, so nothing about its start path can be exercised from a test.
/// This decision is pure — it reads two numbers and one bool — and it is the entire
/// substance of the fix, so it is the part that has to be assertable.
///
/// ### The bug this encodes
///
/// Measured on device three times (2026-08-24, 2026-08-29, 2026-08-30): the audio
/// session momentarily reports no input, the input node latches `sr=0.0 ch=2`, the
/// route comes back a second later and the node keeps the dead format forever. Every
/// dictation after that fails, and only force-quitting the app clears it — because the
/// engine was created once and the only code that replaced it was the
/// media-services-reset handler, which never fired in any of the three captures.
///
/// The old code re-read **the same node** after a 50 ms sleep, which cannot help: the
/// node is what is latched. So a dead format means "this engine is unusable", not "the
/// hardware is unavailable" — and the answer is a new engine.
///
/// ### Why exactly one rebuild
///
/// A second dead format from a node that has never been read before is not a latch, it
/// is an absence. Retrying past that would spin against hardware that is not there
/// while the user waits on a microphone tap.
public enum AudioInputFormatPolicy {

    /// - Parameters:
    ///   - channelCount: `AVAudioFormat.channelCount` from the input node.
    ///   - sampleRate: `AVAudioFormat.sampleRate` from the same format. A NaN — which
    ///     no observed capture has produced, but which is representable — fails the
    ///     `> 0` test and is treated as dead, which is the safe direction.
    ///   - hasRebuiltEngine: whether this start attempt has already replaced the
    ///     engine once. The caller owns that fact; this type only combines it.
    public static func decide(
        channelCount: UInt32,
        sampleRate: Double,
        hasRebuiltEngine: Bool
    ) -> AudioInputFormatDecision {
        if channelCount > 0 && sampleRate > 0 {
            return .proceed
        }
        if !hasRebuiltEngine {
            return .rebuildEngine
        }
        // Channels first when both are missing: a node with no channels has told us
        // less than one with a channel count and no rate, and the reader of the log
        // should see the more fundamental absence named.
        return .fail(channelCount == 0 ? .zeroChannelCount : .zeroSampleRate)
    }
}
