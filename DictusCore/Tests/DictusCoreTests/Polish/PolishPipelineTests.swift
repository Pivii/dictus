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
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "ignored", target: .french, mode: .natural)
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
        let out = PolishPipeline.resolvedOutput(result, preprocessed: preprocessed, target: .french, mode: .natural)
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
        let out = PolishPipeline.resolvedOutput(result, preprocessed: preprocessed, target: .french, mode: .natural)
        XCTAssertEqual(out, preprocessed)
    }

    /// The floor still applies French typography (NBSP before `?`) on fallback,
    /// proving it routes through `decodeFromEngine`, not a bare passthrough.
    func testResolvedOutputAppliesTypographyOnFallback() {
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .cancelled, engineMs: 0, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "ça va ?", target: .french, mode: .natural)
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

    // MARK: - Auto mode (#239)

    /// Auto mode must detect languages outside the four supported ones —
    /// that's the whole point of `detectLanguageCode` vs `detectLanguage`.
    func testDetectLanguageCodeRecognisesUnsupportedLanguages() {
        let zh = PolishPipeline.detectLanguageCode(
            in: "我觉得我们明天再讨论这个问题吧然后周五之前把版本发出去"
        )
        XCTAssertEqual(zh, "zh-Hans")
        let it = PolishPipeline.detectLanguageCode(
            in: "allora ho parlato con Marco ieri sera e mi ha detto che il progetto va bene"
        )
        XCTAssertEqual(it, "it")
    }

    func testDetectLanguageCodeReturnsNilForEmpty() {
        XCTAssertNil(PolishPipeline.detectLanguageCode(in: "   \n  "))
    }

    /// `detectLanguage` keeps its historical contract on top of the code-level
    /// detection: unsupported languages resolve to nil.
    func testDetectLanguageReturnsNilForUnsupportedLanguage() {
        XCTAssertNil(PolishPipeline.detectLanguage(
            in: "allora ho parlato con Marco ieri sera e mi ha detto che il progetto va bene"
        ))
    }

    /// The pairing the per-language skip exit records against (#332): an
    /// unsupported language yields a code but no `SupportedLanguage`, while
    /// gibberish yields neither. Both skip polish, but they are different
    /// events — "you dictated Italian, and this path has no Italian prompt"
    /// versus "we could not read this at all" — and the event only tells them
    /// apart because the code is recorded where it used to write nil.
    func testUnsupportedLanguageAndGibberishAreDistinguishable() {
        let italian = "allora ho parlato con Marco ieri sera e mi ha detto che il progetto va bene"
        XCTAssertEqual(PolishPipeline.detectLanguageCode(in: italian), "it")
        XCTAssertNil(PolishPipeline.detectLanguage(in: italian))

        XCTAssertNil(PolishPipeline.detectLanguageCode(in: "   \n  "))
        XCTAssertNil(PolishPipeline.detectLanguage(in: "   \n  "))
    }

    /// In auto mode the target-language typography must NOT run: a French
    /// input with `target: .french` as engine placeholder keeps its ASCII
    /// space before `?` (no NBSP) — the prompt owns typography in auto mode.
    func testTransformAutoSkipsLanguageTypography() async {
        let input = "bonjour comment ça va aujourd'hui, j'espère que tu vas bien ?"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            target: .french,
            mode: .auto
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
        XCTAssertFalse(result.engineOutput?.contains("\u{00A0}") == true)
    }

    /// CJK text with full-width punctuation must survive the auto transform
    /// byte-for-byte through the passthrough engine — no mangling by any
    /// regex pass.
    func testTransformAutoPreservesCJKPunctuation() async {
        let input = "我觉得我们明天再讨论这个问题吧，然后周五之前把版本发出去。你觉得可以吗？"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            target: .english,
            mode: .auto
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    /// Newline markers still round-trip in auto mode (the marker encode/decode
    /// is language-agnostic and stays on).
    func testTransformAutoPreservesNewlines() async {
        let input = "first line of the message here\nsecond line of the message here"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            target: .english,
            mode: .auto
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    // MARK: - autoPreprocess() (#239 device-test fix: spoken commands in auto mode)

    /// The device-observed bug: "point d'exclamation" / "retour à la ligne"
    /// stayed literal in auto mode. The pre-pass keyed on the DETECTED
    /// language must convert them exactly like the per-language path.
    func testAutoPreprocessConvertsFrenchCommands() {
        let raw = "on va tester si ça arrive à fonctionner point d'exclamation retour à la ligne on va voir"
        let out = PolishPipeline.autoPreprocess(raw, detectedCode: "fr")
        XCTAssertTrue(out.contains("!"))
        XCTAssertTrue(out.contains("\n"))
        XCTAssertFalse(out.lowercased().contains("point d'exclamation"))
        XCTAssertFalse(out.lowercased().contains("retour à la ligne"))
    }

    func testAutoPreprocessConvertsEnglishCommands() {
        let raw = "sounds good exclamation mark new line see you tomorrow question mark"
        let out = PolishPipeline.autoPreprocess(raw, detectedCode: "en")
        XCTAssertTrue(out.contains("!"))
        XCTAssertTrue(out.contains("?"))
        XCTAssertTrue(out.contains("\n"))
        XCTAssertFalse(out.lowercased().contains("exclamation mark"))
        XCTAssertFalse(out.lowercased().contains("new line"))
    }

    /// Same tolerance as the per-language path: the bare "point" word is NOT
    /// converted (#185) — quoting/noun contexts survive.
    func testAutoPreprocessKeepsBarePointNoun() {
        let raw = "de mon point de vue c'est un bon point de départ"
        XCTAssertEqual(PolishPipeline.autoPreprocess(raw, detectedCode: "fr"), raw)
    }

    /// Languages without rules pass through byte-identical — the CJK
    /// guarantee holds through the pre-pass too.
    func testAutoPreprocessLeavesUnsupportedLanguagesUntouched() {
        let zh = "我觉得我们明天再讨论这个问题吧，然后周五之前把版本发出去。"
        XCTAssertEqual(PolishPipeline.autoPreprocess(zh, detectedCode: "zh-Hans"), zh)
        let it = "allora domani andiamo al mare se il tempo è bello"
        XCTAssertEqual(PolishPipeline.autoPreprocess(it, detectedCode: "it"), it)
        XCTAssertEqual(PolishPipeline.autoPreprocess("whatever text", detectedCode: nil), "whatever text")
    }

    /// Auto-mode fallback is the pre-pass floor (worst case output == input
    /// for languages without rules): the placeholder target must not leak
    /// typography into the floor.
    func testResolvedOutputAutoFallbackReturnsInputUnchanged() {
        let input = "ça va ?"
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .engineFailed, engineMs: 100, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: input, target: .french, mode: .auto)
        XCTAssertEqual(out, input, "no NBSP, no typography — raw input is the auto floor")
    }

    func testResolvedOutputAutoSuccessReturnsEngineOutput() {
        let result = PolishPipeline.Result(
            engineOutput: "Polished text.", outcome: .success, engineMs: 100, postprocessMs: 1
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "polished text", target: .english, mode: .auto)
        XCTAssertEqual(out, "Polished text.")
    }
}
