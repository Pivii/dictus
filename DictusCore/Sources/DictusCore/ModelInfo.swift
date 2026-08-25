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

    /// Total bytes the downloader will pull for this model. See the measurement
    /// note above `allIncludingDeprecated` for where these numbers come from.
    public let sizeBytes: Int64

    /// The size shown on the model card and the onboarding download page.
    ///
    /// WHY computed rather than a second stored constant (issue #372):
    /// the label and the byte count used to be two hand-written values that
    /// nothing reconciled, so they could drift apart from each other as well as
    /// from the repository. One number, one place to correct.
    ///
    /// WHY truncating division by 1 000 000: it is exactly what
    /// `ModelManager.updateDownloadProgress` does for the `mbTotal` it logs and
    /// for the MB counter under the progress bar, so the size promised on the
    /// card and the total counted during the download print the same number.
    public var sizeLabel: String { "~\(sizeBytes / 1_000_000) MB" }

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

    /// How long the Core ML prewarm is allowed to run for this model before the
    /// deadline guard gives up (issue #406).
    ///
    /// WHY the budget belongs to the model and not to the app:
    /// the guard serves two opposite jobs at once. On a compile that will never
    /// finish — Whisper Small on an unsupported A13, issue #362 — it is the only
    /// thing standing between the user and an endless spinner, so it wants to be
    /// short. On Turbo it has to let a legitimately long compile run to the end, so
    /// it wants to be long. One number cannot be both, and raising the global one to
    /// suit Turbo would make every #362-class device wait twice as long to be told
    /// what it could have been told in two minutes.
    ///
    /// Only the WhisperKit download path consumes this today
    /// (`ModelManager.downloadWhisperKitModel`). The Parakeet path compiles through
    /// FluidAudio and has never carried a deadline guard of any kind, so the value on
    /// `parakeet-tdt-0.6b-v3` is declarative until one exists.
    public let prewarmTimeoutSeconds: Int

    /// The budget a model gets when its entry does not ask for another one.
    ///
    /// 120s was the Phase 37 global (issue #104), calibrated against the ~17s a
    /// Parakeet Encoder compile took on an iPhone 15 Pro Max. It stays the default:
    /// issue #406 established that it is wrong for Turbo, not that it is wrong
    /// everywhere, and no other variant has been reported timing out.
    ///
    /// Declared here rather than at the call site so the catalogue's default and
    /// `ModelManager`'s fallback for an unknown identifier cannot drift apart.
    public static let defaultPrewarmTimeoutSeconds = 120

    /// WHY an initializer written by hand:
    /// `prewarmTimeoutSeconds` needs a default, so that giving models their own
    /// budget did not mean writing `120` onto seven entries with nothing to say
    /// about it. A `let` carrying an inline initial value is excluded from the
    /// implicit memberwise initializer entirely, so a default is only reachable
    /// through an explicit initializer — or by making the property a `var`, which
    /// would leave the catalogue with one mutable stored field among eight.
    ///
    /// Deliberately internal rather than public: nothing outside DictusCore builds a
    /// `ModelInfo`, and the implicit initializer this replaces was internal too.
    init(
        identifier: String,
        displayName: String,
        sizeBytes: Int64,
        engine: SpeechEngine,
        accuracyScore: Double,
        speedScore: Double,
        description: String,
        visibility: CatalogVisibility,
        prewarmTimeoutSeconds: Int = ModelInfo.defaultPrewarmTimeoutSeconds
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.engine = engine
        self.accuracyScore = accuracyScore
        self.speedScore = speedScore
        self.description = description
        self.visibility = visibility
        self.prewarmTimeoutSeconds = prewarmTimeoutSeconds
    }

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
    ///
    /// SIZES — measured 2026-08-23 against the repositories, issue #372.
    ///
    /// Every `sizeBytes` below is the exact sum of the files `ModelRepoDownloader`
    /// selects for that model: the recursive contents of `<identifier>/` in
    /// `argmaxinc/whisperkit-coreml` for WhisperKit, and the four required
    /// `.mlmodelc` folders plus root-level `.json`/`.txt` in
    /// `FluidInference/parakeet-tdt-0.6b-v3-coreml` for Parakeet. That is the
    /// number the user's connection actually has to carry, and it is what the
    /// progress bar counts down from.
    ///
    /// The previous values understated the download by up to 2.04x — Small
    /// announced 250 MB and pulled 486 MB. They were the sizes of OpenAI's
    /// PyTorch checkpoints (39/74/244/769 MB), not of the Core ML bundles Argmax
    /// serves, so nothing about them was ever measured here.
    ///
    /// `ModelCatalogueSizeAuditTests` re-measures these on demand; a divergence
    /// that appears in the field is logged by `ModelRepoDownloader` as
    /// `modelDownloadSizeMismatch`.
    public static let allIncludingDeprecated: [ModelInfo] = [
        ModelInfo(
            identifier: "openai_whisper-tiny",
            displayName: "Tiny",
            sizeBytes: 76_635_397,
            engine: .whisperKit,
            accuracyScore: 0.3,
            speedScore: 1.0,
            description: "Fast but inaccurate",
            visibility: .deprecated
        ),
        ModelInfo(
            identifier: "openai_whisper-base",
            displayName: "Base",
            sizeBytes: 146_719_453,
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
            sizeBytes: 486_487_465,
            engine: .whisperKit,
            accuracyScore: 0.6,
            speedScore: 0.95,
            description: "Accurate and balanced",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-small_216MB",
            displayName: "Small (Quantized)",
            // 217 MB measured against a name that says 216 MB — the name holds.
            sizeBytes: 217_350_763,
            engine: .whisperKit,
            accuracyScore: 0.55,
            speedScore: 0.95,
            description: "Compact and fast",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-medium",
            displayName: "Medium",
            sizeBytes: 1_529_654_233,
            engine: .whisperKit,
            accuracyScore: 0.8,
            speedScore: 0.55,
            description: "Best accuracy",
            visibility: .available
        ),
        ModelInfo(
            identifier: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet v3",
            // The one entry that OVERSTATED: 800 MB announced, 483 MB served.
            sizeBytes: 483_254_686,
            engine: .parakeet,
            accuracyScore: 0.85,
            speedScore: 0.85,
            description: "Fast and accurate (NVIDIA)",
            visibility: .available
        ),
        // Phase 37 (issue #104): Whisper Turbo re-introduced using an Argmax
        // iPhone-supported QUANTIZED variant.
        //
        // The previous non-quantized `openai_whisper-large-v3_turbo` identifier was
        // the root cause of the historical failures (2026-03 removals + 2026-04-22
        // retest on iPhone 15 Pro Max): that build is M-series-only and triggers
        // `ANE model load has failed ... Must re-compile the E5 bundle` on iPhone
        // ANE regardless of chip generation, because the non-quantized TextDecoder
        // exceeds the mobile ANE's memory budget. That remains true of the identifier
        // it names; both quantized variants below are unaffected by it.
        //
        // Issue #408 changed WHICH quantized variant "Turbo" means. On the French
        // dictation corpus measured 2026-08-25 for #171
        // (https://github.com/getdictus/dictus-ios/issues/171#issuecomment-5409496092)
        // `_954MB` won no clip of five and hallucinated on three, and translated a
        // French sentence carrying English loanwords into English instead of
        // transcribing it. `_v20240930_turbo_632MB` won or tied on four of five,
        // hallucinated on one, and is 39% smaller. Both ship the same four
        // `.mlmodelc` artefacts and carry the same Argmax device gate, so
        // `directoryPatterns`, `requiredPaths` and the RAM rule all stay as they were.
        //
        // Source of truth: https://huggingface.co/argmaxinc/whisperkit-coreml/blob/main/config.json
        // The A15 family (iPhone14) and the A16/A17 Pro/A18/A19 family (iPhone15,
        // iPhone16, iPhone17, iPhone18, iPad15,7-8, iPad16,1-2) list BOTH quantized
        // turbo variants as supported. Neither is listed for A12/A13 or A14.
        ModelInfo(
            identifier: "openai_whisper-large-v3-v20240930_turbo_632MB",
            displayName: "Turbo",
            // 645 MB measured against a name that says 632 MB — the same gap the
            // `_954MB` entry below carries, for the same reason. AudioEncoder
            // (429 MB) + TextDecoder (203 MB) come to the 632 MB in the name, which
            // is the model; `directoryPatterns: ["<variant>/"]` then pulls the whole
            // folder, including the 12 MB TextDecoderContextPrefill.mlmodelc that
            // `requiredPaths` does not require. The name describes the model; this
            // constant describes the download.
            //
            // Re-derived 2026-08-25 by the method described above
            // `allIncludingDeprecated`, which reproduces `1_052_848_880` exactly.
            sizeBytes: 645_668_913,
            engine: .whisperKit,
            // Both scores are CARRIED OVER from `_954MB`, deliberately (issue #408):
            //
            //  - `accuracyScore` is hand-assigned across the whole catalogue, and
            //    #171 shows the ranking is inverted (measured order: Parakeet ~
            //    turbo632 > Medium > turbo954). Recalibrating needs a real WER corpus
            //    and its own issue; moving one entry alone would only relocate the
            //    inconsistency.
            //  - `speedScore` 0.2 is INHERITED, not measured. #171 measured 2.70x RTF
            //    for `_954MB` on an iPhone 15 Pro Max; this variant has no on-device
            //    RTF reading yet. #171's hypothesis 1 predicts it stays slower than
            //    Medium — turbo distils only the decoder, and the served tree agrees
            //    the encoder is the bulk here (429 MB of 632 MB) — but a prediction
            //    is not a measurement. Correct this once #171 has the number.
            accuracyScore: 0.9,
            speedScore: 0.2,
            description: "Most accurate but slowest",
            visibility: .available,
            // 300s, and it is a GUESS rather than a measurement (issue #406).
            //
            // Nobody has ever watched a Turbo compile finish on an iPhone. The flat
            // 120s guard cut every attempt short, on both variants, so the real
            // duration is unknown for both. The only figure that exists at all is the
            // "~2 min on a 15 Pro Max" quoted in `ModelLoadingOverlay.swift`, and that
            // prose describes the `_954MB` variant this entry replaced. 300 is 2.5x
            // it: room for a slow-but-real compile under thermal throttling or disk
            // pressure, while still ending a genuine hang in five minutes rather than
            // never.
            //
            // The maintainer's iPhone 15 Pro Max hit the 120s guard on THIS variant on
            // 2026-08-25, which is what shows issue #408's 39% size cut does not on
            // its own bring the compile inside the old budget.
            //
            // This number is meant to be replaced by a measurement, and produces one
            // for free: the first compile that completes under it logs
            // `modelCompilationCompleted durationMs`, the first real reading of a Turbo
            // compile anyone will have. Do not then shrink 300 to hug that reading —
            // it will be one device, in one thermal state, with one amount of free
            // disk. The TestFlight reporter had 5.3 GB free of 254 GB.
            prewarmTimeoutSeconds: 300
        ),
        // Superseded by the entry above (issue #408). Kept resolvable, and only
        // resolvable: a user who already pulled 1.05 GB of Turbo on an earlier build
        // keeps dictating with it, keeps seeing it in the Settings "Downloaded"
        // section, and can delete it from there — while `available(on:)` stops
        // offering it, so nobody downloads it again. Same soft-deprecation contract
        // as Tiny/Base, and the reason there is no launch-time `activeModel` rewrite:
        // that would have cost an existing Turbo user either a 645 MB download they
        // did not ask for or a silent move off the model they picked.
        //
        // WHY the display name gains a qualifier: a user who holds both variants
        // would otherwise read two rows both called "Turbo" in that section, with
        // nothing but the size to separate them. Follows "Small (Quantized)".
        ModelInfo(
            identifier: "openai_whisper-large-v3_turbo_954MB",
            displayName: "Turbo (Legacy)",
            // 1052 MB measured against a name that says 954 MB, and both are right:
            // TextDecoder + AudioEncoder + their `.mil` files come to ~954 MB, which
            // is the model. The folder also ships TextDecoderContextPrefill.mlmodelc
            // (98 MB), which `directoryPatterns: ["<variant>/"]` pulls even though
            // `requiredPaths` does not require it. The name describes the model; this
            // constant describes the download.
            sizeBytes: 1_052_848_880,
            engine: .whisperKit,
            accuracyScore: 0.9,
            speedScore: 0.2,
            description: "Most accurate but slowest",
            visibility: .deprecated,
            // The same 300s as the entry that supersedes it, for a stronger reason:
            // `_954MB` is the variant the 2026-08-25 TestFlight report actually timed
            // out on at 120s. Declaring 120 here would leave the catalogue asserting a
            // budget the field has already disproved for this exact model.
            //
            // Unreachable in practice: `available(on:)` no longer offers this variant,
            // so no download — and therefore no prewarm — can start for it. Kept
            // correct rather than kept convenient.
            prewarmTimeoutSeconds: 300
        )
    ]

    // MARK: - Announced size vs. served size (issue #372)

    /// How far a declared size may sit from what the repository actually serves
    /// before it counts as drift.
    ///
    /// Generous on purpose: a repository gaining a metadata file is not news, a
    /// repack that doubles the payload is. Declared here rather than at either
    /// call site so the download-time check and the audit test cannot disagree
    /// about what "correct" means.
    public static let sizeTolerance = 0.05

    /// Whether the announced size has drifted from what the repository serves.
    ///
    /// The real total is only knowable after a network round trip the model card
    /// does not make, so `sizeBytes` has to stay a hand-written constant and will
    /// drift again the next time a repository is repacked. This predicate is how
    /// that drift gets noticed: `ModelRepoDownloader` calls it the moment it has
    /// both numbers, and `ModelCatalogueSizeAuditTests` calls it on demand.
    public func sizeHasDrifted(fromMeasured measuredBytes: Int64) -> Bool {
        guard sizeBytes > 0, measuredBytes > 0 else { return false }
        return abs(Double(measuredBytes - sizeBytes)) / Double(sizeBytes) > Self.sizeTolerance
    }

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
    /// For the quantized Whisper Turbo variants (`_v20240930_turbo_632MB` and the
    /// deprecated `_954MB`): requires ≥ 6 GB RAM. This matches Argmax's published
    /// compatibility matrix: the iPhone 14/15/16/17 families (iPhone14,X through
    /// iPhone18,X in Apple identifier nomenclature) list both variants as supported,
    /// and those devices ship with 6 GB+ RAM.
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

    /// Why a model cannot run on a given device, or `nil` when it can.
    ///
    /// WHY the reason is modelled here and not phrased here:
    /// the UI has to tell the user which constraint they are looking at (issue #369),
    /// and that sentence must be localized. DictusCore owns the policy; the app layer
    /// maps each case to its French/English wording in `ModelInfo+Localized.swift`.
    public enum IncompatibilityReason: Equatable, Sendable {
        /// The chip predates the variant. Argmax's support matrix, not memory.
        case hardwareGeneration
        /// The device has less RAM than the variant needs.
        case insufficientMemory(requiredGB: Int)
    }

    /// The reason this model cannot run on the given device, or `nil` if it can.
    ///
    /// WHY `isSupported(on:)` delegates here rather than duplicating the rules:
    /// issue #369 renders the reason next to a disabled row, so a divergence between
    /// "is it gated" and "why is it gated" would be visible as a greyed card with no
    /// explanation, or an explanation on a tappable card. One function, no drift.
    public func incompatibilityReason(on capabilities: DeviceCapabilities) -> IncompatibilityReason? {
        // WHY this branch comes first: on A12/A13 the limit is the Core ML support
        // matrix, not memory. Falling through to the RAM rule would leave Small,
        // Small (Quantized) and Medium selectable in Settings on an iPhone 11, and
        // downloading any of them reproduces the issue #362 optimization hang.
        // Parakeet is excluded here too — it is absent from Argmax's matrix and
        // needs ~800 MB of headroom these 3-4 GB devices do not have.
        if capabilities.isA12OrA13iPhone {
            return Self.a12a13SupportedIdentifiers.contains(identifier) ? nil : .hardwareGeneration
        }
        switch identifier {
        // Both quantized Turbo variants (issue #408): Argmax lists them for exactly
        // the same device families, so they share one rule. The deprecated `_954MB`
        // is matched here too — it is still installed on devices, so the Settings
        // "Downloaded" row it renders must be able to say why it is disabled.
        case "openai_whisper-large-v3-v20240930_turbo_632MB", "openai_whisper-large-v3_turbo_954MB":
            return capabilities.physicalMemoryGB >= 6 ? nil : .insufficientMemory(requiredGB: 6)
        default:
            return nil
        }
    }

    public func isSupported(on capabilities: DeviceCapabilities) -> Bool {
        incompatibilityReason(on: capabilities) == nil
    }

    /// The rows the Settings "Available" section should render for this device:
    /// the visible catalog, plus the device's recommended model even when that model
    /// is deprecated.
    ///
    /// WHY incompatible models are NOT filtered out (issue #369, reversing #104):
    /// hiding them told the user nothing, and the absence read as a property of
    /// Dictus rather than of their phone. On an A12/A13 iPhone the gating from
    /// issue #362 would collapse this list to a single entry. They stay in the list
    /// and the card renders them disabled with a reason; `incompatibilityReason(on:)`
    /// is what the view asks. Deprecation still filters — deprecated means superseded,
    /// not unrunnable, so those rows would have nothing to explain.
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
            if visibleIdentifiers.contains(model.identifier) { return true }
            return model.visibility == .deprecated && model.identifier == recommended
        }
    }
}
