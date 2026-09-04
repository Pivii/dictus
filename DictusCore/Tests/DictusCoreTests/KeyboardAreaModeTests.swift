// DictusCore/Tests/DictusCoreTests/KeyboardAreaModeTests.swift
// Contract tests for the single keyboard-area mode value (#271).
import XCTest
@testable import DictusCore

final class KeyboardAreaModeTests: XCTestCase {

    // MARK: - Cases

    /// The count is the point, not the number: `KeyboardViewController.applyLayout`
    /// switches exhaustively over this enum and every case has to set the hosting
    /// height, the bottom anchor and the grid's visibility explicitly. A case added
    /// without that is the #271 bug returning.
    func testEnumHasExactlyFiveCases() {
        XCTAssertEqual(KeyboardAreaMode.allCases.count, 5)
    }

    func testPanelCaseExistsForIssue241() {
        XCTAssertTrue(KeyboardAreaMode.allCases.contains(.panel))
    }

    func testSmartModeFanCaseExistsForIssue79() {
        XCTAssertTrue(KeyboardAreaMode.allCases.contains(.smartModeFan))
    }

    func testRawValues() {
        XCTAssertEqual(KeyboardAreaMode.keys.rawValue, "keys")
        XCTAssertEqual(KeyboardAreaMode.emoji.rawValue, "emoji")
        XCTAssertEqual(KeyboardAreaMode.panel.rawValue, "panel")
        XCTAssertEqual(KeyboardAreaMode.smartModeFan.rawValue, "smartModeFan")
        XCTAssertEqual(KeyboardAreaMode.recording.rawValue, "recording")
    }

    /// A dictation takes the area from the fan, exactly as it does from the pickers —
    /// the fan is a menu, and the overlay owns the whole area while a dictation is in
    /// flight (#79).
    func testDictationTakesTheAreaFromTheFan() {
        XCTAssertEqual(
            KeyboardAreaMode.resolving(status: .recording, current: .smartModeFan),
            .recording
        )
    }

    /// And an idle status leaves it alone: the fan is dismissed by its own gesture
    /// ending, not by a status write.
    func testIdleStatusLeavesTheFanOpen() {
        XCTAssertEqual(
            KeyboardAreaMode.resolving(status: .idle, current: .smartModeFan),
            .smartModeFan
        )
    }

    // MARK: - Which statuses own the keyboard area

    func testInFlightStatusesOwnTheKeyboardArea() {
        XCTAssertTrue(DictationStatus.requested.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.recording.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.transcribing.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.processing.ownsKeyboardArea)
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
        for status in DictationStatus.allCases {
            for mode in KeyboardAreaMode.allCases {
                let once = KeyboardAreaMode.resolving(status: status, current: mode)
                let twice = KeyboardAreaMode.resolving(status: status, current: once)
                XCTAssertEqual(once, twice, "status=\(status.rawValue) mode=\(mode.rawValue)")
            }
        }
    }
}
