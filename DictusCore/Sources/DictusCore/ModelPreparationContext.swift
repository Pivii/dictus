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
