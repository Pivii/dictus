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

    /// Language-agnostic polish for Auto-detect transcription mode (#239):
    /// the input language was auto-detected by the STT engine, so there is no
    /// per-language prompt to pick. A single English-written prompt instructs
    /// the model to polish the text in whatever language it is written in —
    /// light corrections only, never translate. Active for BOTH engines when
    /// the transcription-language mode is Auto. The verbal-punctuation
    /// pre-pass runs keyed on the DETECTED language (see
    /// `PolishPipeline.autoPreprocess`); the language-specific typography
    /// POST-pass stays off in this mode — the prompt owns typography.
    case auto
}
