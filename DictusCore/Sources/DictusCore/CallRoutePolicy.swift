// DictusCore/Sources/DictusCore/CallRoutePolicy.swift
// Whether a call is holding the microphone, read from the audio route rather than the port type alone.
import Foundation

/// What said a call holds the microphone.
///
/// The two cases exist to be told apart in a log, not to be shown to anyone. They carry
/// no user-facing text — #313 owns that layer, and both end up behind the same sentence
/// there, because from the user's side they are the same event: a call has the mic, and
/// the remedy is to hang up or wait.
public enum CallRouteEvidence: String, Equatable, Sendable {
    /// A telephony port is the input route. This is the signal the guard has always
    /// used, and it is a call on its own: nothing but a call routes input through
    /// telephony. It matches a call carried on the handset or on a wired headset.
    case telephonyInputRoute

    /// A bluetooth hands-free port is the input route while an interruption is in
    /// flight. This is the case #459 was filed on: a call carried over AirPods never
    /// presents as `telephony`, it presents as `BluetoothHFP`, so the port type alone
    /// missed what is, for most people, the majority of their calls.
    case headsetRouteDuringInterruption
}

/// Whether the microphone is currently held by a call.
public enum CallRouteDecision: Equatable, Sendable {
    /// Nothing about the route says a call is in progress. Carry on starting the engine.
    case noCall
    /// A call holds the microphone. Refuse the dictation and say so, naming which signal
    /// said it — the two are indistinguishable in a log that only says "a call".
    case callHoldsMicrophone(CallRouteEvidence)
}

/// Decides whether a call holds the microphone, from the audio session state (issue #459).
///
/// ### Why the port type alone was not enough
///
/// `UnifiedAudioEngine.startEngine` used to decide this by looking for an input port
/// whose type contains `telephony`. **A call carried over AirPods or any bluetooth
/// headset does not present as `telephony`. It presents as `BluetoothHFP`.** So the
/// guard never fired for it. Measured on device 2026-08-31, `rev 2af4d9a`, iPhone16,2,
/// iOS 26.6.1, the maintainer on a call through AirPods:
///
/// ```
/// 09:22:00  audioInterruptionBegan reason=…(0)
/// 09:22:08  audioRouteChanged reason=…(8) details=inputs=BluetoothHFP
/// 09:25:12  … route=BluetoothHFP available=MicrophoneBuiltIn preferred=none
/// ```
///
/// ### Why an HFP route is not a call on its own
///
/// A headset can be the input route with no call in progress, so `BluetoothHFP` alone
/// would misreport an ordinary headset as a call. The discriminator is the
/// **interruption**: iOS interrupts our session when a call takes the audio hardware,
/// and `isInterrupted` stays raised until a start succeeds, so it is still true minutes
/// later when the user taps the mic — three minutes later, in the capture above.
///
/// ### Why the built-in microphone has to still be available
///
/// It is what separates the two messages. "A call holds your microphone, hang up or
/// wait" is only true if there is a microphone to get back; if the mic we would fall
/// back to is not even listed as available, the honest message is the hardware one.
/// The other half of the fact the capture records — that the built-in mic is *not
/// selected* — is already implied by the input route being the headset, so it is not
/// asserted twice here.
///
/// ### Why this is in DictusCore and not next to the engine
///
/// Same reason as `AudioInputFormatPolicy` and `IdleReleasePolicy`: `UnifiedAudioEngine`
/// is `@MainActor` and owns a live `AVAudioEngine`, so nothing about its start path can
/// be exercised from a test. And this one can never be exercised on a simulator either —
/// a simulator has neither a telephony route nor bluetooth audio — so a unit test is the
/// only place the rule can be shown to hold at all.
public enum CallRoutePolicy {

    /// The port type a call over a bluetooth headset presents as.
    ///
    /// `AVAudioSession.Port.bluetoothHFP.rawValue`, spelled out rather than imported:
    /// this type takes plain values so it stays testable without AVFoundation, and the
    /// caller passes `portType.rawValue` straight through.
    private static let bluetoothHandsFreePortType = "bluetoothhfp"

    /// The substring that identifies a telephony input port.
    ///
    /// A substring rather than an equality test, kept exactly as the guard has always
    /// spelled it: the telephony input port has no public `AVAudioSession.Port` constant
    /// to compare against, so the original code matched on the word and this must not
    /// narrow what it already caught.
    private static let telephonyPortTypeFragment = "telephony"

    /// - Parameters:
    ///   - inputPortTypes: `portType.rawValue` for every port in
    ///     `AVAudioSession.sharedInstance().currentRoute.inputs`.
    ///   - isInterrupted: whether an AVAudioSession interruption is currently in flight,
    ///     as the engine tracks it. The caller owns that fact; this type only combines it.
    ///   - builtInMicrophoneIsAvailable: whether the built-in microphone is listed in
    ///     `availableInputs`. Only consulted for the headset case — a telephony route is
    ///     a call whether or not anything else is reachable.
    public static func decide(
        inputPortTypes: [String],
        isInterrupted: Bool,
        builtInMicrophoneIsAvailable: Bool
    ) -> CallRouteDecision {
        let types = inputPortTypes.map { $0.lowercased() }

        if types.contains(where: { $0.contains(telephonyPortTypeFragment) }) {
            return .callHoldsMicrophone(.telephonyInputRoute)
        }

        let hasHandsFreeRoute = types.contains(bluetoothHandsFreePortType)
        if hasHandsFreeRoute && isInterrupted && builtInMicrophoneIsAvailable {
            return .callHoldsMicrophone(.headsetRouteDuringInterruption)
        }

        return .noCall
    }
}
