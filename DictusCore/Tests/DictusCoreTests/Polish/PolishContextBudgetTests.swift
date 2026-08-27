// DictusCore/Tests/DictusCoreTests/Polish/PolishContextBudgetTests.swift
import XCTest
@testable import DictusCore

/// Coverage of the pre-call context guard (#270): the budget arithmetic itself,
/// and the `PolishPipeline` behaviour it drives. Everything here is
/// deterministic and runs without Apple Foundation Models, except the clearly
/// marked section that prices the real shipping prompts.
final class PolishContextBudgetTests: XCTestCase {

    // MARK: - Helpers

    /// A budget with every multiplier neutralised, so a test can reason about
    /// the arithmetic without the safety margin or the output reserve in the
    /// way. Production numbers live in `PolishContextBudget.appleFoundationModels`.
    private func plainBudget(window: Int) -> PolishContextBudget {
        PolishContextBudget(contextWindowTokens: window,
                            scaffoldingTokens: 0,
                            outputReserveRatio: 0,
                            safetyMargin: 1.0)
    }

    /// Largest input length, in characters, that `budget` still accepts.
    /// Binary-searched through the public API so the boundary tests below stay
    /// correct if the estimator's constants are ever retuned.
    private func largestAcceptedLength(budget: PolishContextBudget,
                                       instructions: String) -> Int {
        var accepted = 0
        var refused = 200_000
        while refused - accepted > 1 {
            let mid = (accepted + refused) / 2
            if case .fits = budget.fit(instructions: instructions,
                                       input: String(repeating: "a", count: mid)) {
                accepted = mid
            } else {
                refused = mid
            }
        }
        return accepted
    }

    // MARK: - Estimator

    /// Ideographic scripts pack far more tokens into the same character count.
    /// A single Latin-tuned ratio would wave a long Chinese dictation straight
    /// into an overflow, which is the failure auto mode (#239) makes reachable.
    func testIdeographicTextIsPricedFarAboveLatinTextOfTheSameLength() {
        let latin = String(repeating: "a", count: 600)
        let han = String(repeating: "字", count: 600)
        let latinTokens = PolishContextBudget.estimatedTokens(in: latin)
        let hanTokens = PolishContextBudget.estimatedTokens(in: han)
        XCTAssertGreaterThan(hanTokens, latinTokens * 2)
    }

    func testEmptyTextCostsNothing() {
        XCTAssertEqual(PolishContextBudget.estimatedTokens(in: ""), 0)
    }

    /// The estimator must over-count, never under-count, against the ratios
    /// measured on the real model (French 4.94 characters per token, the least
    /// favourable of the four Latin-script languages).
    func testLatinEstimateIsConservativeAgainstTheMeasuredRatio() {
        let text = String(repeating: "une phrase de dictée tout à fait ordinaire ", count: 100)
        let measuredTokens = Double(text.count) / 4.94
        XCTAssertGreaterThanOrEqual(Double(PolishContextBudget.estimatedTokens(in: text)),
                                    measuredTokens)
    }

    // MARK: - Fit: the four length bands

    func testComfortablyUnderBudgetFits() {
        let budget = plainBudget(window: 1000)
        let fit = budget.fit(instructions: "short prompt", input: "a normal length dictation")
        XCTAssertEqual(fit, .fits)
    }

    func testFarOverBudgetIsRefused() {
        let budget = plainBudget(window: 1000)
        let fit = budget.fit(instructions: "short prompt",
                             input: String(repeating: "a", count: 200_000))
        guard case .exceeds(let estimated, let window) = fit else {
            return XCTFail("expected .exceeds, got \(fit)")
        }
        XCTAssertEqual(window, 1000)
        XCTAssertGreaterThan(estimated, 10_000)
    }

    /// The boundary is exact and inclusive: an estimate equal to the window
    /// fits, one token more does not.
    func testBoundaryIsInclusiveOfTheWindow() {
        let instructions = String(repeating: "b", count: 500)
        let input = String(repeating: "a", count: 2000)
        // Any window works to compute the estimate — `estimatedTokens` does not
        // consult it.
        let estimate = plainBudget(window: 1).estimatedTokens(instructions: instructions,
                                                              input: input)
        XCTAssertEqual(plainBudget(window: estimate).fit(instructions: instructions, input: input),
                       .fits,
                       "an estimate exactly on the window must fit")
        XCTAssertEqual(plainBudget(window: estimate - 1).fit(instructions: instructions, input: input),
                       .exceeds(estimatedTokens: estimate, budgetTokens: estimate - 1),
                       "one token over the window must be refused")
    }

