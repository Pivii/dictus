// DictusCore/Tests/DictusCoreTests/Polish/PolishPipelineTests.swift
import XCTest
@testable import DictusCore

/// Deterministic coverage of the shared transform using the Passthrough engine
/// (returns its input unchanged) — no Apple FM, so it's stable and runnable
/// anywhere. The Apple-FM behaviour is covered separately by the eval harness.
final class PolishPipelineTests: XCTestCase {

    // MARK: - transform()

    func testTransformPassthroughSucceedsAndReturnsInput() async {
        let input = "this is a perfectly normal english sentence about testing things"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            job: PolishJob(task: .natural, promptLanguage: .english, languageAgnosticPath: false)
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    func testTransformPreservesNewlinesThroughMarkerRoundTrip() async {
        // The transform encodes `\n` to the marker before the engine and decodes
        // it after. Passthrough returns the marker verbatim → newline restored.
        let input = "first line here\nsecond line here\nthird line here"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            job: PolishJob(task: .natural, promptLanguage: .english, languageAgnosticPath: false)
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
        XCTAssertTrue(result.engineOutput?.contains("\n") == true)
    }

    // MARK: - resolvedOutput()  (#185)

    /// On success the user gets the engine output verbatim.
    func testResolvedOutputReturnsEngineOutputOnSuccess() {
        let result = PolishPipeline.Result(
            engineOutput: "Ok, petit test.", outcome: .success, engineMs: 5, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "ignored", job: PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false))
        XCTAssertEqual(out, "Ok, petit test.")
    }

