// DictusCore/Sources/DictusCore/Polish/PolishMode.swift
import Foundation

/// Polish prompt variant selected at runtime by `NLLanguageRecognizer`.
///
/// See ADR 0002 for the faithfulness contract that scopes each mode.
public enum PolishMode: String, Codable, Sendable {
    /// Content-words preserved. Punctuation, capitalisation, accents,
    /// digits-from-spoken-numbers, verbal-punctuation, typo fixes.
    /// Active for Whisper always; active for Parakeet when detected == target.
    case light

    /// Words may be substituted to reconstruct the user's intent in the
    /// target language. Active only on Parakeet when detected != target.
    case repair
}
