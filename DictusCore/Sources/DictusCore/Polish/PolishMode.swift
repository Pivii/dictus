// DictusCore/Sources/DictusCore/Polish/PolishMode.swift
import Foundation

/// Polish prompt variant selected at runtime by `NLLanguageRecognizer`.
///
/// See ADR 0003 for the faithfulness contract that scopes each mode.
public enum PolishMode: String, Codable, Sendable {
    /// Natural-register polish: punctuation, capitalisation, accents,
    /// digits-from-spoken-numbers, verbal-punctuation, typo fixes, ASR
    /// hallucination repair, and discreet removal of involuntary repetitions
    /// and oral fillers — while preserving the speaker's word choices,
    /// register, contractions, abbreviations, and code-switching.
    /// Active for Whisper always; active for Parakeet when detected == target.
    case natural

    /// Words may be substituted to reconstruct the user's intent in the
    /// target language. Active only on Parakeet when detected != target.
    case repair
}
