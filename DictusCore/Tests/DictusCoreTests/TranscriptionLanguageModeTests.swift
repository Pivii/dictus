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

    // MARK: - Polish target resolution

    func testFollowPolishTargetIsKeyboardLanguage() {
        XCTAssertEqual(
            TranscriptionLanguageMode.followKeyboard.polishTargetLanguage(keyboardLanguage: .french),
            .french
        )
    }

    func testAutoPolishTargetIsNilSoPolishIsBypassed() {
        // Stopgap per #226 — the dedicated auto-detect polish prompt is #239.
        XCTAssertNil(
            TranscriptionLanguageMode.autoDetect.polishTargetLanguage(keyboardLanguage: .french)
        )
    }

    func testExplicitPolishTargetIsTheExplicitLanguage() {
        XCTAssertEqual(
            TranscriptionLanguageMode.explicit(.english).polishTargetLanguage(keyboardLanguage: .french),
            .english
        )
    }
}
