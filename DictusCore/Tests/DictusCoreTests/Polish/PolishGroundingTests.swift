// DictusCore/Tests/DictusCoreTests/Polish/PolishGroundingTests.swift
import XCTest
@testable import DictusCore

/// #414. The strings marked MEASURED are verbatim from the #393 harness run
/// committed under `docs/research/79-smart-modes/raw/`; they are not invented for
/// the test.
final class PolishGroundingTests: XCTestCase {

    // MARK: - The measured failure

    /// MEASURED, `round1-notes-show-5runs.txt`, N2 run 5, recorded as a **success**.
    /// The last bullet is the first worked example inside `SmartModeNotesPrompt`,
    /// copied word for word into a dictation naming neither Sophie nor December.
    private let sophieRaw = """
    bon alors euh je récapitule ce qu'il faut que je fasse avant la réunion donc déjà faut que je \
    récupère les chiffres de janvier auprès de Marion elle m'a dit qu'elle les aurait mardi enfin \
    non mercredi et euh du coup faudra que je fasse le tableau comparatif avec ceux de l'année \
    dernière et puis aussi tu vois il faut absolument que j'appelle le prestataire parce que leur \
    devis il est encore passé de 12000 à 15000 euros et ça personne l'a validé et enfin bon voilà \
    il faudrait aussi que je pense à réserver la salle du deuxième étage parce que l'autre elle \
    est prise toute la semaine
    """
    private let sophieOutput = """
    - Récupérer les chiffres de janvier auprès de Marion
    - Faire le tableau comparatif avec ceux de l'année dernière
    - Appeler le prestataire pour valider le devis de 12000 euros à 15000 euros
    - Réserver la salle du deuxième étage
    - Appeler Sophie avant : elle a les données de décembre
    """

    func testThePromptExampleCopiedIntoTheOutputIsUngrounded() {
        let ungrounded = PolishGrounding.ungroundedAnchors(
            in: sophieOutput, input: sophieRaw, languageCode: "fr"
        )
        XCTAssertEqual(ungrounded.map(\.text), ["Sophie"])
    }

