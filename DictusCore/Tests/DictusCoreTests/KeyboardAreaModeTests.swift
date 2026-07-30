// DictusCore/Tests/DictusCoreTests/KeyboardAreaModeTests.swift
// Contract tests for the single keyboard-area mode value (#271).
import XCTest
@testable import DictusCore

final class KeyboardAreaModeTests: XCTestCase {

    // MARK: - Cases

    func testEnumHasExactlyFourCases() {
        XCTAssertEqual(KeyboardAreaMode.allCases.count, 4)
    }

    func testPanelCaseExistsForIssue241() {
        XCTAssertTrue(KeyboardAreaMode.allCases.contains(.panel))
    }

    func testRawValues() {
        XCTAssertEqual(KeyboardAreaMode.keys.rawValue, "keys")
        XCTAssertEqual(KeyboardAreaMode.emoji.rawValue, "emoji")
        XCTAssertEqual(KeyboardAreaMode.panel.rawValue, "panel")
        XCTAssertEqual(KeyboardAreaMode.recording.rawValue, "recording")
    }

    // MARK: - Which statuses own the keyboard area

    func testInFlightStatusesOwnTheKeyboardArea() {
        XCTAssertTrue(DictationStatus.requested.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.recording.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.transcribing.ownsKeyboardArea)
    }

    func testTerminalStatusesDoNotOwnTheKeyboardArea() {
        XCTAssertFalse(DictationStatus.idle.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.ready.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.failed.ownsKeyboardArea)
    }

    // MARK: - Transitions

    func testDictationTakesOverFromEveryMode() {
        for mode in KeyboardAreaMode.allCases {
            XCTAssertEqual(
                KeyboardAreaMode.resolving(status: .requested, current: mode),
                .recording,
                "a requested dictation must take the area from \(mode.rawValue)"
            )
        }
    }

    /// The acceptance criterion "starting a dictation from the emoji picker
    /// dismisses the picker" is this transition — no coordination between flags.
    func testStartingADictationDismissesTheEmojiPicker() {
        XCTAssertEqual(
            KeyboardAreaMode.resolving(status: .recording, current: .emoji),
            .recording
        )
    }

    func testEndingADictationReturnsToTheKeyGrid() {
        for status in [DictationStatus.idle, .ready, .failed] {
            XCTAssertEqual(
                KeyboardAreaMode.resolving(status: status, current: .recording),
                .keys,
                "leaving a dictation via \(status.rawValue) must restore the key grid"
            )
        }
    }

    /// The picker is not restored after a dictation that started from it — the
    /// pre-#271 code cleared its emoji flag when the overlay appeared.
    func testTheEmojiPickerIsNotRestoredAfterADictation() {
        let duringDictation = KeyboardAreaMode.resolving(status: .recording, current: .emoji)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .idle, current: duringDictation), .keys)
    }

    func testAnIdleStatusLeavesAFullAreaPresentationAlone() {
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .idle, current: .emoji), .emoji)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .idle, current: .panel), .panel)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .idle, current: .keys), .keys)
    }

    func testResolvingIsIdempotent() {
        for status in [DictationStatus.idle, .requested, .recording, .transcribing, .ready, .failed] {
            for mode in KeyboardAreaMode.allCases {
                let once = KeyboardAreaMode.resolving(status: status, current: mode)
                let twice = KeyboardAreaMode.resolving(status: status, current: once)
                XCTAssertEqual(once, twice, "status=\(status.rawValue) mode=\(mode.rawValue)")
            }
        }
    }
}
