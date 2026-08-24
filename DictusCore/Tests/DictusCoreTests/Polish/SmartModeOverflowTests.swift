// DictusCore/Tests/DictusCoreTests/Polish/SmartModeOverflowTests.swift
// What an armed mode inserts when the context guard refuses it (#79, block B decision).
import XCTest
@testable import DictusCore

final class SmartModeOverflowTests: XCTestCase {

    private func job(_ mode: SmartMode) -> PolishJob {
        PolishJob(task: .smart(mode), promptLanguage: .french, languageAgnosticPath: false)
    }

    private func result(_ outcome: PolishMetrics.Outcome) -> PolishPipeline.Result {
        PolishPipeline.Result(engineOutput: nil, outcome: outcome, engineMs: 0, postprocessMs: 0)
    }

    // MARK: - The catalogue's answers

    func testNotesDegradesToTheRawText() {
        XCTAssertEqual(SmartModeCatalogue.notes.overflowBehaviour, .insertRawText)
    }

    /// Translation cannot degrade: the floor is the input language, which is the one
    /// thing the mode exists to change.
    func testEveryTranslateModeRefuses() {
        for language in SupportedLanguage.allCases {
            XCTAssertEqual(
                SmartModeCatalogue.translate(to: language).overflowBehaviour,
                .insertNothing,
                "translate.\(language.rawValue) must not fall back to the input language"
            )
        }
    }

    // MARK: - What the pipeline does with them

    func testNotesInsertsTheDeterministicFloorOnOverflow() {
        let out = PolishPipeline.resolvedOutput(
            result(.exceededContextBudget),
            preprocessed: "Ok, petit test ?",
            job: job(SmartModeCatalogue.notes)
        )
        XCTAssertEqual(
            out, "Ok, petit test\u{00A0}?",
            "the floor is the pre-pass output with typography, never the literal raw (#185)"
        )
    }

    func testTranslateInsertsNothingOnOverflow() {
        XCTAssertNil(PolishPipeline.resolvedOutput(
            result(.exceededContextBudget),
            preprocessed: "Ok, petit test ?",
            job: job(SmartModeCatalogue.translate(to: .english))
        ))
    }

    /// The exception is as narrow as the argument for it. Every other non-success
    /// reached the engine, or describes a process that will not call it again, so
    /// fail-closed still applies to Notes as much as to Translate.
    func testEveryOtherFailureStaysClosedEvenForADegradingMode() {
        let others: [PolishMetrics.Outcome] = [
            .engineFailed, .rejectedGuardrail, .cancelled, .engineUnavailable, .skipped
        ]
        for outcome in others {
            XCTAssertNil(
                PolishPipeline.resolvedOutput(
                    result(outcome), preprocessed: "Ok", job: job(SmartModeCatalogue.notes)
                ),
                "\(outcome.rawValue) must not degrade — a transformation was attempted"
            )
            XCTAssertFalse(
                PolishPipeline.degradesToFloor(SmartModeCatalogue.notes, outcome: outcome)
            )
        }
    }

    func testSuccessIsUnaffected() {
        let succeeded = PolishPipeline.Result(
            engineOutput: "• un point", outcome: .success, engineMs: 1, postprocessMs: 0
        )
        XCTAssertEqual(
            PolishPipeline.resolvedOutput(
                succeeded, preprocessed: "un point", job: job(SmartModeCatalogue.notes)
            ),
            "• un point"
        )
    }

    /// The free polish never changed: it falls back on everything, mode or no mode.
    func testFreePolishStillFallsBackOnOverflow() {
        XCTAssertEqual(
            PolishPipeline.resolvedOutput(
                result(.exceededContextBudget),
                preprocessed: "Ok, petit test ?",
                job: PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false)
            ),
            "Ok, petit test\u{00A0}?"
        )
    }

    // MARK: - Crossing the App Group

    func testBehaviourSurvivesAnEncodeDecodeRoundTrip() throws {
        let encoded = try JSONEncoder().encode(SmartModeCatalogue.notes)
        let decoded = try JSONDecoder().decode(SmartMode.self, from: encoded)
        XCTAssertEqual(decoded.overflowBehaviour, .insertRawText)
        XCTAssertEqual(decoded, SmartModeCatalogue.notes)
    }

    /// A record written by a build that predates the field — an app update landing
    /// between the snapshot and the read. It must decode, and it must decode to the
    /// safe half: losing one Notes dictation across one upgrade is recoverable,
    /// sending French to an American client is not.
    func testARecordWithoutTheFieldDecodesAsRefusing() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(SmartModeCatalogue.notes)
            ) as? [String: Any]
        )
        json.removeValue(forKey: "overflowBehaviour")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(SmartMode.self, from: stripped)
        XCTAssertEqual(decoded.id, SmartModeCatalogue.notesIdentifier)
        XCTAssertEqual(decoded.overflowBehaviour, .insertNothing)
    }
}
