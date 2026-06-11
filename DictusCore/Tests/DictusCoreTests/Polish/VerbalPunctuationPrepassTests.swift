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

    /// The bare "point" word is intentionally NOT converted (#185): it collides
    /// with the common French noun. The LLM supplies the terminal period.
    func testFrenchBarePointNotConverted() {
        let raw = "la phrase est finie point"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .french), raw)
    }

    /// The noun "point" inside a sentence must survive untouched (#185) — this
    /// is the whole reason the bare rule was dropped.
    func testFrenchPointNounPreserved() {
        let raw = "je partage un point de vue sur ce point final"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .french), raw)
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

    /// "trois points" (plural) is untouched — and since the bare "point" rule
    /// was dropped (#185), so is the singular form.
    func testFrenchPointsPluralUntouched() {
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

    /// "full stop" converts but the bare "period" word does not (#185) — it
    /// collides with the common English noun ("a period of time").
    func testEnglishBarePeriodNotConverted() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("hello comma world period", language: .english),
            "hello, world period"
        )
    }

    func testEnglishPeriodNounPreserved() {
        let raw = "we had a long period of calm"
        XCTAssertEqual(VerbalPunctuationPrepass.apply(raw, language: .english), raw)
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
        // "period" stays a word (#185); "full stop" gives the terminal mark.
        let raw = "Hi how are you question mark I read your report comma and I think it's great full stop"
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

    /// Multi-word "point d'interrogation" still converts; the trailing bare
    /// "point" now stays a word (#185).
    func testFrenchMultiWordConvertsBarePointStays() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("la question est point d'interrogation pas point", language: .french),
            "la question est ? pas point"
        )
    }

    // MARK: - Parakeet-in-the-wild artifacts

    /// Real observation from on-device test: Parakeet writes `"rapport, virgule,
    /// et"` (its own commas around the verbal command). Naive substitution would
    /// produce `"rapport,,, et"`. Cleanup must collapse to a single comma.
    func testFrenchVirguleSurroundedByParakeetCommas() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("J'ai bien lu ton rapport, virgule, et je pense", language: .french),
            "J'ai bien lu ton rapport, et je pense"
        )
    }

    /// Real observation: Parakeet writes `"vas ? Point d'interrogation."` —
    /// already inserts its own `?` plus the verbal keyword plus a period.
    /// Cleanup must keep a single `?`.
    func testFrenchPointDInterrogationAfterExistingQuestionMark() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("comment tu vas ? Point d'interrogation. J'ai bien lu", language: .french),
            "comment tu vas ? J'ai bien lu"
        )
    }

    /// Real observation: Parakeet writes `"bien. Nouvelle ligne. A bientôt."` —
    /// a period before AND after the newline verbal command. Newline must
    /// absorb both.
    func testFrenchNewlineAbsorbsAdjacentPeriods() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("J'espère que tu vas bien. Nouvelle ligne. A bientôt", language: .french),
            "J'espère que tu vas bien.\nA bientôt"
        )
    }

    /// Real observation: chained `"point virgule"` and `"point d'exclamation"`
    /// each surrounded by parakeet commas/periods. Result must be clean
    /// `";"` and `"!"`.
    func testFrenchChainedPointVirguleAndExclamation() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("Première partie, point virgule, deuxième partie, point d'exclamation.", language: .french),
            "Première partie ; deuxième partie !"
        )
    }

    /// EN equivalent: Parakeet often adds commas/periods around its English
    /// verbal commands too.
    func testEnglishCommaSurroundedByParakeetCommas() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("I read your report, comma, and I think it's great", language: .english),
            "I read your report, and I think it's great"
        )
    }

    func testEnglishQuestionMarkAfterExistingQuestionMark() {
        XCTAssertEqual(
            VerbalPunctuationPrepass.apply("how are you? Question mark. Hello", language: .english),
            "how are you? Hello"
        )
    }
}
