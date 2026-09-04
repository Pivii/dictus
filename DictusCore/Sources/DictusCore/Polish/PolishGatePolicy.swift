// DictusCore/Sources/DictusCore/Polish/PolishGatePolicy.swift
// Which gates may skip the engine, and when (issue #79).
import Foundation

/// The three gates that can stop the polish engine running, as pure rules.
///
/// All three were written for the free polish, where skipping the model is
/// invisible: the user gets their text, slightly less tidy. **A Smart Mode turns
/// every one of them into a silent failure** — arm "→ EN", say a short sentence in
/// 1.8 s, and the keyboard inserts French. So each one asks whether a mode is armed
/// before it skips (#79).
///
/// WHY they are here rather than inline in `PolishService`: that type is `@MainActor`
/// and reads the App Group, so the rules were unreachable from a test. They are the
/// part of this change most likely to be got wrong twice — once per polish path —
/// which is exactly the shape `ColdStartResolutionPolicy` and `KeyboardHandoffStage`
/// were extracted for.
public enum PolishGatePolicy {

    /// Recording duration (seconds) below which the free polish skips the engine
    /// (#141). On flash dictations the user wants instant text and the model rarely
    /// adds value for the latency. Deterministic passes still run.
    public static let engineMinDuration: TimeInterval = 2.0

    /// Whether the user's global polish toggle may stop this task.
    ///
    /// It may not stop a Smart Mode. The toggle defaults to off and is the user
    /// saying they do not want their transcriptions tidied; arming a mode is the
    /// same user explicitly asking for a transformation of that dictation, which is
    /// a narrower and later instruction. Honouring the toggle over it would insert
    /// untransformed text on the one path where that is the worst outcome.
    public static func runsDespiteToggle(task: PolishTask, polishEnabled: Bool) -> Bool {
        polishEnabled || task.isSmart
    }

    /// Whether the duration gate skips the engine for this dictation.
    public static func skipsForDuration(_ duration: TimeInterval, task: PolishTask) -> Bool {
        guard !task.isSmart else { return false }
        return duration < engineMinDuration
    }

    /// Whether the gibberish gate skips the engine for this dictation.
    ///
    /// `hasDetectedLanguage` is false when `NLLanguageRecognizer` was not confident
    /// — and, on the per-language path, also when it was confident about a language
    /// that path has no prompt for. Below that confidence the free polish returns
    /// the deterministic floor, which preserves trust (ADR 0002). A Smart Mode runs
    /// anyway: short sentences to translate land here routinely, and its prompt does
    /// not depend on detection having succeeded.
    public static func skipsForGibberish(hasDetectedLanguage: Bool, task: PolishTask) -> Bool {
        guard !task.isSmart else { return false }
        return !hasDetectedLanguage
    }
}
