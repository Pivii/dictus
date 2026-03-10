// DictusCore/Sources/DictusCore/SpeechEngine.swift
import Foundation

/// Identifies which speech-to-text engine a model uses.
///
/// WHY an enum with raw values:
/// Each model belongs to a specific engine (WhisperKit or Parakeet). Storing
/// as a Codable rawValue ("WK"/"PK") allows persistence in UserDefaults and
/// easy serialization. Parakeet is a placeholder for future FluidAudio integration.
public enum SpeechEngine: String, Codable {
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
