// DictusCore/Tests/DictusCoreTests/Polish/PolishFailureReasonTests.swift
import XCTest
@testable import DictusCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Coverage of the engine-failure reason (#315): the mapping itself, the path it
/// travels from a throwing engine to a persisted metric, and the two things this
/// work must NOT have changed — what the user receives on a failure, and the
/// decodability of events written before the field existed.
final class PolishFailureReasonTests: XCTestCase {

    // MARK: - Slug mapping

    /// The slugs are a wire format: they land in the debug export, in the
    /// persistent log, and in reports written against one build and read against
    /// the next. Renaming one silently would make two exports incomparable, so
    /// every value is pinned literally here.
    func testSlugsAreStableStrings() {
        XCTAssertEqual(PolishFailureReason.exceededContextWindowSize.slug, "exceededContextWindowSize")
        XCTAssertEqual(PolishFailureReason.assetsUnavailable.slug, "assetsUnavailable")
        XCTAssertEqual(PolishFailureReason.guardrailViolation.slug, "guardrailViolation")
        XCTAssertEqual(PolishFailureReason.unsupportedGuide.slug, "unsupportedGuide")
        XCTAssertEqual(PolishFailureReason.unsupportedLanguageOrLocale.slug, "unsupportedLanguageOrLocale")
        XCTAssertEqual(PolishFailureReason.decodingFailure.slug, "decodingFailure")
        XCTAssertEqual(PolishFailureReason.rateLimited.slug, "rateLimited")
        XCTAssertEqual(PolishFailureReason.concurrentRequests.slug, "concurrentRequests")
        XCTAssertEqual(PolishFailureReason.refusal.slug, "refusal")
    }

    func testCatchAllCarriesTheErrorTypeName() {
        XCTAssertEqual(PolishFailureReason.other(UnrecognisedFailure()).slug, "other:UnrecognisedFailure")
    }

    /// An engine that classifies nothing — every backend but Apple FM today —
    /// still reports an identifiable reason through the protocol's default
    /// implementation.
    func testDefaultEngineImplementationFallsBackToTheCatchAll() {
        let engine = PassthroughPolishEngine()
        XCTAssertEqual(engine.failureReason(for: UnrecognisedFailure()), .other(UnrecognisedFailure()))
        XCTAssertEqual(engine.failureReason(for: UnrecognisedFailure()).slug, "other:UnrecognisedFailure")
    }

    #if canImport(FoundationModels)
    /// The acceptance criterion of #315: each of Apple's nine `GenerationError`
    /// cases must map to its own slug. Distinctness is what makes the per-reason
    /// count in the export meaningful — the whole investigation turns on telling
    /// `rateLimited` (Apple capping us) from `concurrentRequests` (our own two
    /// calls overlapping).
    func testEveryGenerationErrorCaseMapsToItsOwnSlug() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("LanguageModelSession.GenerationError requires the iOS/macOS 26 SDK")
        }
        let engine = AppleFoundationModelsPolishEngine()
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let expected: [(LanguageModelSession.GenerationError, PolishFailureReason)] = [
            (.exceededContextWindowSize(context), .exceededContextWindowSize),
            (.assetsUnavailable(context), .assetsUnavailable),
            (.guardrailViolation(context), .guardrailViolation),
            (.unsupportedGuide(context), .unsupportedGuide),
            (.unsupportedLanguageOrLocale(context), .unsupportedLanguageOrLocale),
            (.decodingFailure(context), .decodingFailure),
            (.rateLimited(context), .rateLimited),
            (.concurrentRequests(context), .concurrentRequests),
            (.refusal(LanguageModelSession.GenerationError.Refusal(transcriptEntries: []), context), .refusal)
        ]
        for (error, reason) in expected {
            XCTAssertEqual(engine.failureReason(for: error), reason)
        }
        XCTAssertEqual(Set(expected.map { engine.failureReason(for: $0.0) }).count, expected.count,
                       "two GenerationError cases collapsed into one slug — the export could not tell them apart")
    }

    /// An error Apple FM did not throw itself still has to be identifiable.
    func testAppleEngineMapsAnUnrecognisedErrorToTheCatchAll() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("AppleFoundationModelsPolishEngine requires the iOS/macOS 26 SDK")
        }
        let engine = AppleFoundationModelsPolishEngine()
        XCTAssertEqual(engine.failureReason(for: UnrecognisedFailure()).slug, "other:UnrecognisedFailure")
    }

    /// The reason must never quote the error's message: `Context.debugDescription`
    /// can carry the prompt, which is the user's dictation, and the reason
    /// travels into a shared export.
    func testSlugDoesNotLeakTheErrorContext() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("LanguageModelSession.GenerationError requires the iOS/macOS 26 SDK")
        }
        let secret = "rendez-vous chez le docteur mardi à quinze heures"
        let error = LanguageModelSession.GenerationError.rateLimited(
            .init(debugDescription: secret)
        )
        let slug = AppleFoundationModelsPolishEngine().failureReason(for: error).slug
        XCTAssertEqual(slug, "rateLimited")
        XCTAssertFalse(slug.contains("docteur"))
    }
    #endif

    // MARK: - The path from engine to metric

    /// The engine throws, the pipeline records the reason the engine gave, and
    /// the metric built from that result carries it unchanged.
    func testReasonSurvivesFromTheEngineIntoTheMetric() async {
        let result = await PolishPipeline.transform(
            preprocessed: "une dictée parfaitement ordinaire qu'il faudrait polir",
            engine: ClassifyingStubEngine(reason: .rateLimited),
            target: .french,
            mode: .natural
        )
        XCTAssertEqual(result.outcome, .engineFailed)
        XCTAssertEqual(result.failureReason, .rateLimited)

        let metric = PolishMetrics(
            engine: "classifying-stub", mode: .natural, targetLanguage: .french,
            detectedLanguage: "fr", rawCharCount: 54, polishedCharCount: 54,
            latencyMs: 20, outcome: result.outcome, failureReason: result.failureReason
        )
        XCTAssertEqual(metric.failureReason, .rateLimited)
    }

    /// The metric is persisted as one JSON object per line in the 7-day debug
    /// ring, so "carried into the metric" only counts if it survives the round
    /// trip to disk — as a bare string, which is what the export and any reader
    /// of the .jsonl expects.
    func testReasonSurvivesTheMetricJSONRoundTrip() throws {
        let metric = PolishMetrics(
            engine: "apple-fm", mode: .natural, targetLanguage: .french,
            detectedLanguage: "fr", rawCharCount: 354, polishedCharCount: 354,
            latencyMs: 20, outcome: .engineFailed,
            timings: PolishTimings(preprocessMs: 16, engineMs: 4, postprocessMs: 0),
            failureReason: .concurrentRequests
        )
        let data = try JSONEncoder().encode(metric)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"failureReason\":\"concurrentRequests\""),
                      "the reason must encode as a bare string, not a nested object: \(json)")
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)
        XCTAssertEqual(decoded.failureReason, .concurrentRequests)
    }

    /// Backward compatibility, the reason the field is optional: the ring holds
    /// seven days of events written by whatever build was installed at the time.
    /// This payload is shaped exactly like one written by 1.8.0 (25) — the build
    /// the field report came from — and it must still decode.
    func testEventEncodedWithoutAReasonStillDecodes() throws {
        let shipped = """
        {"engine":"apple-fm","mode":"natural","targetLanguage":"fr","detectedLanguage":"fr",\
        "rawCharCount":354,"polishedCharCount":354,"latencyMs":20,"outcome":"engineFailed",\
        "sttEngine":"PK","sttModelID":"parakeet-tdt-0.6b-v3",\
        "timings":{"preprocessMs":16,"engineMs":4,"postprocessMs":0}}
        """
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: XCTUnwrap(shipped.data(using: .utf8)))
        XCTAssertEqual(decoded.outcome, .engineFailed)
        XCTAssertNil(decoded.failureReason, "a missing key means 'written before the reason existed', not a failed decode")
        XCTAssertEqual(decoded.timings?.engineMs, 4)
    }

    // MARK: - What must NOT have changed

    /// #315 instruments the failure; it does not touch what the user receives.
    /// On an engine failure that is still the deterministic floor — the pre-pass
    /// output with target typography — never the literal raw. (#185)
    func testFailureStillReturnsTheDeterministicFloor() async {
        // The pre-pass has already turned the spoken "virgule" into a comma; the
        // floor must keep that work and apply French NBSP on top.
        let preprocessed = "Ok, petit test ?"
        let result = await PolishPipeline.transform(
            preprocessed: preprocessed,
            engine: ClassifyingStubEngine(reason: .rateLimited),
            target: .french,
            mode: .natural
        )
        XCTAssertEqual(result.outcome, .engineFailed)
        XCTAssertNil(result.engineOutput)
        let out = PolishPipeline.resolvedOutput(
            result, preprocessed: preprocessed, target: .french, mode: .natural
        )
        XCTAssertEqual(out, "Ok, petit test\u{00A0}?")
    }

    /// A cancellation is not an engine failure and must carry no reason — the
    /// pipeline catches it first, and #315 must not have blurred the two.
    func testCancellationCarriesNoReason() async {
        let task = Task {
            await PolishPipeline.transform(
                preprocessed: "une dictée que l'on va interrompre avant la fin",
                engine: SlowStubEngine(),
                target: .french,
                mode: .natural
            )
        }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertNil(result.failureReason)
    }

    /// Nothing reached the engine on a context overflow (#270), so there is
    /// nothing for it to have failed at.
    func testContextOverflowCarriesNoReason() async {
        let result = await PolishPipeline.transform(
            preprocessed: String(repeating: "a", count: 20_000),
            engine: NarrowStubEngine(),
            target: .french,
            mode: .natural
        )
        XCTAssertEqual(result.outcome, .exceededContextBudget)
        XCTAssertNil(result.failureReason)
    }
}

