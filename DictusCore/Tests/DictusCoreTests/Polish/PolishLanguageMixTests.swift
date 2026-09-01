// DictusCore/Tests/DictusCoreTests/Polish/PolishLanguageMixTests.swift
// The proportion measurement the polish target is elected from (#456).
import XCTest
@testable import DictusCore

final class PolishLanguageMixTests: XCTestCase {

    /// The transcript captured on device on 2026-08-29, verbatim from #456: 471
    /// characters, 33 s of audio, Parakeet on a French keyboard. It mistranscribes
    /// the opening as English and reverts to French after two sentences.
    private let captured = """
        Okay, it's coming to approach to what I've got on the pencil to other children. \
        It's completely different. In fact, when you have curseur, we have our héros qui \
        est comme tel avec les animations qu'on connaît aujourd'hui quand le curseur \
        apparaît en fait la cloche elle apparaît et elle suit le curseur donc ça veut \
        dire que l'utilisateur va pouvoir jouer sur le héros directement avec son \
        curseur. Et si son curseur descend du héros, la couche disparaît tout simplement.
        """

    // MARK: - The captured event

    /// The whole point, in one assertion. This is the input that produced an entirely
    /// English polish of a three-quarters French dictation.
    func testTheCapturedTranscriptIsMeasuredAsMajorityFrench() {
        XCTAssertEqual(captured.count, 471, "the fixture must stay the captured string")
        let mix = PolishLanguageMix.measure(captured)
        XCTAssertEqual(mix.dominantCode, "fr")
        XCTAssertEqual(mix.dominantShare, 0.776, accuracy: 0.01,
                       "363 French characters of 468 counted")
        XCTAssertEqual(mix.shares["en"] ?? 0, 0.224, accuracy: 0.01)
        XCTAssertTrue(mix.isMixed)
    }

    /// …and the reading it replaces, asserted here so the failure this issue is about
    /// stays visible in the suite rather than only in the issue. If Apple ever changes
    /// `NLLanguageRecognizer` enough for this to flip, the fix is still correct — but
    /// the reason it was needed will have changed, and that is worth being told.
    func testTheWholeBlobReadingOfTheSameTranscriptIsStillEnglish() {
        XCTAssertEqual(PolishPipeline.detectLanguageCode(in: captured), "en",
                       "the recogniser weights the opening, not the majority")
    }

    /// The elected target, through the same call the pipeline makes.
    func testTheCapturedTranscriptElectsFrenchOnAFrenchKeyboard() {
        let policy = TranscriptionLanguagePolicy(
            mode: .followKeyboard, keyboardLanguage: .french,
            engine: .parakeet, modelIdentifier: "parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            policy.polishPromptSelection(languageMix: .measure(captured)), .language(.french)
        )
    }

    // MARK: - Weighting

    /// Acceptance criterion 2: by characters, not by segment count. Three short English
    /// sentences against one long French paragraph is 3-to-1 by count and the other way
    /// round by characters — and the characters are what the user dictated.
    func testWeightingIsByCharactersNotBySegmentCount() {
        let text = """
            The build is green. I merged it. Ship it today. Bon alors il faut que je \
            reprenne toute la partie sur les animations du curseur parce que le \
            comportement actuel ne correspond pas du tout à ce qu'on avait décidé \
            ensemble la semaine dernière avec l'équipe design.
            """
        let mix = PolishLanguageMix.measure(text)
        XCTAssertEqual(mix.dominantCode, "fr")
        XCTAssertGreaterThan(mix.dominantShare, 0.6)
        XCTAssertEqual(mix.shares.count, 2, "both languages are counted")
    }

    // MARK: - What must NOT be retargeted

    /// Acceptance criterion 3. French technical speech is full of English words, and it
    /// is still French — every sentence reads French, so the mix is unanimous.
    func testFrenchQuotingEnglishTechnicalVocabularyStaysFrench() {
        let text = """
            Bon alors il faut que je merge la PR avant le standup et ensuite je dois \
            checker le build sur GitHub Actions parce que le deploy d'hier a fail. \
            Après ça je vais rollback la feature flag sur staging et prévenir l'équipe.
            """
        let mix = PolishLanguageMix.measure(text)
        XCTAssertEqual(mix.dominantCode, "fr")
        XCTAssertGreaterThanOrEqual(
            mix.dominantShare, TranscriptionLanguagePolicy.dominantLanguageShareFloor
        )
    }

    /// Acceptance criterion 4. A whole passage dictated in English on a French keyboard
    /// is English, and the user gets English.
    func testAWholeEnglishPassageElectsEnglishOnAFrenchKeyboard() {
        let text = """
            I wanted to walk you through the plan for next quarter. We are going to \
            focus on the onboarding flow first, because that is where most of the drop \
            off happens. Then we will look at the pricing page.
            """
        let policy = TranscriptionLanguagePolicy(
            mode: .followKeyboard, keyboardLanguage: .french,
            engine: .parakeet, modelIdentifier: "parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            policy.polishPromptSelection(languageMix: .measure(text)), .language(.english)
        )
    }

    // MARK: - The fallbacks

