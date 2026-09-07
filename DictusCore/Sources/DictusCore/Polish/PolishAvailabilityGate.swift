// DictusCore/Sources/DictusCore/Polish/PolishAvailabilityGate.swift
import Foundation

/// When to stop calling a polish engine that is refusing us (#315).
///
/// WHY this exists: `rateLimited` is not a flake. Apple documents it as a
/// refusal applied to apps running in the background, and DictusApp is
/// backgrounded for every polish call by design — the keyboard holds the screen.
/// A controlled test on 2026-08-13 showed the refusal is decided per call: the
/// same process, seconds apart, was refused backgrounded and served in the
/// foreground. So there is nothing to wait for and nothing to retry. Once the
/// refusals start, every further call costs a round trip and returns nothing.
///
/// WHY two and not three: every `rateLimited` run captured on #315 arrives in a
/// run of at least two, and a single isolated one has never been observed. Two
/// is the smallest threshold that cannot fire on a one-off.
///
/// WHY there is no reset rule: only a fresh process restores the budget. Twenty
/// seconds of foreground did not refund it, and no amount of wall-clock ever has
/// in any capture on that issue. A fresh process gets a fresh value of this
/// type, which *is* the reset — so the correct implementation is to have no
/// timer, no re-arm and no retry, and this type deliberately offers none.
public struct PolishAvailabilityGate: Sendable, Equatable {

    /// How many consecutive `rateLimited` refusals put polish into its
    /// unavailable state.
    public static let consecutiveRefusalsBeforeUnavailable = 2

    /// The engine that is being held unavailable, or `nil` while polish is
    /// available. Exposed so a caller can name it in a log line.
    public private(set) var unavailableEngine: String?

    /// The engine the current refusal run belongs to. A run is per engine: the
    /// backend can change mid-process (Apple Intelligence toggled off drops the
    /// coordinator to the passthrough engine), and refusals from one say nothing
    /// about another.
    private var refusingEngine: String?

    /// Length of the current refusal run, reset by any verdict that proves the
    /// engine served the call.
    private var consecutiveRefusals = 0

    /// A fresh gate is available. This is the whole of the reset rule.
    public init() {}

    /// Whether `engine` may be called at all.
    public func allowsCall(engine: String) -> Bool {
        unavailableEngine != engine
    }

    /// Feed one completed transform outcome.
    ///
    /// Returns `true` on the single call that flips the gate to unavailable, and
    /// `false` on every other, so the caller can announce and log the transition
    /// exactly once without tracking the edge itself.
    @discardableResult
    public mutating func record(outcome: PolishMetrics.Outcome,
                                reason: PolishFailureReason?,
                                engine: String) -> Bool {
        guard unavailableEngine == nil else { return false }

        switch outcome {
        case .engineFailed where reason == .rateLimited:
            // A run belongs to one engine; a refusal from a different backend
            // starts a new one rather than continuing the old count.
            if refusingEngine != engine {
                refusingEngine = engine
                consecutiveRefusals = 0
            }
            consecutiveRefusals += 1
            guard consecutiveRefusals >= Self.consecutiveRefusalsBeforeUnavailable else { return false }
            unavailableEngine = engine
            return true

        case .success, .rejectedGuardrail, .engineFailed:
            // The engine took the call and came back with a verdict — it ran, or
            // it refused for a reason that is not the rate limit (a guardrail
            // violation is a real generation that was rejected). Either way the
            // run is broken.
            refusingEngine = nil
            consecutiveRefusals = 0
            return false

        case .cancelled, .exceededContextBudget, .engineUnavailable,
             .unsupportedInputLanguage,
             .skipped, .skippedShort, .skippedAutoMode:
            // No evidence either way: the engine was never reached, or the call
            // was cut short before it could answer. Leaving the run untouched is
            // what lets a flash dictation in the middle of a refusal run avoid
            // hiding it.
            return false
        }
    }
}
