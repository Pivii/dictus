// DictusCore/Sources/DictusCore/ModelInfo.swift
import Foundation

/// Visibility state of a model in the download catalog.
///
/// WHY soft deprecation instead of removal:
/// Users who already downloaded Tiny/Base models should still be able to use them.
/// We hide deprecated models from the "new download" catalog but keep them resolvable
/// so ModelManager can display and manage them if present on device.
public enum CatalogVisibility {
    case available
    case deprecated
}

/// Metadata for a supported WhisperKit model variant.
/// Used by the model manager UI and dictation pipeline.
///
/// Each model has a WhisperKit identifier (matching the argmaxinc/whisperkit-coreml
/// repository naming), a human-readable display name, numeric gauge scores for
/// accuracy and speed (0.0-1.0), and a French description.
public struct ModelInfo: Identifiable {
    /// Identifiable conformance uses `identifier` as the unique ID.
    /// WHY Identifiable: SwiftUI's ForEach requires elements to be Identifiable
    /// so it can efficiently diff and animate list changes.
    public var id: String { identifier }

    public let identifier: String
    public let displayName: String
    public let sizeLabel: String
    public let sizeBytes: Int64

    /// Speech-to-text engine this model uses (WhisperKit or Parakeet).
    public let engine: SpeechEngine

    /// Accuracy score from 0.0 (worst) to 1.0 (best), used for gauge display.
    public let accuracyScore: Double

    /// Speed score from 0.0 (slowest) to 1.0 (fastest), used for gauge display.
    public let speedScore: Double

    /// Short French description for the model selection UI.
    public let description: String

    /// Whether this model is shown in the download catalog or only kept for backward compat.
    public let visibility: CatalogVisibility

    // MARK: - Deprecated label properties (backward compat)

    /// Use accuracyScore instead. Kept temporarily for existing UI references.
    @available(*, deprecated, message: "Use accuracyScore gauge instead")
    public var accuracyLabel: String {
        switch accuracyScore {
        case 0.8...: return "Best"
        case 0.5...: return "Better"
        default: return "Good"
        }
    }

    /// Use speedScore instead. Kept temporarily for existing UI references.
    @available(*, deprecated, message: "Use speedScore gauge instead")
    public var speedLabel: String {
        switch speedScore {
        case 0.8...: return "Fast"
        case 0.5...: return "Balanced"
        default: return "Slow"
        }
    }

    // MARK: - Catalog

    /// Models available for new downloads. Excludes deprecated Tiny/Base.
    public static let all: [ModelInfo] = allIncludingDeprecated.filter { $0.visibility == .available }

    /// All known models including deprecated ones. Used for backward compatibility
    /// so already-downloaded Tiny/Base models still resolve and function.
    public static let allIncludingDeprecated: [ModelInfo] = [
        ModelInfo(
            identifier: "openai_whisper-tiny",
            displayName: "Tiny",
            sizeLabel: "~40 MB",
            sizeBytes: 40_000_000,
            engine: .whisperKit,
            accuracyScore: 0.3,
            speedScore: 1.0,
            description: "Rapide mais imprecis",
            visibility: .deprecated
        ),
        ModelInfo(
            identifier: "openai_whisper-base",
            displayName: "Base",
            sizeLabel: "~75 MB",
            sizeBytes: 75_000_000,
            engine: .whisperKit,
            accuracyScore: 0.4,
            speedScore: 0.9,
            description: "Rapide mais imprecis",
            visibility: .deprecated
        ),
        ModelInfo(
            identifier: "openai_whisper-small",
            displayName: "Small",
            sizeLabel: "~250 MB",
            sizeBytes: 250_000_000,
            engine: .whisperKit,
            accuracyScore: 0.6,
            speedScore: 0.7,
            description: "Precis et equilibre",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-medium",
            displayName: "Medium",
            sizeLabel: "~750 MB",
            sizeBytes: 750_000_000,
            engine: .whisperKit,
            accuracyScore: 0.8,
            speedScore: 0.4,
            description: "Meilleure precision",
            visibility: .available
        ),
    ]

    /// Set of all supported model identifiers for quick lookup.
    /// Uses allIncludingDeprecated so downloaded Tiny/Base models still resolve.
    public static let supportedIdentifiers: Set<String> = Set(allIncludingDeprecated.map(\.identifier))

    /// Look up a model by its WhisperKit identifier.
    /// Searches allIncludingDeprecated so deprecated models are still resolvable.
    /// Returns nil if the identifier is not in the supported list.
    public static func forIdentifier(_ id: String) -> ModelInfo? {
        allIncludingDeprecated.first { $0.identifier == id }
    }
}
