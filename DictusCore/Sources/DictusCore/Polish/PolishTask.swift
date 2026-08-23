// DictusCore/Sources/DictusCore/Polish/PolishTask.swift
// What the model is being asked to do for one dictation (issue #79).
import Foundation

/// The transformation one dictation runs: the free polish, or an armed Smart Mode.
///
/// ### Why one value instead of two parameters
///
/// A prompt and the contract its output is judged against must not be able to
/// disagree. Threading a `PolishMode` and an optional `SmartMode` side by side
/// through the pipeline would make that a convention every call site has to keep;
/// carrying one value makes it structural — there is no way to run Notes' prompt and
/// then judge its output against the faithful-polish band, because the band comes
/// off the same value the prompt did.
///
/// It is also what makes the session cache key identifier-based, which #79 asks for:
/// `AppleFoundationModelsPolishEngine` keyed its `LanguageModelSession` cache on
/// `(PolishMode, SupportedLanguage)`, and a mode that is a record has no enum case to
/// key on.
public enum PolishTask: Equatable, Sendable {

    /// The free polish, in one of its three prompt variants (ADR 0003, #239).
    case polish(PolishMode)

    /// An armed Smart Mode (#79). Pro, and intentionally transformative — the line
    /// the paywall copy carries is that polish is free and faithful, and a Smart
    /// Mode is neither.
    case smart(SmartMode)

    // MARK: - Shorthands for the free-polish variants

    public static let natural = PolishTask.polish(.natural)
    public static let repair = PolishTask.polish(.repair)
    public static let auto = PolishTask.polish(.auto)

    // MARK: - What the pipeline asks of it

    /// Stable name for this task. The session-cache key component, the value the
    /// metrics event records, and what a debug export is read by — so it must not
    /// change once a mode has shipped.
    ///
    /// Smart Modes are namespaced so a future custom mode (#269) called "natural"
    /// cannot collide with the polish variant of that name.
    public var identifier: String {
        switch self {
        case .polish(let mode): return mode.rawValue
        case .smart(let mode): return "smart.\(mode.id)"
        }
    }

    /// What the engine's output has to look like to be accepted.
    public var contract: PolishAcceptanceContract {
        switch self {
        case .polish(.natural): return .natural
        case .polish(.repair): return .repair
        case .polish(.auto): return .auto
        case .smart(let mode): return mode.contract
        }
    }

    /// The armed Smart Mode, or nil for the free polish.
    public var smartMode: SmartMode? {
        guard case .smart(let mode) = self else { return nil }
        return mode
    }

    /// The free-polish prompt variant, or nil when a Smart Mode is armed.
    public var polishMode: PolishMode? {
        guard case .polish(let mode) = self else { return nil }
        return mode
    }

    /// Whether a Smart Mode is armed.
    ///
    /// The pipeline branches on this in three places, all of them the same
    /// principle: **a Smart Mode must never silently insert untransformed text.**
    /// For polish, falling back to the raw is invisible and harmless. For a mode it
    /// is the worst outcome — French sent to an American client, or two minutes of
    /// rambling pasted where three bullets were expected.
    public var isSmart: Bool { smartMode != nil }

    // MARK: - What the engine asks of it

    /// The imperative that opens the user turn.
    ///
    /// Per task since #79. `AppleFoundationModelsPolishEngine` hardcoded the polish
    /// framing around every input, and asking the model to produce notes under an
    /// instruction that says "polish" is self-defeating.
    public var userInstruction: String {
        switch self {
        case .polish: return "Polish this text. Output only the polished version, nothing else."
        case .smart(let mode): return mode.prompt.userInstruction
        }
    }

    /// The trailing marker that biases the model toward continuing the transform
    /// rather than starting a chat reply.
    public var outputMarker: String {
        switch self {
        case .polish: return "Polished output:"
        case .smart(let mode): return mode.prompt.outputMarker
        }
    }

    /// The user turn the engine sends: the imperative, the input under an explicit
    /// `Input:` label, and the trailing marker.
    ///
    /// Without this framing Apple FM treats the raw as a conversational turn and
    /// emits chat-reply acknowledgements ("I'll polish it for you") instead of the
    /// transformed text.
    ///
    /// WHY it lives on the task rather than inside the engine: the #268 spike sends
    /// these exact bytes to a Core ML model outside the engine's process, and it
    /// briefly had a hand-copy of the framing — which would silently measure a
    /// different prompt the moment either side changed. It is also pure string
    /// composition with no availability gate, unlike the engine that sends it.
    public func userTurn(raw: String) -> String {
        """
        \(userInstruction)

        Input:
        \(raw)

        \(outputMarker)
        """
    }

    /// Whether this task's prompt is written once for every input language, so the
    /// engine must not vary its session key with the caller-supplied language.
    ///
    /// True for `.auto` (#239) and for every Smart Mode (#79): both follow the
    /// one-English-prompt pattern. A translation mode names its target *inside* its
    /// instructions, so its session is still per-target — the target is part of the
    /// identifier, not of the language key.
    public var hasLanguageAgnosticPrompt: Bool {
        switch self {
        case .polish(let mode): return mode == .auto
        case .smart: return true
        }
    }
}
