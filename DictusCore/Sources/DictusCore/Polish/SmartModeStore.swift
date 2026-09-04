// DictusCore/Sources/DictusCore/Polish/SmartModeStore.swift
// The armed Smart Mode and the pinned list, in the App Group (issue #79).
import Foundation

/// A dictation's armed mode was resolved away, and the user has not been told (#423).
///
/// Carries the mode's own name rather than only its identifier because the surface
/// that shows the sentence is in the other process, and it should not have to resolve
/// a record to name what did not happen.
public struct SmartModeSkipNotice: Codable, Equatable, Sendable {

    /// The mode that stayed armed and did not run.
    public let modeIdentifier: String

    /// Its catalogue label — "List", "\u{2192} EN" — for the sentence.
    public let modeDisplayName: String

    /// Why it did not run. Decides which sentence the surface shows.
    public let reason: SmartModeUnavailableReason

    public init(modeIdentifier: String, modeDisplayName: String, reason: SmartModeUnavailableReason) {
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.reason = reason
    }

    /// What `SmartModeStore.hasAnnouncedSkip` compares. Both halves, because the same
    /// mode can become unrunnable for a different reason and that is a new thing to
    /// say.
    var token: String { "\(modeIdentifier)|\(reason.slug)" }
}

/// What a starting dictation gets back from `SmartModeStore.resolveArmedMode()`.
///
/// Two values rather than one because the second used to be thrown away. The mode is
/// what the pipeline runs; the notice is what the user is owed when the answer to
/// "which mode" is "none of the one you armed". #79 specifies that an unavailable
/// Smart Mode fails closed with an explicit message, and this path failed **open**
/// and said nothing.
public struct SmartModeResolution: Equatable, Sendable {

    /// The mode this dictation will actually run, or nil for Normal.
    public let mode: SmartMode?

    /// Set only when a mode was armed, will not run, and the user should hear about
    /// it. Nil when nothing was armed, when the mode runs, or when the armed value
    /// was garbage this build cleared on sight — there is no user choice to explain
    /// in that last case.
    public let skipped: SmartModeSkipNotice?

