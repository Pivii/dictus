// DictusCore/Tests/DictusCoreTests/Polish/VerbalPunctuationPrepassTests.swift
import XCTest
@testable import DictusCore

final class VerbalPunctuationPrepassTests: XCTestCase {

    // MARK: - French

    func testFrenchVirgule() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("hello virgule world", language: .french),
            "hello, world"
        )
    }

    func testFrenchPointDInterrogation() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("salut comment tu vas point d'interrogation", language: .french),
            "salut comment tu vas ?"
        )
    }

    func testFrenchPointDExclamation() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("super point d'exclamation", language: .french),
            "super !"
        )
    }

    func testFrenchPointVirgule() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("un texte point virgule un autre", language: .french),
            "un texte ; un autre"
        )
    }

    func testFrenchDeuxPoints() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("voici deux points la liste", language: .french),
            "voici : la liste"
        )
    }

    func testFrenchPointSingleWord() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("la phrase est finie point", language: .french),
            "la phrase est finie."
        )
    }

    func testFrenchMultipleSubstitutionsInOneSentence() {
        // The exact failure case from round 3 testing (event 12).
        let raw = "Salut, comment tu vas point d'interrogation J'ai bien lu ton rapport virgule et je pense que c'est bien"
        let expected = "Salut, comment tu vas ? J'ai bien lu ton rapport, et je pense que c'est bien"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .french), expected)
    }

    func testFrenchRetourALaLigne() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("bonjour retour à la ligne au revoir", language: .french),
            "bonjour\nau revoir"
        )
    }

    func testFrenchNouvelleLigne() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("bonjour nouvelle ligne au revoir", language: .french),
            "bonjour\nau revoir"
        )
    }

    func testFrenchALaLigne() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("bonjour à la ligne au revoir", language: .french),
            "bonjour\nau revoir"
        )
    }

    /// Case-insensitive matching: "Point D'Interrogation" must trigger.
    func testFrenchCaseInsensitive() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("Salut Point D'Interrogation", language: .french),
            "Salut ?"
        )
    }

    /// Typographic apostrophe (’) must trigger too — STT and the Light prompt
    /// both emit it on French outputs.
    func testFrenchTypographicApostrophe() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("salut point d’interrogation", language: .french),
            "salut ?"
        )
    }

    /// "trois points" (plural) must NOT match the singular "point" rule.
    func testFrenchWordBoundaryProtectsPlural() {
        let raw = "j'ai mis trois points sur ma carte"
        let result = VerbalPunctuationPrepass.apply(raw, language: .french)
        XCTAssertEqual(result, raw)
    }

    // MARK: - English

    func testEnglishComma() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("hello comma world", language: .english),
            "hello, world"
        )
    }

    func testEnglishQuestionMark() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("how are you question mark", language: .english),
            "how are you ?"
        )
    }

    func testEnglishExclamationMark() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("great exclamation mark", language: .english),
            "great !"
        )
    }

    func testEnglishExclamationPoint() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("great exclamation point", language: .english),
            "great !"
        )
    }

    func testEnglishFullStop() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("this is the end full stop", language: .english),
            "this is the end."
        )
    }

    func testEnglishPeriodAndComma() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("hello comma world period", language: .english),
            "hello, world."
        )
    }

    func testEnglishSemicolonAndColon() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("first semicolon second colon here", language: .english),
            "first ; second : here"
        )
    }

    func testEnglishNewLine() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("hello new line world", language: .english),
            "hello\nworld"
        )
    }

    func testEnglishNewlineSingleToken() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("hello newline world", language: .english),
            "hello\nworld"
        )
    }

    func testEnglishMultipleSubstitutions() {
        let raw = "Hi how are you question mark I read your report comma and I think it's great period"
        let expected = "Hi how are you ? I read your report, and I think it's great."
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .english), expected)
    }

    // MARK: - Languages without rules

    func testSpanishPassthrough() {
        let raw = "hola comma mundo"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .spanish), raw)
    }

    func testGermanPassthrough() {
        let raw = "hallo comma welt"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .german), raw)
    }

    // MARK: - Edge cases

    func testEmptyString() {
        XCTAssertEqual(VerbalPunctuationPrepass.apply("", language: .french), "")
    }

    func testNoSubstitutionNeeded() {
        let raw = "Bonjour, comment ça va ?"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .french), raw)
    }

    /// Multiple-word punctuation must win over single-word: don't let \bpoint\b
    /// match the "point" inside "point d'interrogation".
    func testFrenchOrderingMultiWordWins() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("la question est point d'interrogation pas point", language: .french),
            "la question est ? pas."
        )
    }
}
