import Foundation

/// The user-facing flow that caused model preparation to be shown.
///
/// The same preparation overlay is reused by onboarding, model selection, and
/// the keyboard cold-start handoff. Keeping the context explicit lets each flow
/// explain what is happening without duplicating the loading UI.
public enum ModelPreparationContext: String, Codable, CaseIterable, Sendable {
    case onboarding
    case modelSelection
    case keyboardColdStart

    /// Keyboard cold start is deliberately prepare-only: it must never begin
    /// recording automatically after a potentially long wait.
    public var isPrepareOnly: Bool {
        self == .keyboardColdStart
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
