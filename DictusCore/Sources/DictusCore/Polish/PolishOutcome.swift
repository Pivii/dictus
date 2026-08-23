// DictusCore/Sources/DictusCore/Polish/PolishOutcome.swift
// What a polish call hands back, including "nothing" (issue #79).
import Foundation

/// Why an armed Smart Mode produced no text.
///
/// Carries what a surface needs to say so without reopening the pipeline: which mode
/// it was, and enough about the failure to tell a rejected transformation from a
/// backend that never answered.
public struct SmartModeFailure: Equatable, Sendable {

    /// `SmartMode.id` of the mode that was armed.
    public let modeIdentifier: String

    /// Its display name, so the message can name the mode the user chose.
    public let modeDisplayName: String

    /// The `PolishMetrics.Outcome` raw value that refused the text —
    /// `rejectedGuardrail`, `engineFailed`, `exceededContextBudget`,
    /// `engineUnavailable`, `cancelled`.
    public let outcome: String

    /// The engine's own name for what it threw (`PolishFailureReason.slug`), or "-"
    /// when nothing was thrown. A string rather than the reason itself because
    /// `PolishFailureReason` wraps an `Error` and is not `Equatable`.
    public let reason: String

    public init(modeIdentifier: String,
                modeDisplayName: String,
                outcome: String,
                reason: String) {
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.outcome = outcome
        self.reason = reason
    }
}

/// The result of one polish call.
///
/// ### Why this is not just a `String`
///
/// The free polish always has an answer: on any failure it returns the deterministic
/// floor, and the user gets their text slightly less tidy. A Smart Mode does not.
/// Its floor is the *untransformed* text, and inserting that is the worst outcome
/// available — French sent to an American client, or two minutes of rambling pasted
/// where three bullets were expected. #79 states it as a rule: **Smart Mode must
/// never silently insert untransformed text.**
///
/// So a call can now come back with nothing, and the caller has to decide what to do
/// about it rather than typing whatever string it was handed.
public struct PolishOutcome: Equatable, Sendable {

    /// The text to insert, or nil when an armed Smart Mode failed and nothing may be
    /// inserted in its place.
    public let text: String?

    /// Set with, and only with, a nil `text`.
    public let smartModeFailure: SmartModeFailure?

    /// A successful call, or a free-polish call that fell back to its floor.
    public init(text: String) {
        self.text = text
        self.smartModeFailure = nil
    }

    /// A Smart Mode that produced nothing insertable.
    public init(failure: SmartModeFailure) {
        self.text = nil
        self.smartModeFailure = failure
    }
}
