// DictusCore/Sources/DictusCore/ModelInfo.swift
import Foundation

/// Metadata for a supported WhisperKit model variant.
/// Used by the model manager UI and smart routing logic.
///
/// Each model has a WhisperKit identifier (matching the argmaxinc/whisperkit-coreml
/// repository naming), a human-readable display name, and labels for size/accuracy/speed.
public struct ModelInfo {
    public let identifier: String
    public let displayName: String
    public let sizeLabel: String
    public let accuracyLabel: String
    public let speedLabel: String
    public let sizeBytes: Int64

    /// All supported WhisperKit models for Dictus, ordered from smallest to largest.
    public static let all: [ModelInfo] = [
        ModelInfo(
            identifier: "openai_whisper-tiny",
            displayName: "Tiny",
            sizeLabel: "~40 MB",
            accuracyLabel: "Good",
            speedLabel: "Fast",
            sizeBytes: 40_000_000
        ),
        ModelInfo(
            identifier: "openai_whisper-base",
            displayName: "Base",
            sizeLabel: "~75 MB",
            accuracyLabel: "Good",
            speedLabel: "Fast",
            sizeBytes: 75_000_000
        ),
        ModelInfo(
            identifier: "openai_whisper-small",
            displayName: "Small",
            sizeLabel: "~250 MB",
            accuracyLabel: "Better",
            speedLabel: "Balanced",
            sizeBytes: 250_000_000
        ),
        ModelInfo(
            identifier: "openai_whisper-medium",
            displayName: "Medium",
            sizeLabel: "~750 MB",
            accuracyLabel: "Best",
            speedLabel: "Slow",
            sizeBytes: 750_000_000
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v3_turbo",
            displayName: "Large v3 Turbo",
            sizeLabel: "~950 MB",
            accuracyLabel: "Best",
            speedLabel: "Balanced",
            sizeBytes: 950_000_000
        ),
    ]

    /// Set of all supported model identifiers for quick lookup.
    public static let supportedIdentifiers: Set<String> = Set(all.map(\.identifier))

    /// Look up a model by its WhisperKit identifier.
    /// Returns nil if the identifier is not in the supported list.
    public static func forIdentifier(_ id: String) -> ModelInfo? {
        all.first { $0.identifier == id }
    }
}
