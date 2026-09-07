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
    /// condense under an instruction that says "polish" is self-defeating.
    func testTheUserTurnCarriesTheTasksOwnImperativeAndMarker() {
        let polish = PolishTask.natural.userTurn(raw: "salut")
        XCTAssertTrue(polish.hasPrefix("Polish this text."))
        XCTAssertTrue(polish.hasSuffix("Polished output:"))
        XCTAssertTrue(polish.contains("\n\nsalut\n\n"))

        let notes = PolishTask.smart(SmartModeCatalogue.notes).userTurn(raw: "salut")
        XCTAssertTrue(notes.hasPrefix("Condense this text into a bulleted list."))
        XCTAssertTrue(notes.hasSuffix("Condensed output:"))
        XCTAssertFalse(notes.contains("Polish this text"))

        let translate = PolishTask
            .smart(SmartModeCatalogue.translate(to: .english))
            .userTurn(raw: "salut")
        XCTAssertTrue(translate.hasPrefix("Translate this text into English."))
        XCTAssertTrue(translate.hasSuffix("Translated output:"))
    }

    /// #518: no task may put an English label immediately before the transcript.
    ///
    /// The framing shipped with an `Input:` line there, and Apple FM answered
    /// ordinary French with `unsupportedLanguageOrLocale` — a language it supports,
    /// refused at the session boundary before generating anything. 10/10 refused
    /// with the label, 0/10 without it, on the two committed fixtures in
    /// `polish-harness/fixtures/refusal-fr.json`. Moving the label onto the same
    /// line as the text did not help (10/10) and translating it did (0/10), so the
    /// property to hold is the absence of the English label, not the layout.
    ///
    /// Asserted on every task because the composition is shared: a Smart Mode's
    /// user turn is the same string with its own imperative and marker, so a label
    /// reintroduced here would reach all eleven prompts at once.
    func testNoTaskLabelsTheTranscriptInEnglish() {
        let labels = ["input:", "text:", "transcript:", "source:", "original:"]
        let tasks = [PolishTask.natural, .repair, .auto]
            + SmartModeCatalogue.builtIns.map(PolishTask.smart)
        for task in tasks {
            // The marker is a label too and is deliberately kept — it trails the
            // transcript instead of preceding it, and removing it alone left the
            // refusal at 10/10 while costing the chat-reply bias it was measured
            // to provide. So the assertion is scoped to what comes BEFORE the text.
            let framing = task.userTurn(raw: "TRANSCRIPT")
            guard let placed = framing.range(of: "TRANSCRIPT") else {
                XCTFail("\(task.identifier) did not include the raw text at all")
                continue
            }
            let head = framing[..<placed.lowerBound].lowercased()
            for label in labels {
                XCTAssertFalse(
                    head.contains(label),
                    "\(task.identifier) labels the transcript with '\(label)' (#518)"
                )
            }
        }
    }

    /// The genre-prior finding, pinned so a later edit cannot reintroduce it.
    ///
    /// PR #388 measured that naming a written genre in the user turn pulls in that
    /// genre's furniture — 0 hallucinated openers/closers/names in 190 calls under
    /// the polish framing, 6 in 40 under "as the body of an email", including a
    /// `[Votre Nom]` the instructions had banned by name. So no mode's framing may
    /// name a document type, and all of them keep the shape measured at zero.
    func testNoModesFramingNamesAWrittenGenre() {
        let genres = ["email", "e-mail", "note", "memo", "letter", "report", "essay"]
        for mode in SmartModeCatalogue.builtIns {
            let framing = PolishTask.smart(mode).userTurn(raw: "x").lowercased()
            for genre in genres {
                XCTAssertFalse(
                    framing.contains(genre),
                    "\(mode.id) names the genre '\(genre)' in its user turn"
                )
            }
            XCTAssertTrue(
                framing.contains("output only"),
                "\(mode.id) does not follow the framing shape measured at zero"
            )
        }
    }

    /// A placeholder ban has to match the bracket shape, not a vocabulary: banning
    /// `[Your Name]` is exactly what produced `[Votre Nom]` (PR #388).
    func testEveryModesPromptBansTheBracketShapeRatherThanAWordList() {
        for mode in SmartModeCatalogue.builtIns {
            XCTAssertTrue(
                mode.prompt.instructions.contains("square brackets"),
                "\(mode.id) has no shape-matched placeholder ban"
            )
        }
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
