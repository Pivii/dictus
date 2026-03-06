// DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift
import XCTest
@testable import DictusCore

final class ModelInfoTests: XCTestCase {

    func testAllContainsExactlyFourModels() {
        XCTAssertEqual(ModelInfo.all.count, 4)
    }

    func testEachModelHasNonEmptyLabels() {
        for model in ModelInfo.all {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.identifier) has empty displayName")
            XCTAssertFalse(model.sizeLabel.isEmpty, "\(model.identifier) has empty sizeLabel")
            XCTAssertFalse(model.accuracyLabel.isEmpty, "\(model.identifier) has empty accuracyLabel")
            XCTAssertFalse(model.speedLabel.isEmpty, "\(model.identifier) has empty speedLabel")
        }
    }

    func testTinyModelIdentifier() {
        let tiny = ModelInfo.all.first { $0.identifier == "openai_whisper-tiny" }
        XCTAssertNotNil(tiny, "Tiny model should exist in ModelInfo.all")
        XCTAssertEqual(tiny?.displayName, "Tiny")
    }

    func testSupportedIdentifiersContainsAllFour() {
        let ids = ModelInfo.supportedIdentifiers
        XCTAssertEqual(ids.count, 4)
        XCTAssertTrue(ids.contains("openai_whisper-tiny"))
        XCTAssertTrue(ids.contains("openai_whisper-base"))
        XCTAssertTrue(ids.contains("openai_whisper-small"))
        XCTAssertTrue(ids.contains("openai_whisper-medium"))
    }
}
