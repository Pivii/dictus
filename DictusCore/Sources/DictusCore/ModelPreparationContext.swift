import Foundation

/// The user-facing flow that caused model preparation to be shown.
///
/// The same preparation overlay is reused by onboarding, model selection, the
/// keyboard cold-start handoff, and an in-app record tap that landed during a load.
/// Keeping the context explicit lets each flow explain what is happening without
/// duplicating the loading UI.
public enum ModelPreparationContext: String, Codable, CaseIterable, Sendable {
    case onboarding
    case modelSelection
    case keyboardColdStart

    /// A record button *inside Dictus* was tapped while a model load was in flight (#484).
    ///
    /// Before this case the tap was refused in silence by `startDictation`'s load guard —
    /// twelve taps in eleven seconds, no overlay, no message, no disabled state — because
    /// the guard's only route out was the keyboard's, and the keyboard is not where this
    /// user is. It is `.keyboardColdStart`'s in-app twin and shares its one hard rule
    /// (`isPrepareOnly`), but not its assumption that the user came from somewhere else.
    case appRecordTap

    /// Whether this preparation must never turn into a recording by itself.
    ///
    /// Both prepare-only contexts are reached from a *tap the user has already made*, and a
    /// Turbo compile can take three and a half minutes (#432). Starting the microphone at
    /// the end of a wait that long acts on an intent that has almost certainly expired, and
    /// on a phone that may well be back in a pocket. The user taps again; nothing is queued.
    ///
    /// WHY a switch and not `self == …`: a fifth context must be forced to answer this
    /// question rather than inherit `false` from the shape of an equality test.
    public var isPrepareOnly: Bool {
        switch self {
        case .onboarding, .modelSelection:
            return false
        case .keyboardColdStart, .appRecordTap:
            return true
        }
    }

    /// Whether the user reached this screen from *outside* Dictus.
    ///
    /// WHY THIS IS A SECOND BOOLEAN AND NOT `isPrepareOnly` (#484): the flag above used to
    /// carry both "do not start recording by itself" and "you came here from another app",
    /// which held only as long as the keyboard was the sole prepare-only entry point. The
    /// two questions have different answers for `.appRecordTap`, and it is *this* one that
    /// decides the completion sentence — "return to your app" is false for someone who never
    /// left it — and which of the two waiting notices is shown. Staying in the foreground is
    /// what keeps a compile off the system's background throttle (#472), so the in-app case
    /// asks the user to stay on the page rather than merely to wait.
    public var startedFromAnotherApp: Bool {
        switch self {
        case .keyboardColdStart:
            return true
        case .onboarding, .modelSelection, .appRecordTap:
            return false
        }
    }

}

/// How a preparation ends, for the screen that is watching it (issue #428).
///
/// This type used to time an escape hatch as well. The escape was cut from #428 after
/// four review passes put every serious finding in it or in something it forced; what
/// remains is the part that has nothing to do with the user leaving the screen, and
/// everything to do with the screen telling the truth about how a load finished.
public enum ModelPreparationOutcome {

    /// The launch preload's deadline expired. Written by `runLaunchPreload`.
    public static let deadlineExpiredReason = "init-preload-deadline"

    public static let gaveUpReasons: Set<String> = [deadlineExpiredReason]

    /// Whether a load-state reason means the app gave up rather than finished.
    public static func reasonMeansGaveUp(_ reason: String) -> Bool {
        gaveUpReasons.contains(reason)
    }
}
