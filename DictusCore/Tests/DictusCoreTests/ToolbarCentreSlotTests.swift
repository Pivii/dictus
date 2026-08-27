// DictusCore/Tests/DictusCoreTests/ToolbarCentreSlotTests.swift
// The centre slot's priority table (#79, #241, #266, #315).
import XCTest
@testable import DictusCore

final class ToolbarCentreSlotTests: XCTestCase {

    /// Everything competing at once. Each test below removes the winner and asserts
    /// the next one down, which is what actually tests an ordering — asserting each
    /// case in isolation would pass against any order at all.
    private func resolve(isChoosingMode: Bool = false,
                         errorMessage: String? = nil,
                         offersDictationUndo: Bool = false,
                         hasSuggestions: Bool = false,
                         polishUnavailable: Bool = false,
                         armedModeName: String? = nil,
                         offersDiscoveryHint: Bool = false) -> ToolbarCentreSlot {
        ToolbarCentreSlot.resolve(
            isChoosingMode: isChoosingMode,
            errorMessage: errorMessage,
            offersDictationUndo: offersDictationUndo,
            hasSuggestions: hasSuggestions,
            polishUnavailable: polishUnavailable,
            armedModeName: armedModeName,
            offersDiscoveryHint: offersDiscoveryHint
        )
    }

    // MARK: - The ladder, one rung at a time

    /// The fan is open under the user's thumb, so the bar titles it — even over an
    /// error, which by then describes a dictation that already ended.
    func testChoosingAModeOutranksEverything() {
        XCTAssertEqual(
            resolve(
                isChoosingMode: true, errorMessage: "boom", offersDictationUndo: true,
                hasSuggestions: true, polishUnavailable: true,
                armedModeName: "List", offersDiscoveryHint: true
            ),
            .choosingMode
        )
    }

    func testErrorOutranksEverything() {
        XCTAssertEqual(
            resolve(
                errorMessage: "boom", offersDictationUndo: true, hasSuggestions: true,
                polishUnavailable: true, armedModeName: "List", offersDiscoveryHint: true
            ),
            .error("boom")
        )
    }

    func testUndoOutranksSuggestions() {
        XCTAssertEqual(
            resolve(
                offersDictationUndo: true, hasSuggestions: true,
                polishUnavailable: true, armedModeName: "List", offersDiscoveryHint: true
            ),
            .dictationUndo
        )
    }

    func testSuggestionsOutrankThePolishNotice() {
        XCTAssertEqual(
            resolve(
                hasSuggestions: true, polishUnavailable: true,
                armedModeName: "List", offersDiscoveryHint: true
            ),
            .suggestions
        )
    }

    /// #315's notice above the armed mode's name: when polish will not run, the mode
    /// will not run either, so naming it would advertise something this process has
    /// already stopped doing.
    func testThePolishNoticeOutranksTheArmedMode() {
        XCTAssertEqual(
            resolve(polishUnavailable: true, armedModeName: "List", offersDiscoveryHint: true),
            .polishUnavailable
        )
    }

    func testTheArmedModeOutranksTheHint() {
        XCTAssertEqual(
            resolve(armedModeName: "→ EN", offersDiscoveryHint: true),
            .armedMode("→ EN")
        )
    }

    func testTheHintIsTheLastThingBeforeNothing() {
        XCTAssertEqual(resolve(offersDiscoveryHint: true), .discoveryHint)
    }

    func testNothingToSayIsEmpty() {
        XCTAssertEqual(resolve(), .empty)
    }

    // MARK: - Who takes the hamburger's 32 pt

    /// The three occupants that arrive mid-task and are read at a glance take the
    /// whole bar; the three that describe a state share it, so the panel stays
    /// reachable (#241).
    func testOnlyTheWideOccupantsEvictTheHamburger() {
        XCTAssertTrue(ToolbarCentreSlot.error("x").evictsHamburger)
        XCTAssertTrue(ToolbarCentreSlot.dictationUndo.evictsHamburger)
        XCTAssertTrue(ToolbarCentreSlot.suggestions.evictsHamburger)

        XCTAssertFalse(ToolbarCentreSlot.choosingMode.evictsHamburger)
        XCTAssertFalse(ToolbarCentreSlot.polishUnavailable.evictsHamburger)
        XCTAssertFalse(ToolbarCentreSlot.armedMode("List").evictsHamburger)
        XCTAssertFalse(ToolbarCentreSlot.discoveryHint.evictsHamburger)
        XCTAssertFalse(ToolbarCentreSlot.empty.evictsHamburger)
    }
}