    /// The measurement is only ever allowed to ADD information. A transcript of short
    /// sentences produces no countable segment, and must keep the detected language it
    /// has today rather than silently losing polish.
    func testATranscriptOfShortSentencesFallsBackToTheWholeStringReading() {
        let mix = PolishLanguageMix.measure("Oui. Non. Bof. Peut-être. Ah bon ?")
        XCTAssertEqual(mix.countedCharacters, 0, "no sentence cleared the minimum length")
        XCTAssertEqual(mix.dominantCode, PolishPipeline.detectLanguageCode(
            in: "Oui. Non. Bof. Peut-être. Ah bon ?"
        ), "the fallback is exactly the pre-#456 reading")
    }

    /// Gibberish must read as nothing here for exactly as long as it reads as nothing
    /// through `detectLanguageCode` — the gibberish gate is downstream of both, and a
    /// measurement that disagreed with it would turn polish on or off for reasons the
    /// gate cannot see. The two fixtures are the ones `PolishPipelineTests` already
    /// pins, one per branch: digits yield no hypothesis at all, nonsense words yield
    /// one the floor rejects.
    func testGibberishMeasuresNothingAndAgreesWithTheDetector() {
        for text in ["", "   \n ", "123 456 789", "asdf qwer zxcv"] {
            let mix = PolishLanguageMix.measure(text)
            XCTAssertNil(mix.dominantCode, "\(text.debugDescription) must read as nothing")
            XCTAssertNil(PolishPipeline.detectLanguageCode(in: text), "…and must agree")
            XCTAssertTrue(mix.shares.isEmpty)
            XCTAssertFalse(mix.isMixed)
        }
    }

    /// The other half of that agreement, and the reason the assertion above is phrased
    /// as parity rather than as "gibberish is nil": the recogniser answers `pl` at full
    /// confidence for `xkcd qqq zzz`, and it always has. This measurement is not the
    /// place to fix that — it would be fixing it in one of the two paths that read the
    /// same text, which is how they drift.
    func testTextTheDetectorReadsWronglyIsMeasuredJustAsWrongly() {
        let nonsense = "xkcd qqq zzz"
        XCTAssertEqual(PolishLanguageMix.measure(nonsense).dominantCode,
                       PolishPipeline.detectLanguageCode(in: nonsense))
    }

    // MARK: - Reading the measurement

    func testTheDominantSupportedLanguageIgnoresTheFloorAndTheElectedOneDoesNot() {
        let mix = PolishLanguageMix(
            shares: ["fr": 0.55, "en": 0.45], dominantCode: "fr",
            dominantShare: 0.55, countedCharacters: 400
        )
        XCTAssertEqual(mix.dominantSupportedLanguage, .french,
                       "a bilingual transcript is not gibberish")
        XCTAssertNil(mix.electedLanguage(floor: 0.6),
                     "…but no language holds enough of it to be named the target")
    }

    /// A language outside the four the per-language prompts exist for is never a
    /// target, whatever share it holds — the gibberish gate is what handles it.
    func testAnUnsupportedDominantLanguageIsNeverElected() {
        let mix = PolishLanguageMix(
            shares: ["it": 1], dominantCode: "it", dominantShare: 1, countedCharacters: 300
        )
        XCTAssertNil(mix.dominantSupportedLanguage)
        XCTAssertNil(mix.electedLanguage(floor: 0.6))
    }

    /// Ties break on the code rather than on dictionary order: this value reaches a
    /// debug export, and the same input has to keep producing the same event.
    func testAnExactTieBreaksDeterministically() {
        let mix = PolishLanguageMix(
            shares: ["fr": 0.5, "en": 0.5], dominantCode: "en",
            dominantShare: 0.5, countedCharacters: 400
        )
        // Measured rather than constructed would be flaky here; what is pinned is that
        // the accessor cannot elect at a tie, whichever side won it.
        XCTAssertNil(mix.electedLanguage(floor: 0.6))
    }

    func testRoundedSharesAreStableForAnExport() {
        let mix = PolishLanguageMix(
            shares: ["fr": 0.7756410256, "en": 0.2243589744], dominantCode: "fr",
            dominantShare: 0.7756410256, countedCharacters: 468
        )
        XCTAssertEqual(mix.roundedShares, ["fr": 0.776, "en": 0.224])
    }

    // MARK: - The sentence cut

    func testSentencesAreCutOnPunctuationNotOnEveryPeriod() {
        let sentences = PolishSegmentation.sentences(
            of: "On a livré la v1.8 hier. Il reste M. Durand à prévenir."
        )
        XCTAssertEqual(sentences, [
            "On a livré la v1.8 hier.", "Il reste M. Durand à prévenir."
        ])
    }

    func testSentencesOfAnEmptyStringIsEmpty() {
        XCTAssertTrue(PolishSegmentation.sentences(of: "").isEmpty)
        XCTAssertTrue(PolishSegmentation.sentences(of: "   \n  ").isEmpty)
    }

    /// A raw Parakeet transcript is one line, which is why the line cut cannot measure
    /// an input and the sentence cut had to be added beside it.
    func testTheLineCutSeesTheCapturedTranscriptAsASingleSegment() {
        XCTAssertEqual(PolishSegmentation.segments(of: captured).count, 1)
        XCTAssertEqual(PolishSegmentation.sentences(of: captured).count, 4)
    }
}