    /// On a non-success outcome the user gets the deterministic floor (decoded
    /// pre-pass), NOT the literal raw — the verbal-punctuation work survives an
    /// engine failure. Here the pre-pass already turned "virgule" into ",".
    func testResolvedOutputFallsBackToPreprocessedOnEngineFailed() {
        let preprocessed = "Ok, petit test."
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .engineFailed, engineMs: 600, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: preprocessed, job: PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false))
        XCTAssertEqual(out, preprocessed)
        XCTAssertFalse(out?.contains("virgule") ?? true)
    }

    /// A guardrail rejection discards the engine output and also falls back to
    /// the deterministic floor rather than the raw.
    func testResolvedOutputFallsBackToPreprocessedOnGuardrailReject() {
        let preprocessed = "Bonjour Pierre."
        let result = PolishPipeline.Result(
            engineOutput: "something the guardrail rejected", outcome: .rejectedGuardrail, engineMs: 700, postprocessMs: 1
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: preprocessed, job: PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false))
        XCTAssertEqual(out, preprocessed)
    }

    /// The floor still applies French typography (NBSP before `?`) on fallback,
    /// proving it routes through `decodeFromEngine`, not a bare passthrough.
    func testResolvedOutputAppliesTypographyOnFallback() {
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .cancelled, engineMs: 0, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "ça va ?", job: PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false))
        XCTAssertEqual(out, "ça va\u{00A0}?")
    }

    // MARK: - Smart Modes: fail closed (#79)

    /// The rule the whole feature hangs on: **a Smart Mode must never silently
    /// insert untransformed text.** For polish the floor is a slightly less tidy
    /// version of what was asked for; for a mode it is the opposite of it.
    func testASmartModeResolvesToNothingOnEveryNonSuccess() {
        let outcomes: [PolishMetrics.Outcome] = [
            .engineFailed, .rejectedGuardrail, .cancelled,
            .exceededContextBudget, .engineUnavailable
        ]
        let job = PolishJob(
            task: .smart(SmartModeCatalogue.translate(to: .english)),
            promptLanguage: .french,
            languageAgnosticPath: false
        )
        for outcome in outcomes {
            let result = PolishPipeline.Result(
                engineOutput: "bonjour tout le monde", outcome: outcome,
                engineMs: 10, postprocessMs: 0
            )
            XCTAssertNil(
                PolishPipeline.resolvedOutput(result, preprocessed: "bonjour", job: job),
                "\(outcome.rawValue) should insert nothing"
            )
        }
    }

    func testASmartModeStillReturnsItsOutputOnSuccess() {
        let job = PolishJob(
            task: .smart(SmartModeCatalogue.notes), promptLanguage: .french,
            languageAgnosticPath: false
        )
        let result = PolishPipeline.Result(
            engineOutput: "- premier point", outcome: .success, engineMs: 10, postprocessMs: 0
        )
        XCTAssertEqual(
            PolishPipeline.resolvedOutput(result, preprocessed: "euh premier point", job: job),
            "- premier point"
        )
    }

    // MARK: - Smart Modes: the language contract

    /// For translation the language check flips from obstacle to asset — it is what
    /// catches the model forgetting to translate.
    func testTranslationIsRejectedWhenTheOutputStayedInTheInputLanguage() async {
        let french = "bonjour, comment ça va aujourd'hui, j'espère que tu vas bien"
        let result = await PolishPipeline.transform(
            preprocessed: "hello, how are you doing today, i hope you are doing well",
            engine: FixedOutputEngine(output: french),
            job: PolishJob(
                task: .smart(SmartModeCatalogue.translate(to: .english)),
                promptLanguage: .english,
                languageAgnosticPath: false
            )
        )
        XCTAssertEqual(result.outcome, .rejectedGuardrail)
    }

    func testTranslationIsAcceptedWhenTheOutputIsInTheTarget() async {
        let english = "hello, how are you doing today, i hope everything is going well"
        let result = await PolishPipeline.transform(
            preprocessed: "bonjour, comment ça va aujourd'hui, j'espère que tout va bien",
            engine: FixedOutputEngine(output: english),
            job: PolishJob(
                task: .smart(SmartModeCatalogue.translate(to: .english)),
                promptLanguage: .french,
                languageAgnosticPath: false
            )
        )
        XCTAssertEqual(result.outcome, .success)
    }

    /// A mode that keeps the speaker's language uses the never-translate check
    /// written for auto mode in #239, reused as-is.
    func testNotesIsRejectedWhenTheOutputChangedLanguage() async {
        let english = "- we should ship it tomorrow morning without waiting any longer"
        let result = await PolishPipeline.transform(
            preprocessed: "faut qu'on livre ça demain matin sans attendre plus longtemps",
            engine: FixedOutputEngine(output: english),
            job: PolishJob(
                task: .smart(SmartModeCatalogue.notes),
                promptLanguage: .french,
                languageAgnosticPath: false
            )
        )
        XCTAssertEqual(result.outcome, .rejectedGuardrail)
    }

    // MARK: - The two holes #393 found, end to end (#413, #414)

    /// The measured #413 case, through the whole pipeline: the guardrail must
    /// refuse it, and a Smart Mode refusing means NOTHING is inserted.
    func testABilingualListIsRefusedAndTheModeInsertsNothing() async {
        let raw = "alors euh je fais le point général donc côté design c'est bon les maquettes ont "
            + "été validées vendredi par contre le dev a pris deux semaines de retard à cause de "
            + "l'API du prestataire et on décale la livraison au 15 mars"
        let drift = """
        - Design: maquettes validées vendredi
        - Development: two-week delay due to API issues
        - Delivery: potential delay to March 15
        - Budget: 8000 euros remaining, 3000 euros from February licenses
        """
        let job = PolishJob(
            task: .smart(SmartModeCatalogue.notes), promptLanguage: .french, languageAgnosticPath: false
        )
        let result = await PolishPipeline.transform(
            preprocessed: raw, engine: FixedOutputEngine(output: drift), job: job
        )
        XCTAssertEqual(result.outcome, .rejectedGuardrail)
        XCTAssertNil(PolishPipeline.resolvedOutput(result, preprocessed: raw, job: job))
    }

    /// The measured #414 case, through the whole pipeline. The last bullet is the
    /// worked example inside `SmartModeNotesPrompt`, on a dictation naming neither
    /// Sophie nor December.
    func testAFabricatedNameIsRefusedAndTheModeInsertsNothing() async {
        let raw = "bon alors euh je récapitule ce qu'il faut que je fasse avant la réunion donc "
            + "déjà faut que je récupère les chiffres de janvier auprès de Marion et puis il faut "
            + "que j'appelle le prestataire et réserver la salle du deuxième étage"
        let output = """
        - Récupérer les chiffres de janvier auprès de Marion
        - Appeler le prestataire
        - Réserver la salle du deuxième étage
        - Appeler Sophie avant : elle a les données de décembre
        """
        let job = PolishJob(
            task: .smart(SmartModeCatalogue.notes), promptLanguage: .french, languageAgnosticPath: false
        )
        let result = await PolishPipeline.transform(
            preprocessed: raw, engine: FixedOutputEngine(output: output), job: job
        )
        XCTAssertEqual(result.outcome, .rejectedGuardrail)
        XCTAssertNil(PolishPipeline.resolvedOutput(result, preprocessed: raw, job: job))
    }

    /// The counter-test that matters just as much: the same fixture, condensed
    /// faithfully, still reaches the document.
    func testAGroundedFrenchListIsStillAccepted() async {
        let raw = "bon alors euh je récapitule ce qu'il faut que je fasse avant la réunion donc "
            + "déjà faut que je récupère les chiffres de janvier auprès de Marion et puis il faut "
            + "que j'appelle le prestataire et réserver la salle du deuxième étage"
        let output = """
        - Récupérer les chiffres de janvier auprès de Marion
        - Appeler le prestataire
        - Réserver la salle du deuxième étage
        """
        let result = await PolishPipeline.transform(
            preprocessed: raw,
            engine: FixedOutputEngine(output: output),
            job: PolishJob(task: .smart(SmartModeCatalogue.notes),
                           promptLanguage: .french, languageAgnosticPath: false)
        )
        XCTAssertEqual(result.outcome, .success)
    }

    /// A translation legitimately localises a name, so the grounding check must not
    /// run on it. `Londres` -> `London` appears in no input; refusing it would be
    /// refusing a correct translation.
    func testATranslationThatLocalisesANameIsNotRefusedForGrounding() async {
        let result = await PolishPipeline.transform(
            preprocessed: "je pars à Londres lundi prochain pour trois jours",
            engine: FixedOutputEngine(output: "I am going to London next Monday for three days"),
            job: PolishJob(task: .smart(SmartModeCatalogue.translate(to: .english)),
                           promptLanguage: .french, languageAgnosticPath: false)
        )
        XCTAssertEqual(result.outcome, .success)
    }

    /// Repair reconstructs words to rebuild intent (ADR 0002), so a name it rebuilds
    /// need not appear in the raw. #349 is the reason this exclusion is deliberate
    /// rather than an oversight.
    func testRepairIsNotRefusedForAReconstructedName() async {
        let result = await PolishPipeline.transform(
            preprocessed: "je dois rappeler Mario un demain matin avant la réunion",
            engine: FixedOutputEngine(output: "Je dois rappeler Marion demain matin avant la réunion."),
            job: PolishJob(task: .repair, promptLanguage: .french, languageAgnosticPath: false)
        )
        XCTAssertEqual(result.outcome, .success)
    }

    /// The typography post-pass keys on the OUTPUT language, which for a translation
    /// is the target — here French NBSP applied to output produced from English.
    func testTranslationAppliesTheTargetsTypographyNotTheInputs() async {
        let result = await PolishPipeline.transform(
            preprocessed: "how are you doing today my friend",
            engine: FixedOutputEngine(output: "comment ça va aujourd'hui mon ami ?"),
            job: PolishJob(
                task: .smart(SmartModeCatalogue.translate(to: .french)),
                promptLanguage: .english,
                languageAgnosticPath: false
            )
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, "comment ça va aujourd'hui mon ami\u{00A0}?")
    }

    // MARK: - detectLanguage()

    func testDetectLanguageReturnsNilForEmpty() {
        XCTAssertNil(PolishPipeline.detectLanguage(in: "   \n  "))
    }

    func testDetectLanguageRecognisesFrench() {
        let lang = PolishPipeline.detectLanguage(
            in: "bonjour, comment ça va aujourd'hui, j'espère que tu vas bien"
        )
        XCTAssertEqual(lang, .french)
    }

    // MARK: - mode()

    func testModeWhisperAlwaysNatural() {
        XCTAssertEqual(PolishPipeline.mode(sttEngine: .whisperKit, detected: .english, target: .french), .natural)
    }

    func testModeParakeetNaturalWhenMatched() {
        XCTAssertEqual(PolishPipeline.mode(sttEngine: .parakeet, detected: .french, target: .french), .natural)
    }

    func testModeParakeetRepairWhenMismatched() {
        XCTAssertEqual(PolishPipeline.mode(sttEngine: .parakeet, detected: .english, target: .french), .repair)
    }

    // MARK: - Auto mode (#239)

    /// Auto mode must detect languages outside the four supported ones —
    /// that's the whole point of `detectLanguageCode` vs `detectLanguage`.
    func testDetectLanguageCodeRecognisesUnsupportedLanguages() {
        let zh = PolishPipeline.detectLanguageCode(
            in: "我觉得我们明天再讨论这个问题吧然后周五之前把版本发出去"
        )
        XCTAssertEqual(zh, "zh-Hans")
        let it = PolishPipeline.detectLanguageCode(
            in: "allora ho parlato con Marco ieri sera e mi ha detto che il progetto va bene"
        )
        XCTAssertEqual(it, "it")
    }

    func testDetectLanguageCodeReturnsNilForEmpty() {
        XCTAssertNil(PolishPipeline.detectLanguageCode(in: "   \n  "))
    }

    /// `detectLanguage` keeps its historical contract on top of the code-level
    /// detection: unsupported languages resolve to nil.
    func testDetectLanguageReturnsNilForUnsupportedLanguage() {
        XCTAssertNil(PolishPipeline.detectLanguage(
            in: "allora ho parlato con Marco ieri sera e mi ha detto che il progetto va bene"
        ))
    }

    /// The detection pairing the per-language skip exit relies on (#332): an
    /// unsupported language yields a code but no `SupportedLanguage`, while
    /// text that cannot be read yields neither. Both skip polish, and the
    /// coordinator records `detectedLanguage: detectedCode` at that exit so
    /// the two stay distinguishable on the event — "you dictated Italian, and
    /// this path has no Italian prompt" is not "we could not read this".
    ///
    /// SCOPE: this asserts the detection pairing only. That the skip exit
    /// actually writes the code onto the event is NOT covered — it lives in
    /// `PolishCoordinator` (DictusApp), and the project has no app test
    /// bundle, so DictusCore is the only suite that exists. That half is a
    /// manual check: a sub-2s dictation should produce a `skippedShort` event
    /// carrying a detected language.
    ///
    /// Both undetectable cases below are non-empty on purpose, so they reach
    /// the recognizer rather than the empty-input guard covered above, and
    /// they exercise different branches of it: digits produce no hypothesis at
    /// all, while nonsense words produce one the threshold then rejects
    /// (measured 0.27 against a 0.5 threshold — a fixture nearer the boundary,
    /// e.g. "xyz" at 0.46, would be one NL revision from flipping).
    func testDetectionSeparatesUnsupportedLanguageFromUnreadableText() {
        let italian = "allora ho parlato con Marco ieri sera e mi ha detto che il progetto va bene"
        XCTAssertEqual(PolishPipeline.detectLanguageCode(in: italian), "it",
                       "an unsupported language must still yield its code")
        XCTAssertNil(PolishPipeline.detectLanguage(in: italian),
                     "…while resolving to no SupportedLanguage")

        for unreadable in ["123 456 789", "asdf qwer zxcv"] {
            XCTAssertNil(PolishPipeline.detectLanguageCode(in: unreadable),
                         "no confident language in \(unreadable)")
            XCTAssertNil(PolishPipeline.detectLanguage(in: unreadable))
        }
    }

    /// In auto mode the target-language typography must NOT run: a French
    /// input with `target: .french` as engine placeholder keeps its ASCII
    /// space before `?` (no NBSP) — the prompt owns typography in auto mode.
    func testTransformAutoSkipsLanguageTypography() async {
        let input = "bonjour comment ça va aujourd'hui, j'espère que tu vas bien ?"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            job: PolishJob(task: .auto, promptLanguage: .french, languageAgnosticPath: true)
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
        XCTAssertFalse(result.engineOutput?.contains("\u{00A0}") == true)
    }

    /// CJK text with full-width punctuation must survive the auto transform
    /// byte-for-byte through the passthrough engine — no mangling by any
    /// regex pass.
    func testTransformAutoPreservesCJKPunctuation() async {
        let input = "我觉得我们明天再讨论这个问题吧，然后周五之前把版本发出去。你觉得可以吗？"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            job: PolishJob(task: .auto, promptLanguage: .english, languageAgnosticPath: true)
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    /// Newline markers still round-trip in auto mode (the marker encode/decode
    /// is language-agnostic and stays on).
    func testTransformAutoPreservesNewlines() async {
        let input = "first line of the message here\nsecond line of the message here"
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: PassthroughPolishEngine(),
            job: PolishJob(task: .auto, promptLanguage: .english, languageAgnosticPath: true)
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.engineOutput, input)
    }

    // MARK: - autoPreprocess() (#239 device-test fix: spoken commands in auto mode)

    /// The device-observed bug: "point d'exclamation" / "retour à la ligne"
    /// stayed literal in auto mode. The pre-pass keyed on the DETECTED
    /// language must convert them exactly like the per-language path.
    func testAutoPreprocessConvertsFrenchCommands() {
        let raw = "on va tester si ça arrive à fonctionner point d'exclamation retour à la ligne on va voir"
        let out = PolishPipeline.autoPreprocess(raw, detectedCode: "fr")
        XCTAssertTrue(out.contains("!"))
        XCTAssertTrue(out.contains("\n"))
        XCTAssertFalse(out.lowercased().contains("point d'exclamation"))
        XCTAssertFalse(out.lowercased().contains("retour à la ligne"))
    }

    func testAutoPreprocessConvertsEnglishCommands() {
        let raw = "sounds good exclamation mark new line see you tomorrow question mark"
        let out = PolishPipeline.autoPreprocess(raw, detectedCode: "en")
        XCTAssertTrue(out.contains("!"))
        XCTAssertTrue(out.contains("?"))
        XCTAssertTrue(out.contains("\n"))
        XCTAssertFalse(out.lowercased().contains("exclamation mark"))
        XCTAssertFalse(out.lowercased().contains("new line"))
    }

    /// Same tolerance as the per-language path: the bare "point" word is NOT
    /// converted (#185) — quoting/noun contexts survive.
    func testAutoPreprocessKeepsBarePointNoun() {
        let raw = "de mon point de vue c'est un bon point de départ"
        XCTAssertEqual(PolishPipeline.autoPreprocess(raw, detectedCode: "fr"), raw)
    }

    /// Languages without rules pass through byte-identical — the CJK
    /// guarantee holds through the pre-pass too.
    func testAutoPreprocessLeavesUnsupportedLanguagesUntouched() {
        let zh = "我觉得我们明天再讨论这个问题吧，然后周五之前把版本发出去。"
        XCTAssertEqual(PolishPipeline.autoPreprocess(zh, detectedCode: "zh-Hans"), zh)
        let it = "allora domani andiamo al mare se il tempo è bello"
        XCTAssertEqual(PolishPipeline.autoPreprocess(it, detectedCode: "it"), it)
        XCTAssertEqual(PolishPipeline.autoPreprocess("whatever text", detectedCode: nil), "whatever text")
    }

    /// Auto-mode fallback is the pre-pass floor (worst case output == input
    /// for languages without rules): the placeholder target must not leak
    /// typography into the floor.
    func testResolvedOutputAutoFallbackReturnsInputUnchanged() {
        let input = "ça va ?"
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .engineFailed, engineMs: 100, postprocessMs: 0
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: input, job: PolishJob(task: .auto, promptLanguage: .french, languageAgnosticPath: true))
        XCTAssertEqual(out, input, "no NBSP, no typography — raw input is the auto floor")
    }

    func testResolvedOutputAutoSuccessReturnsEngineOutput() {
        let result = PolishPipeline.Result(
            engineOutput: "Polished text.", outcome: .success, engineMs: 100, postprocessMs: 1
        )
        let out = PolishPipeline.resolvedOutput(result, preprocessed: "polished text", job: PolishJob(task: .auto, promptLanguage: .english, languageAgnosticPath: true))
        XCTAssertEqual(out, "Polished text.")
    }
}

/// Returns a fixed string whatever it is handed, so a test can drive the guardrails
/// with an output that has nothing to do with the input — which is what a
/// translation, and a mistranslation, both look like from the pipeline's side.
private struct FixedOutputEngine: PolishEngineProtocol {
    let identifier = "fixed-output"
    let output: String

    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                task: PolishTask) async throws -> String {
        output
    }
}
