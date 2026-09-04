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
    /// The preamble's signature: the body IS the user's text, so the output is not
    /// "unrelated" — it is an output whose **opening line** is not theirs. That is
    /// what tells a preamble from a refusal, and both are refused.
    func testCapturedPreambleIsRefusedOnItsOpeningLine() {
        guard case .openingLineNotTheSpeakers(let share) = PolishPrefixAlignment.alignment(
            ofOutput: Self.preamblePolished, against: Self.preambleRaw
        ) else {
            return XCTFail("the captured preamble should be refused on its opening line")
        }
        XCTAssertLessThan(share, PolishPrefixAlignmentThresholds.default.supportFloor)
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
            .neverSupported
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
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned
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
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned
        )
    }

    // MARK: - The comparison itself

    /// Case and diacritics fold, so an accent the polish *added* — ADR 0003 rule 2
    /// — does not read as a different word.
    func testFoldingMakesAnAddedAccentTheSameWord() {
        let raw = "ecoute la reunion de demain est decalee a quinze heures pour tout le monde"
        let polished = "Écoute, la réunion de demain est décalée à 15 h pour tout le monde."
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned
        )
    }

    /// The floor is a floor: it rounds up. Stated as a test because the arithmetic
    /// is what a threshold sweep reads, and an off-by-one there moves every column.
    func testSupportFloorRoundsUp() {
        let thresholds = PolishPrefixAlignmentThresholds(
            windowWords: 10, supportFloor: 0.7, minimumWords: 8
        )
        // A 10-word window at 0.70 asks for 7 supported words, not 6.
        let raw = "alpha bravo charlie delta echo foxtrot golf hotel india juliett"
        let six = "alpha bravo charlie delta echo foxtrot zulu yankee xray whisky"
        let seven = "alpha bravo charlie delta echo foxtrot golf yankee xray whisky"
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: six, against: raw, thresholds: thresholds),
            .neverSupported
        )
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: seven, against: raw, thresholds: thresholds),
            .aligned
        )
    }

    // MARK: - The device regression (#466, second capture)

    /// **The case that falsified the first mechanism.** Captured on device on
    /// `rev 27819c2` — the first version of this check — App 1.8.1 (29), event
    /// `FB137B5E-BC76-4C51-A9B3-572F13A15B72`. Verbatim from the export.
    ///
    /// Its preamble is **six words** where the P1 capture's is fifteen. The first
    /// mechanism slid a 12-word window along the output looking for the input's
    /// opening; on this output that window straddles the preamble, reaches into the
    /// real text behind it, and still carries enough of the input's opening to pass
    /// at every threshold pair in the sweep. A window cannot see a preamble
    /// substantially shorter than itself, which is a limit of the shape and not a
    /// number to tune — hence the mechanism now judges the output's own head.
    static let shortPreambleRaw = """
    Okay donc là je refais les tests que je fais parce que j'ai été en détection de langue.     Là je repasse en français pour avoir des bons tests. Comme ça fera des tests complets.
    """
    static let shortPreamblePolished = """
    Bien sûr, voici la version polie :
    Je vais donc refaire les tests que je fais parce que j'ai été en détection de langue.     Là, je repasse en français pour avoir des bons tests. Comme ça fera des tests complets.
    """

    func testTheSixWordDevicePreambleIsRejected() {
        XCTAssertFalse(PolishPrefixAlignment.accepts(
            polished: Self.shortPreamblePolished, raw: Self.shortPreambleRaw
        ))
    }

    /// And it is rejected for the right reason: its opening line carries almost none
    /// of the speaker's words. Measured over 480 outputs, every legitimate multi-line
    /// free polish scores **1.00** here and every captured preamble **0.38 or less**,
    /// so the floor of 0.70 sits in an empty band 0.62 wide.
    func testTheSixWordPreambleIsRefusedOnItsOpeningLine() {
        guard case .openingLineNotTheSpeakers(let share) = PolishPrefixAlignment.alignment(
            ofOutput: Self.shortPreamblePolished, against: Self.shortPreambleRaw
        ) else {
            return XCTFail("the six-word preamble should be refused on its opening line")
        }
        XCTAssertLessThan(share, 0.4)
    }

    /// A **four-word** preamble on its own line, which the offset mechanism could
    /// not see and this one does. Length stopped mattering when the test became
    /// per-line: a preamble is a line, whatever its length.
    func testAFourWordPreambleOnItsOwnLineIsRefused() {
        let raw = "il faut que je pense à rappeler le plombier avant vendredi soir "
            + "et à préparer le dossier pour la réunion de lundi matin"
        let polished = "Voici le texte poli :\n"
            + "Il faut que je pense à rappeler le plombier avant vendredi soir "
            + "et à préparer le dossier pour la réunion de lundi matin."
        XCTAssertFalse(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    // MARK: - Scripts that write no word separators (the third regression)

    /// **A Chinese preamble, which was invisible until CodeRabbit asked.**
    ///
    /// `PolishLexicon` splits on "not a letter or a digit". Han characters *are*
    /// letters and Chinese writes no separators, so a whole dictation came out as one
    /// token, the eight-word floor was never met, and the check returned
    /// `.notApplicable` and accepted anything. Measured at `caught 0/1` before the
    /// tokeniser refinement.
    ///
    /// Auto mode (#239) is explicitly the language-agnostic route — `PolishPostpass`
    /// already skips per-language typography there because it would mangle CJK — so
    /// this is a path real users reach (#409), not a theoretical one.
    func testAChinesePreambleIsRefused() {
        let raw = "好的那我再做一次测试因为我之前在语言检测模式现在我切换回中文以便获得正确的测试结果这样就能做完整的测试了"
        let polished = "当然，以下是润色后的文本：\n"
            + "好的，那我再做一次测试，因为我之前在语言检测模式。现在我切换回中文，以便获得正确的测试结果，这样就能做完整的测试了。"
        XCTAssertFalse(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    /// The counter-test that matters as much: the same Chinese dictation polished
    /// faithfully still reaches the document. Segmenting a script is only worth
    /// anything if it does not start refusing that script's good output.
    func testAFaithfulChinesePolishIsAccepted() {
        let raw = "好的那我再做一次测试因为我之前在语言检测模式现在我切换回中文以便获得正确的测试结果这样就能做完整的测试了"
        let polished = "好的，那我再做一次测试，因为我之前在语言检测模式。现在我切换回中文，以便获得正确的测试结果，这样就能做完整的测试了。"
        XCTAssertTrue(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    /// The tokeniser refines only what the split could not break, and this pins the
    /// half that must **not** move: French elision and hyphenation tokenise exactly
    /// as they did before.
    ///
    /// Letting `NLTokenizer` own the whole job reads `l'utilisateur` as one token,
    /// which folds to `lutilisateur` — and then `PolishGrounding`, matching an
    /// output's anchor against the input's words, would see an input saying
    /// `le rapport d'Alice` as holding `dalice` while the output's anchor is `alice`.
    /// A real name, present in the dictation, would read as fabricated. No corpus
    /// entry has that shape, so only a test keeps it from being rediscovered.
    func testElisionAndHyphenationTokeniseAsBefore() {
        XCTAssertEqual(
            PolishLexicon.words(in: "le rapport d'Alice et de Jean-Pierre, qu'on attend"),
            ["le", "rapport", "d", "alice", "et", "de", "jean", "pierre", "qu", "on", "attend"]
        )
        // A German compound is long enough to be offered to the tokeniser, and comes
        // back whole — which is why the refinement is safe for a language that
        // welds its nouns together.
        XCTAssertEqual(
            PolishLexicon.words(in: "Geschwindigkeitsbegrenzung"), ["geschwindigkeitsbegrenzung"]
        )
    }

    // MARK: - The #456 shape: a legitimately translated opening (the second regression)

    /// **The case that falsified the offset mechanism.** The #456 transcript opens
    /// with speech Parakeet mistranscribed as English; the polish target is elected
    /// French from the majority, so ADR 0003 rule 8 licenses the model to reconstruct
    /// that opening in French. The output's head is then legitimately **none** of the
    /// speaker's words — exactly what a preamble looks like to an offset test, which
    /// refused 14 such polishes out of 14 on 50 real runs.
    ///
    /// Verbatim from run #5 of that measurement.
    func testATranslatedOpeningIsNotAPreamble() {
        let raw = "Okay, it's coming to approach to what I've got on the pencil to other "
            + "children. It's completely different. In fact, when you have curseur, we have "
            + "our héros qui est comme tel avec les animations qu'on connaît aujourd'hui "
            + "quand le curseur apparaît en fait la cloche elle apparaît et elle suit le "
            + "curseur donc ça veut dire que l'utilisateur va pouvoir jouer sur le héros "
            + "directement avec son curseur."
        let polished = "Okay, c'est en approche de ce que j'ai sur le crayon à partager avec "
            + "d'autres enfants. C'est complètement différent. En fait, lorsque vous avez le "
            + "curseur, nous avons notre héros tel qu'il est avec les animations que nous "
            + "connaissons aujourd'hui. Quand le curseur apparaît, en fait, la cloche "
            + "apparaît et elle suit le curseur, donc cela signifie que l'utilisateur pourra "
            + "jouer sur le héros directement avec son curseur."
        XCTAssertEqual(
            PolishPrefixAlignment.alignment(ofOutput: polished, against: raw), .aligned
        )
        XCTAssertTrue(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }

    /// The same transcript, the same translated opening, **with** a preamble line in
    /// front. Verbatim from the same run set. The pair is the whole point: the two
    /// differ by one line, and only the line boundary separates them.
    func testTheSameTranslatedOpeningBehindAPreambleIsRefused() {
        let raw = "Okay, it's coming to approach to what I've got on the pencil to other "
            + "children. It's completely different. In fact, when you have curseur, we have "
            + "our héros qui est comme tel avec les animations qu'on connaît aujourd'hui "
            + "quand le curseur apparaît en fait la cloche elle apparaît et elle suit le "
            + "curseur donc ça veut dire que l'utilisateur va pouvoir jouer sur le héros "
            + "directement avec son curseur."
        let polished = "Bien sûr, voici la version polie de votre texte :\n"
            + "Okay, c'est en approche de ce que j'ai sur le crayon à partager avec "
            + "d'autres enfants. C'est complètement différent. En fait, lorsque vous avez le "
            + "curseur, nous avons notre héros tel qu'il est avec les animations que nous "
            + "connaissons aujourd'hui."
        XCTAssertFalse(PolishPrefixAlignment.accepts(polished: polished, raw: raw))
    }
}
