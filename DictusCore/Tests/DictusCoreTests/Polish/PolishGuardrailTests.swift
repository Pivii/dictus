// DictusCore/Tests/DictusCoreTests/Polish/PolishGuardrailTests.swift
import XCTest
@testable import DictusCore

final class PolishGuardrailTests: XCTestCase {

    func testLightAcceptsIdenticalLength() {
        XCTAssertTrue(PolishGuardrail.accepts(raw: "hello world", polished: "hello world", mode: .natural))
    }

    func testLightAcceptsLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 50)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testLightAcceptsUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 200)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testLightRejectsBelowLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 49)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testLightRejectsAboveUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 201)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testRepairAcceptsLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 30)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testRepairAcceptsUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 300)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testRepairRejectsBelowLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 29)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testRepairRejectsAboveUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 301)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testEmptyRawAcceptsOnlyEmptyPolished() {
        XCTAssertTrue(PolishGuardrail.accepts(raw: "", polished: "", mode: .natural))
        XCTAssertTrue(PolishGuardrail.accepts(raw: "", polished: "", mode: .repair))
        XCTAssertFalse(PolishGuardrail.accepts(raw: "", polished: "x", mode: .natural))
        XCTAssertFalse(PolishGuardrail.accepts(raw: "", polished: "x", mode: .repair))
    }

    // MARK: - Language-match guardrail

    func testLanguageMatchAcceptsFrenchOutputForFrenchTarget() {
        let polished = "Bonjour, comment allez-vous aujourd’hui ? J’espère que tout va bien."
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .french))
    }

    func testLanguageMatchAcceptsEnglishOutputForEnglishTarget() {
        let polished = "Hello, how are you doing today? I hope everything is going well."
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .english))
    }

    /// The exact failure mode observed in production logs: target=fr, model
    /// emitted a chat reply in English. Must reject.
    func testLanguageMatchRejectsEnglishChatReplyForFrenchTarget() {
        let polished = "I'll ensure accurate transcription of the input despite the English words."
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .french))
    }

    func testLanguageMatchRejectsFrenchOutputForEnglishTarget() {
        let polished = "Bonjour, je vais bien aujourd’hui et j’espère que vous allez bien aussi."
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .english))
    }

    /// NLLanguageRecognizer is unreliable on very short outputs — pass them.
    func testLanguageMatchPassesShortOutputs() {
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "Hi.", target: .french))
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "Ok.", target: .english))
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "", target: .french))
    }

    // MARK: - Auto-mode language-match guardrail (#239)

    /// Auto mode ratio band mirrors Natural: light corrections only.
    func testAutoAcceptsNaturalBandAndRejectsOutside() {
        let raw = String(repeating: "a", count: 100)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 50), mode: .auto))
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 200), mode: .auto))
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 49), mode: .auto))
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 201), mode: .auto))
    }

    func testAutoLanguageMatchAcceptsSameLanguageAsInput() {
        let polished = "Allora domani andiamo al mare, se il tempo è bello. Ci vediamo alle nove."
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: "it"))
    }

    /// The #239 device failure mode: English speech, French keyboard, polish
    /// translated into French. With the input code as reference the translated
    /// output must be rejected.
    func testAutoLanguageMatchRejectsTranslationDrift() {
        let polished = "Salut, tu viens à la réunion demain matin ? Je crois qu’on commence à neuf heures."
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: "en"))
    }

    func testAutoLanguageMatchAcceptsChineseRoundTrip() {
        let polished = "我觉得我们明天再讨论这个问题吧，然后周五之前把版本发出去。"
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: "zh-Hans"))
    }

    func testAutoLanguageMatchPassesShortOutputs() {
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "Ok.", inputLanguageCode: "it"))
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "", inputLanguageCode: "en"))
    }

    // MARK: - Codable roundtrip

    /// Round-trip every Outcome through JSON. Required because the persistent
    /// `PolishMetricsRing` encodes events as JSON Lines on disk; a regression
    /// in Codable conformance would silently lose data on the next app launch.
    func testPolishMetricsRoundTripJSON() throws {
        let original = PolishMetrics(
            engine: "apple-fm",
            mode: "repair",
            targetLanguage: .french,
            detectedLanguage: "en",
            rawCharCount: 42,
            polishedCharCount: 48,
            latencyMs: 1234,
            outcome: .success
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)

        XCTAssertEqual(decoded.engine, original.engine)
        XCTAssertEqual(decoded.mode, original.mode)
        XCTAssertEqual(decoded.targetLanguage, original.targetLanguage)
        XCTAssertEqual(decoded.detectedLanguage, original.detectedLanguage)
        XCTAssertEqual(decoded.rawCharCount, original.rawCharCount)
        XCTAssertEqual(decoded.polishedCharCount, original.polishedCharCount)
        XCTAssertEqual(decoded.latencyMs, original.latencyMs)
        XCTAssertEqual(decoded.outcome, original.outcome)
    }

    /// nil mode (skipped events) and nil detectedLanguage (gibberish) must survive.
    func testPolishMetricsRoundTripJSONWithNilFields() throws {
        let original = PolishMetrics(
            engine: "passthrough",
            mode: nil,
            targetLanguage: .english,
            detectedLanguage: nil,
            rawCharCount: 0,
            polishedCharCount: 0,
            latencyMs: 0,
            outcome: .skipped
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)
        XCTAssertNil(decoded.mode)
        XCTAssertNil(decoded.detectedLanguage)
        XCTAssertEqual(decoded.outcome, .skipped)
    }

    /// The refusing check survives the ring (#466), and an event written before the
    /// field existed still decodes — which is the whole reason it is optional. The
    /// seven-day ring holds events from whatever build was installed at the time.
    func testPolishMetricsCarriesTheRefusingCheckAndToleratesItsAbsence() throws {
        let original = PolishMetrics(
            engine: "apple-fm", mode: "natural", targetLanguage: .french,
            detectedLanguage: "fr", rawCharCount: 177, polishedCharCount: 283,
            latencyMs: 3900, outcome: .rejectedGuardrail, guardrailCheck: .prefixAlignment
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(
            try JSONDecoder().decode(PolishMetrics.self, from: data).guardrailCheck,
            .prefixAlignment
        )
        XCTAssertTrue(
            String(data: data, encoding: .utf8)?.contains("\"prefixAlignment\"") == true,
            "the slug is a wire value and must encode as a bare string"
        )

        let legacy = Data("""
        {"engine":"apple-fm","mode":"natural","targetLanguage":"fr","detectedLanguage":"fr",
         "rawCharCount":177,"polishedCharCount":283,"latencyMs":3900,"outcome":"rejectedGuardrail"}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(PolishMetrics.self, from: legacy).guardrailCheck)
    }

    /// The contract answers the order question itself (#466), and a record written
    /// by a build that predates the field decodes to the safe half — off, so one
    /// dictation across one upgrade behaves exactly as it does today rather than
    /// meeting a brand-new rejection nobody measured.
    func testPreservesOrderIsAnsweredPerTaskAndDefaultsOffWhenAbsent() throws {
        XCTAssertTrue(PolishAcceptanceContract.natural.preservesOrder)
        XCTAssertTrue(PolishAcceptanceContract.auto.preservesOrder)
        XCTAssertTrue(PolishAcceptanceContract.repair.preservesOrder)
        XCTAssertFalse(SmartModeCatalogue.notes.contract.preservesOrder)
        XCTAssertFalse(SmartModeCatalogue.translate(to: .english).contract.preservesOrder)

        let legacy = Data("""
        {"minimumLengthRatio":0.5,"maximumLengthRatio":2.0,"outputLanguage":"polishTarget"}
        """.utf8)
        let decoded = try JSONDecoder().decode(PolishAcceptanceContract.self, from: legacy)
        XCTAssertFalse(decoded.preservesOrder)
        XCTAssertFalse(decoded.requiresGroundedNames)
    }

    // MARK: - Per-mode acceptance contracts (#79)

    /// The reason the band had to stop being a table keyed by mode: a good
    /// three-bullet synthesis of a long dictation is far below the ADR 0003 floor,
    /// and the faithful-polish contract rejects it by construction.
    func testNotesAcceptsACondensationTheNaturalBandRejects() {
        let raw = String(repeating: "a", count: 400)
        let condensed = String(repeating: "a", count: 60)   // ratio 0.15
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: condensed, mode: .natural))
        XCTAssertTrue(PolishGuardrail.accepts(
            raw: raw, polished: condensed, contract: SmartModeCatalogue.notes.contract
        ))
    }

    /// Widening the floor is not removing it: an empty or near-empty answer is still
    /// a failure, not a synthesis.
    func testNotesStillRejectsARunawayOrACollapse() {
        let raw = String(repeating: "a", count: 400)
        let contract = SmartModeCatalogue.notes.contract
        XCTAssertFalse(PolishGuardrail.accepts(
            raw: raw, polished: String(repeating: "a", count: 5), contract: contract
        ))
        XCTAssertFalse(PolishGuardrail.accepts(
            raw: raw, polished: String(repeating: "a", count: 1_000), contract: contract
        ))
    }

    /// Translation changes length by a lot in either direction, so the band is wide
    /// — the check that guards this mode is the language one.
    func testTranslationAcceptsALargeLengthSwing() {
        let raw = String(repeating: "a", count: 100)
        let contract = SmartModeCatalogue.translate(to: .german).contract
        XCTAssertTrue(PolishGuardrail.accepts(
            raw: raw, polished: String(repeating: "a", count: 250), contract: contract
        ))
        XCTAssertTrue(PolishGuardrail.accepts(
            raw: raw, polished: String(repeating: "a", count: 45), contract: contract
        ))
    }

    func testAnEmptyRawStillOnlyAcceptsAnEmptyOutputWhateverTheContract() {
        XCTAssertTrue(PolishGuardrail.accepts(
            raw: "", polished: "", contract: SmartModeCatalogue.notes.contract
        ))
        XCTAssertFalse(PolishGuardrail.accepts(
            raw: "", polished: "x", contract: SmartModeCatalogue.notes.contract
        ))
    }

    /// The free-polish convenience must keep reporting the ADR 0003 bands exactly.
    func testTheModeConvenienceStillReportsTheHistoricalBands() {
        XCTAssertEqual(PolishTask.natural.contract.lengthBand, 0.5...2.0)
        XCTAssertEqual(PolishTask.repair.contract.lengthBand, 0.3...3.0)
        XCTAssertEqual(PolishTask.auto.contract.lengthBand, 0.5...2.0)
    }

    // MARK: - The bilingual output the dominant-language check could not see (#413)

    /// MEASURED, `round1-notes-show-5runs.txt`, N3 run 3, recorded as a
    /// **success** — this text would have been inserted. Five English bullets and
    /// one French one, on a French dictation.
    private let bilingualDrift = """
    - Design: maquettes validées vendredi
    - Development: two-week delay due to API issues
    - Delivery: potential delay to March 15
    - Budget: 8000 euros remaining, 3000 euros from February licenses
    - Thomas: three-week vacation starting March 20
    - Payment: need to be completed before March 20
    """

    /// MEASURED, same fixture, run 2. One bullet fewer, and it was correctly
    /// rejected. The two landed on opposite sides of the check on a one-bullet
    /// difference, which is the whole of #413.
    private let englishDrift = """
    - Design: maquettes validées vendredi
    - Development: two weeks delay due to API issues
    - Delivery: potential delay to March 15
    - Budget: 8000 euros remaining, 3000 euros due to licenses in February
    - Thomas: three weeks of vacation starting March 20
    """

    /// MEASURED, same fixture, run 4. A sound French synthesis of the same input.
    private let goodFrenchList = """
    - Côté design, les maquettes ont été validées vendredi
    - Le dev a pris deux semaines de retard à cause de l'API du prestataire
    - On envisage de décaler la livraison au 15 mars
    - Le budget est à peu près dans les clous, il reste 8000 euros
    - Il faut compter les licences de février, ce qui ajoute 3000 euros
    - Thomas part en congé trois semaines à partir du 20
    - La partie paiement doit être bouclée avant le 20 pour respecter la date
    """

    /// The regression test #413 asks for by name.
    func testTheFiveEnglishBulletsPlusOneFrenchOutputIsNowRejected() {
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(
            polished: bilingualDrift, inputLanguageCode: "fr"
        ))
    }

    /// Pins WHY it used to pass, so a future reader can see the regression test is
    /// testing the thing it claims to. Read as one blob this text is French: the
    /// single French bullet, the proper nouns and "euros" carry the aggregate.
    func testTheSameOutputStillReadsAsFrenchWhenTakenAsOneBlob() {
        let asOneParagraph = bilingualDrift.replacingOccurrences(of: "\n", with: " ")
        XCTAssertEqual(PolishPipeline.detectLanguageCode(in: asOneParagraph), "fr")
    }

    /// The output that was already rejected must stay rejected.
    func testTheWhollyEnglishDriftIsStillRejected() {
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(
            polished: englishDrift, inputLanguageCode: "fr"
        ))
    }

    /// The counter-test that matters just as much.
    func testASoundFrenchListIsStillAccepted() {
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(
            polished: goodFrenchList, inputLanguageCode: "fr"
        ))
    }

    /// #413's second acceptance criterion. Every bullet is French; several would
    /// read as English to a per-word heuristic, and one of them —
    /// `Checker le build sur GitHub Actions` — is the worst legitimate misreading
    /// in the whole measured corpus, at **en 0.504**. The 0.85 floor is sized so
    /// this passes with room.
    func testAFrenchListQuotingEnglishTechnicalTermsIsAccepted() {
        let output = """
        - Merger la PR avant le standup
        - Checker le build sur GitHub Actions
        - Le deploy d'hier a fail
        - Rollback de la feature flag sur staging
        """
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: output, inputLanguageCode: "fr"))
    }

    /// An English list carrying French proper nouns is the mirror case: the names
    /// must not read as a language switch.
    func testAnEnglishListCarryingFrenchProperNounsIsAccepted() {
        let output = """
        - Send the deck to Bouygues before Friday
        - Follow up with Aurélie about the Créteil site
        - Book the flight
        """
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: output, inputLanguageCode: "en"))
    }

    /// Below the minimum a segment is not evidence of anything, so it passes
    /// untested. `Thomas` alone reads as English at 0.164 on a French list.
    func testSegmentsTooShortToReadPassUntested() {
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(
            polished: "- Marion\n- Thomas\n- Sophie\n- Léa\n- Karim", inputLanguageCode: "fr"
        ))
    }

    /// #413's fourth acceptance criterion: free polish returns one continuous
    /// passage, which has a single segment, so the per-segment pass cannot fire on
    /// it in either direction.
    func testFreePolishSinglePassageBehaviourIsUnchanged() {
        let french = "Salut, je voulais te dire que le rendez-vous de mardi est décalé à jeudi, "
            + "même heure, même endroit. Tu me confirmes ?"
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: french, target: .french))
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: french, target: .english))
        // The Apple FM chat reply this guardrail was written for, which has no
        // segment structure at all: the whole-output pass is what still catches it.
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(
            polished: "Sure, I'll polish that text for you right away.", target: .french
        ))
    }

    /// The floor exists to stop the check acting on noise, and #413 records that a
    /// floor alone was never the fix: 0.789 was a CONFIDENT wrong answer on the
    /// whole blob. Raising it far enough to catch that would reject good output.
    func testRaisingTheFloorToOneDisablesTheSegmentPassWithoutTouchingTheBlobPass() {
        let never = PolishLanguageSegmentThresholds(minimumSegmentCharacters: 12, confidenceFloor: 1.1)
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(
            polished: bilingualDrift, inputLanguageCode: "fr", thresholds: never
        ))
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(
            polished: englishDrift, inputLanguageCode: "fr", thresholds: never
        ))
    }
}
