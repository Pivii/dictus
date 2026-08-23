// DictusCore/Sources/DictusCore/Polish/SmartMode.swift
// A Smart Mode: one record, not an enum case (issue #79).
import Foundation

/// The three strings one Smart Mode sends to the engine.
///
/// Split out from `SmartMode` because they are the engine's business and nothing
/// else's, and because the user turn is not decoration: `AppleFoundationModelsPolishEngine`
/// used to hardcode *"Polish this text. Output only the polished version, nothing
/// else."* around every input. Asking a model to produce notes under an instruction
/// that says "polish" is self-defeating, so the framing became per-mode (#79).
public struct SmartModePrompt: Equatable, Sendable, Codable {

    /// The system prompt. One per mode, written in English, instructing the model
    /// to answer in the language of the input — except translation, which names its
    /// target. This is the #239 auto-prompt pattern, applied so a mode costs one
    /// file instead of one file per supported language.
    public let instructions: String

    /// The imperative that opens the user turn, e.g. "Turn this text into notes."
    public let userInstruction: String

    /// The trailing marker that biases the model toward continuing the transform
    /// rather than starting a chat reply, e.g. "Notes:". Same device as the
    /// "Polished output:" marker the polish framing has always used.
    public let outputMarker: String

    public init(instructions: String, userInstruction: String, outputMarker: String) {
        self.instructions = instructions
        self.userInstruction = userInstruction
        self.outputMarker = outputMarker
    }
}

/// One Smart Mode.
///
/// ### Data, not enum cases
///
/// A mode is a record — identifier, prompt, acceptance contract, display name,
/// icon, pinned flag. v1 ships built-ins only (`SmartModeCatalogue`), but they are
/// already records, so the custom-mode editor (#269) adds a row rather than forcing
/// a refactor, and the whole record can cross the App Group with the dictation it
/// governs.
///
/// ### What is persisted, and what is not
///
/// The *armed selection* persists as an identifier (`SmartModeStore`); the record
/// itself is rebuilt from the catalogue each time it is needed. That is deliberate:
/// persisting a built-in's prompt would freeze whichever version of it was current
/// when the user first armed the mode, and prompts are versioned with the binary.
///
/// The one place a whole record *is* written down is the per-dictation snapshot —
/// taken in DictusApp at transcription start and read by the keyboard extension,
/// which runs the engine since #361. It is a snapshot for exactly the reason
/// `TranscriptionLanguagePolicy` is one (#226): the user must not be able to change
/// the mode mid-transcription and have the transformation disagree with what was
/// transcribed. Re-reading the armed mode on the far side would reintroduce that in
/// the worst possible place, since the keyboard is where the mode is armed.
public struct SmartMode: Equatable, Sendable, Codable, Identifiable {

    /// Stable identifier. Also the session-cache key component and what the metrics
    /// event records, so it must not change once a mode has shipped.
    public let id: String

    /// Name shown in the fan, in the recording overlay, and in the app's mode list.
    public let displayName: String

    /// SF Symbol name.
    public let icon: String

    /// What the engine is told to do.
    public let prompt: SmartModePrompt

    /// What the engine is allowed to hand back. Per mode, because the faithful-polish
    /// contract rejects half the catalogue by construction — see
    /// `PolishAcceptanceContract`.
    public let contract: PolishAcceptanceContract

    /// Whether the user put this mode in the keyboard's long-press fan.
    ///
    /// Part of the record because the fan is chosen per mode, but stored separately
    /// from it — `SmartModeStore.pinnedIdentifiers` is the authority, and
    /// `SmartModeCatalogue` stamps this field when it builds the list. A record that
    /// travelled with a dictation carries whatever the flag was at snapshot time and
    /// nothing reads it there.
    public var isPinned: Bool

    public init(id: String,
                displayName: String,
                icon: String,
                prompt: SmartModePrompt,
                contract: PolishAcceptanceContract,
                isPinned: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.prompt = prompt
        self.contract = contract
        self.isPinned = isPinned
    }

    /// The same record with its pinned flag set. Used by the catalogue when it
    /// merges the stored pin list onto the built-in rows.
    public func pinned(_ isPinned: Bool) -> SmartMode {
        var copy = self
        copy.isPinned = isPinned
        return copy
    }
}
