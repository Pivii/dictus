// DictusCore/Sources/DictusCore/Polish/PolishAvailabilityChannel.swift
// Whether polish is still calling its engine, shared across the two processes (#315).
import Foundation

/// Says whether polish has given up on its engine for the rest of the app's
/// process, so a surface in the other process can tell the user.
///
/// WHY a named contract rather than three `UserDefaults` calls, same argument as
/// `DictationErrorChannel`: the rule is not in the key, it is in *when the key is
/// cleared*, and that is the part a future reader would otherwise have to
/// reconstruct. Stated once here:
///
/// **Only a fresh DictusApp process clears this.** No timer, no re-arm on
/// foreground, no retry. That is not a simplification — it is the measured
/// behaviour of the thing being reported. Apple's background rate limit is not
/// refunded by waiting (calls three minutes apart on 61-character inputs were
/// still refused instantly) and not refunded by a foreground visit (twenty
/// seconds of foreground changed nothing; the very next backgrounded call was
/// refused). Every capture on #315 that recovered did so across a process
/// restart and nothing else.
///
/// The clear therefore belongs to the object that owns the in-memory
/// `PolishAvailabilityGate` — `PolishCoordinator`, at its `init` — so the flag
/// on disk and the gate in memory can never describe different states.
///
/// The keyboard extension only reads. It has its own process lifetime, and
/// nothing it does can restore the app's budget.
public enum PolishAvailabilityChannel {

    /// Whether polish has stopped calling its engine. False when nothing was
    /// recorded, which is the available state.
    public static var isUnavailable: Bool {
        AppGroup.defaults.bool(forKey: SharedKeys.polishUnavailable)
    }

    /// Record that polish has stopped calling its engine. Called once, on the
    /// transition.
    public static func markUnavailable() {
        let defaults = AppGroup.defaults
        defaults.set(true, forKey: SharedKeys.polishUnavailable)
        defaults.synchronize()
    }

    /// Return to the available state. Called from `PolishCoordinator.init()`, and
    /// from nowhere else — see the rule above.
    public static func clear() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: SharedKeys.polishUnavailable)
        defaults.synchronize()
    }
}
