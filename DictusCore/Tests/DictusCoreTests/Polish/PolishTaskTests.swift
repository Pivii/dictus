// DictusCore/Tests/DictusCoreTests/Polish/PolishTaskTests.swift
// The task: identifiers, contracts, and the user turn (issue #79).
import XCTest
@testable import DictusCore

final class PolishTaskTests: XCTestCase {

    // MARK: - Identifiers (the session-cache key)

    func testFreePolishIdentifiersMatchTheModeNamesAlreadyInTheDebugExport() {
        XCTAssertEqual(PolishTask.natural.identifier, "natural")
        XCTAssertEqual(PolishTask.repair.identifier, "repair")
        XCTAssertEqual(PolishTask.auto.identifier, "auto")
    }

    /// Namespaced so a future custom mode (#269) called "natural" cannot collide
    /// with the polish variant of that name and share its warmed session.
    func testSmartModeIdentifiersAreNamespaced() {
        XCTAssertEqual(PolishTask.smart(SmartModeCatalogue.notes).identifier, "smart.notes")
        XCTAssertEqual(
            PolishTask.smart(SmartModeCatalogue.translate(to: .english)).identifier,
            "smart.translate.en"
        )
    }

    func testEveryTaskThisBuildCanRunHasADistinctIdentifier() {
        var identifiers = [PolishTask.natural, .repair, .auto].map(\.identifier)
        identifiers += SmartModeCatalogue.builtIns.map { PolishTask.smart($0).identifier }
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    // MARK: - Contracts

    func testFreePolishContractsAreTheADR0003Bands() {
        XCTAssertEqual(PolishTask.natural.contract, .natural)
        XCTAssertEqual(PolishTask.repair.contract, .repair)
        XCTAssertEqual(PolishTask.auto.contract, .auto)
    }

    func testASmartTaskCarriesItsOwnModesContract() {
        let notes = SmartModeCatalogue.notes
        XCTAssertEqual(PolishTask.smart(notes).contract, notes.contract)
    }

    func testIsSmartSeparatesTheTwoHalves() {
        XCTAssertFalse(PolishTask.natural.isSmart)
        XCTAssertNil(PolishTask.natural.smartMode)
        XCTAssertEqual(PolishTask.natural.polishMode, .natural)

        let smart = PolishTask.smart(SmartModeCatalogue.notes)
        XCTAssertTrue(smart.isSmart)
        XCTAssertEqual(smart.smartMode?.id, "notes")
        XCTAssertNil(smart.polishMode)
    }

    // MARK: - The user turn

    /// The framing used to be hardcoded to the polish wording. Asking the model to
    /// produce notes under an instruction that says "polish" is self-defeating.
    func testTheUserTurnCarriesTheTasksOwnImperativeAndMarker() {
        let polish = PolishTask.natural.userTurn(raw: "salut")
        XCTAssertTrue(polish.hasPrefix("Polish this text."))
        XCTAssertTrue(polish.hasSuffix("Polished output:"))
        XCTAssertTrue(polish.contains("Input:\nsalut"))

        let notes = PolishTask.smart(SmartModeCatalogue.notes).userTurn(raw: "salut")
        XCTAssertTrue(notes.hasPrefix("Turn this text into notes."))
        XCTAssertTrue(notes.hasSuffix("Notes:"))
        XCTAssertFalse(notes.contains("Polish this text"))

        let translate = PolishTask
            .smart(SmartModeCatalogue.translate(to: .english))
            .userTurn(raw: "salut")
        XCTAssertTrue(translate.hasPrefix("Translate this text into English."))
        XCTAssertTrue(translate.hasSuffix("Translation:"))
    }

    // MARK: - Session-key normalisation

    /// `.auto` and every Smart Mode are written once for every input language, so
    /// their session key must not vary with the caller-supplied placeholder — a
    /// prewarm and the polish that follows it would otherwise miss each other.
    func testLanguageAgnosticPromptsAreTheAutoModeAndEverySmartMode() {
        XCTAssertFalse(PolishTask.natural.hasLanguageAgnosticPrompt)
        XCTAssertFalse(PolishTask.repair.hasLanguageAgnosticPrompt)
        XCTAssertTrue(PolishTask.auto.hasLanguageAgnosticPrompt)
        for mode in SmartModeCatalogue.builtIns {
            XCTAssertTrue(PolishTask.smart(mode).hasLanguageAgnosticPrompt, mode.id)
        }
    }
}
