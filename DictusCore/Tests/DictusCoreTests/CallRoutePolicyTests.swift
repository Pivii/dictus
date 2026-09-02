import XCTest
@testable import DictusCore

/// Coverage for the call detection behind the AirPods-call fix (issue #459).
///
/// These tests carry more than usual, because this rule cannot be checked anywhere else:
/// `UnifiedAudioEngine.startEngine` is `@MainActor`, owns a live `AVAudioEngine` and
/// lives in the DictusApp target, and a simulator has neither a telephony route nor
/// bluetooth audio. On device, reproducing it costs a real phone call. So this suite is
/// the only place the two halves of the rule — a headset call is a call, a headset alone
/// is not — are asserted at all.
final class CallRoutePolicyTests: XCTestCase {

    /// The raw values `AVAudioSession` reports, as they appear in the device log lines
    /// this fix was written from (`route=BluetoothHFP available=MicrophoneBuiltIn`).
    private enum Port {
        static let bluetoothHandsFree = "BluetoothHFP"
        static let builtInMic = "MicrophoneBuiltIn"
        static let bluetoothA2DP = "BluetoothA2DPOutput"
        static let wiredHeadset = "HeadsetMicrophone"
    }

    // MARK: - The case the issue was filed on

    func testTheMeasuredAirPodsCallIsDetectedAsACall() {
        // Device session 2026-08-31, rev 2af4d9a, iPhone16,2, iOS 26.6.1: the maintainer
        // was on a call through AirPods and tapped the mic. Before this fix the guard saw
        // no `telephony` port and let the start proceed into a hardware-unavailable error.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.bluetoothHandsFree],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: true
            ),
            .callHoldsMicrophone(.headsetRouteDuringInterruption)
        )
    }

    // MARK: - A headset that is merely the route is not a call

    func testAHandsFreeRouteWithNoInterruptionIsNotACall() {
        // The criterion that stops this fix being a false-positive machine: a headset can
        // be the input route with nothing holding it. Only the interruption says a call.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.bluetoothHandsFree],
                isInterrupted: false,
                builtInMicrophoneIsAvailable: true
            ),
            .noCall
        )
    }

    func testAnInterruptionWithNoHandsFreeRouteIsNotACall() {
        // Siri, an alarm, another app taking the session: the engine is interrupted with
        // the built-in mic still the route. Nothing here says a call, so nothing claims one.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.builtInMic],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: true
            ),
            .noCall
        )
    }

    func testAHandsFreeRouteWithNoBuiltInMicrophoneToFallBackOnIsNotReportedAsACall() {
        // "A call holds your microphone, hang up or wait" promises a microphone to get
        // back. With none listed as available, the hardware message is the truer one.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.bluetoothHandsFree],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: false
            ),
            .noCall
        )
    }

    func testAnA2DPHeadsetIsNotAHandsFreeRoute() {
        // What #85 leaves us in normally: AirPods as an A2DP output, capture on the
        // iPhone's own mic. `contains` on the port list must not match this on the
        // shared "Bluetooth" prefix.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.bluetoothA2DP, Port.builtInMic],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: true
            ),
            .noCall
        )
    }

    // MARK: - The telephony route, unchanged

    func testATelephonyRouteIsACallOnItsOwn() {
        // What the guard has always caught: a call on the handset or a wired headset.
        // No interruption term — nothing but a call routes input through telephony.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: ["Telephony"],
                isInterrupted: false,
                builtInMicrophoneIsAvailable: true
            ),
            .callHoldsMicrophone(.telephonyInputRoute)
        )
    }

    func testATelephonyRouteIsACallEvenWithNoBuiltInMicrophoneAvailable() {
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: ["Telephony"],
                isInterrupted: false,
                builtInMicrophoneIsAvailable: false
            ),
            .callHoldsMicrophone(.telephonyInputRoute)
        )
    }

    func testTelephonyMatchingIsCaseInsensitiveAndPartial() {
        // The original guard was `portType.rawValue.lowercased().contains("telephony")`.
        // This fix widens the detection; it must not narrow what was already caught, and
        // the telephony input port has no public constant to compare against.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: ["AVAudioSessionPortTelephonyReceiver"],
                isInterrupted: false,
                builtInMicrophoneIsAvailable: true
            ),
            .callHoldsMicrophone(.telephonyInputRoute)
        )
    }

    func testTelephonyWinsOverAHandsFreeRoute() {
        // Both present: the stronger signal names the evidence, so a log reader is not
        // told a headset explained something telephony already explained.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.bluetoothHandsFree, "Telephony"],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: true
            ),
            .callHoldsMicrophone(.telephonyInputRoute)
        )
    }

    // MARK: - Ordinary states

    func testTheBuiltInMicrophoneAloneIsNotACall() {
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.builtInMic],
                isInterrupted: false,
                builtInMicrophoneIsAvailable: true
            ),
            .noCall
        )
    }

    func testAWiredHeadsetMicrophoneIsNotACall() {
        // A wired headset is an ordinary input route. A call on one presents as telephony,
        // which the first rule catches; the headset port itself claims nothing.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [Port.wiredHeadset],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: true
            ),
            .noCall
        )
    }

    func testAnEmptyRouteIsNotACall() {
        // `inputs=none` is the #123 signature, and it is a hardware absence, not a call.
        // The guard must leave it to `AudioInputFormatPolicy` to explain.
        XCTAssertEqual(
            CallRoutePolicy.decide(
                inputPortTypes: [],
                isInterrupted: true,
                builtInMicrophoneIsAvailable: false
            ),
            .noCall
        )
    }
}
