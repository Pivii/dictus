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

}

/// Engine-aware per-dictation policy snapshot (#226 review follow-up, #239):
/// the STT setting is Whisper-only-effective, but the polish-stage prompt
/// selection uses the auto prompt for BOTH engines in Auto mode (#239 scope
/// amendment — Parakeet auto-detects natively, so its output language is just
/// as unknown as Whisper's).
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
        XCTAssertEqual(sut.polishPromptSelection, .language(.french))
        XCTAssertFalse(sut.insertsTranscriptionAsIs)
    }

    func testWhisperAutoDetectUsesAutoPromptAndSkipsSeparator() {
        let sut = policy(.autoDetect, keyboard: .french, engine: .whisperKit)
        XCTAssertNil(sut.sttLanguageCode, "nil enables Whisper language detection")
        XCTAssertEqual(sut.polishPromptSelection, .autoDetected,
                       "auto mode polishes with the language-agnostic prompt (#239)")
        XCTAssertTrue(sut.insertsTranscriptionAsIs)
    }

    func testWhisperExplicitIgnoresKeyboardLanguage() {
        let sut = policy(.explicit(.english), keyboard: .french, engine: .whisperKit)
        XCTAssertEqual(sut.sttLanguageCode, "en")
        XCTAssertEqual(sut.polishPromptSelection, .language(.english),
                       "polish must match the dictated language, not the keyboard")
        XCTAssertFalse(sut.insertsTranscriptionAsIs)
    }

    // MARK: - Parakeet: STT stage unchanged, polish stage engine-aware

    func testParakeetFollowBehavesLikeToday() {
        let sut = policy(.followKeyboard, keyboard: .spanish, engine: .parakeet)
        XCTAssertEqual(sut.sttLanguageCode, "es")
        XCTAssertEqual(sut.polishPromptSelection, .language(.spanish))
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
        XCTAssertEqual(sut.polishPromptSelection, .autoDetected)
        XCTAssertFalse(sut.insertsTranscriptionAsIs,
                       "separator behavior is Whisper-auto-only, untouched by #239")
    }

    func testParakeetExplicitKeepsKeyboardPolishTarget() {
        // Explicit mode cannot influence Parakeet — polish keeps targeting
        // the keyboard language exactly as before #226.
        let sut = policy(.explicit(.english), keyboard: .french, engine: .parakeet)
        XCTAssertEqual(sut.sttLanguageCode, "fr")
        XCTAssertEqual(sut.polishPromptSelection, .language(.french))
        XCTAssertFalse(sut.insertsTranscriptionAsIs)
    }
}