    public init(mode: SmartMode?, skipped: SmartModeSkipNotice? = nil) {
        self.mode = mode
        self.skipped = skipped
    }
}

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
        // The state changed, so whatever the user was last told about a skip no
        // longer describes what they have set (#423).
        clearAnnouncedSkip()
        defaults.synchronize()
    }

    /// Return to Normal: the free polish, which is the default state.
    public static func disarm() {
        defaults.removeObject(forKey: SharedKeys.smartModeArmed)
        clearAnnouncedSkip()
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
    /// ### Why it falls back rather than failing closed
    ///
    /// A mode can only be armed on a device that could run it — that is the arming
    /// policy — but the device can lose Apple Intelligence afterwards, and then the
    /// armed mode describes a transformation nothing can perform. Returning it
    /// anyway would fail closed on every dictation from then on, and the user would
    /// get *nothing* inserted, indefinitely, for a setting they made weeks ago. So
    /// the dictation runs Normal and a line says why.
    ///
    /// ### And why it only sometimes disarms
    ///
    /// **Clearing the setting is reserved for conditions that can never lift on
    /// their own** — ineligible hardware, an OS too old, a build without the SDK.
    /// A model still downloading is recoverable, and a mode disarmed over it would
    /// be a setting silently lost to a temporary state: the user would come back an
    /// hour later to a keyboard that had quietly forgotten what they armed.
    ///
    /// The device half of availability and the entitlement are consulted; the #315
    /// rate-limit latch is not. That latch belongs to whichever process is running
    /// generations and clears on its next launch, and reading a transient,
    /// per-process condition from the wrong process to decide a sticky setting would
    /// be worse than the failure it avoids.
    ///
    /// The entitlement belongs here for the opposite reason: it is not transient and
    /// it is not per-process. A subscription that lapsed a month ago is still lapsed
    /// in every process, and this is the one call every dictation makes — so it is
    /// where a cancelled user stops getting the paid feature, rather than whenever
    /// they next open the app (#392). It does not disarm, because `.notSubscribed`
    /// is recoverable: resubscribe and the mode they chose is still there.
    ///
    /// ### Why it returns a notice as well as a mode
    ///
    /// Keeping the armed value is right and stays. What was wrong is that the
    /// fallback was **silent** (#423): text was inserted, the outcome was an
    /// ordinary success, and the only trace was a WARNING in a log the user never
    /// reads. #79 specifies that an unavailable Smart Mode fails closed with an
    /// explicit message; this path fails open, so it owes one. The notice travels
    /// to whichever surface can say it — for a keyboard dictation, across the App
    /// Group, because the toolbar belongs to the other process.
    public static func resolveArmedMode() -> SmartModeResolution {
        guard let identifier = armedIdentifier else { return SmartModeResolution(mode: nil) }
        guard let mode = SmartModeCatalogue.mode(withIdentifier: identifier) else {
            // An identifier this build does not know: a downgrade, or a corrupted
            // value. Definitively unusable, so clear it — the state on disk should
            // match the Normal the user is actually getting.
            //
            // No notice, and that is the one skip with nothing to explain: there is
            // no mode to name, and the user made no choice this build can describe.
            disarm()
            PersistentLog.log(.smartModeSkipped(
                mode: identifier, reason: "unknown-mode", disarmed: true
            ))
            return SmartModeResolution(mode: nil)
        }
        // The enforcement point for a lapsed subscription (#392) and for a switched
        // off feature (#423). Checked on every dictation, in the process that runs
        // it, so a cancellation stops applying the mode without waiting for the user
        // to open the app — otherwise a cancelled subscriber keeps the paid feature
        // until something else happens to clear the value.
        //
        // `SmartModeAvailability.forDictation` and not an inline call, so the
        // surfaces that draw the armed mode resolve it from the same expression. The
        // two answering differently is #423.
        guard let reason = SmartModeAvailability.forDictation.reason else {
            // The mode is running, so any skip the user was told about is over.
            clearAnnouncedSkip()
            return SmartModeResolution(mode: mode)
        }
        let disarms = !reason.isRecoverable
        if disarms { disarm() }
        PersistentLog.log(.smartModeSkipped(
            mode: identifier, reason: reason.slug, disarmed: disarms
        ))
        return SmartModeResolution(
            mode: nil,
            skipped: SmartModeSkipNotice(
                modeIdentifier: identifier,
                modeDisplayName: mode.displayName,
                reason: reason
            )
        )
    }

    // MARK: - Telling the user, once

    /// Whether `notice` has already been shown since the state last changed (#423).
    ///
    /// WHY the decision lives here and the *act* of announcing does not: the resolve
    /// runs in DictusApp and the sentence appears in the keyboard, and DictusApp has
    /// no non-fatal notice surface of its own (see `DictationHandoff`). A resolve
    /// that marked the notice spent would let an in-app dictation consume the one
    /// showing the keyboard was going to do. So the surface that actually put the
    /// words on screen is the one that calls `noteSkipAnnounced`.
    public static func hasAnnouncedSkip(_ notice: SmartModeSkipNotice) -> Bool {
        defaults.string(forKey: SharedKeys.smartModeSkipAnnounced) == notice.token
    }

    /// Record that the user has now been told about `notice`.
    public static func noteSkipAnnounced(_ notice: SmartModeSkipNotice) {
        defaults.set(notice.token, forKey: SharedKeys.smartModeSkipAnnounced)
        defaults.synchronize()
    }

    /// Forget what the user was told, so the next skip is announced again.
    ///
    /// Called from `arm`, `disarm` and a successful resolve — the three ways the
    /// state this describes can change.
    public static func clearAnnouncedSkip() {
        defaults.removeObject(forKey: SharedKeys.smartModeSkipAnnounced)
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
