// DictusCore/Tests/DictusCoreTests/Polish/PolishPipelineTests.swift
import XCTest
@testable import DictusCore

/// Deterministic coverage of the shared transform using the Passthrough engine
/// (returns its input unchanged) — no Apple FM, so it's stable and runnable
/// anywhere. The Apple-FM behaviour is covered separately by the eval harness.
final class PolishPipelineTests: XCTestCase {

    // MARK: - transform()

    func testTransformPassthroughSucceedsAndReturnsInput() async {
        let input = "this is a perfectly normal english sentence about testing things"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            target: .english,
            mode: .natural
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    func testTransformPreservesNewlinesThroughMarkerRoundTrip() async {
        // The transform encodes `\n` to the marker before the engine and decodes
        // it after. Passthrough returns the marker verbatim → newline restored.
        let input = "first line here\nsecond line here\nthird line here"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            target: .english,
            mode: .natural
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
        XCTAssertTrue(result.engineOutput?.contains("\n") == true)
    }

    // MARK: - detectLanguage()

    func testDetectLanguageReturnsNilForEmpty() {
        XCTAssertNil(PolishPipeline.detectLanguage(in: "   \n  "))
    }

    func testDetectLanguageRecognisesFrench() {
        let lang = PolishPipeline.detectLanguage(
            in: "bonjour, comment ça va aujourd'hui, j'espère que tu vas bien"
        )
        XCTAssertEqual(lang, .french)
    }

    // MARK: - mode()

    func testModeWhisperAlwaysNatural() {
        XCTAssertEqual(PolishPipeline.mode(sttEngine: .whisperKit, detected: .english, target: .french), .natural)
    }

    func testModeParakeetNaturalWhenMatched() {
        XCTAssertEqual(PolishPipeline.mode(sttEngine: .parakeet, detected: .french, target: .french), .natural)
    }

    func testModeParakeetRepairWhenMismatched() {
        XCTAssertEqual(PolishPipeline.mode(sttEngine: .parakeet, detected: .english, target: .french), .repair)
    }
}
