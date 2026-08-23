// DictusCore/Tests/DictusCoreTests/Polish/PolishAvailabilityGateTests.swift
import XCTest
@testable import DictusCore

/// Coverage of decision 14 on #315: stop calling an engine that is refusing us.
///
/// The rule (when to stop), the effect (the engine is not called and the call
/// costs nothing), and the two things this must NOT have changed — what the user
/// receives, and the decodability of events written before the outcome existed.
final class PolishAvailabilityGateTests: XCTestCase {

    private let apple = "apple-fm"

    // MARK: - The rule

    /// A fresh gate is the whole of the reset rule: a new process starts
    /// available because it starts with a new value of this type.
    func testFreshGateAllowsTheCall() {
        XCTAssertTrue(PolishAvailabilityGate().allowsCall(engine: apple))
        XCTAssertNil(PolishAvailabilityGate().unavailableEngine)
    }

    /// One refusal is not enough. Every `rateLimited` run captured on #315
    /// arrives in a run of at least two, so a single one must not cost the user
    /// their polish for the rest of the process.
    func testOneRefusalDoesNotStopTheEngine() {
        var gate = PolishAvailabilityGate()
        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple))
        XCTAssertTrue(gate.allowsCall(engine: apple))
    }

    /// Two, not three — and the transition is reported exactly once, so the
    /// caller can log and announce it without tracking the edge itself.
    func testTwoConsecutiveRefusalsStopTheEngine() {
        var gate = PolishAvailabilityGate()
        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple))
        XCTAssertTrue(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple),
                      "the second refusal is the transition")
        XCTAssertFalse(gate.allowsCall(engine: apple))
        XCTAssertEqual(gate.unavailableEngine, apple)

        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple),
                       "the transition must be reported once, not on every further refusal")
    }

    /// Consecutive means consecutive. A polish that ran between two refusals is
    /// proof the engine is serving this process, and the count starts over.
    func testASuccessBetweenTwoRefusalsResetsTheRun() {
        var gate = PolishAvailabilityGate()
        gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple)
        gate.record(outcome: .success, reason: nil, engine: apple)
        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple))
        XCTAssertTrue(gate.allowsCall(engine: apple), "the run was broken by the success")
    }

    /// A guardrail violation is a real generation the model ran and Apple then
    /// rejected — the opposite of the instant refusal this gate watches for. It
    /// breaks the run like a success does.
    func testAnotherFailureReasonResetsTheRun() {
        for reason in [PolishFailureReason.guardrailViolation, .unsupportedLanguageOrLocale] {
            var gate = PolishAvailabilityGate()
            gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple)
            gate.record(outcome: .engineFailed, reason: reason, engine: apple)
            XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple),
                           "\(reason.slug) must have broken the run")
            XCTAssertTrue(gate.allowsCall(engine: apple))
        }
        var rejected = PolishAvailabilityGate()
        rejected.record(outcome: .engineFailed, reason: .rateLimited, engine: apple)
        rejected.record(outcome: .rejectedGuardrail, reason: nil, engine: apple)
        XCTAssertFalse(rejected.record(outcome: .engineFailed, reason: .rateLimited, engine: apple))
        XCTAssertTrue(rejected.allowsCall(engine: apple))
    }

    /// Outcomes where the engine was never reached, or was cut off before it
    /// could answer, carry no evidence either way — they must neither count nor
    /// reset. A flash dictation in the middle of a refusal run would otherwise
    /// hide the run.
    func testOutcomesThatNeverReachedTheEngineLeaveTheRunAlone() {
        let inert: [PolishMetrics.Outcome] = [
            .cancelled, .exceededContextBudget, .skipped, .skippedShort,
            .skippedAutoMode, .engineUnavailable
        ]
        for outcome in inert {
            var gate = PolishAvailabilityGate()
            gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple)
            XCTAssertFalse(gate.record(outcome: outcome, reason: nil, engine: apple))
            XCTAssertTrue(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple),
                          "\(outcome.rawValue) must not have reset the run")
        }
    }

    /// The run belongs to one backend. Apple Intelligence being switched off
    /// mid-process drops the coordinator to the passthrough engine, and refusals
    /// from the model it left say nothing about the one it moved to.
    func testTheGateIsScopedToTheEngineThatRefused() {
        var gate = PolishAvailabilityGate()
        gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple)
        gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple)
        XCTAssertFalse(gate.allowsCall(engine: apple))
        XCTAssertTrue(gate.allowsCall(engine: "passthrough"))
    }

    /// Two refusals from two different backends are not a run.
    func testRefusalsFromDifferentEnginesDoNotAccumulate() {
        var gate = PolishAvailabilityGate()
        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: "other-engine"))
        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: apple))
        XCTAssertTrue(gate.allowsCall(engine: apple))
        XCTAssertTrue(gate.allowsCall(engine: "other-engine"))
    }

    /// The threshold is a documented number, not an accident of the loop above.
    func testThresholdIsTwo() {
        XCTAssertEqual(PolishAvailabilityGate.consecutiveRefusalsBeforeUnavailable, 2)
    }

    // MARK: - The effect on the transform

    /// The point of the whole change: while unavailable the engine is not
    /// invoked at all. The stub fails the test if it is.
    func testTransformDoesNotCallAnUnavailableEngine() async {
        let result = await PolishPipeline.transform(
            preprocessed: "une dictée parfaitement ordinaire qu'il faudrait polir",
            engine: MustNotRunEngine(),
            target: .french,
            mode: .natural,
            gate: blockedGate(for: MustNotRunEngine().identifier)
        )
        XCTAssertEqual(result.outcome, .engineUnavailable)
        XCTAssertEqual(result.engineMs, 0)
        XCTAssertEqual(result.postprocessMs, 0)
        XCTAssertNil(result.engineOutput)
    }

    /// Nothing failed, so nothing named a reason. `engineUnavailable` and
    /// `engineFailed` have to stay separable in an export: one counts outages,
    /// the other counts failures, and folding them would inflate the failure
    /// rate this issue has been tracking since 2026-08-05.
    func testUnavailableCarriesNoFailureReason() async {
        let result = await PolishPipeline.transform(
            preprocessed: "une dictée parfaitement ordinaire qu'il faudrait polir",
            engine: MustNotRunEngine(),
            target: .french,
            mode: .natural,
            gate: blockedGate(for: MustNotRunEngine().identifier)
        )
        XCTAssertNil(result.failureReason)
    }

    /// "Latency on that path should drop to roughly zero." Measured against the
    /// same engine on the same input, with the gate as the only difference: a
    /// 300 ms backend is waited for when polish is available and not waited for
    /// when it is not.
    func testUnavailablePathCostsNothingComparedToACall() async {
        let input = "une dictée parfaitement ordinaire qu'il faudrait polir"
        let engine = SlowEngine()

        let openStart = Date()
        let served = await PolishPipeline.transform(
            preprocessed: input, engine: engine, target: .french, mode: .natural
        )
        let openMs = Date().timeIntervalSince(openStart) * 1000
        XCTAssertEqual(served.outcome, .success)
        XCTAssertGreaterThan(openMs, 250, "the control arm must actually have waited for the engine")

        let blockedStart = Date()
        let skipped = await PolishPipeline.transform(
            preprocessed: input, engine: engine, target: .french, mode: .natural,
            gate: blockedGate(for: engine.identifier)
        )
        let blockedMs = Date().timeIntervalSince(blockedStart) * 1000
        XCTAssertEqual(skipped.outcome, .engineUnavailable)
        XCTAssertLessThan(blockedMs, 50, "the skip must not wait for anything")
    }

    // MARK: - What must NOT have changed

    /// The user gets the deterministic floor, exactly as on a guardrail
    /// rejection: the pre-pass output with target typography, never the literal
    /// raw. The pre-pass has already turned the spoken "virgule" into a comma
    /// here, and French NBSP goes on top.
    func testUnavailableStillReturnsTheDeterministicFloor() async {
        let preprocessed = "Ok, petit test ?"
        let result = await PolishPipeline.transform(
            preprocessed: preprocessed,
            engine: MustNotRunEngine(),
            target: .french,
            mode: .natural,
            gate: blockedGate(for: MustNotRunEngine().identifier)
        )
        let out = PolishPipeline.resolvedOutput(
            result, preprocessed: preprocessed, target: .french, mode: .natural
        )
        XCTAssertEqual(out, "Ok, petit test\u{00A0}?")
    }

    /// Auto mode keeps its own floor — the pre-pass output with no typography,
    /// so a placeholder target cannot leak French NBSP onto another language.
    func testUnavailableAutoModeReturnsTheAutoFloor() async {
        let preprocessed = "ça va ?"
        let result = await PolishPipeline.transform(
            preprocessed: preprocessed,
            engine: MustNotRunEngine(),
            target: .french,
            mode: .auto,
            gate: blockedGate(for: MustNotRunEngine().identifier)
        )
        XCTAssertEqual(result.outcome, .engineUnavailable)
        let out = PolishPipeline.resolvedOutput(
            result, preprocessed: preprocessed, target: .french, mode: .auto
        )
        XCTAssertEqual(out, preprocessed)
    }

    /// A default-constructed gate is what the harness and every pre-existing
    /// call site get, and it must change nothing.
    func testTheDefaultGateLeavesTheTransformUntouched() async {
        let input = "this is a perfectly normal english sentence about testing things"
        let result = await PolishPipeline.transform(
            preprocessed: input, engine: PassthroughPolishEngine(), target: .english, mode: .natural
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    // MARK: - The record of it

    /// The outcome is a wire value: it lands in the polish debug export and gets
    /// compared across builds.
    func testOutcomeSlugIsStable() {
        XCTAssertEqual(PolishMetrics.Outcome.engineUnavailable.rawValue, "engineUnavailable")
    }

    func testOutcomeSurvivesTheMetricJSONRoundTrip() throws {
        let metric = PolishMetrics(
            engine: "apple-fm", mode: .natural, targetLanguage: .french,
            detectedLanguage: "fr", rawCharCount: 61, polishedCharCount: 61,
            latencyMs: 1, outcome: .engineUnavailable,
            timings: PolishTimings(preprocessMs: 1, engineMs: 0, postprocessMs: 0)
        )
        let data = try JSONEncoder().encode(metric)
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)
        XCTAssertEqual(decoded.outcome, .engineUnavailable)
        XCTAssertNil(decoded.failureReason)
        XCTAssertEqual(decoded.timings?.engineMs, 0)
    }

    /// The seven-day ring holds events written by whatever build was installed at
    /// the time. Adding an outcome must not have broken any of them — this
    /// payload is shaped like one written by 1.8.0 (26).
    func testEventsFromShippedBuildsStillDecode() throws {
        let shipped = """
        {"engine":"apple-fm","mode":"natural","targetLanguage":"fr","detectedLanguage":"fr",\
        "rawCharCount":354,"polishedCharCount":354,"latencyMs":20,"outcome":"engineFailed",\
        "failureReason":"rateLimited","sttEngine":"PK","sttModelID":"parakeet-tdt-0.6b-v3",\
        "timings":{"preprocessMs":16,"engineMs":4,"postprocessMs":0}}
        """
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: XCTUnwrap(shipped.data(using: .utf8)))
        XCTAssertEqual(decoded.outcome, .engineFailed)
        XCTAssertEqual(decoded.failureReason, .rateLimited)
    }

    /// The persistent log line a future capture is read against. Pinned because
    /// it is what a grep will look for.
    func testUnavailableLogLineNamesTheEngineAndTheReason() {
        let event = LogEvent.polishEngineUnavailable(
            engine: "apple-fm", reason: "rateLimited", consecutiveRefusals: 2
        )
        XCTAssertEqual(event.name, "polishEngineUnavailable")
        XCTAssertEqual(event.subsystem, .transcription)
        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.message, "engine=apple-fm reason=rateLimited consecutiveRefusals=2")
    }

    // MARK: - Helpers

    /// A gate that has already seen the two refusals, i.e. the state the device
    /// reaches after a `rateLimited` run.
    private func blockedGate(for engine: String) -> PolishAvailabilityGate {
        var gate = PolishAvailabilityGate()
        gate.record(outcome: .engineFailed, reason: .rateLimited, engine: engine)
        gate.record(outcome: .engineFailed, reason: .rateLimited, engine: engine)
        XCTAssertFalse(gate.allowsCall(engine: engine))
        return gate
    }
}

// MARK: - Stubs

/// Fails the test if the pipeline calls it. "Do not invoke the engine" is the
/// behaviour under test, and the only way to assert it is to make the call
/// itself an error.
private struct MustNotRunEngine: PolishEngineProtocol {
    let identifier = "must-not-run"

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        XCTFail("the engine must not be called while polish is unavailable")
        return raw
    }
}

/// Slow enough that waiting for it is measurable — the control arm of the
/// latency assertion.
private struct SlowEngine: PolishEngineProtocol {
    let identifier = "slow-engine"

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        return raw
    }
}
