// DictusCore/Sources/DictusCore/ActiveCallPolicy.swift
// Whether a call holds the microphone, read from CallKit's call list rather than the audio route.
import Foundation

/// One call as CallKit reports it, reduced to the two flags the rule reads.
///
/// A plain value rather than a `CXCall` so the rule stays testable: this package builds for
/// macOS too — `swift test` and the polish harness both run there — and CallKit's types are
/// `API_UNAVAILABLE(macos)`. `SystemCallObserver` does the mapping on iOS, and nothing else
/// in DictusCore imports CallKit.
public struct ObservedCall: Equatable, Sendable {
    /// `CXCall.hasConnected` — the call is up and the remote party can hear.
    public let hasConnected: Bool
    /// `CXCall.hasEnded` — CallKit still lists the call, but it is over.
    public let hasEnded: Bool

    public init(hasConnected: Bool, hasEnded: Bool) {
        self.hasConnected = hasConnected
        self.hasEnded = hasEnded
    }
}

/// What said a call holds the microphone.
///
/// The two cases exist to be told apart in a log, not to be shown to anyone. They carry no
/// user-facing text — #313 owns that layer, and both end up behind the same sentence there,
/// because from the user's side they are the same event: a call has the mic, and the remedy
/// is to hang up or wait.
public enum ActiveCallEvidence: String, Equatable, Sendable {
    /// A call that has connected. The ordinary case: the user is talking to someone.
    case connectedCall

    /// A call CallKit lists that has neither connected nor ended — ringing, dialling, or
    /// still being set up. It holds the audio hardware just as firmly as a connected one,
    /// and it is named separately because a log that could not tell them apart would leave
    /// "the mic was refused while the phone was merely ringing" unprovable.
    case pendingCall
}

/// Whether the microphone is currently held by a call.
public enum ActiveCallDecision: Equatable, Sendable {
    /// CallKit reports no live call. Carry on starting the engine.
    case noCall
    /// A call holds the microphone. Refuse the dictation and say so, naming which signal
    /// said it.
    case callHoldsMicrophone(ActiveCallEvidence)
}

/// Decides whether a call holds the microphone, from CallKit's call list (issue #483).
///
/// ### What this replaces, and why the heuristic had to go
///
/// Until #483 this question was answered from the audio session — `CallRoutePolicy`, deleted
/// with this file's arrival. Two device sessions falsified that approach outright.
///
/// The predicate the guard had used since the beginning looked for an input port whose type
/// contains `telephony`. It never fired. Measured 2026-09-03, `rev b290af2`, iPhone16,2, iOS
/// 26.6.1, on a real call held on the iPhone's own earpiece:
///
/// ```
/// 08:24:16  audioRouteChanged reason=categoryChange(3)
///             previous=MicrophoneBuiltIn route=MicrophoneBuiltIn available=MicrophoneBuiltIn
/// 08:24:24  dictationFailed error=installTap NSException: … <AVAudioFormat 1 ch, 48000 Hz>
/// ```
///
/// **During a native call carried on the iPhone itself the input route is `MicrophoneBuiltIn`,
/// never `telephony`.** #476 then widened the heuristic to catch a call on a bluetooth headset
/// — `BluetoothHFP` + an interruption in flight + the built-in mic still available, measured
/// 4/4 — which is real, and which cannot reach the case above.
///
/// And no session-level signal ever will. During a call on the earpiece the three facts
/// available are: an interruption is active, the route is `MicrophoneBuiltIn`, the built-in
/// mic is listed available. **Siri produces exactly those three** — five captures on
/// 2026-09-02 (14:18:15, 14:19:13, 14:20:23, 14:20:33, 14:23:32) show the identical
/// `installTap NSException` under them — and `AVAudioSession.InterruptionReason` exposes
/// neither `.phoneCall` nor `.siri`. So the heuristic could only miss real calls or claim a
/// call while Siri listened; #476 knowingly shipped the second.
///
/// CallKit answers the question that was being guessed at, so the guess is gone rather than
/// kept as a fallback: CallKit says "no call" while Siri listens, and a fallback underneath
/// it would therefore fire on Siri every single time — reinstating the exact false positive
/// this rule exists to kill.
///
/// **Accepted cost:** a VoIP app that does not report its calls to CallKit is no longer
/// detected. FaceTime, WhatsApp and Messenger all do.
///
/// ### Why a call that has not connected still counts
///
/// A ringing or dialling call has already taken the audio hardware — that is what the
/// interruption in every capture above is. Waiting for `hasConnected` would leave the whole
/// ringing window answering "no call", which is the window a user is most likely to tap the
/// mic in, having just been interrupted.
///
/// ### Why `isOnHold` and `isOutgoing` are not read
///
/// They are not asked because no capture in this repo says what they imply for the
/// microphone. A held call is still a call the telephony stack owns the route for, and
/// claiming the mic is free on the strength of a flag we have never observed would be the
/// same class of guess this issue exists to remove. `SystemCallObserver` still writes both
/// into the log line, so the first capture that contradicts this can be read off it.
///
/// ### Why this is in DictusCore and not next to the engine
///
/// Same reason as `AudioInputFormatPolicy` and `IdleReleasePolicy`: `UnifiedAudioEngine` is
/// `@MainActor` and owns a live `AVAudioEngine`, so nothing about its start path can be
/// exercised from a test. And this one can never be exercised on a simulator either — a
/// simulator has no telephony at all — so a unit test is the only place the rule can be shown
/// to hold. It is also the shared boundary: since #483 the keyboard extension asks the same
/// question before it hands off to the app, and both sides have to answer it identically.
public enum ActiveCallPolicy {

    /// - Parameter calls: every call `CXCallObserver.calls` reports, mapped to
    ///   `ObservedCall`. An empty array is the normal state and means no call.
    public static func decide(calls: [ObservedCall]) -> ActiveCallDecision {
        // A call CallKit still lists but that has ended holds nothing. It is listed for a
        // moment after the hang-up, which is exactly when a user who waited for the call to
        // finish taps the mic — reading it as live would refuse the tap they were told to make.
        let live = calls.filter { !$0.hasEnded }

        guard !live.isEmpty else { return .noCall }

        // Connected wins when both are present — call waiting puts a second, pending call
        // beside a connected one, and the connected one is the truer description of the state.
        if live.contains(where: { $0.hasConnected }) {
            return .callHoldsMicrophone(.connectedCall)
        }
        return .callHoldsMicrophone(.pendingCall)
    }
}
