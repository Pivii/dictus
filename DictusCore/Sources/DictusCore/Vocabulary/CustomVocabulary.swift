// DictusCore/Sources/DictusCore/Vocabulary/CustomVocabulary.swift
// Who may use the vocabulary, and the two things it does with it (#80).
import Foundation

/// The entitlement policy for custom vocabulary (#80).
///
/// A type rather than two `if`s at the call sites, for the reason
/// `HistoryAvailability` gives: an entitlement answered inline, in whichever
/// consumer happens to need it, is an entitlement the next consumer will answer
/// differently. There are already two — the replacement pass in DictusApp and the
/// glossary in whichever process is polishing.
public enum VocabularyAvailability {

    /// Whether the user is paying for the vocabulary **and** has it switched on.
    ///
    /// `FeatureGate.isAvailable` and not `isProActive`, matching
    /// `HistoryAvailability.isEntitled`: `SharedKeys.vocabularyEnabled` is seeded to
    /// `true` by `ProStatusManager.seedFeatureTogglesIfNeeded`, and a subscriber who
    /// switched it off in Settings has said what they want.
    ///
    /// Turning it off stops the replacements and the glossary contribution. It does
    /// not delete anything — see `VocabularyStore`, where removal is ungated.
    public static var isEntitled: Bool {
        FeatureGate.isAvailable(.vocabulary)
    }
}

/// The two things the vocabulary does, behind one gate.
///
/// Both consumers go through here rather than reading the store directly, so the
/// entitlement is checked in one place and the "nothing stored" path is one
/// expression instead of two.
public enum CustomVocabulary {

    /// Rewrite the engine's variants into the user's spellings.
    ///
    /// **Called at the consumer of `TranscriptionService.transcribe()`**, which is
    /// `DictationCoordinator` — upstream of both the in-app tail and the keyboard
    /// hand-off, and upstream of `VerbalPunctuationPrepass` and the polish. See
    /// `VocabularyReplacer` for why that position is the only correct one.
    ///
    /// Returns its input, unchanged and un-copied, for every user who is not
    /// entitled or has stored nothing. That identity is the issue's pre-registered
    /// bar.
    public static func corrected(_ text: String,
                                 entries: [VocabularyEntry]? = nil) -> String {
        let entries = entries ?? activeEntries()
        guard !entries.isEmpty else { return text }
        return VocabularyReplacer.apply(text, entries: entries)
    }

    /// The user's canonical terms, for the polish glossary (#80 decision 7).
    ///
    /// This is what makes an entry with no variants useful: the prompt is told to
    /// spell the term exactly as written. It only reaches users with Apple
    /// Intelligence, which is why the issue calls it a silent bonus rather than
    /// something the paywall promises.
    public static func glossaryTerms() -> [String] {
        activeEntries().map(\.term)
    }

    /// The enabled entries, or none at all when the feature is not the user's.
    ///
    /// Read from disk on every call rather than cached. A dictation is the unit
    /// here: one read of at most 200 short records per transcription, in a process
    /// that has just finished running a speech model, against a cache that would
    /// have to be invalidated across two processes to stay correct.
    static func activeEntries() -> [VocabularyEntry] {
        guard VocabularyAvailability.isEntitled else { return [] }
        return VocabularyStore.loadEntries().filter(\.isEnabled)
    }
}
