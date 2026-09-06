import XCTest
@testable import DictusCore

/// Coverage for the CallKit call detection that replaced the audio-route heuristic (#483).
///
/// These tests carry more than usual, because this rule cannot be checked anywhere else.
/// `UnifiedAudioEngine.startEngine` is `@MainActor`, owns a live `AVAudioEngine` and lives in
/// the DictusApp target; `KeyboardState` needs a keyboard extension around it; and a
/// simulator has no telephony at all, so `CXCallObserver.calls` is empty there whatever is
/// happening. On device, reproducing this costs a real phone call — the most awkward test in
/// this repo to set up. So this suite is the only place the rule is asserted at all.
final class ActiveCallPolicyTests: XCTestCase {

    /// The four states CallKit can describe, spelled once so each test reads as a situation.
    private enum Call {
        static let connected = ObservedCall(hasConnected: true, hasEnded: false)
        static let pending = ObservedCall(hasConnected: false, hasEnded: false)
        static let ended = ObservedCall(hasConnected: true, hasEnded: true)
        static let endedWithoutConnecting = ObservedCall(hasConnected: false, hasEnded: true)
    }

    // MARK: - The cases the issue was filed on

    /// A call on the iPhone's own earpiece, 2026-09-03, `rev b290af2`, iPhone16,2, iOS 26.6.1.
    /// The audio route said `MicrophoneBuiltIn` and the old heuristic saw nothing at all;
    /// CallKit lists one connected call and the answer is no longer inferred.
    func testAConnectedCallHoldsTheMicrophone() {
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.connected]),
            .callHoldsMicrophone(.connectedCall)
        )
    }

    /// The bluetooth case #476 already fixed, which must not regress: from CallKit's side a
    /// call on AirPods is the same connected call, and the route it happens to be carried on
    /// is no longer part of the question.
    func testACallOnAHeadsetIsTheSameConnectedCall() {
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.connected]),
            .callHoldsMicrophone(.connectedCall)
        )
    }

    /// The regression guard on Decision 1. Siri holds the microphone and produces the same
    /// three session-level signals a call does, and CallKit lists nothing — which is exactly
    /// why the heuristic was deleted rather than kept underneath this as a fallback.
    func testSiriListeningIsNotACall() {
        XCTAssertEqual(ActiveCallPolicy.decide(calls: []), .noCall)
    }

    // MARK: - Live but not connected

    func testARingingOrDiallingCallHoldsTheMicrophoneToo() {
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.pending]),
            .callHoldsMicrophone(.pendingCall)
        )
    }

    // MARK: - Ended calls hold nothing

    /// The moment that matters: the user hung up because the message told them to, and taps
    /// the mic while CallKit still lists the call. Reading it as live would refuse the very
    /// tap the message asked for.
    func testACallThatHasEndedIsNotACall() {
        XCTAssertEqual(ActiveCallPolicy.decide(calls: [Call.ended]), .noCall)
    }

    func testAMissedCallThatNeverConnectedIsNotACall() {
        XCTAssertEqual(ActiveCallPolicy.decide(calls: [Call.endedWithoutConnecting]), .noCall)
    }

    func testAnEmptyCallListIsTheOrdinaryState() {
        XCTAssertEqual(ActiveCallPolicy.decide(calls: []), .noCall)
    }

    // MARK: - More than one call

    /// Call waiting: a second call rings while the first is up. The connected one is the
    /// truer description of the state, so it is the one named in the log.
    func testAConnectedCallIsNamedAheadOfAPendingOne() {
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.pending, Call.connected]),
            .callHoldsMicrophone(.connectedCall)
        )
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.connected, Call.pending]),
            .callHoldsMicrophone(.connectedCall)
        )
    }

    /// A call that ended beside one that is still ringing must not hide the live one.
    func testALiveCallBesideAnEndedOneStillHoldsTheMicrophone() {
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.ended, Call.pending]),
            .callHoldsMicrophone(.pendingCall)
        )
    }

    func testSeveralEndedCallsAreStillNoCall() {
        XCTAssertEqual(
            ActiveCallPolicy.decide(calls: [Call.ended, Call.endedWithoutConnecting]),
            .noCall
        )
    }
}
