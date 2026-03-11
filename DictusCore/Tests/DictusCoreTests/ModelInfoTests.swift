// DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift
import XCTest
@testable import DictusCore

final class ModelInfoTests: XCTestCase {

    // MARK: - Catalog visibility

    func testAllContainsOnlyAvailableModels() {
        // ModelInfo.all should contain 5 available models (4 WhisperKit + 1 Parakeet)
        XCTAssertEqual(ModelInfo.all.count, 5)
        let ids = Set(ModelInfo.all.map(\.identifier))
        XCTAssertTrue(ids.contains("openai_whisper-small"))
        XCTAssertTrue(ids.contains("openai_whisper-small_216MB"))
        XCTAssertTrue(ids.contains("openai_whisper-medium"))
        XCTAssertTrue(ids.contains("openai_whisper-large-v3_turbo"))
        XCTAssertTrue(ids.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertFalse(ids.contains("openai_whisper-tiny"))
        XCTAssertFalse(ids.contains("openai_whisper-base"))
    }

    func testAllIncludingDeprecatedContainsEight() {
        // allIncludingDeprecated should contain all 7 models (2 deprecated + 5 available)
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
        XCTAssertEqual(whisperKitModels.count, 6, "Should have 6 WhisperKit models")
        XCTAssertEqual(parakeetModels.count, 1, "Should have 1 Parakeet model")
        XCTAssertEqual(parakeetModels.first?.identifier, "parakeet-tdt-0.6b-v3")
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
