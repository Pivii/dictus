// DictusCore/Tests/DictusCoreTests/TranscriptionLanguageModeTests.swift
// Tests for the transcription language decoupling (issue #226).
import XCTest
@testable import DictusCore

final class TranscriptionLanguageModeTests: XCTestCase {

    // MARK: - SharedKeys contract

    func testTranscriptionLanguageKeyExists() {
        XCTAssertEqual(SharedKeys.transcriptionLanguage, "dictus.transcriptionLanguage")
    }

    func testTranscriptionLanguageKeyIsDistinctFromKeyboardLanguageKey() {
        // The whole point of #226: STT reads its own key, the keyboard
        // toolbar switcher writes only SharedKeys.language.
        XCTAssertNotEqual(SharedKeys.transcriptionLanguage, SharedKeys.language)
    }

    // MARK: - Parsing (App Group stored value -> mode)

    func testMissingValueParsesAsFollow() {
        // Fresh installs and pre-#226 upgrades have no stored value:
        // they must behave exactly as today (STT follows the keyboard).
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: nil), .followKeyboard)
    }

    func testFollowMarkerParsesAsFollow() {
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "follow"), .followKeyboard)
    }

    func testAutoMarkerParsesAsAutoDetect() {
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "auto"), .autoDetect)
    }

    func testExplicitCodesParseAsExplicit() {
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "fr"), .explicit(.french))
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "en"), .explicit(.english))
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "es"), .explicit(.spanish))
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "de"), .explicit(.german))
    }

    func testUnknownValueDegradesToFollow() {
        // Unknown codes (e.g. a future value read by an older build, or a
        // corrupted default) must never break transcription — degrade to the
        // safe historical behavior.
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "zh"), .followKeyboard)
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: ""), .followKeyboard)
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "garbage"), .followKeyboard)
    }

    // MARK: - Encoding round-trip

    func testStoredValueRoundTrip() {
        let modes: [TranscriptionLanguageMode] = [
            .followKeyboard, .autoDetect,
            .explicit(.french), .explicit(.english), .explicit(.spanish), .explicit(.german)
        ]
        for mode in modes {
            XCTAssertEqual(TranscriptionLanguageMode(storedValue: mode.storedValue), mode)
        }
    }

    // MARK: - STT language resolution

    func testFollowResolvesToKeyboardLanguage() {
        let mode = TranscriptionLanguageMode.followKeyboard
        XCTAssertEqual(mode.resolvedLanguageCode(keyboardLanguageCode: "fr"), "fr")
        XCTAssertEqual(mode.resolvedLanguageCode(keyboardLanguageCode: "de"), "de")
    }

    func testAutoResolvesToNilForWhisperAutoDetection() {
        // nil is what enables Whisper's language detection in DecodingOptions.
        XCTAssertNil(TranscriptionLanguageMode.autoDetect.resolvedLanguageCode(keyboardLanguageCode: "fr"))
    }

    func testExplicitResolvesToItsOwnCodeRegardlessOfKeyboard() {
        // The keyboard toolbar switcher changes the keyboard language;
        // an explicit transcription choice must never follow it.
        let mode = TranscriptionLanguageMode.explicit(.english)
        XCTAssertEqual(mode.resolvedLanguageCode(keyboardLanguageCode: "fr"), "en")
        XCTAssertEqual(mode.resolvedLanguageCode(keyboardLanguageCode: "es"), "en")
    }

    // MARK: - Telemetry description (#332)

    func testTelemetryDescriptionNamesTheModeNotJustTheLanguage() {
        // The whole point: "fr" alone cannot say whether the user chose French
        // or the keyboard happened to be French.
        XCTAssertEqual(TranscriptionLanguageMode.followKeyboard.telemetryDescription,
                       "followKeyboard")
        XCTAssertEqual(TranscriptionLanguageMode.autoDetect.telemetryDescription,
                       "autoDetect")
        XCTAssertEqual(TranscriptionLanguageMode.explicit(.french).telemetryDescription,
                       "explicit(fr)")
        XCTAssertEqual(TranscriptionLanguageMode.explicit(.german).telemetryDescription,
                       "explicit(de)")
    }

    func testTelemetryDescriptionIsDistinctFromStoredValue() {
        // If they were interchangeable the export would still be ambiguous.
        let explicit = TranscriptionLanguageMode.explicit(.french)
        XCTAssertEqual(explicit.storedValue, "fr")
        XCTAssertNotEqual(explicit.telemetryDescription, explicit.storedValue)
    }

}

