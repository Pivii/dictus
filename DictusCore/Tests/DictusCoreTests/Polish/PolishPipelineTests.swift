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

    // MARK: - resolvedOutput()  (#185)

    /// On success the user gets the engine output verbatim.
    func testResolvedOutputReturnsEngineOutputOnSuccess() {
        let result = PolishPipeline.Result(
            engineOutput: "Ok, petit test.", outcome: .success, engineMs: 5, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "ignored", target: .french)
        XCTAssertEqual(out, "Ok, petit test.")
    }

    /// On a non-success outcome the user gets the deterministic floor (decoded
    /// pre-pass), NOT the literal raw — the verbal-punctuation work survives an
    /// engine failure. Here the pre-pass already turned "virgule" into ",".
    func testResolvedOutputFallsBackToPreprocessedOnEngineFailed() {
        let preprocessed = "Ok, petit test."
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .engineFailed, engineMs: 600, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: preprocessed, target: .french)
        XCTAssertEqual(out, preprocessed)
        XCTAssertFalse(out.contains("virgule"))
    }

    /// A guardrail rejection discards the engine output and also falls back to
    /// the deterministic floor rather than the raw.
    func testResolvedOutputFallsBackToPreprocessedOnGuardrailReject() {
        let preprocessed = "Bonjour Pierre."
        let result = PolishPipeline.Result(
            engineOutput: "something the guardrail rejected", outcome: .rejectedGuardrail, engineMs: 700, postprocessMs: 1
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: preprocessed, target: .french)
        XCTAssertEqual(out, preprocessed)
    }

    /// The floor still applies French typography (NBSP before `?`) on fallback,
    /// proving it routes through `decodeFromEngine`, not a bare passthrough.
    func testResolvedOutputAppliesTypographyOnFallback() {
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .cancelled, engineMs: 0, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "ça va ?", target: .french)
        XCTAssertEqual(out, "ça va\u{00A0}?")
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
