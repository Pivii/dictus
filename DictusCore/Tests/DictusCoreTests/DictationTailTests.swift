// DictusCore/Tests/DictusCoreTests/DictationTailTests.swift
// Tests for the trailing separator (#361): the rule moved into the keyboard with
// polish, and now has two callers in two processes.

import XCTest
@testable import DictusCore

final class DictationTailTests: XCTestCase {

    private func policy(
        mode: TranscriptionLanguageMode,
        engine: SpeechEngine = .whisperKit
    ) -> TranscriptionLanguagePolicy {
        TranscriptionLanguagePolicy(
            mode: mode,
            keyboardLanguage: .french,
            engine: engine,
            modelIdentifier: "openai_whisper-small"
        )
    }

    // MARK: - The historical separator

    func testUnpunctuatedTextGetsAFullStopAndASpace() {
        let out = DictationTail.apply("bonjour tout le monde", policy: policy(mode: .followKeyboard))
        XCTAssertEqual(out, "bonjour tout le monde. ")
    }

    func testTextEndingInAFullStopGetsOnlyASpace() {
        let out = DictationTail.apply("Bonjour.", policy: policy(mode: .followKeyboard))
        XCTAssertEqual(out, "Bonjour. ")
    }

    func testEveryTerminatorCountsAsPunctuated() {
        for terminator in [".", "!", "?", "…"] {
            let out = DictationTail.apply("Bonjour\(terminator)", policy: policy(mode: .followKeyboard))
            XCTAssertEqual(out, "Bonjour\(terminator) ", "terminator \(terminator)")
        }
    }

    func testExplicitModeKeepsTheSeparator() {
        let out = DictationTail.apply("hello", policy: policy(mode: .explicit(.english)))
        XCTAssertEqual(out, "hello. ")
    }

    func testEmptyTextGetsTheDefaultSeparator() {
        // No last character to inspect, so the punctuated branch cannot be taken.
        XCTAssertEqual(DictationTail.apply("", policy: policy(mode: .followKeyboard)), ". ")
    }

    // MARK: - Whisper auto-detect inserts as-is

    func testWhisperAutoDetectIsLeftAlone() {
        let out = DictationTail.apply("你好。", policy: policy(mode: .autoDetect))
        XCTAssertEqual(out, "你好。", "coercing Western punctuation onto CJK corrupts it")
    }

    func testParakeetAutoDetectKeepsTheSeparator() {
        // The setting is Whisper-only-effective: Parakeet auto-detects natively and
        // ignores it, so its flows stay byte-identical to the pre-#226 behaviour.
        let out = DictationTail.apply("bonjour", policy: policy(mode: .autoDetect, engine: .parakeet))
        XCTAssertEqual(out, "bonjour. ")
    }
}
