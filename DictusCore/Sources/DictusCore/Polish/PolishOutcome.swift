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

    /// What the transcript was read as, as an `NLLanguage` raw code, or nil when
    /// nothing was readable (#490).
    ///
    /// Here because one refusal has to name it: `unsupportedInputLanguage` means the
    /// language the user spoke is one the model does not read, and a message that
    /// says so without saying which language would leave them guessing. Every other
    /// outcome ignores it.
    public let detectedLanguage: String?

    public init(modeIdentifier: String,
                modeDisplayName: String,
                outcome: String,
                reason: String,
                detectedLanguage: String? = nil) {
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.outcome = outcome
        self.reason = reason
        self.detectedLanguage = detectedLanguage
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
///
/// ### Three shapes, not two
///
/// A mode may also come back with *text and a failure at once*: the transformation
/// did not happen, but this mode declared that the untransformed floor is better
/// than nothing for this particular refusal — see `SmartModeOverflowBehaviour`. The
/// user is told in both failing shapes. Refusing in silence and degrading in silence
/// are the same defect, which is why `smartModeFailure` is what a surface keys on
/// and `text` only decides whether anything is typed.
public struct PolishOutcome: Equatable, Sendable {

    /// The text to insert, or nil when an armed Smart Mode failed and nothing may be
    /// inserted in its place.
    public let text: String?

    /// Set whenever an armed Smart Mode did not produce its transformation —
    /// including the degraded case, where `text` is the untransformed floor rather
    /// than nil.
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

    /// A Smart Mode that did not run, on a mode that accepts the untransformed floor
    /// for this refusal. `text` is that floor.
    public init(degradedTo text: String, failure: SmartModeFailure) {
        self.text = text
        self.smartModeFailure = failure
    }

    /// Whether the text being inserted is the untransformed floor rather than the
    /// mode's own output. What tells the two failure messages apart.
    public var isDegraded: Bool { text != nil && smartModeFailure != nil }
}
