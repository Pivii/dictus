// DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift
import XCTest
@testable import DictusCore

final class ModelInfoTests: XCTestCase {

    // MARK: - Catalog visibility

    func testAllContainsOnlyAvailableModels() {
        // ModelInfo.all should contain 5 available models (4 WhisperKit + 1 Parakeet).
        // Phase 37 (issue #104) re-introduced Whisper Turbo to the catalog with per-device
        // gating — it is present here regardless of device; UI filtering happens via
        // `available(on:)` using `isSupported(on:)` in the view layer.
        XCTAssertEqual(ModelInfo.all.count, 5)
        let ids = Set(ModelInfo.all.map(\.identifier))
        XCTAssertTrue(ids.contains("openai_whisper-small"))
        XCTAssertTrue(ids.contains("openai_whisper-small_216MB"))
        XCTAssertTrue(ids.contains("openai_whisper-medium"))
        XCTAssertTrue(ids.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(ids.contains("openai_whisper-large-v3_turbo_954MB"))
        XCTAssertFalse(ids.contains("openai_whisper-tiny"))
        XCTAssertFalse(ids.contains("openai_whisper-base"))
    }

    func testAllIncludingDeprecatedContainsEight() {
        // allIncludingDeprecated should contain all 7 models (2 deprecated + 5 available).
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.count, 7)
        let deprecated = ModelInfo.allIncludingDeprecated.filter { $0.visibility == .deprecated }
        XCTAssertEqual(deprecated.count, 2)
        let available = ModelInfo.allIncludingDeprecated.filter { $0.visibility == .available }
        XCTAssertEqual(available.count, 5)
    }

    func testDeprecatedModelStillResolvable() {
        // Tiny and Base must still be found by forIdentifier (backward compat)
        XCTAssertNotNil(ModelInfo.forIdentifier("openai_whisper-tiny"))
        XCTAssertNotNil(ModelInfo.forIdentifier("openai_whisper-base"))
        XCTAssertEqual(ModelInfo.forIdentifier("openai_whisper-tiny")?.visibility, .deprecated)
    }

    // MARK: - Gauge scores

