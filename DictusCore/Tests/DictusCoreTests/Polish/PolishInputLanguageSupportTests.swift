// DictusCore/Tests/DictusCoreTests/Polish/PolishInputLanguageSupportTests.swift
// The pre-flight that refuses a transcript no polish backend can read (#490).

import XCTest
@testable import DictusCore

/// Coverage for the rule alone. Apple's own list is not reachable from a test on
/// every machine, and it is not what this issue got wrong — the rule that reads it
/// is, so the rule takes the list as an argument and is tested against it directly.
final class PolishInputLanguageSupportTests: XCTestCase {

    /// The set Apple Foundation Models reports, collapsed to primary subtags.
    /// Written down rather than read, so the assertions below say what they mean on a
    /// machine with Apple Intelligence off.
    ///
    /// Measured on 2026-09-07: 23 locales, 15 subtags. Wider than the nine #490's body
    /// names — `da nb nl sv tr vi` are readable and the issue did not know it — which
    /// only ever makes this pre-flight refuse less. None of Parakeet's fourteen
    /// unreadable languages moved.
    private let appleFM: Set<String> = [
        "da", "de", "en", "es", "fr", "it", "ja", "ko", "nb", "nl", "pt", "sv", "tr", "vi", "zh"
    ]

    // MARK: - The verdict

