// DictusCore/Sources/DictusCore/SpeechEngine.swift
import Foundation

/// Identifies which speech-to-text engine a model uses.
///
/// WHY an enum with raw values:
/// Each model belongs to a specific engine (WhisperKit or Parakeet). Storing
/// as a Codable rawValue ("WK"/"PK") allows persistence in UserDefaults and
/// easy serialization. Parakeet is a placeholder for future FluidAudio integration.
///
/// `Sendable` is stated rather than inferred: a public frozen-by-default enum in a
/// library gets no implicit conformance across module boundaries, so every
/// `Sendable` type holding one — `TranscriptionLanguagePolicy` is the first, and it
/// crosses the App Group into the keyboard — warns without it. A `String`-backed
/// enum with no associated values carries no mutable state, so the conformance is
/// a statement of fact and needs no `@unchecked`.
public enum SpeechEngine: String, Codable, Sendable {
    case whisperKit = "WK"
    case parakeet = "PK"

    /// Human-readable name for UI display.
    public var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet: return "Parakeet"
        }
    }
}