    func testGaugeScoresInValidRange() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertTrue((0.0...1.0).contains(model.accuracyScore),
                          "\(model.identifier) accuracyScore \(model.accuracyScore) out of range")
            XCTAssertTrue((0.0...1.0).contains(model.speedScore),
                          "\(model.identifier) speedScore \(model.speedScore) out of range")
        }
    }

    func testAllModelsHaveNonEmptyDescription() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertFalse(model.description.isEmpty, "\(model.identifier) has empty description")
        }
    }

    // MARK: - SpeechEngine

    func testSpeechEngineRawValues() {
        XCTAssertEqual(SpeechEngine.whisperKit.rawValue, "WK")
        XCTAssertEqual(SpeechEngine.parakeet.rawValue, "PK")
    }

    func testSpeechEngineDisplayNames() {
        XCTAssertEqual(SpeechEngine.whisperKit.displayName, "WhisperKit")
        XCTAssertEqual(SpeechEngine.parakeet.displayName, "Parakeet")
    }

    func testEngineAssignment() {
        let whisperKitModels = ModelInfo.allIncludingDeprecated.filter { $0.engine == .whisperKit }
        let parakeetModels = ModelInfo.allIncludingDeprecated.filter { $0.engine == .parakeet }
        XCTAssertEqual(whisperKitModels.count, 6, "Should have 6 WhisperKit models (incl. Turbo)")
        XCTAssertEqual(parakeetModels.count, 1, "Should have 1 Parakeet model")
        XCTAssertEqual(parakeetModels.first?.identifier, "parakeet-tdt-0.6b-v3")
    }

    // MARK: - Phase 37: per-device gating (issue #104)

    /// Helper to build a synthetic capability snapshot for gating tests.
    /// Values other than `physicalMemoryGB` are not currently consulted by the gating
    /// rule but are supplied with plausible defaults so future rule extensions do not
    /// force this helper to be updated everywhere at once.
    private func makeCapabilities(
        ramGB: Int,
        availableMB: Int = 3000,
        model: String = "iPhoneTest,1",
        thermal: ProcessInfo.ThermalState = .nominal
    ) -> DeviceCapabilities {
        DeviceCapabilities(
            physicalMemoryGB: ramGB,
            availableMemoryMB: availableMB,
            deviceModelIdentifier: model,
            thermalState: thermal
        )
    }

    func testTurboGatedOutOnLowRamDevices() {
        // iPhone 12 / iPhone SE tier: 4 GB RAM — Turbo must not be runnable.
        // Issue #369: it stays LISTED, disabled with a reason, instead of vanishing.
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        guard let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB") else {
            XCTFail("openai_whisper-large-v3_turbo_954MB is missing from the catalogue")
            return
        }
        XCTAssertFalse(turbo.isSupported(on: iphone12))
        XCTAssertEqual(turbo.incompatibilityReason(on: iphone12), .insufficientMemory(requiredGB: 6))
        XCTAssertTrue(ModelInfo.available(on: iphone12).map(\.identifier).contains("openai_whisper-large-v3_turbo_954MB"))
    }

    func testTurboAvailableOnSixGBPlusDevices() {
        // iPhone 14 Pro / iPhone 15 tier: 6 GB — passes the quantized Turbo gate.
        // Argmax lists iPhone14/15/16/17 families as supported for `_954MB`.
        let iphone15 = makeCapabilities(ramGB: 6, model: "iPhone15,4")
        guard let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB") else {
            XCTFail("openai_whisper-large-v3_turbo_954MB is missing from the catalogue")
            return
        }
        XCTAssertTrue(turbo.isSupported(on: iphone15))
    }

    func testTurboAvailableOnEightGBDevices() {
        // iPhone 15 Pro Max / iPhone 16: 8 GB — well above the bar.
        let iphone15ProMax = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        guard let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB") else {
            XCTFail("openai_whisper-large-v3_turbo_954MB is missing from the catalogue")
            return
        }
        XCTAssertTrue(turbo.isSupported(on: iphone15ProMax))
        XCTAssertTrue(ModelInfo.available(on: iphone15ProMax).map(\.identifier).contains("openai_whisper-large-v3_turbo_954MB"))

        let iphone17Pro = makeCapabilities(ramGB: 12, model: "iPhone18,1")
        XCTAssertTrue(turbo.isSupported(on: iphone17Pro))
    }

    func testNonTurboModelsNotGated() {
        // Every non-Turbo model must remain visible regardless of RAM tier — Phase 37
        // must not silently shrink the catalog for existing users.
        let lowRam = makeCapabilities(ramGB: 4)
        for model in ModelInfo.all where model.identifier != "openai_whisper-large-v3_turbo_954MB" {
            XCTAssertTrue(model.isSupported(on: lowRam),
                          "\(model.identifier) must not be gated on low-RAM devices")
        }
    }

    func testRecommendedIdentifierNeverReturnsTurbo() {
        // Turbo is intentionally never recommended by default during Phase 37.
        // Verify across the full RAM spectrum to catch any future rule drift.
        for ram in [4, 6, 8, 12, 16] {
            let caps = makeCapabilities(ramGB: ram)
            XCTAssertNotEqual(ModelInfo.recommendedIdentifier(for: caps),
                              "openai_whisper-large-v3_turbo_954MB",
                              "Turbo must not be recommended at \(ram) GB")
        }
    }

    func testRecommendedIdentifierRespectsRamThreshold() {
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 4)),
                       "openai_whisper-small")
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 6)),
                       "parakeet-tdt-0.6b-v3")
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 8)),
                       "parakeet-tdt-0.6b-v3")
    }

    func testRecommendedIdentifierUsesBaseOnA12AndA13IPhones() {
        for identifier in ["iPhone11,2", "iPhone11,8", "iPhone12,1", "iPhone12,8"] {
            let device = makeCapabilities(ramGB: 4, model: identifier)
            XCTAssertEqual(ModelInfo.recommendedIdentifier(for: device),
                           "openai_whisper-base",
                           "\(identifier) must stay within Argmax's A12/A13 support matrix")
        }
    }

    func testRecommendedIdentifierKeepsSmallOnA14FourGBIPhone() {
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")

        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: iphone12),
                       "openai_whisper-small")
    }

    // MARK: - Issue #362: A12/A13 catalog gating

    /// On an iPhone 11 only the Argmax-listed variants may be RUNNABLE. Before the
    /// fix, Small/Medium/Parakeet were all downloadable and picking any of them
    /// reproduced the Core ML optimization hang.
    ///
    /// Issue #369: they must still be LISTED. The row is what tells the user their
    /// phone is the limit; an empty section reads as Dictus being thin.
    func testA12A13IPhonesCanRunOnlyArgmaxSupportedVariants() {
        for identifier in ["iPhone11,2", "iPhone11,8", "iPhone12,1", "iPhone12,8"] {
            let device = makeCapabilities(ramGB: 4, model: identifier)
            let rows = ModelInfo.available(on: device)
            let runnable = Set(rows.filter { $0.isSupported(on: device) }.map(\.identifier))

            XCTAssertTrue(runnable.isSubset(of: ModelInfo.a12a13SupportedIdentifiers),
                          "\(identifier) can run \(runnable.subtracting(ModelInfo.a12a13SupportedIdentifiers))")
            for unsupported in ["openai_whisper-small",
                                "openai_whisper-small_216MB",
                                "openai_whisper-medium",
                                "parakeet-tdt-0.6b-v3",
                                "openai_whisper-large-v3_turbo_954MB"] {
                XCTAssertFalse(runnable.contains(unsupported),
                               "\(identifier) must not be able to run \(unsupported)")
                XCTAssertTrue(rows.map(\.identifier).contains(unsupported),
                              "\(identifier) must still LIST \(unsupported) (issue #369)")
            }
        }
    }

    /// Issue #369's headline: the section an iPhone 11 owner opens is the full
    /// catalogue with one usable entry, not a one-line list.
    func testA12A13AvailableSectionKeepsTheWholeCatalogue() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        let rows = ModelInfo.available(on: iphone11)
        let identifiers = Set(rows.map(\.identifier))

        // Everything visible, plus Base via the #362 recommendation exception.
        XCTAssertEqual(identifiers, Set(ModelInfo.all.map(\.identifier)).union(["openai_whisper-base"]))
        XCTAssertEqual(rows.filter { $0.isSupported(on: iphone11) }.map(\.identifier),
                       ["openai_whisper-base"])
        // Tiny is deprecated AND not recommended: superseded, not unrunnable, so it
        // has nothing to explain and stays out.
        XCTAssertFalse(identifiers.contains("openai_whisper-tiny"))
    }

    /// Every disabled row must be able to say why. A row greyed with no sentence is
    /// the failure mode issue #369 exists to remove.
    func testEveryUnrunnableRowCarriesAReason() {
        let devices = [
            makeCapabilities(ramGB: 4, model: "iPhone12,1"),
            makeCapabilities(ramGB: 4, model: "iPhone13,2"),
            makeCapabilities(ramGB: 8, model: "iPhone16,2")
        ]
        for device in devices {
            for model in ModelInfo.available(on: device) {
                XCTAssertEqual(model.incompatibilityReason(on: device) == nil,
                               model.isSupported(on: device),
                               "\(model.identifier) on \(device.deviceModelIdentifier): reason and gate disagree")
            }
        }
    }

    func testIncompatibilityReasonNamesTheRightConstraint() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        let a14 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        guard let small = ModelInfo.forIdentifier("openai_whisper-small") else {
            XCTFail("openai_whisper-small is missing from the catalogue")
            return
        }
        guard let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB") else {
            XCTFail("openai_whisper-large-v3_turbo_954MB is missing from the catalogue")
            return
        }

        // Old chip, not memory: an iPhone 11 has the RAM, it lacks the generation.
        XCTAssertEqual(small.incompatibilityReason(on: iphone11), .hardwareGeneration)
        XCTAssertEqual(turbo.incompatibilityReason(on: iphone11), .hardwareGeneration)
        // Right generation, not enough memory.
        XCTAssertEqual(turbo.incompatibilityReason(on: a14), .insufficientMemory(requiredGB: 6))
        XCTAssertNil(small.incompatibilityReason(on: a14))
    }

    func testIsSupportedOnA12A13AcceptsOnlyTinyAndBase() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        for model in ModelInfo.allIncludingDeprecated {
            let expected = ModelInfo.a12a13SupportedIdentifiers.contains(model.identifier)
            XCTAssertEqual(model.isSupported(on: iphone11), expected,
                           "\(model.identifier) gating on iPhone 11")
        }
    }

    /// The dead-end guard. Base is `.deprecated` and therefore absent from `all`, so
    /// without the exception in `available(on:)` an iPhone 11 user who deleted Base
    /// had no way to reinstall it and no usable model left.
    func testRecommendedModelIsAlwaysOfferedEvenWhenDeprecated() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")

        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: iphone11), "openai_whisper-base")
        XCTAssertEqual(ModelInfo.forIdentifier("openai_whisper-base")?.visibility, .deprecated)
        XCTAssertFalse(ModelInfo.all.map(\.identifier).contains("openai_whisper-base"))
        XCTAssertTrue(ModelInfo.available(on: iphone11).map(\.identifier).contains("openai_whisper-base"))
    }

    /// The same invariant stated once for every tier: whatever the app tells a device
    /// to install must be reachable from the Settings "Available" list on that device.
    func testEveryTierCanReachItsOwnRecommendation() {
        let devices = [
            makeCapabilities(ramGB: 4, model: "iPhone11,2"),
            makeCapabilities(ramGB: 4, model: "iPhone12,1"),
            makeCapabilities(ramGB: 4, model: "iPhone13,2"),
            makeCapabilities(ramGB: 6, model: "iPhone15,4"),
            makeCapabilities(ramGB: 8, model: "iPhone16,2"),
            makeCapabilities(ramGB: 12, model: "iPhone18,1")
        ]
        for device in devices {
            let recommended = ModelInfo.recommendedIdentifier(for: device)
            XCTAssertTrue(ModelInfo.available(on: device).map(\.identifier).contains(recommended),
                          "\(device.deviceModelIdentifier) recommends \(recommended) but cannot install it")
        }
    }

    /// The deprecation exception must not leak: an A14 iPhone still sees Small, and
    /// Base stays hidden there because Small is the better model on that hardware.
    func testDeprecationExceptionDoesNotLeakToA14Devices() {
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        let offered = ModelInfo.available(on: iphone12).map(\.identifier)

        XCTAssertTrue(offered.contains("openai_whisper-small"))
        XCTAssertFalse(offered.contains("openai_whisper-base"))
        XCTAssertFalse(offered.contains("openai_whisper-tiny"))
        // Issue #369: Turbo is present but disabled here, not absent.
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_turbo_954MB"))
    }

    /// Guards the >= 6 GB path against collateral damage from the A12/A13 branch.
    func testSixGBDeviceCatalogUnchanged() {
        let iphone15 = makeCapabilities(ramGB: 6, model: "iPhone15,4")
        let offered = Set(ModelInfo.available(on: iphone15).map(\.identifier))

        XCTAssertEqual(offered, Set(ModelInfo.all.map(\.identifier)))
        XCTAssertTrue(offered.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_turbo_954MB"))
    }

    /// Issue #369 criterion: on a 8 GB+ device nothing is disabled and the section
    /// looks exactly as it does today.
    func testNothingIsDisabledOnEightGBDevices() {
        let iphone15ProMax = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        let rows = ModelInfo.available(on: iphone15ProMax)

        XCTAssertEqual(rows.map(\.identifier), ModelInfo.all.map(\.identifier))
        XCTAssertTrue(rows.allSatisfy { $0.isSupported(on: iphone15ProMax) })
    }

    // MARK: - Supported identifiers

    func testSupportedIdentifiersMatchesAllIncludingDeprecated() {
        let ids = ModelInfo.supportedIdentifiers
        XCTAssertEqual(ids.count, ModelInfo.allIncludingDeprecated.count)
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertTrue(ids.contains(model.identifier))
        }
    }

    // MARK: - Labels backward compat

    func testEachModelHasNonEmptyLabels() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.identifier) has empty displayName")
            XCTAssertFalse(model.sizeLabel.isEmpty, "\(model.identifier) has empty sizeLabel")
        }
    }

    // MARK: - Announced size (issue #372)

    /// The label and the byte count can no longer disagree, because there is only
    /// one number. This pins the rendering so the card keeps printing the same MB
    /// figure the download progress counts down from.
    func testSizeLabelIsDerivedFromSizeBytes() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertEqual(model.sizeLabel, "~\(model.sizeBytes / 1_000_000) MB",
                           "\(model.identifier) label and byte count disagree")
        }
        XCTAssertEqual(ModelInfo.forIdentifier("openai_whisper-small")?.sizeLabel, "~486 MB")
    }

    /// A zero or negative size would render as "~0 MB" on the card and would make
    /// the download-time reconciliation in `ModelRepoDownloader` skip the entry.
    func testEveryCatalogueEntryDeclaresAPositiveSize() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertGreaterThan(model.sizeBytes, 0, "\(model.identifier) declares no size")
        }
    }

    /// The predicate behind the `modelDownloadSizeMismatch` log line. The 250 MB case
    /// is the bug this issue was filed for: that was the announced size while the
    /// repository served 486 MB, and it has to read as drift.
    func testSizeDriftIsJudgedAgainstTheAnnouncedSize() {
        guard let small = ModelInfo.forIdentifier("openai_whisper-small") else {
            XCTFail("openai_whisper-small is missing from the catalogue")
            return
        }
        XCTAssertFalse(small.sizeHasDrifted(fromMeasured: small.sizeBytes))
        XCTAssertFalse(small.sizeHasDrifted(fromMeasured: Int64(Double(small.sizeBytes) * 1.04)))
        XCTAssertFalse(small.sizeHasDrifted(fromMeasured: Int64(Double(small.sizeBytes) * 0.96)))
        XCTAssertTrue(small.sizeHasDrifted(fromMeasured: Int64(Double(small.sizeBytes) * 1.10)))
        XCTAssertTrue(small.sizeHasDrifted(fromMeasured: 250_000_000))
        // A repository that reports no sizes is a missing measurement, not drift.
        XCTAssertFalse(small.sizeHasDrifted(fromMeasured: 0))
    }
}
