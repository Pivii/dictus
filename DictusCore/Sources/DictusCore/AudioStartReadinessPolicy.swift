// DictusCore/Sources/DictusCore/AudioStartReadinessPolicy.swift
// Whether an engine start may build its input node now, or is the one paying for a route
// that an interruption took away.
import Foundation

/// What a start attempt should do before it reads the input node's format.
public enum AudioStartReadiness: Equatable, Sendable {
    /// The route is up and has stayed up. Build the node and start, exactly as before.
    case startNow

    /// This attempt is the one re-establishing the input route. Wait for the route to come
    /// back — at most `waitMilliseconds`, `0` when it is already back — then throw the
    /// engine away and read the format from a node built against the route that is
    /// actually there.
    case rebuildOnceInputRouteReturns(waitMilliseconds: Int)
}

/// Decides whether a start attempt is the one paying for a route an interruption took
/// away (issue #515).
///
/// ### What the device captures show
///
/// `rev 550dc6a@HEAD`, iPhone16,2, iOS 26.6.1, two sessions on 2026-09-06, seven
/// activations. When an interruption ends, iOS leaves the input route empty and leaves it
/// there:
///
/// ```
/// 14:57:08  audioRouteChanged reason=routeConfigurationChange(8) previous=MicrophoneBuiltIn route=none
/// 14:57:08  audioInterruptionEnded shouldResume=true restored=false
/// ```
///
/// The next `setActive(true)` is what brings it back, and **every attempt that had to do
/// that captured nothing**:
///
/// | attempt | own activation followed by `previous=none route=…` | samples |
/// | --- | --- | --- |
/// | 14:46:36, 14:47:18, 14:57:19 | yes | 0, 0, 0 — `Zombie engine: 0 samples after 2s` |
/// | six others across both sessions | no | 24015 … 72045 |
///
/// ### Why this is the rule and not "wait a bit longer"
///
/// The obvious theory — the call's session needs a moment to let go — is falsified by the
/// same captures: a tap 10 s after the interruption ended failed, and a tap 9 s after a
/// failure succeeded. Time is not the variable.
///
/// What settles it is the seventh activation. At 14:54:20 the app's own `didBecomeActive`
/// re-warm — not a dictation, nobody waiting on it — logged `previous=none
/// route=MicrophoneBuiltIn`, i.e. **it** paid for the route. The dictation that followed it
/// two minutes later logged no such line and captured 35222 samples. So the cost is paid
/// once, by whichever activation comes first, and the attempt that pays it is the one that
/// gets silence. That is a mechanism, not a correlation.
///
/// ### What is decided here and what is not
///
/// Decided, on the evidence above: **which** attempts must not build their input node
/// straight away. That is the whole of this type.
///
/// Not decided, and not decidable from a log: whether waiting for the route and rebuilding
/// the engine is *sufficient*. The wait is bounded at 1 s because the route came back
/// inside the same log second in all three failures; the rebuild is this repo's established
/// answer to "this node cannot capture" (#123 / #457, and `handleMediaServicesReset`
/// before it). Both need a device to confirm, and the caller logs the wait it actually
/// measured so the next capture says so.
///
/// ### What this deliberately does not do
///
/// It does not re-activate the session when the interruption ends. #106's contract stands:
/// the user has just finished a call and has not asked to dictate, and re-warming there
/// holds the audio hardware — orange mic indicator and all — with no Dictus UI to explain
/// it. The room to act in is inside the user's own tap, which is where this runs.
public enum AudioStartReadinessPolicy {

    /// How long a start may wait for the input route to come back before giving up and
    /// letting the existing format guards have their say.
    ///
    /// One second, because that is the observed upper bound: in all three captured
    /// failures the route returned within the same log second as the activation that asked
    /// for it.
    ///
    /// ### This number does not carry the fix, and the device says so
    ///
    /// Device validation of `rev e955db1@HEAD`, 2026-09-06: six dictations, six
    /// successes, no `Zombie engine` line anywhere. One of the five post-interruption
    /// starts logged
    ///
    /// ```
    /// engineRebuiltAfterEmptyRoute waitedMs=1163 budgetMs=1000 route=none
    /// ```
    ///
    /// — the wait ran out, **the route had still not come back, and the dictation worked
    /// anyway**. So what repairs this is the `replaceEngine()` that follows, not the
    /// waiting. Raising this constant would buy nothing and would only make a user wait
    /// longer for a start that is going to succeed regardless.
    ///
    /// (`waitedMs` is wall-clock and the loop counts `10` per `usleep(10_000)`, so it
    /// overshoots the budget by the syscall overhead of a hundred iterations. That is why
    /// 1163 is not a contradiction of a 1000 ms bound.)
    ///
    /// Also measured in the same session: one interruption never delivered an
    /// `audioInterruptionEnded` at all, and the fix still held — which is the argument for
    /// keying this on the route rather than on the interruption, made by the device.
    public static let inputRouteWaitMilliseconds = 1000

    /// - Parameters:
    ///   - inputPortCount: how many ports `AVAudioSession.currentRoute.inputs` holds right
    ///     now. Zero is the state an interruption leaves behind.
    ///   - routeWentEmptySinceLastStart: whether the input route has been observed empty
    ///     since the last engine start that succeeded. The caller owns that fact — it is
    ///     one bool set from the route-change notification — and this type only combines it.
    public static func decide(
        inputPortCount: Int,
        routeWentEmptySinceLastStart: Bool
    ) -> AudioStartReadiness {
        // The ordinary path, and by far the common one: nothing took the route away, so
        // nothing about the start changes. Six of the seven captured activations are here.
        guard routeWentEmptySinceLastStart else { return .startNow }

        // The route is already back — it returned between the interruption and this tap,
        // or our own activation a moment ago brought it back. Nothing to wait for, but the
        // node this engine holds was built against hardware that is no longer the hardware.
        if inputPortCount > 0 {
            return .rebuildOnceInputRouteReturns(waitMilliseconds: 0)
        }

        return .rebuildOnceInputRouteReturns(waitMilliseconds: inputRouteWaitMilliseconds)
    }
}
