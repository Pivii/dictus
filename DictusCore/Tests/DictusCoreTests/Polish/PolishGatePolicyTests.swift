// DictusCore/Tests/DictusCoreTests/Polish/PolishGatePolicyTests.swift
// The three gates that can skip the engine, and what a mode does to them (#79).
import XCTest
@testable import DictusCore

final class PolishGatePolicyTests: XCTestCase {

    private let notes = PolishTask.smart(SmartModeCatalogue.notes)

    // MARK: - The toggle

    func testTheFreePolishHonoursTheToggle() {
        XCTAssertTrue(PolishGatePolicy.runsDespiteToggle(task: .natural, polishEnabled: true))
        XCTAssertFalse(PolishGatePolicy.runsDespiteToggle(task: .natural, polishEnabled: false))
    }

    /// The toggle defaults to off and says "do not tidy my transcriptions". Arming a
    /// mode is the same user asking for a transformation of this dictation, which is
    /// narrower and later.
    func testAnArmedModeRunsEvenWithTheToggleOff() {
        XCTAssertTrue(PolishGatePolicy.runsDespiteToggle(task: notes, polishEnabled: false))
    }

    // MARK: - Duration

    func testTheDurationGateSkipsShortDictationsForTheFreePolish() {
        XCTAssertTrue(PolishGatePolicy.skipsForDuration(1.8, task: .natural))
        XCTAssertFalse(PolishGatePolicy.skipsForDuration(2.0, task: .natural))
        XCTAssertFalse(PolishGatePolicy.skipsForDuration(4.0, task: .auto))
    }

    /// The failure #79 names: arm "→ EN", say a short sentence in 1.8 s, and the
    /// keyboard would otherwise insert French.
    func testTheDurationGateNeverSkipsAnArmedMode() {
        let toEnglish = PolishTask.smart(SmartModeCatalogue.translate(to: .english))
        XCTAssertFalse(PolishGatePolicy.skipsForDuration(1.8, task: toEnglish))
        XCTAssertFalse(PolishGatePolicy.skipsForDuration(0.1, task: toEnglish))
    }

    // MARK: - Gibberish

    func testTheGibberishGateSkipsUndetectedInputForTheFreePolish() {
        XCTAssertTrue(PolishGatePolicy.skipsForGibberish(hasDetectedLanguage: false, task: .natural))
        XCTAssertFalse(PolishGatePolicy.skipsForGibberish(hasDetectedLanguage: true, task: .natural))
    }

    /// Short sentences to translate land below the detection confidence threshold
    /// routinely, and a Smart Mode's prompt does not depend on detection at all.
    func testTheGibberishGateNeverSkipsAnArmedMode() {
        XCTAssertFalse(PolishGatePolicy.skipsForGibberish(hasDetectedLanguage: false, task: notes))
    }

    // MARK: - The threshold itself

    /// Moved from `PolishService` unchanged (#141). Pinned so a change to it is a
    /// deliberate act.
    func testTheDurationThresholdIsStillTwoSeconds() {
        XCTAssertEqual(PolishGatePolicy.engineMinDuration, 2.0)
    }
}