/// Engine-aware per-dictation policy snapshot (#226 review follow-up, #239,
/// #332): the STT setting is Whisper-only-effective, but the polish-stage
/// target follows its own order — explicit choice, then detection, then the
/// keyboard as a last resort (#332) — and Auto mode uses the auto prompt for
/// BOTH engines (#239 scope amendment).
final class TranscriptionLanguagePolicyTests: XCTestCase {

    private func policy(_ mode: TranscriptionLanguageMode,
                        keyboard: SupportedLanguage,
                        engine: SpeechEngine) -> TranscriptionLanguagePolicy {
        TranscriptionLanguagePolicy(
            mode: mode, keyboardLanguage: keyboard, engine: engine, modelIdentifier: "test-model"
        )
    }

    // MARK: - Whisper: the setting is effective

    func testWhisperFollowBehavesLikeToday() {
        let sut = policy(.followKeyboard, keyboard: .french, engine: .whisperKit)
        XCTAssertEqual(sut.sttLanguageCode, "fr")
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: .french), .language(.french))
        XCTAssertFalse(sut.insertsTranscriptionAsIs)
    }

    func testWhisperAutoDetectUsesAutoPromptAndSkipsSeparator() {
        let sut = policy(.autoDetect, keyboard: .french, engine: .whisperKit)
        XCTAssertNil(sut.sttLanguageCode, "nil enables Whisper language detection")
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: .german), .autoDetected,
                       "auto mode polishes with the language-agnostic prompt (#239)")
        XCTAssertTrue(sut.insertsTranscriptionAsIs)
    }

    func testWhisperExplicitIgnoresKeyboardLanguage() {
        let sut = policy(.explicit(.english), keyboard: .french, engine: .whisperKit)
        XCTAssertEqual(sut.sttLanguageCode, "en")
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: .english), .language(.english),
                       "polish must match the dictated language, not the keyboard")
        XCTAssertFalse(sut.insertsTranscriptionAsIs)
    }

    // MARK: - Parakeet: STT stage unchanged, polish stage follows the order

    func testParakeetFollowUsesTheDetectedLanguage() {
        let sut = policy(.followKeyboard, keyboard: .spanish, engine: .parakeet)
        XCTAssertEqual(sut.sttLanguageCode, "es")
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: .spanish), .language(.spanish))
        XCTAssertFalse(sut.insertsTranscriptionAsIs)
    }

    func testParakeetAutoDetectUsesAutoPrompt() {
        // #239 scope amendment: Parakeet transcribes whichever of its 25
        // languages is spoken, so targeting the keyboard language in Auto mode
        // made polish TRANSLATE foreign speech (observed on device). The
        // polish stage uses the auto prompt; the STT stage keeps the follow
        // behavior (the engine ignores the language parameter anyway).
        let sut = policy(.autoDetect, keyboard: .french, engine: .parakeet)
        XCTAssertEqual(sut.sttLanguageCode, "fr", "STT stage untouched by #239")
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: .french), .autoDetected)
        XCTAssertFalse(sut.insertsTranscriptionAsIs,
                       "separator behavior is Whisper-auto-only, untouched by #239")
    }

    // MARK: - Polish target resolution order (#332)

    /// The regression this issue is about: three device reproductions caught
    /// French speech polished into German and into English, purely because the
    /// keyboard had been switched while the setting said French. Before #332,
    /// explicit mode resolved to the keyboard language on any non-Whisper
    /// engine — and Parakeet is the shipping engine, so the user's choice was
    /// discarded on essentially every real dictation.
    func testExplicitTargetIsNeverOverriddenByTheKeyboard() {
        for engine in [SpeechEngine.whisperKit, .parakeet] {
            for keyboard in [SupportedLanguage.german, .english, .spanish] {
                let sut = policy(.explicit(.french), keyboard: keyboard, engine: engine)
                XCTAssertEqual(
                    sut.polishPromptSelection(detectedLanguage: .french), .language(.french),
                    "explicit fr must survive a \(keyboard.rawValue) keyboard on \(engine.rawValue)"
                )
            }
        }
    }

    /// Rank 1 beats rank 2: the user's own words outrank a detector's guess,
    /// including when the detector disagrees.
    func testExplicitTargetOutranksDetection() {
        let sut = policy(.explicit(.french), keyboard: .german, engine: .parakeet)
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: .german), .language(.french))
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: nil), .language(.french),
                       "an explicit choice does not need detection to back it up")
    }

    /// Rank 2 beats rank 3: with no explicit choice, what the transcript reads
    /// as decides the target — so a keyboard switch cannot retarget polish
    /// onto a language the user never spoke.
    func testDetectedLanguageOutranksTheKeyboardInFollowMode() {
        for engine in [SpeechEngine.whisperKit, .parakeet] {
            let sut = policy(.followKeyboard, keyboard: .german, engine: engine)
            XCTAssertEqual(
                sut.polishPromptSelection(detectedLanguage: .french), .language(.french),
                "French transcript on a German keyboard must not be polished into German"
            )
        }
    }

    /// Rank 3: the keyboard is still the answer when nothing better exists —
    /// detection was unconfident, or landed outside the four supported
    /// languages. That is a guess, and it is the only case where one is made.
    func testKeyboardLanguageIsTheLastResortOnly() {
        let sut = policy(.followKeyboard, keyboard: .german, engine: .parakeet)
        XCTAssertEqual(sut.polishPromptSelection(detectedLanguage: nil), .language(.german))
    }

    // MARK: - STT telemetry (#332)

    /// The `stt=en engine=PK` log line that read as "transcribed in English"
    /// above a French transcript. The code is real, the engine ignores it.
    func testSttLanguageIsMarkedIneffectiveForParakeet() {
        let parakeet = policy(.explicit(.english), keyboard: .french, engine: .parakeet)
        XCTAssertEqual(parakeet.sttLanguageCode, "fr",
                       "STT stage keeps its pre-#226 follow behavior")
        XCTAssertFalse(parakeet.sttLanguageIsEffective,
                       "Parakeet auto-detects from audio and ignores the parameter")

        let whisper = policy(.explicit(.english), keyboard: .french, engine: .whisperKit)
        XCTAssertTrue(whisper.sttLanguageIsEffective)
    }

    func testSttLanguageDescriptionSpellsOutWhisperAutoDetection() {
        let sut = policy(.autoDetect, keyboard: .french, engine: .whisperKit)
        XCTAssertNil(sut.sttLanguageCode)
        XCTAssertEqual(sut.sttLanguageCodeDescription, "auto",
                       "a dropped nil would read as 'not recorded'")
    }

    func testLanguageResolutionTrailCarriesEachFactApart() {
        // The export must let a reader separate the mode, the keyboard, and
        // what STT was handed — the failure that made three device re-tests
        // necessary was that these collapsed into one mislabelled field.
        let sut = policy(.explicit(.french), keyboard: .german, engine: .parakeet)
        let trail = PolishMetrics.LanguageResolution(policy: sut)
        XCTAssertEqual(trail.transcriptionMode, "explicit(fr)")
        XCTAssertEqual(trail.keyboardLanguage, "de")
        XCTAssertEqual(trail.sttLanguageCode, "de")
        XCTAssertFalse(trail.sttLanguageIsEffective)
    }
}

