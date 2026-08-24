// DictusCore/Sources/DictusCore/Polish/SmartModeCatalogue.swift
// The Smart Modes this build ships (issue #79).
import Foundation

/// The catalogue of Smart Modes.
///
/// ### v1 ships two families, and Email is not one of them
///
/// **Notes** moves the text along the structure axis, **Translate → X** along the
/// language axis. SMS and Summary were cut in the design session: the free polish
/// already produces natural conversational text — that is literally the ADR 0003
/// `natural` contract — so an SMS mode would be the one paid mode whose output is
/// indistinguishable from the free one, and Notes already synthesises.
///
/// **Email is conditional and absent from this build.** Two independent
/// implementations fail the same way — they invent greetings and sign-offs the user
/// never dictated, with names the model cannot know — and #79 makes Email's
/// inclusion conditional on the harness showing it can change register and structure
/// while inventing neither. That validation is separate work. When it passes, Email
/// is a row in `builtIns` and a prompt file; nothing else has to move.
///
/// ### The list is data
///
/// Built-in rows are constructed here rather than persisted, so a prompt fix ships
/// with the binary instead of being frozen on every device that ever armed the mode.
/// What persists is the user's part: which mode is armed, and which are pinned
/// (`SmartModeStore`). Custom modes (#269) become a second source merged into `all`.
public enum SmartModeCatalogue {

    // MARK: - Identifiers

    /// Identifier of the Notes mode. Stable — it is the session-cache key component
    /// and what a metrics event records.
    public static let notesIdentifier = "notes"

    /// Identifier of the Translate mode targeting `language`.
    public static func translateIdentifier(target: SupportedLanguage) -> String {
        "translate.\(target.rawValue)"
    }

    // MARK: - The rows

    /// Notes: bullets, synthesised, filler removed, in the speaker's own language.
    ///
    /// The `0.1` floor is what makes this mode possible at all: the ADR 0003 band
    /// starts at `0.5`, and a good three-bullet synthesis of a two-minute dictation
    /// is nowhere near half the input's length. It is a judgement call sized against
    /// what the transformation does, not a measurement — the first thing to revisit
    /// if the harness shows Notes rejecting its own good output.
    public static let notes = SmartMode(
        id: notesIdentifier,
        displayName: "Notes",
        icon: "list.bullet",
        prompt: SmartModePrompt(
            instructions: SmartModeNotesPrompt.instructions(glossary: PolishGlossary.promptBlock),
            userInstruction: SmartModeNotesPrompt.userInstruction,
            outputMarker: SmartModeNotesPrompt.outputMarker
        ),
        contract: PolishAcceptanceContract(
            minimumLengthRatio: 0.1,
            maximumLengthRatio: 2.0,
            outputLanguage: .sameAsInput
        )
    )

    /// Translate → `target`.
    ///
    /// The band is wide on both sides because translation legitimately changes
    /// length by a lot in either direction — German compounds against English, a
    /// French circumlocution against a Spanish verb — and the check that actually
    /// guards this mode is the language one, not the length one.
    public static func translate(to target: SupportedLanguage) -> SmartMode {
        SmartMode(
            id: translateIdentifier(target: target),
            // Deliberately language-neutral, so one string works in every UI locale
            // and fits a 46 pt fan row. A longer, localised label is the app's to
            // render from the identifier if it wants one.
            displayName: "\u{2192} \(target.shortCode)",
            icon: "globe",
            prompt: SmartModePrompt(
                instructions: SmartModeTranslatePrompt.instructions(
                    target: target, glossary: PolishGlossary.promptBlock
                ),
                userInstruction: SmartModeTranslatePrompt.userInstruction(target: target),
                outputMarker: SmartModeTranslatePrompt.outputMarker
            ),
            contract: PolishAcceptanceContract(
                minimumLengthRatio: 0.4,
                maximumLengthRatio: 3.0,
                outputLanguage: .fixed(target)
            )
        )
    }

    /// Every mode this build defines, in catalogue order, with no pin state applied.
    ///
    /// Translation targets are the four tested languages — the same set explicit
    /// transcription and the per-language polish prompts are limited to. They are
    /// **not** filtered by the keyboard language: the spoken language is unknown
    /// until the user speaks, so "→ FR" stays offerable on a French keyboard.
    public static let builtIns: [SmartMode] =
        [notes] + SupportedLanguage.allCases.map { translate(to: $0) }

    /// Every mode, with the user's pin state stamped on each row.
    public static var all: [SmartMode] {
        let pinned = Set(SmartModeStore.pinnedIdentifiers)
        return builtIns.map { $0.pinned(pinned.contains($0.id)) }
    }

    /// The mode with this identifier, or nil when the identifier belongs to no mode
    /// this build ships — an install downgraded from a build with more modes, or a
    /// corrupted value. Nil means Normal, which is the safe answer: the dictation
    /// gets the free polish instead of a transformation nobody can resolve.
    public static func mode(withIdentifier identifier: String) -> SmartMode? {
        all.first { $0.id == identifier }
    }

    /// The modes the user pinned, **in the order they pinned them**, capped at
    /// `maximumPinnedModes`.
    ///
    /// WHY this maps the stored list rather than filtering the catalogue (found
    /// reviewing PR #389): `SmartModeStore.setPinned` states that the order is the
    /// user's and is preserved, and `pinnedIdentifiers` honours it — but filtering
    /// `all` returns catalogue order, so the two disagreed. Pinning
    /// `["translate.de", "notes"]` produced `[notes, translate.de]` here. Block B
    /// builds the long-press fan from this property, so the divergence would have
    /// shipped as a fan that ignores the order the user arranged.
    ///
    /// `compactMap` drops an identifier that belongs to no mode this build ships,
    /// for the same reason `mode(withIdentifier:)` returns nil: a downgrade or a
    /// corrupted value should cost that one entry, not the whole fan.
    public static var pinnedModes: [SmartMode] {
        Array(SmartModeStore.pinnedIdentifiers.compactMap(mode(withIdentifier:)).prefix(maximumPinnedModes))
    }

    /// How many modes may be pinned to the keyboard's long-press fan.
    ///
    /// **#79 is not self-consistent on this number and it is block B/C's to settle.**
    /// Its acceptance criterion says "up to four modes are pinnable"; its geometry
    /// paragraph measures the space below the toolbar at four *entries* — from the
    /// real `KeyMetrics` values, 205 pt on a standard iPhone and 187 pt on an
    /// iPhone SE, at roughly 46 pt a row — and says the fan holds "Normal plus the
    /// modes the user pinned", which makes four entries three modes. The criterion
    /// is the contract, so this follows it; whoever builds the fan owns the
    /// discrepancy.
    public static let maximumPinnedModes = 4

    /// What a fresh install has pinned before the user has ever opened the mode list.
    ///
    /// A seed, not a rule: the moment the user pins anything, `SmartModeStore` holds
    /// their list and this stops being consulted. Notes and "→ EN" because they are
    /// the two entries that demonstrate the two axes the catalogue moves text along.
    public static let defaultPinnedIdentifiers = [
        notesIdentifier,
        translateIdentifier(target: .english)
    ]
}
