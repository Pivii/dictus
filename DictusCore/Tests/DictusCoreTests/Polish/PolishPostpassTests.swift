// DictusCore/Tests/DictusCoreTests/Polish/PolishPostpassTests.swift
import XCTest
@testable import DictusCore

final class PolishPostpassTests: XCTestCase {

    // MARK: - Encode

    func testEncodeReplacesNewlinesWithMarker() {
        XCTAssertEqual(
            PolishPostpass.encodeForEngine("a\nb\nc"),
            "a<<NL>>b<<NL>>c"
        )
    }

    func testEncodePreservesTextWithoutNewlines() {
        XCTAssertEqual(
            PolishPostpass.encodeForEngine("hello world"),
            "hello world"
        )
    }

    func testEncodePreservesAdjacentMarkers() {
        XCTAssertEqual(
            PolishPostpass.encodeForEngine("\n\n"),
            "<<NL>><<NL>>"
        )
    }

    // MARK: - Decode: marker round-trip

    func testDecodeRestoresNewlinesFromMarker() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a<<NL>>b<<NL>>c", language: .french),
            "a\nb\nc"
        )
    }

    func testRoundTripPreservesMixedContent() {
        let original = "Bonjour,\nça va ?\nÀ bientôt."
        let encoded = PolishPostpass.encodeForEngine(original)
        // NBSP would be re-added on decode for `?` — bake the expected NBSP in.
        let expected = "Bonjour,\nça va\u{00A0}?\nÀ bientôt."
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(encoded, language: .french),
            expected
        )
    }

    // MARK: - Decode: French NBSP

    func testDecodeInsertsNBSPBeforeFrenchQuestion() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Salut, comment ça va ?", language: .french),
            "Salut, comment ça va\u{00A0}?"
        )
    }

    func testDecodeInsertsNBSPBeforeAllFrenchDoubleMarks() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Hey ! Quoi ? Vraiment : oui ; non.", language: .french),
            "Hey\u{00A0}! Quoi\u{00A0}? Vraiment\u{00A0}: oui\u{00A0}; non."
        )
    }

    func testDecodeLeavesExistingNBSPUntouched() {
        let alreadyClean = "Salut\u{00A0}? J'ai bien lu."
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(alreadyClean, language: .french),
            alreadyClean
        )
    }

    func testDecodeDoesNotTouchNonFrenchTypography() {
        let input = "Hi how are you ? Just asking ! Right ?"
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(input, language: .english),
            input
        )
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(input, language: .spanish),
            input
        )
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(input, language: .german),
            input
        )
    }

    func testDecodeDoesNotInsertNBSPWhenNoSpacePresent() {
        // No space between word and mark → leave alone (model already produced
        // tight punctuation, no French rule violation to repair).
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Salut?", language: .french),
            "Salut?"
        )
    }

    func testDecodeInsertsNBSPOnlyOnceForOneSpace() {
        // Defensive: pattern should not match `[ \t]` runs greedily and end up
        // inserting multiple NBSPs.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a ?", language: .french),
            "a\u{00A0}?"
        )
    }

    // MARK: - Decode: stray-newline collapse (fix A)

    func testDecodeCollapsesStackedNewlines() {
        // Marker decodes to one `\n`; the model added 3 more around it.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a.<<NL>>\n\n\nb", language: .french),
            "a.\nb"
        )
    }

    func testDecodeCollapsesNewlinesWithSurroundingSpaces() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("réunion. \n\n\n\n Premièrement", language: .french),
            "réunion.\nPremièrement"
        )
    }

    func testDecodeLeavesSingleNewlineUntouched() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a<<NL>>b", language: .french),
            "a\nb"
        )
    }

    func testDecodeTrickyMeetingRecapHasSingleBreaks() {
        // Test 4 from the 08/06 Wispr comparison: 3 line breaks, each previously
        // ballooned to `\n\n\n\n`. Expect exactly one `\n` per section.
        let engineOutput = "Voici le compte rendu.<<NL>>\n\n\nPremièrement, on a validé le budget\u{00A0}!<<NL>>\n\n\nDeuxièmement, d'accord\u{00A0}?<<NL>>\n\n\nA très vite."
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(engineOutput, language: .french),
            "Voici le compte rendu.\nPremièrement, on a validé le budget\u{00A0}!\nDeuxièmement, d'accord\u{00A0}?\nÀ très vite."
        )
    }

    // MARK: - Decode: capital À accent (fix C)

    func testDecodeRestoresSentenceInitialAAfterNewline() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Budget validé\u{00A0}!<<NL>>A très vite.", language: .french),
            "Budget validé\u{00A0}!\nÀ très vite."
        )
    }

    func testDecodeRestoresAAtStringStart() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("A demain, on en reparle.", language: .french),
            "À demain, on en reparle."
        )
    }

    func testDecodeRestoresAAfterPeriod() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("C'est noté. A plus tard.", language: .french),
            "C'est noté. À plus tard."
        )
    }

    func testDecodeDoesNotTouchAFollowedByUppercase() {
        // "A" before an acronym / proper noun is left alone.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("A WhisperKit on doit ça.", language: .french),
            "A WhisperKit on doit ça."
        )
    }

    func testDecodeDoesNotTouchAbbreviationA() {
        // "A." (abbreviation, no following space+lowercase) is left alone.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("A. Dupont est là.", language: .french),
            "A. Dupont est là."
        )
    }

    func testDecodeAAccentIsFrenchOnly() {
        let input = "A demain."
        XCTAssertEqual(PolishPostpass.decodeFromEngine(input, language: .english), input)
        XCTAssertEqual(PolishPostpass.decodeFromEngine(input, language: .german), input)
    }

    // MARK: - Combined behaviour

    func testFullPipelineFrench() {
        // Simulate the full round-trip for the round-1 batch-1 event 2 case.
        let preprocessed = "Bonjour, comment ça va ?\nj'espère que tu vas bien,\nà bientôt."
        let engineInput = PolishPostpass.encodeForEngine(preprocessed)
        // Engine returns the same text with capitalisation (best-case model
        // behaviour) and a marker preserved.
        let engineOutput = "Bonjour, comment ça va ?<<NL>>J'espère que tu vas bien,<<NL>>À bientôt."
        let final = PolishPostpass.decodeFromEngine(engineOutput, language: .french)
        XCTAssertEqual(
            final,
            "Bonjour, comment ça va\u{00A0}?\nJ'espère que tu vas bien,\nÀ bientôt."
        )
        // Sanity: the encoding step turned every `\n` into the marker.
        XCTAssertFalse(engineInput.contains("\n"))
        XCTAssertTrue(engineInput.contains(PolishPostpass.newlineMarker))
    }
}