/// The language-resolution trail is only useful if it reaches the JSON export
/// intact, and only safe if adding it does not invalidate the events already
/// on disk (#332). The debug ring is 7 days of JSON Lines written by whatever
/// build was installed at the time.
final class PolishLanguageResolutionPersistenceTests: XCTestCase {

    private func metric(resolution: PolishMetrics.LanguageResolution?) -> PolishMetrics {
        PolishMetrics(
            engine: "apple-fm", mode: .repair, targetLanguage: .german,
            detectedLanguage: "fr", rawCharCount: 423, polishedCharCount: 342,
            latencyMs: 3203, outcome: .success,
            sttEngine: "PK", sttModelID: "parakeet-tdt-0.6b-v3",
            languageResolution: resolution
        )
    }

    func testTrailSurvivesTheMetricJSONRoundTrip() throws {
        let sut = metric(resolution: PolishMetrics.LanguageResolution(
            transcriptionMode: "explicit(fr)", keyboardLanguage: "de",
            sttLanguageCode: "de", sttLanguageIsEffective: false
        ))
        let data = try JSONEncoder().encode(sut)
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)
        XCTAssertEqual(decoded.languageResolution?.transcriptionMode, "explicit(fr)")
        XCTAssertEqual(decoded.languageResolution?.keyboardLanguage, "de")
        XCTAssertEqual(decoded.languageResolution?.sttLanguageCode, "de")
        XCTAssertEqual(decoded.languageResolution?.sttLanguageIsEffective, false)
        // The distinction the export existed to make and could not: the polish
        // target and the keyboard language are separate values on one event.
        XCTAssertEqual(decoded.targetLanguage, .german)
        XCTAssertNotEqual(decoded.detectedLanguage, decoded.targetLanguage?.rawValue)
    }

    /// The auto path targets no language: the prompt is language-agnostic and
    /// the model writes in whatever the input is. Recording the keyboard
    /// language there — as this did until the device test caught it — puts a
    /// language that had no influence under the field named for the one that
    /// does, which is the confusion #332 exists to end. On device it produced
    /// `detected=fr, target=de` on a dictation that correctly came out French.
    func testAutoPathRecordsNoTargetAtAll() throws {
        let sut = PolishMetrics(
            engine: "apple-fm", mode: .auto, targetLanguage: nil,
            detectedLanguage: "fr", rawCharCount: 200, polishedCharCount: 210,
            latencyMs: 2800, outcome: .success,
            sttEngine: "PK", sttModelID: "parakeet-tdt-0.6b-v3",
            languageResolution: PolishMetrics.LanguageResolution(
                transcriptionMode: "autoDetect", keyboardLanguage: "de",
                sttLanguageCode: "de", sttLanguageIsEffective: false
            )
        )
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(sut), encoding: .utf8))
        XCTAssertFalse(json.contains("\"targetLanguage\""),
                       "a nil target must be omitted, not encoded as a language: \(json)")
        // The keyboard language is still on the event — under its own name.
        XCTAssertTrue(json.contains("\"keyboardLanguage\":\"de\""))

        let decoded = try JSONDecoder().decode(
            PolishMetrics.self, from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertNil(decoded.targetLanguage)
        XCTAssertEqual(decoded.languageResolution?.keyboardLanguage, "de")
    }

    /// Absent must mean "nothing was targeted", never "not recorded" — which
    /// holds only because every event written before #332 carries a value.
    func testPreFixEventsStillCarryTheirTarget() throws {
        let shipped = """
        {"engine":"apple-fm","mode":"auto","targetLanguage":"de","detectedLanguage":"fr",\
        "rawCharCount":200,"polishedCharCount":210,"latencyMs":2800,"outcome":"success"}
        """
        let decoded = try JSONDecoder().decode(
            PolishMetrics.self, from: XCTUnwrap(shipped.data(using: .utf8))
        )
        XCTAssertEqual(decoded.targetLanguage, .german)
        XCTAssertNil(decoded.languageResolution,
                     "no trail is what marks an auto event as predating the fix")
    }

    /// Backward compatibility: a payload shaped exactly like one written by
    /// 1.8.0 (26) — the build the third reproduction came from — must decode.
    func testEventEncodedWithoutATrailStillDecodes() throws {
        let shipped = """
        {"engine":"apple-fm","mode":"repair","targetLanguage":"en","detectedLanguage":"fr",\
        "rawCharCount":423,"polishedCharCount":342,"latencyMs":3203,"outcome":"success",\
        "sttEngine":"PK","sttModelID":"parakeet-tdt-0.6b-v3",\
        "timings":{"preprocessMs":16,"engineMs":3180,"postprocessMs":7}}
        """
        let decoded = try JSONDecoder().decode(
            PolishMetrics.self, from: XCTUnwrap(shipped.data(using: .utf8))
        )
        XCTAssertEqual(decoded.outcome, .success)
        XCTAssertNil(decoded.languageResolution,
                     "a missing key means 'written before the trail existed', not a failed decode")
        XCTAssertEqual(decoded.timings?.engineMs, 3180)
    }
}
