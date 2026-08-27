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

    /// Whether this flow can offer the user a way off the preparation screen (#428).
    ///
    /// Onboarding cannot, and the reason is not politeness: at that point there is no
    /// second model on disk to switch to and no tab bar behind the screen to land on,
    /// so an escape would dismiss the flow into nothing.
    ///
    /// The other two must. Both are reachable with a model already installed and a
    /// compile that may never finish, and both hide the entire app while they wait.
    /// The escape is offered late (`ModelPreparationEscape.revealDelaySeconds`) and is
    /// an offer, not an interruption: taking it stops the app waiting, it does not and
    /// cannot stop the compile.
    public var allowsEscape: Bool {
        self != .onboarding
    }
}

/// How the preparation screen's escape hatch is timed (issue #428).
public enum ModelPreparationEscape {
    /// How long the screen stays escapeless before it offers a way out.
    ///
    /// WHY not immediately: the screen exists to stop the user tapping the mic
    /// mid-load, which is what produced the `CancellationError` cascade in issue #144.
    /// That reason still holds for every healthy load, and the healthy loads are the
    /// common case. An escape offered at second zero would just be a button that
    /// breaks the thing the screen is for.
    ///
    /// WHY 45s, and why it must not be tuned to "cover" a compile:
    ///
    /// The two figures anyone will find in the device log are 3.6s and 212s+, and both
    /// are real. They are the same model on the same iPhone in the same session:
    ///
    ///     09:19:53Z modelCompilationStarted   turbo_632MB
    ///     09:23:25Z modelPrewarmTimeout       turbo_632MB    <- 212s in, still running
    ///     09:28:44Z modelCompilationStarted   turbo_632MB
    ///     09:28:48Z modelCompilationCompleted turbo_632MB duration=3636ms
    ///
    /// The FIRST compile of a variant on a device builds the Core ML bundle cache and
    /// runs into the minutes. Three cold readings on that iPhone agree: 212s and still
    /// going above, 236s on 2026-08-25, and 202s start to finish on 2026-08-27. Every
    /// load after it finds that cache and takes seconds.
    ///
    /// The cache lives in the app container, so every development install discards it:
    /// the first launch after an install always pays a cold compile, which is why this
    /// button shows up so readily during testing.
    ///
    /// So 45s sits above every routine wait — a warm load is seconds, and the slowest
    /// preparation measured outside a first compile is Medium at 32s — and below every
    /// per-model deadline in the catalogue, which is at least 120s. The user is always
    /// offered the choice before a deadline makes it for them. `ModelInfoTests` pins
    /// both ends of that window.
    ///
    /// It follows that this button WILL appear during a perfectly healthy first-time
    /// Turbo preparation, because that preparation takes minutes. That is intended, not
    /// a miscalibration, and the copy beside it is written as an offer rather than an
    /// alarm. Do not lengthen this to sit above a cold compile: that would restore the
    /// lockout for exactly the wait that produced issue #428. Do not shorten it either:
    /// the screen refuses input for a real reason (#144) and a routine load must be
    /// allowed to finish undisturbed.
    public static let revealDelaySeconds = 45
}
