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
/// accuracy and speed (0.0-1.0), and a short English description.
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

    /// Short English description for the model selection UI.
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
    /// On iOS 17+, includes Parakeet models. On iOS 16, Parakeet is filtered out.
    ///
    /// WHY runtime OS version check instead of #available:
    /// ModelInfo is in DictusCore (a framework), not the app target.
    /// Static properties can't use @available. ProcessInfo gives the same
    /// result at runtime, ensuring iOS 16 users never see Parakeet models
    /// they can't download or use.
    public static let all: [ModelInfo] = {
        let isIOS17OrLater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17
        return allIncludingDeprecated.filter { model in
            guard model.visibility == .available else { return false }
            // Hide Parakeet models on iOS 16
            if model.engine == .parakeet && !isIOS17OrLater { return false }
            return true
        }
    }()

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
            description: "Fast but inaccurate",
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
            description: "Fast but inaccurate",
            visibility: .deprecated
        ),
        // Speed scores recalibrated 2026-05-09 from measured RTF on iPhone 15 Pro Max
        // (issue #168 audit / PR #170): small ~17×, medium ~4×, turbo ~2.7×.
        // The pre-recalibration scores ranked turbo above medium for speed, which
        // contradicted measurement and misled users at model selection.
        ModelInfo(
            identifier: "openai_whisper-small",
            displayName: "Small",
            sizeLabel: "~250 MB",
            sizeBytes: 250_000_000,
            engine: .whisperKit,
            accuracyScore: 0.6,
            speedScore: 0.95,
            description: "Accurate and balanced",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-small_216MB",
            displayName: "Small (Quantized)",
            sizeLabel: "~216 MB",
            sizeBytes: 216_000_000,
            engine: .whisperKit,
            accuracyScore: 0.55,
            speedScore: 0.95,
            description: "Compact and fast",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-medium",
            displayName: "Medium",
            sizeLabel: "~750 MB",
            sizeBytes: 750_000_000,
            engine: .whisperKit,
            accuracyScore: 0.8,
            speedScore: 0.55,
            description: "Best accuracy",
            visibility: .available
        ),
        ModelInfo(
            identifier: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet v3",
            sizeLabel: "~800 MB",
            sizeBytes: 800_000_000,
            engine: .parakeet,
            accuracyScore: 0.85,
            speedScore: 0.85,
            description: "Fast and accurate (NVIDIA)",
            visibility: .available
        ),
        // Phase 37 (issue #104): Whisper Turbo re-introduced using Argmax's
        // iPhone-supported quantized variant `openai_whisper-large-v3_turbo_954MB`.
        //
        // The previous non-quantized `openai_whisper-large-v3_turbo` identifier was
        // the root cause of the historical failures (2026-03 removals + 2026-04-22
        // retest on iPhone 15 Pro Max): that build is M-series-only and triggers
        // `ANE model load has failed ... Must re-compile the E5 bundle` on iPhone
        // ANE regardless of chip generation, because the non-quantized TextDecoder
        // exceeds the mobile ANE's memory budget.
        //
        // Source of truth: https://huggingface.co/argmaxinc/whisperkit-coreml/blob/main/config.json
        // iPhone 14/15/16/17 families (identifiers iPhone15,iPhone16,iPhone17,iPhone18)
        // list this `_954MB` variant as supported.
        ModelInfo(
            identifier: "openai_whisper-large-v3_turbo_954MB",
            displayName: "Turbo",
            sizeLabel: "~954 MB",
            sizeBytes: 954_000_000,
            engine: .whisperKit,
            accuracyScore: 0.9,
            speedScore: 0.2,
            description: "Most accurate but slowest",
            visibility: .available
        )
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

    // MARK: - Device-compatible Recommendation

    /// Returns the recommended model identifier based on hardware compatibility
    /// first, then device RAM.
    ///
    /// WHY compatibility before RAM:
    /// Argmax only supports Tiny/Base on A12/A13 iPhones, while A14 devices with the
    /// same 4 GB RAM tier support Small — so RAM alone cannot separate them, and
    /// recommending Small on an iPhone 11 traps onboarding in Core ML optimization
    /// and can jetsam the app (issue #362). `DeviceCapabilities.isA12OrA13iPhone`
    /// owns that test; `isSupported(on:)` reads the same predicate. After the
    /// hardware exception, Parakeet v3 (~800 MB) remains the pick for >= 6 GB.
    ///
    /// WHY in ModelInfo (not ModelManager):
    /// This is catalog-level logic — which model fits this device. It doesn't
    /// depend on download state or any @Published properties. Accessible from
    /// both ModelManager and onboarding without passing an ObservableObject.
    ///
    /// WHY a function taking `DeviceCapabilities` instead of a cached static let:
    /// Phase 37 introduces per-device gating that needs deterministic inputs for
    /// unit testing. The caller-less overload still exists for convenience — it
    /// reads the current device, same behaviour as before.
    /// Turbo is intentionally never recommended by default during Phase 37.
    public static func recommendedIdentifier(for capabilities: DeviceCapabilities) -> String {
        if capabilities.isA12OrA13iPhone {
            // Base, not Tiny: it is the most accurate variant Argmax lists for this
            // tier, and `a12a13SupportedIdentifiers` keeps the two consistent.
            return "openai_whisper-base"
        }
        return capabilities.physicalMemoryGB >= 6
            ? "parakeet-tdt-0.6b-v3"
            : "openai_whisper-small"
    }

    public static func recommendedIdentifier() -> String {
        recommendedIdentifier(for: DeviceCapabilities.current())
    }

    /// Whether the given model identifier matches the device-recommended model.
    public static func isRecommended(_ identifier: String) -> Bool {
        identifier == recommendedIdentifier()
    }

    // MARK: - Per-device gating (Phase 37, issue #104)

    /// Whether this model is safe to expose on a device with the given capabilities.
    ///
    /// For the quantized Whisper Turbo (`_954MB`): requires ≥ 6 GB RAM. This matches
    /// Argmax's published compatibility matrix: all iPhone 14/15/16/17 families
    /// (iPhone15,X through iPhone18,X in Apple identifier nomenclature) list this
    /// variant as supported, and those devices ship with 6 GB+ RAM.
    /// For every other model: returns true — existing catalog entries have already
    /// been validated on the minimum supported device class.
    ///
    /// Called from the Settings UI to decide whether the Turbo row appears in the
    /// "Available" section. Backend paths (ModelManager download/delete, already-
    /// downloaded list) intentionally do NOT filter by this, so a user who obtained
    /// Turbo under a more permissive build can still manage it.
    /// The only Whisper variants Argmax lists as supported on A12/A13 iPhones.
    ///
    /// WHY the `.en` variants are listed even though Dictus does not ship them:
    /// this set is a transcription of Argmax's published matrix, so it stays
    /// comparable against the source when that matrix is revisited. They simply
    /// never match a catalog entry today.
    ///
    /// Source of truth: https://huggingface.co/argmaxinc/whisperkit-coreml/raw/main/config.json
    static let a12a13SupportedIdentifiers: Set<String> = [
        "openai_whisper-tiny",
        "openai_whisper-tiny.en",
        "openai_whisper-base",
        "openai_whisper-base.en"
    ]

    public func isSupported(on capabilities: DeviceCapabilities) -> Bool {
        // WHY this branch comes first: on A12/A13 the limit is the Core ML support
        // matrix, not memory. Falling through to the RAM rule would leave Small,
        // Small (Quantized) and Medium offered in Settings on an iPhone 11, and
        // downloading any of them reproduces the issue #362 optimization hang.
        // Parakeet is excluded here too — it is absent from Argmax's matrix and
        // needs ~800 MB of headroom these 3-4 GB devices do not have.
        if capabilities.isA12OrA13iPhone {
            return Self.a12a13SupportedIdentifiers.contains(identifier)
        }
        switch identifier {
        case "openai_whisper-large-v3_turbo_954MB":
            return capabilities.physicalMemoryGB >= 6
        default:
            return true
        }
    }

    /// The subset of the catalog that is both visible and gated-in for this device,
    /// plus the device's recommended model even when that model is deprecated.
    /// This is the list the Settings "Available" section should render.
    ///
    /// WHY the recommendation is force-included (issue #362):
    /// On A12/A13 iPhones the recommendation is Base, which is `.deprecated` and so
    /// absent from `all`. Without this exception the app has a reachable dead end:
    /// onboarding installs Base, the user downloads a second model, deleting Base
    /// then becomes permitted, and Base cannot be reinstalled from anywhere. Base
    /// stays deprecated globally on purpose — on A14+ Small is strictly better — so
    /// the exception is scoped to the model this device is actually told to use.
    ///
    /// WHY the exception is guarded on `.deprecated` rather than matching the
    /// identifier alone: `all` also drops Parakeet on iOS 16 through a runtime OS
    /// check, while `recommendedIdentifier(for:)` returns Parakeet on any >= 6 GB
    /// device regardless of OS. A bare identifier match would smuggle Parakeet back
    /// onto iOS 16. This exception must undo deprecation and nothing else.
    ///
    /// Filters `allIncludingDeprecated` rather than `all` so the rendered order stays
    /// catalog order instead of appending the recommendation at the end.
    public static func available(on capabilities: DeviceCapabilities) -> [ModelInfo] {
        let recommended = recommendedIdentifier(for: capabilities)
        let visibleIdentifiers = Set(all.map(\.identifier))
        return allIncludingDeprecated.filter { model in
            guard model.isSupported(on: capabilities) else { return false }
            if visibleIdentifiers.contains(model.identifier) { return true }
            return model.visibility == .deprecated && model.identifier == recommended
        }
    }
}
