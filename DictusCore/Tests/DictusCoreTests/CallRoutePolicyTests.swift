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

    // MARK: - The flag this policy reads must not be able to latch

    /// The defect the #459 review caught, as a tripwire.
    ///
    /// This policy is pure and cannot latch: feed it `isInterrupted: false` and it
    /// answers `.noCall`, as the tests above show. The latch was in the *caller*. The
    /// engine's `isInterrupted` is documented as "an interruption is currently in
    /// flight", but the interruption-ended handler never cleared it — the only clear was
    /// at the end of a **successful** `startEngine`. Since #459 the guard reads that flag
    /// before the start, so a raised flag refuses the start, and a refused start never
    /// reaches the clear. The user cannot get out of it by tapping again.
    ///
    /// Nothing saves that but iOS dropping the HFP route when the call ends, which is
    /// luck rather than design — so the clear that does not depend on a successful start
    /// is checked here, at source level, because there is nowhere else it can be checked:
    /// `UnifiedAudioEngine` is `@MainActor`, owns a live `AVAudioEngine`, and lives in a
    /// target with no test bundle. Extracting the flag's four writes into a pure
    /// event-to-Bool mapping would move a `switch` into this package and let a test
    /// restate it, which would assert nothing this does not.
    ///
    /// The pattern — resolving a repo path from `#filePath` rather than copying source
    /// into test resources — is `DictationErrorCopyTests`', for the reason it gives: a
    /// copy would drift, and drift is the failure being checked for. Brittle by nature;
    /// if a refactor moves this clear, read the message and decide deliberately.
    func testTheInterruptionEndedHandlerClearsTheFlagThisPolicyIsGivenAsLive() throws {
        let source = try engineSource()
        let handler = try XCTUnwrap(
            Self.body(ofFunction: "handleInterruption", in: source),
            "handleInterruption not found in \(Self.enginePath) — this tripwire has gone blind"
        )
        let ended = try XCTUnwrap(
            handler.range(of: "case .ended:").map { String(handler[$0.upperBound...]) },
            "handleInterruption has no `case .ended:` branch any more"
        )
        let endedBranch = ended.components(separatedBy: "@unknown default:").first ?? ended

        XCTAssertTrue(
            endedBranch.contains("isInterrupted = false"),
            """
            The interruption-ended branch does not clear `isInterrupted`.
            Since #459 the call guard refuses a start while that flag is raised, and a
            refused start never reaches the clear at the end of `startEngine` — so the
            flag latches and the user cannot recover by tapping again.
            """
        )
    }

    /// The other clear, which the #459 review asked to keep. It answers a different
    /// question — this start succeeded, so the audio layer is healthy — and it is what
    /// covers an interruption iOS never delivers an `.ended` for.
    func testASuccessfulStartStillClearsTheFlagToo() throws {
        let source = try engineSource()
        let start = try XCTUnwrap(
            Self.body(ofFunction: "startEngine", in: source),
            "startEngine not found in \(Self.enginePath) — this tripwire has gone blind"
        )
        XCTAssertTrue(
            start.contains("isInterrupted = false"),
            "startEngine no longer clears `isInterrupted` on a successful start"
        )
    }

    // MARK: - Source-level helpers

    private static let enginePath = "DictusApp/Audio/UnifiedAudioEngine.swift"

    private func engineSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DictusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // DictusCore
            .deletingLastPathComponent()  // repo root
        let url = root.appendingPathComponent(Self.enginePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Source not found at \(url.path)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return text
    }

    /// The text of one function, read by matching braces from its `{`.
    ///
    /// Brace counting rather than a line range: both functions below contain nested
    /// closures and `switch` blocks, and a line-based read would stop at the first `}`.
    /// String literals are tracked so a brace inside one cannot unbalance the count.
    private static func body(ofFunction name: String, in source: String) -> String? {
        guard let declaration = source.range(of: "func \(name)(") else { return nil }
        guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else { return nil }

        var depth = 1
        var index = open.upperBound
        var inString = false

        while index < source.endIndex, depth > 0 {
            let character = source[index]
            if character == "\"" { inString.toggle() }
            if !inString {
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1 }
            }
            index = source.index(after: index)
        }

        return depth == 0 ? String(source[open.upperBound..<index]) : nil
    }
}