    /// Just under and just over, expressed in input length rather than tokens —
    /// the dimension the user actually varies.
    func testJustUnderFitsAndJustOverIsRefused() {
        let budget = PolishContextBudget.appleFoundationModels
        let instructions = String(repeating: "instruction line. ", count: 300)
        let limit = largestAcceptedLength(budget: budget, instructions: instructions)
        XCTAssertGreaterThan(limit, 0, "the prompt alone must not exhaust the window")
        XCTAssertEqual(budget.fit(instructions: instructions,
                                  input: String(repeating: "a", count: limit)),
                       .fits)
        if case .fits = budget.fit(instructions: instructions,
                                   input: String(repeating: "a", count: limit + 1)) {
            XCTFail("one character past the limit must be refused")
        }
    }

    // MARK: - Fit: the instructions are part of the bill

    /// The criterion the whole design turns on: an input that fits on its own
    /// stops fitting once the resolved prompt is priced with it. Measurement
    /// showed instruction tokens and input tokens trade one for one inside the
    /// window, so a fixed instruction allowance would under-estimate on exactly
    /// the modes with the longest prompts.
    func testInputUnderBudgetAloneIsRefusedOnceInstructionsAreAdded() {
        let budget = plainBudget(window: 500)
        let input = String(repeating: "a", count: 2000) // ~409 tokens
        XCTAssertEqual(budget.fit(instructions: "", input: input), .fits)
        let longPrompt = String(repeating: "b", count: 2000) // another ~409 tokens
        guard case .exceeds = budget.fit(instructions: longPrompt, input: input) else {
            return XCTFail("the same input must be refused once the prompt is counted")
        }
    }

    /// Two prompts of different length must produce different verdicts for the
    /// same input — i.e. the estimate is mode- and language-specific by
    /// construction, not by a constant.
    func testLongerInstructionsShrinkTheAcceptedInputLength() {
        let budget = PolishContextBudget.appleFoundationModels
        let shortPrompt = String(repeating: "instruction line. ", count: 100)
        let longPrompt = String(repeating: "instruction line. ", count: 400)
        XCTAssertGreaterThan(largestAcceptedLength(budget: budget, instructions: shortPrompt),
                             largestAcceptedLength(budget: budget, instructions: longPrompt))
    }

    // MARK: - Latency

    /// The guard runs on every dictation, so it has to be free. Measured over a
    /// realistic pair: a full-size system prompt and a two-minute dictation.
    func testEstimatorCostIsNegligibleOnANormalDictation() {
        let instructions = String(repeating: "an instruction line of the system prompt. ", count: 150)
        let input = String(repeating: "une phrase de dictée tout à fait ordinaire. ", count: 40)
        let budget = PolishContextBudget.appleFoundationModels
        let iterations = 1000
        let start = Date()
        for _ in 0..<iterations {
            _ = budget.fit(instructions: instructions, input: input)
        }
        let perCallMs = Date().timeIntervalSince(start) * 1000 / Double(iterations)
        XCTAssertLessThan(perCallMs, 1.0,
                          "estimator cost \(perCallMs) ms/call — it must not be visible in the latency breakdown")
    }

    // MARK: - Pipeline behaviour

    func testTransformRefusesOversizedInputWithoutCallingTheEngine() async {
        let engine = CeilingStubEngine(window: 200)
        let result = await PolishPipeline.transform(
            preprocessed: String(repeating: "a", count: 20_000),
            engine: engine,
            target: .french,
            mode: .natural
        )
        XCTAssertEqual(result.outcome, .exceededContextBudget)
        XCTAssertEqual(engine.polishCallCount, 0, "the engine must never be called on an overflow")
        XCTAssertNil(result.engineOutput)
        XCTAssertEqual(result.engineMs, 0)
    }

