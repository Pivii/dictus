// DictusCore/Tests/DictusCoreTests/Polish/PolishPrefixAlignmentTests.swift
// #466 (a chat preamble typed into the document) and #349 (a refusal inserted as
// the dictation), on the strings actually captured on device.
import XCTest
@testable import DictusCore

final class PolishPrefixAlignmentTests: XCTestCase {

    // MARK: - The two captures

    /// #466, event `198AC87D-1D6D-471B-851C-881B96AD26B1`, 2026-09-01T09:16:20Z,
    /// App 1.8.1 (28), `rev 69c5404@HEAD`. Verbatim from the issue.
    static let preambleRaw = """
    Okay donc là je refait les tests que j'ai fait parce que j'étais en détection de langue. \
    Là je repasse en français pour avoir les bons tests comme ça ça fera des tests complets.
    """
    static let preamblePolished = """
    Bien sûr, je vais vous aider à polir votre texte. Voici la version polie :
    Je vais donc faire de nouveau les tests que j'ai faits, car je suis en détection de langue. \
    Ensuite, je vais repasser en français pour avoir les bons tests, afin que cela permette de \
    faire des tests complets.
    """

    /// #349, export `dictus-polish-debug-20260812-135525.json`, event at 11:55:07Z,
    /// build 1.8.0 (26). Verbatim from the issue.
    static let refusalRaw = "Chops chop cheats chop kickpapiti papu papati tsu pa t."
    static let refusalPolished = """
    Je suis désolé, mais je ne peux pas fournir une sortie polie pour ce texte. Il semble \
    contenir des mots ou une structure inappropriée pour une sortie acceptable.
    """

    func testCapturedPreambleIsRejected() {
        XCTAssertFalse(PolishPrefixAlignment.accepts(
            polished: Self.preamblePolished, raw: Self.preambleRaw
        ))
    }

    /// The preamble's signature: the user's opening IS in the output, several words
    /// in. That is what tells it apart from a refusal, and what makes it a
    /// displacement rather than an unrelated answer.
    func testCapturedPreambleAlignsLateRatherThanNotAtAll() {
        guard case .aligned(let offset) = PolishPrefixAlignment.alignment(
            ofOutput: Self.preamblePolished, against: Self.preambleRaw
        ) else {
            return XCTFail("the captured preamble should align late, not fail to align")
        }
        XCTAssertGreaterThan(offset, PolishPrefixAlignmentThresholds.default.maximumOffsetWords)
    }

    func testCapturedRefusalIsRejectedByTheSameCheck() {
        XCTAssertFalse(PolishPrefixAlignment.accepts(
            polished: Self.refusalPolished, raw: Self.refusalRaw
        ))
    }

    /// #349's shape, and the reason `PolishGrounding` could never see it: a refusal
    /// shares no vocabulary with the gibberish it refuses, so there is nothing to
    /// align anywhere.
    func testCapturedRefusalDoesNotAlignAnywhere() {
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: Self.refusalPolished, against: Self.refusalRaw),
            .unaligned
        )
    }

    // MARK: - Legitimate polish is not touched

    /// The ordinary case: punctuation, capitalisation, one accent. Offset 0.
    func testFaithfulPolishAlignsAtZero() {
        let raw = "salut ça va j'espère que tu es passé un bon week-end moi de mon côté "
            + "c'était tranquille j'ai bossé sur le projet et franchement ça avance bien"
        let polished = "Salut, ça va ? J'espère que tu es passé un bon week-end. Moi de mon côté, "
            + "c'était tranquille, j'ai bossé sur le projet, et franchement, ça avance bien."
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned(offset: 0)
        )
        XCTAssertTrue(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    /// ADR 0003 rules 6 and 7 license deleting an opening filler run, which shifts
    /// the output's head. The tolerance exists for exactly this.
    func testOpeningFillersRemovedStillAccepted() {
        let raw = "euh alors euh donc en fait je voulais te dire que la réunion de demain "
            + "est décalée à quinze heures et que Marc ne pourra pas venir"
        let polished = "Je voulais te dire que la réunion de demain est décalée à 15 h "
            + "et que Marc ne pourra pas venir."
        XCTAssertTrue(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    /// A dictation whose own first line legitimately ends in a colon — #466's second
    /// acceptance criterion. The check reads words, not punctuation, so a colon is
    /// not a signal here and cannot be one.
    func testDictationWhoseFirstLineEndsInAColonIsNotDamaged() {
        let raw = "voici les trois points à retenir pour la réunion de lundi prochain "
            + "premièrement le budget deuxièmement le planning troisièmement les recrutements"
        let polished = "Voici les trois points à retenir pour la réunion de lundi prochain :\n"
            + "Premièrement, le budget. Deuxièmement, le planning. Troisièmement, les recrutements."
        XCTAssertTrue(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    // MARK: - The pass-through branches

    func testTextTooShortToCarryAPrefixPassesUntested() {
        // Seven words each side, under the eight-word floor: no prefix to align.
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(
                ofOutput: "Voici la version polie de votre texte",
                against: "on se voit demain matin vers dix"
            ),
            .notApplicable
        )
        XCTAssertTrue(PolishPrefixAlignment.accepts(
            polished: "Voici la version polie de votre texte",
            raw: "on se voit demain matin vers dix"
        ))
    }

    func testEmptyInputPassesUntested() {
        XCTAssertTrue(PolishPrefixAlignment.accepts(polished: Self.refusalPolished, raw: ""))
    }

    /// A dictation shorter than the window is compared on all of itself, not on a
    /// window padded with nothing.
    func testWindowIsClampedToTheShorterSide() {
        let raw = "il faut absolument que je rappelle le plombier avant vendredi soir"
        let polished = "Il faut absolument que je rappelle le plombier avant vendredi soir."
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned(offset: 0)
        )
    }

    // MARK: - The comparison itself

    /// Case and diacritics fold, so an accent the polish *added* — ADR 0003 rule 2
    /// — does not read as a different word.
    func testFoldingMakesAnAddedAccentTheSameWord() {
        let raw = "ecoute la reunion de demain est decalee a quinze heures pour tout le monde"
        let polished = "Écoute, la réunion de demain est décalée à 15 h pour tout le monde."
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned(offset: 0)
        )
    }

    /// The floor is a floor: it rounds up. Stated as a test because the arithmetic
    /// is what a threshold sweep reads, and an off-by-one there moves every column.
    func testOverlapFloorRoundsUp() {
        let thresholds = PolishPrefixAlignmentThresholds(
            windowWords: 10, overlapFloor: 0.4, maximumOffsetWords: 4, minimumWords: 8
        )
        // Ten distinct reference words; 0.4 asks for four of them, so three is not
        // enough anywhere in the output.
        let raw = "alpha bravo charlie delta echo foxtrot golf hotel india juliett"
        let three = "alpha bravo charlie zulu yankee xray whisky victor uniform tango"
        let four = "alpha bravo charlie delta yankee xray whisky victor uniform tango"
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: three, against: raw, thresholds: thresholds),
            .unaligned
        )
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: four, against: raw, thresholds: thresholds),
            .aligned(offset: 0)
        )
    }
}
