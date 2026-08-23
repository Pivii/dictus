// DictusCore/Sources/DictusCore/Polish/SmartModeStore.swift
// The armed Smart Mode and the pinned list, in the App Group (issue #79).
import Foundation

/// What the user has chosen about Smart Modes, shared across the two processes.
///
/// ### The mode is sticky
///
/// It survives keyboard and app restarts, exactly like the keyboard language, and it
/// is cleared by selecting Normal. That is the one thing #79 keeps from Typeless's
/// gesture and Typeless does not: without persistence a user working in English
/// long-press-and-swipes before every single dictation, and with it the following
/// dictations cost one plain tap.
///
/// ### What is stored, and what is not
///
/// An identifier, not a record. The record is rebuilt from `SmartModeCatalogue` on
/// every read, so a prompt fix ships with the binary rather than being frozen on
/// every device that ever armed the mode. See `SmartMode` for where a whole record
/// *is* written down — the per-dictation snapshot, which is a different job.
///
/// WHY a named contract rather than four `UserDefaults` calls, the same argument
/// `DictationErrorChannel` and `PendingDictationChannel` make: the rule is not in the
/// key, it is in what a read is allowed to do. Stated once — **`resolveArmedMode()`
/// may disarm and `armedMode` may not**, because one of them is a dictation starting
/// and the other is a screen being drawn.
public enum SmartModeStore {

    private static var defaults: UserDefaults { AppGroup.defaults }

    // MARK: - The armed mode

    /// Identifier of the armed mode, or nil for Normal.
    public static var armedIdentifier: String? {
        defaults.string(forKey: SharedKeys.smartModeArmed)
    }

    /// The armed mode as a record, or nil for Normal.
    ///
    /// Read-only in every sense: an identifier that resolves to nothing reads as
    /// Normal here without touching what is stored. Use this to draw a surface; use
    /// `resolveArmedMode()` to start a dictation.
    public static var armedMode: SmartMode? {
        armedIdentifier.flatMap(SmartModeCatalogue.mode(withIdentifier:))
    }

    /// Arm `mode`. Replaces whatever was armed before — there is one armed mode, not
    /// a stack.
    public static func arm(_ mode: SmartMode) {
        defaults.set(mode.id, forKey: SharedKeys.smartModeArmed)
        defaults.synchronize()
    }

    /// Return to Normal: the free polish, which is the default state.
    public static func disarm() {
        defaults.removeObject(forKey: SharedKeys.smartModeArmed)
        defaults.synchronize()
    }

    /// The armed mode for a dictation that is starting, disarming it if this device
    /// can no longer honour it.
    ///
    /// Called once per dictation, at transcription start, and the result is what
    /// travels with the text (#226's reasoning, applied to the mode: the user must
    /// not be able to change it mid-transcription and have the transformation
    /// disagree with what was transcribed).
    ///
    /// ### Why it disarms rather than falling through
    ///
    /// A mode can only be armed on a device that could run it — that is the arming
    /// policy — but the device can lose Apple Intelligence afterwards, and then the
    /// armed mode describes a transformation nothing can perform. Leaving it armed
    /// would fail closed on every dictation from then on, so the user would get
    /// *nothing* inserted, indefinitely, for a setting they made weeks ago. Clearing
    /// it puts them back on the free polish and — once the fan and the mic pill
    /// exist — changes what they see, which is the honest signal.
    ///
    /// Only the device half of availability is consulted. The #315 rate-limit latch
    /// belongs to whichever process is running generations and clears on its next
    /// launch; disarming a sticky setting over a transient, per-process condition
    /// read from the wrong process would be worse than the failure it avoids.
    public static func resolveArmedMode() -> SmartMode? {
        guard let identifier = armedIdentifier else { return nil }
        guard let mode = SmartModeCatalogue.mode(withIdentifier: identifier) else {
            // An identifier this build does not know: a downgrade, or a corrupted
            // value. Clear it so the state on disk matches the Normal the user is
            // actually getting.
            disarm()
            PersistentLog.log(.smartModeDisarmed(mode: identifier, reason: "unknown-mode"))
            return nil
        }
        guard SmartModeAvailability.deviceCanRunModes else {
            let reason = SmartModeAvailability
                .armability(engineState: PolishAvailability.state, engineIsRefusing: false)
                .reason?.slug ?? "unavailable"
            disarm()
            PersistentLog.log(.smartModeDisarmed(mode: identifier, reason: reason))
            return nil
        }
        return mode
    }

    // MARK: - The pinned list

    /// Identifiers of the modes the user pinned to the keyboard's long-press fan.
    ///
    /// Absent means the user has never chosen, which is not the same as choosing
    /// nothing — an install with no list gets `SmartModeCatalogue.defaultPinnedIdentifiers`
    /// so the fan has something in it before they ever open the mode list. An empty
    /// stored array is a real choice and is honoured.
    public static var pinnedIdentifiers: [String] {
        guard let stored = defaults.stringArray(forKey: SharedKeys.smartModePinned) else {
            return SmartModeCatalogue.defaultPinnedIdentifiers
        }
        return stored
    }

    /// Replace the pinned list. Order is the user's and is preserved; the list is
    /// capped at `SmartModeCatalogue.maximumPinnedModes` because the fan cannot draw
    /// more than that.
    public static func setPinned(_ identifiers: [String]) {
        let capped = Array(identifiers.prefix(SmartModeCatalogue.maximumPinnedModes))
        defaults.set(capped, forKey: SharedKeys.smartModePinned)
        defaults.synchronize()
    }

    /// Forget the user's pinned list, returning to the seed. Exists for tests and
    /// for a settings reset; nothing in the dictation path calls it.
    public static func resetPinned() {
        defaults.removeObject(forKey: SharedKeys.smartModePinned)
        defaults.synchronize()
    }
}