// MARK: - Stubs

/// An error no engine knows about — the catch-all's input.
private struct UnrecognisedFailure: Error {}

/// An engine that always throws and classifies its own failure, standing in for
/// Apple FM (which cannot run in a test process, let alone be made to rate-limit
/// on command).
private struct ClassifyingStubEngine: PolishEngineProtocol {
    let identifier = "classifying-stub"
    let reason: PolishFailureReason

    struct Failure: Error {}

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        throw Failure()
    }

    func failureReason(for error: Error) -> PolishFailureReason { reason }
}

/// Slow enough that a caller can cancel the surrounding task before it returns.
private struct SlowStubEngine: PolishEngineProtocol {
    let identifier = "slow-stub"

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        try Task.checkCancellation()
        return raw
    }
}

/// A ceiling so low that any real dictation is refused before the engine runs.
private struct NarrowStubEngine: PolishEngineProtocol {
    let identifier = "narrow-stub"

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        XCTFail("the engine must not be called on a context overflow")
        return raw
    }

    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    mode: PolishMode) -> PolishContextFit {
        PolishContextBudget(contextWindowTokens: 200, scaffoldingTokens: 0,
                            outputReserveRatio: 1.1, safetyMargin: 1.2)
            .fit(instructions: "", input: input)
    }
}
