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
        // iPhone 12 / iPhone SE tier: 4 GB RAM — Turbo must not be offered.
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")
        XCTAssertNotNil(turbo)
        XCTAssertFalse(turbo!.isSupported(on: iphone12))
        XCTAssertFalse(ModelInfo.available(on: iphone12).map(\.identifier).contains("openai_whisper-large-v3_turbo_954MB"))
    }

    func testTurboAvailableOnSixGBPlusDevices() {
        // iPhone 14 Pro / iPhone 15 tier: 6 GB — passes the quantized Turbo gate.
        // Argmax lists iPhone14/15/16/17 families as supported for `_954MB`.
        let iphone15 = makeCapabilities(ramGB: 6, model: "iPhone15,4")
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")!
        XCTAssertTrue(turbo.isSupported(on: iphone15))
    }

    func testTurboAvailableOnEightGBDevices() {
        // iPhone 15 Pro Max / iPhone 16: 8 GB — well above the bar.
        let iphone15ProMax = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")!
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
}
