// DictusCore/Sources/DictusCore/Polish/PolishAvailabilityChannel.swift
// Whether polish is still calling its engine, shared across the two processes (#315).
import Foundation

/// Says whether polish has given up on its engine for the rest of the keyboard
/// extension's process, so the toolbar can tell the user.
///
/// WHY a named contract rather than three `UserDefaults` calls, same argument as
/// `DictationErrorChannel`: the rule is not in the key, it is in *when the key is
/// cleared*, and that is the part a future reader would otherwise have to
/// reconstruct. Stated once here:
///
/// **Only a fresh keyboard-extension process clears this.** No timer, no re-arm on
/// foreground, no retry. That is not a simplification — it is the measured
/// behaviour of the thing being reported. Apple's background rate limit is not
/// refunded by waiting (calls three minutes apart on 61-character inputs were
/// still refused instantly) and not refunded by a foreground visit (twenty
/// seconds of foreground changed nothing; the very next backgrounded call was
/// refused). Every capture on #315 that recovered did so across a process
/// restart and nothing else.
///
/// The clear therefore belongs to the object that owns the in-memory
/// `PolishAvailabilityGate` — so the flag on disk and the gate in memory can never
/// describe different states.
///
/// ### The owner changed with #361, and that is the whole point of the flag
///
/// Until #361 DictusApp made every polish call, so the app's gate was the one the
/// notice described and the app cleared this at launch. Polish for a keyboard
/// dictation now runs in the extension, and the app's budget says nothing about the
/// keyboard's. Leaving the app as the writer would put a permanent, false "polish
/// unavailable" line on a keyboard that is polishing perfectly well, for as long as
/// the app process lived.
///
/// So the keyboard owns it: it writes on its own gate's transition and clears at its
/// own process start, which is exactly the reset rule the measurements support.
/// DictusApp keeps a gate for in-app dictations and announces nothing — it has the
/// screen when those run, and no second surface to tell.
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

    /// Return to the available state. Called once per keyboard-extension process,
    /// from `KeyboardState.init()`, and from nowhere else — see the rule above.
    public static func clear() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: SharedKeys.polishUnavailable)
        defaults.synchronize()
    }
}