    func testTransformStillCallsTheEngineWhenTheInputFits() async {
        let engine = CeilingStubEngine(window: 4096)
        let input = "une dictée de longueur parfaitement ordinaire"
        let result = await PolishPipeline.transform(
            preprocessed: input, engine: engine, target: .french, mode: .natural
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(engine.polishCallCount, 1)
        XCTAssertEqual(result.engineOutput, input)
    }

    /// An overflow must be tellable apart from a backend failure by a caller
    /// inspecting the result — that distinction is the point of the case.
    func testOverflowIsDistinguishableFromAnEngineFailure() async {
        let oversized = String(repeating: "a", count: 20_000)
        let refused = await PolishPipeline.transform(
            preprocessed: oversized, engine: CeilingStubEngine(window: 200),
            target: .french, mode: .natural
        )
        // Same oversized input through an engine with no ceiling that throws:
        // the pipeline records the generic failure it always did.
        let failed = await PolishPipeline.transform(
            preprocessed: oversized, engine: ThrowingStubEngine(),
            target: .french, mode: .natural
        )
        XCTAssertEqual(refused.outcome, .exceededContextBudget)
        XCTAssertEqual(failed.outcome, .engineFailed)
        XCTAssertNotEqual(refused.outcome, failed.outcome)
    }

    /// An overflow returns the deterministic floor, exactly as an engine
    /// failure does — the user's text is never at risk, only the polish is.
    func testResolvedOutputFallsBackToTheFloorOnOverflow() {
        let preprocessed = "Ok, petit test ?"
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .exceededContextBudget, engineMs: 0, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(
            result, preprocessed: preprocessed, target: .french, mode: .natural
        )
        XCTAssertEqual(out, "Ok, petit test\u{00A0}?", "the floor still applies French typography")
    }

    // MARK: - Engines without a ceiling

    /// The default protocol implementation: an engine that declares no ceiling
    /// is never refused, however long the input.
    func testPassthroughEngineDeclaresNoCeiling() {
        let engine = PassthroughPolishEngine()
        let fit = engine.contextFit(input: String(repeating: "a", count: 500_000),
                                    targetLanguage: .french,
                                    mode: .natural)
        XCTAssertEqual(fit, .fits)
    }

    func testTransformRunsAnUnboundedEngineOnAnEnormousInput() async {
        // 40 000 characters — well past the Apple FM ceiling, irrelevant here.
        let input = String(repeating: "une phrase de dictée ordinaire. ", count: 1250)
        let result = await PolishPipeline.transform(
            preprocessed: input, engine: PassthroughPolishEngine(), target: .french, mode: .natural
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    // MARK: - The real shipping prompts

    #if canImport(FoundationModels)
    /// The prompts differ enough in length to matter: the language-agnostic
    /// Auto prompt is the longest and the English Repair prompt the shortest,
    /// so the same dictation can fit under one and overflow the other.
    func testRealPromptsPriceDifferentlyPerModeAndLanguage() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Apple Foundation Models prompts require the iOS/macOS 26 SDK")
        }
        let budget = PolishContextBudget.appleFoundationModels
        let auto = AppleFoundationModelsPolishEngine.instructions(for: .auto, language: .english)
        let repairEN = AppleFoundationModelsPolishEngine.instructions(for: .repair, language: .english)
        let autoLimit = largestAcceptedLength(budget: budget, instructions: auto)
        let repairLimit = largestAcceptedLength(budget: budget, instructions: repairEN)
        XCTAssertLessThan(autoLimit, repairLimit,
                          "the longest prompt must leave the least room for input")
    }

    /// A regression guard on the constants, deliberately loose. The sweep
    /// recorded in `PolishContextBudget.appleFoundationModels` puts the useful
    /// range for the French Natural prompt at roughly 4 000–4 500 characters of
    /// input: below it the engine reliably succeeds with a usable output, above
    /// it it truncates and increasingly often throws.
    func testFrenchNaturalPromptAcceptsARealisticDictationLength() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Apple Foundation Models prompts require the iOS/macOS 26 SDK")
        }
        let instructions = AppleFoundationModelsPolishEngine.instructions(
            for: .natural, language: .french
        )
        let limit = largestAcceptedLength(budget: .appleFoundationModels,
                                          instructions: instructions)
        XCTAssertGreaterThan(limit, 3500,
                             "refusing under ~3 500 characters would take polish away from dictations that measurably work today")
        XCTAssertLessThan(limit, 4800,
                          "accepting past ~4 800 characters buys output the guardrail rejects, when the engine does not throw first")
    }

    /// A one-line dictation must be nowhere near any ceiling, on every prompt.
    func testShortDictationFitsUnderEveryRealPrompt() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Apple Foundation Models prompts require the iOS/macOS 26 SDK")
        }
        let engine = AppleFoundationModelsPolishEngine()
        let input = "bonjour, on se voit demain matin pour parler du projet"
        for mode in [PolishMode.natural, .repair, .auto] {
            for language in SupportedLanguage.allCases {
                XCTAssertEqual(engine.contextFit(input: input, targetLanguage: language, mode: mode),
                               .fits,
                               "\(mode)/\(language) refused a one-line dictation")
            }
        }
    }
    #endif
}

// MARK: - Stub engines

/// An engine that declares a ceiling and records whether it was called. The
/// instruction text is empty so a test can reason about the input alone; the
/// window is the knob.
private final class CeilingStubEngine: PolishEngineProtocol, @unchecked Sendable {

    let identifier = "ceiling-stub"
    private let budget: PolishContextBudget
    private let lock = NSLock()
    private var calls = 0

    var polishCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    init(window: Int) {
        self.budget = PolishContextBudget(contextWindowTokens: window,
                                          scaffoldingTokens: 0,
                                          outputReserveRatio: 1.1,
                                          safetyMargin: 1.2)
    }

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        return raw
    }

    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    mode: PolishMode) -> PolishContextFit {
        budget.fit(instructions: "", input: input)
    }
}

/// An engine with no ceiling that always throws — the generic backend failure
/// an overflow must remain distinguishable from.
private struct ThrowingStubEngine: PolishEngineProtocol {
    let identifier = "throwing-stub"

    struct Failure: Error {}

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        throw Failure()
    }
}