    /// #490's reproduced case: a Czech transcript, nothing else in it.
    func testATranscriptEntirelyInAnUnreadableLanguageIsRefused() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["cs"], readableCodes: appleFM),
            .unsupported
        )
    }

    /// The four languages measured as refused on #490, one per run.
    func testEveryLanguageMeasuredAsRefusedIsRefusedHere() {
        for code in ["cs", "ru", "uk", "el"] {
            XCTAssertEqual(
                PolishInputLanguage.support(countedCodes: [code], readableCodes: appleFM),
                .unsupported,
                "\(code) was measured as refused 5/5 by Apple FM and must be caught locally"
            )
        }
    }

    /// The #518 case, which this pre-flight must never touch: French is readable, so
    /// a refusal on it is Apple's classifier misreading our prompt, not a fact about
    /// the dictation. Refusing it here would put a lie on the user's screen.
    func testAReadableLanguageIsNeverRefusedLocally() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["fr"], readableCodes: appleFM),
            .supported
        )
    }

    /// The conservative half of the rule: one readable language anywhere in the mix
    /// sends the call to the engine, which is free to refuse it itself.
    func testAMixWithOneReadableLanguageStillReachesTheEngine() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["cs", "fr"], readableCodes: appleFM),
            .supported,
            "a bilingual transcript with a readable half is not a case this pre-flight measured"
        )
    }

    /// Every language unreadable is the only shape that refuses, whatever the count.
    func testAMixOfUnreadableLanguagesIsRefused() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["cs", "pl", "uk"], readableCodes: appleFM),
            .unsupported
        )
    }

    // MARK: - Everything that must not refuse

    /// A backend that publishes no list. This is what a device with Apple
    /// Intelligence off, or an OS before 26, hands over — and a refusal built on it
    /// would turn polish off for everyone on those devices.
    func testAnEmptyReadableSetNeverRefuses() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["cs"], readableCodes: []),
            .unknown
        )
    }

    /// Gibberish, or a transcript short enough that the mix counted nothing. The mix
    /// is only ever allowed to add information; a verdict on no reading would remove
    /// polish from text that gets it today.
    func testNothingReadInTheTranscriptNeverRefuses() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: [], readableCodes: appleFM),
            .unknown
        )
    }

    // MARK: - Subtags

    /// Our reading says `zh-Hans`, Apple's list says `zh`. Comparing at full width
    /// would refuse Chinese, which Apple reads.
    func testAScriptTaggedCodeMatchesItsPrimarySubtag() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["zh-Hans"], readableCodes: appleFM),
            .supported
        )
    }

    /// The same, from the other side: Apple's list arrives as `fr-Latn-FR` in some
    /// readings of it.
    func testAReadableCodeWithRegionAndScriptStillMatches() {
        XCTAssertEqual(
            PolishInputLanguage.support(countedCodes: ["fr"], readableCodes: ["fr-Latn-FR"]),
            .supported
        )
    }

    func testPrimarySubtagStripsScriptRegionAndCase() {
        XCTAssertEqual(PolishInputLanguage.primarySubtag("zh-Hans"), "zh")
        XCTAssertEqual(PolishInputLanguage.primarySubtag("fr-Latn-FR"), "fr")
        XCTAssertEqual(PolishInputLanguage.primarySubtag("pt_BR"), "pt")
        XCTAssertEqual(PolishInputLanguage.primarySubtag("CS"), "cs")
        XCTAssertEqual(PolishInputLanguage.primarySubtag("cs"), "cs")
    }

    // MARK: - Naming the language to the user

    /// The sentence #490 asks for has to say which language was dictated, in the
    /// user's own language.
    func testTheDictatedLanguageIsNamedInTheReadersLanguage() {
        XCTAssertEqual(PolishLanguageName.display(for: "cs", locale: Locale(identifier: "en")), "Czech")
        XCTAssertEqual(PolishLanguageName.display(for: "cs", locale: Locale(identifier: "fr")), "tchèque")
    }

    /// A script-tagged code is named at full width when the locale knows it, so a
    /// user is not told "Chinese" for a reading that was specifically Simplified.
    func testAScriptTaggedCodeIsNamedAtFullWidthWhenPossible() {
        let name = PolishLanguageName.display(for: "zh-Hans", locale: Locale(identifier: "en"))
        XCTAssertTrue(name.contains("Chinese"), "expected a Chinese name, got \(name)")
    }

    /// A code with no name falls back to itself rather than to an empty sentence.
    func testAnUnnameableCodeFallsBackToTheCode() {
        XCTAssertEqual(
            PolishLanguageName.display(for: "zzz", locale: Locale(identifier: "en")),
            "zzz"
        )
    }

    // MARK: - What the mix hands the pre-flight

    func testCountedCodesAreEveryLanguageTheMixCounted() {
        let mix = PolishLanguageMix(
            shares: ["cs": 0.7, "fr": 0.3], dominantCode: "cs", dominantShare: 0.7,
            countedCharacters: 100
        )
        XCTAssertEqual(mix.countedCodes, ["cs", "fr"])
    }

    func testAnUndeterminedMixCountsNoCodes() {
        XCTAssertEqual(PolishLanguageMix.undetermined.countedCodes, [])
    }

    // MARK: - The pipeline

    /// The whole point of the pre-flight: the engine is never asked. Measured on
    /// #490 at 22 ms on device and 3 to 5 ms on the Mac — cheap, but paid on every
    /// dictation in a language the model was never going to read.
    func testAnUnreadableInputRefusesWithoutCallingTheEngine() async {
        let result = await PolishPipeline.transform(
            preprocessed: "Dobrý den, dnes je opravdu hezký den a musím zavolat kolegovi.",
            engine: UnreadableInputEngine(),
            job: PolishJob(
                task: .smart(SmartModeCatalogue.translate(to: .english)),
                promptLanguage: .french, languageAgnosticPath: false,
                inputLanguageCodes: ["cs"]
            )
        )
        XCTAssertEqual(result.outcome, .unsupportedInputLanguage)
        XCTAssertEqual(result.engineMs, 0)
        XCTAssertNil(result.engineOutput)
    }

    /// An engine that publishes no list is the default, and the default never
    /// refuses: every backend but Apple FM, and Apple FM itself on a device with
    /// Apple Intelligence off.
    func testAnEngineThatPublishesNoListStillRuns() async {
        let result = await PolishPipeline.transform(
            preprocessed: "this is a perfectly ordinary english sentence to polish",
            engine: PassthroughPolishEngine(),
            job: PolishJob(
                task: .natural, promptLanguage: .english, languageAgnosticPath: false,
                inputLanguageCodes: ["cs"]
            )
        )
        XCTAssertEqual(result.outcome, .success)
    }

    /// A Smart Mode stays fail-closed: the floor here is text in a language the model
    /// cannot read, which is not the offer an overflow makes.
    func testARefusedLanguageInsertsNothingForASmartMode() {
        let job = PolishJob(
            task: .smart(SmartModeCatalogue.notes),
            promptLanguage: .french, languageAgnosticPath: false, inputLanguageCodes: ["cs"]
        )
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .unsupportedInputLanguage, engineMs: 0, postprocessMs: 0
        )
        XCTAssertNil(PolishPipeline.resolvedOutput(result, preprocessed: "Dobrý den.", job: job))
        XCTAssertFalse(
            PolishPipeline.degradesToFloor(SmartModeCatalogue.notes, outcome: .unsupportedInputLanguage)
        )
    }

    /// The free polish keeps its floor, exactly as it does for every other refusal:
    /// the user's words are never what is at risk here, only the polish.
    func testARefusedLanguageStillReturnsTheFloorForTheFreePolish() {
        let job = PolishJob(
            task: .natural, promptLanguage: .french, languageAgnosticPath: false,
            inputLanguageCodes: ["cs"]
        )
        let result = PolishPipeline.Result(
            engineOutput: nil, outcome: .unsupportedInputLanguage, engineMs: 0, postprocessMs: 0
        )
        XCTAssertEqual(
            PolishPipeline.resolvedOutput(result, preprocessed: "Dobrý den.", job: job),
            "Dobrý den."
        )
    }

    // MARK: - The availability gate (#315)

    /// A local refusal is no evidence about the backend's rate limit, because the
    /// backend was never asked. It must neither start a refusal run nor break one.
    func testALocalRefusalLeavesTheRateLimitRunUntouched() {
        var gate = PolishAvailabilityGate()
        XCTAssertFalse(gate.record(outcome: .engineFailed, reason: .rateLimited, engine: "apple-fm"))
        XCTAssertFalse(gate.record(outcome: .unsupportedInputLanguage, reason: nil, engine: "apple-fm"))
        XCTAssertTrue(
            gate.record(outcome: .engineFailed, reason: .rateLimited, engine: "apple-fm"),
            "the local refusal broke a rate-limit run it has no evidence about"
        )
    }
}

// MARK: - Stubs

/// Reports every input unreadable, and fails the test if it is called anyway.
/// "Do not invoke the engine" is the behaviour under test.
private struct UnreadableInputEngine: PolishEngineProtocol {
    let identifier = "unreadable-input"

    func inputLanguageSupport(countedCodes: Set<String>) -> PolishInputLanguageSupport {
        .unsupported
    }

    func polish(raw: String, targetLanguage: SupportedLanguage, task: PolishTask) async throws -> String {
        XCTFail("the engine must not be called for a language it cannot read")
        return raw
    }
}
