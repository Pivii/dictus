// DictusCore/Tests/DictusCoreTests/Polish/PolishTimeBudgetTests.swift
// Tests for how long a polish generation is allowed to take (#361). The flat 10 s of
// decision 14 lost a 1,015-character dictation on device; these pin the envelope that
// replaced it against the timings that falsified it.

import XCTest
@testable import DictusCore

final class PolishTimeBudgetTests: XCTestCase {

    // MARK: - The measurements that set the envelope

    /// Every generation measured on device must fit inside the budget for its input,
    /// or the watchdog is calibrated against the wrong distribution again. The last
    /// two of these exceeded the flat 10 s that shipped in decision 14.
    func testEveryMeasuredGenerationFitsItsBudget() {
        let measured: [(chars: Int, ms: Double)] = [
            (462, 5_067),    // probe burst, slowest of twenty
            (391, 12_002),   // device, 2026-08-23
            (1_015, 21_182)  // device, 2026-08-23, the dictation that was lost
        ]
        for point in measured {
            let budget = PolishTimeBudget.generationCeiling(forCharacters: point.chars)
            XCTAssertGreaterThan(
                budget, point.ms / 1_000,
                "\(point.chars) chars took \(point.ms) ms and the budget is \(budget) s"
            )
        }
    }

    /// The two that broke the old number, stated as the regression they are.
    func testTheOldFlatTenSecondsWouldHaveFiredOnBothLongCases() {
        XCTAssertGreaterThan(12.002, 10.0)
        XCTAssertGreaterThan(21.182, 10.0)
        XCTAssertGreaterThan(PolishTimeBudget.generationCeiling(forCharacters: 391), 12.002)
        XCTAssertGreaterThan(PolishTimeBudget.generationCeiling(forCharacters: 1_015), 21.182)
    }

    // MARK: - Shape

    func testShortInputsGetTheFloor() {
        // A 50-character dictation completes in about a second; the floor dominates.
        XCTAssertEqual(PolishTimeBudget.generationCeiling(forCharacters: 50),
                       PolishTimeBudget.floor, accuracy: 0.001)
        XCTAssertEqual(PolishTimeBudget.generationCeiling(forCharacters: 0),
                       PolishTimeBudget.floor, accuracy: 0.001)
    }

    /// Nothing shrinks below the number that shipped, so no dictation that completed
    /// under decision 14's flat 10 s can fail under this.
    func testTheFloorIsNeverBelowTheNumberItReplaces() {
        XCTAssertGreaterThanOrEqual(PolishTimeBudget.floor, 10)
    }

    func testTheBudgetGrowsWithTheInput() {
        let short = PolishTimeBudget.generationCeiling(forCharacters: 500)
        let long = PolishTimeBudget.generationCeiling(forCharacters: 2_000)
        XCTAssertGreaterThan(long, short)
        XCTAssertEqual(long, 2_000 * PolishTimeBudget.perCharacter, accuracy: 0.001)
    }

    func testANegativeCountCannotProduceANegativeBudget() {
        XCTAssertEqual(PolishTimeBudget.generationCeiling(forCharacters: -1),
                       PolishTimeBudget.floor, accuracy: 0.001)
    }

    // MARK: - Which watchdog wins

    /// The keyboard's expiry ends the dictation cleanly on both sides; the app's is
    /// the blunt one. The clean path has to be the one that normally happens.
    func testTheAppWaitsLongerThanTheKeyboard() {
        for chars in [0, 50, 462, 1_015, 4_160] {
            XCTAssertGreaterThan(
                PolishTimeBudget.handoffCeiling(forCharacters: chars),
                PolishTimeBudget.generationCeiling(forCharacters: chars),
                "\(chars) chars"
            )
        }
    }

    /// The worst case the context guard (#270) can let through — about 4,160
    /// characters for the French Natural prompt. Recorded so the ceiling this design
    /// has is visible, since it declares no ceiling of its own.
    func testTheLongestPermittedInputHasABoundedBudget() {
        let worst = PolishTimeBudget.handoffCeiling(forCharacters: 4_160)
        XCTAssertLessThan(worst, 180, "an Island stranded this long needs a rethink")
    }
}