    /// The same output minus the fabricated bullet is the run that ran four other
    /// times on the same fixture, and it must still be accepted — the check has to
    /// separate the two, not reject the whole fixture.
    func testTheSameListWithoutTheFabricatedBulletIsGrounded() {
        let good = sophieOutput.split(separator: "\n").dropLast().joined(separator: "\n")
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(in: good, input: sophieRaw, languageCode: "fr").count, 0
        )
    }

    /// The name the speaker DID say is found and grounded, so the acceptance above
    /// is not the check silently finding nothing.
    func testTheNameTheSpeakerDidSayIsFoundAndGrounded() {
        let anchors = PolishGrounding.anchors(in: sophieOutput, languageCode: "fr").map(\.text)
        XCTAssertTrue(anchors.contains("Marion"), "expected Marion among \(anchors)")
        XCTAssertTrue(anchors.contains("Sophie"), "expected Sophie among \(anchors)")
    }

    // MARK: - German, the reason NLTagger was chosen over capitalised words

    /// German capitalises every noun. A capitalised-token heuristic proposes
    /// `Rechnung`, `Büro` and `Freitag` as names and refuses an ordinary German
    /// note; the tagger returns the person and nothing else. The #393 campaign
    /// measured no German at all, so this had to be safe by construction.
    func testAGermanListIsNotFlaggedForItsCapitalisedNouns() {
        let raw = "also ich muss noch die Rechnung für das Büro bezahlen bis Freitag und dann "
            + "muss ich Herrn Müller anrufen wegen dem Angebot und die Unterlagen vorbereiten"
        let output = """
        - Rechnung für das Büro bis Freitag bezahlen
        - Herrn Müller wegen dem Angebot anrufen
        - Unterlagen vorbereiten
        """
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(in: output, input: raw, languageCode: "de").map(\.text), []
        )
    }

    // MARK: - Normalisation

    func testMatchingIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(
                in: "- Appeler Léa demain", input: "il faut appeler LEA demain", languageCode: "fr"
            ).map(\.text),
            []
        )
    }

    /// The one inflection allowance: a NON-FINAL word of a MULTI-word anchor may
    /// carry one extra trailing letter in the input. German declension is what it is
    /// for — an output writing `Herr Müller` where the input said `Herrn Müller`.
    /// Deliberately too narrow to reopen the prefix hole below: a single-word anchor
    /// gets no allowance, and the surname must always match exactly.
    func testAnInflectedInputStillSupportsTheJoinedName() {
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(
                in: "- Herr Müller anrufen", input: "ich muss Herrn Müller anrufen", languageCode: "de"
            ).map(\.text),
            []
        )
    }

    /// Found in review. A fabricated name that happens to be a PREFIX of a real one
    /// is exactly the shape this check exists to catch, and the first version of the
    /// matching accepted it.
    /// Tested on the matching seam rather than end to end, because `NLTagger` does
    /// not fire on `Paul` in an ordinary French bullet — see `isGrounded(_:in:)`.
    /// A test routed through extraction would pass while asserting nothing.
    func testAPrefixOfARealNameIsNotGrounded() {
        XCTAssertFalse(PolishGrounding.isGrounded("Paul", in: "il faut rappeler Pauline avant jeudi"))
        XCTAssertTrue(PolishGrounding.isGrounded("Pauline", in: "il faut rappeler Pauline avant jeudi"))
        // And the other direction: a longer fabrication over a shorter real name.
        XCTAssertFalse(PolishGrounding.isGrounded("Pauline", in: "il faut rappeler Paul avant jeudi"))
    }

    /// The inflection allowance must not reach a single-word anchor, which is what
    /// made `Paul` / `Pauline` pass before.
    func testTheInflectionAllowanceDoesNotApplyToASingleWordName() {
        XCTAssertFalse(PolishGrounding.isGrounded("Marc", in: "il faut appeler Marco demain"))
        XCTAssertTrue(PolishGrounding.isGrounded("Herr Müller", in: "ich muss Herrn Müller anrufen"))
        // The surname is the part that identifies, so it never gets the allowance.
        XCTAssertFalse(PolishGrounding.isGrounded("Herr Mülle", in: "ich muss Herrn Müller anrufen"))
    }

    /// Found in review. The model can compose a person nobody named out of two who
    /// were, and matching each word independently accepted that. The words have to
    /// be contiguous and in order.
    func testANameAssembledFromTwoUnrelatedInputWordsIsNotGrounded() {
        let ungrounded = PolishGrounding.ungroundedAnchors(
            in: "- Envoyer le dossier à Alice Smith",
            input: "Alice s'occupe du dossier et le rapport de Smith arrive lundi",
            languageCode: "fr"
        )
        XCTAssertEqual(ungrounded.map(\.text), ["Alice Smith"])
    }

    /// The counter-test: the same two words, adjacent and in order, ARE the person
    /// the speaker named.
    func testTheSameNameIsGroundedWhenTheInputActuallyNamesThatPerson() {
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(
                in: "- Envoyer le dossier à Alice Smith",
                input: "il faut envoyer le dossier à Alice Smith avant lundi", languageCode: "fr"
            ).map(\.text),
            []
        )
    }

    /// Order matters, not just adjacency.
    func testTheWordsOfANameMustAppearInOrder() {
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(
                in: "- Appeler Alice Smith", input: "Smith Alice a rappelé hier", languageCode: "fr"
            ).map(\.text),
            ["Alice Smith"]
        )
    }

    /// Exact match, NOT a substring: `lea` is a substring of `release`, and
    /// accepting that would ground a fabricated Léa on any input mentioning a
    /// release.
    func testASubstringCoincidenceDoesNotGroundAName() {
        let ungrounded = PolishGrounding.ungroundedAnchors(
            in: "- Demander à Léa de valider", input: "il faut valider la release avant jeudi", languageCode: "fr"
        )
        XCTAssertEqual(ungrounded.map(\.text), ["Léa"])
    }

    // MARK: - Every uncertainty resolves toward accepting

    func testAnOutputWithNoNameIsGroundedVacuously() {
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(
                in: "- Acheter du pain\n- Payer le loyer", input: "acheter du pain et payer le loyer"
            ).map(\.text),
            []
        )
    }

    func testAnEmptyInputCannotUngroundAnything() {
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(in: "- Appeler Sophie", input: "").map(\.text), []
        )
    }

    /// MEASURED, device export of 2026-08-12 (#349). Apple FM refused and its
    /// apology was inserted as the user's dictation. DECLARED IN ADVANCE as a case
    /// this check cannot see: it carries no person, place or organisation, so there
    /// is nothing to compare. #349 needs the other query over this type — how much
    /// of the output's vocabulary appears in the input at all.
    func testARefusalCarryingNoNameIsInvisibleToThisCheckAndThatIsKnown() {
        let refusal = "Je suis désolé, mais je ne peux pas fournir une sortie polie pour ce texte. "
            + "Il semble contenir des mots ou une structure inappropriée pour une sortie acceptable."
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(
                in: refusal, input: "Chops chop cheats chop kickpapiti papu papati tsu pa t.",
                languageCode: "fr"
            ).map(\.text),
            []
        )
    }

    /// MEASURED LIVE on 2026-08-27, in the 30-call Notes run made to verify this
    /// very change. The Sophie fabrication reproduced with one clause reworded, and
    /// the check **accepted it**.
    ///
    /// `NLTagger` tags `Sophie` in `Appeler Sophie avant : elle a les données…` and
    /// does not tag it in `Appeler Sophie avant parce qu'elle a les données…` —
    /// same name, same position, same language, a different continuation. No
    /// framing recovers it: the tagger was run over the whole output, over each
    /// line with its marker, and over each line without, and none of the three
    /// finds it.
    ///
    /// This test asserts the MISS on purpose. #414's first acceptance criterion is
    /// not met, and a test that records the gap is worth more than a sentence in a
    /// report nobody re-reads. **When a future primitive closes it, this assertion
    /// flips — that is the signal, and it is the point of writing it down.**
    func testTheSameFabricationWithOneClauseRewordedIsMISSED() {
        let output = """
        - Récupérer les chiffres de janvier auprès de Marion
        - Appeler le prestataire pour validé le devis
        - Appeler Sophie avant parce qu'elle a les données de décembre
        """
        XCTAssertEqual(
            PolishGrounding.ungroundedAnchors(in: output, input: sophieRaw, languageCode: "fr").map(\.text),
            [],
            "if this now finds Sophie, #414's remaining gap has closed — update the issue and this test"
        )
    }

    // MARK: - Which contracts ask for it

    func testTheFaithfulContractsAskForGroundingAndTheReconstructingOnesDoNot() {
        XCTAssertTrue(PolishAcceptanceContract.natural.requiresGroundedNames)
        XCTAssertTrue(PolishAcceptanceContract.auto.requiresGroundedNames)
        // Repair substitutes words to reconstruct intent (ADR 0002), so a name it
        // rebuilds need not appear in the raw.
        XCTAssertFalse(PolishAcceptanceContract.repair.requiresGroundedNames)
    }

    func testNotesAsksForGroundingAndTranslationDoesNot() {
        XCTAssertTrue(SmartModeCatalogue.notes.contract.requiresGroundedNames)
        for language in SupportedLanguage.allCases {
            XCTAssertFalse(
                SmartModeCatalogue.translate(to: language).contract.requiresGroundedNames,
                "translation localises names, so the check is unsound for → \(language.rawValue)"
            )
        }
    }

    /// A contract crosses the App Group inside the per-dictation snapshot, and an
    /// app update can land between the write and the read. A record written by a
    /// build that predates this field must decode, and must decode to today's
    /// behaviour rather than to a brand-new rejection nobody measured.
    func testAContractWrittenBeforeThisFieldDecodesWithTheCheckOff() throws {
        let legacy = Data("""
        {"minimumLengthRatio":0.1,"maximumLengthRatio":2.0,"outputLanguage":"sameAsInput"}
        """.utf8)
        let decoded = try JSONDecoder().decode(PolishAcceptanceContract.self, from: legacy)
        XCTAssertFalse(decoded.requiresGroundedNames)
        XCTAssertEqual(decoded.outputLanguage, .sameAsInput)
    }

    func testTheFieldSurvivesARoundTrip() throws {
        let encoded = try JSONEncoder().encode(SmartModeCatalogue.notes.contract)
        let decoded = try JSONDecoder().decode(PolishAcceptanceContract.self, from: encoded)
        XCTAssertTrue(decoded.requiresGroundedNames)
    }
}
