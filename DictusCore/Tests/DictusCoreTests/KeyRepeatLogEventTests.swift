// DictusCore/Tests/DictusCoreTests/KeyRepeatLogEventTests.swift
// Tests for the held-key auto-repeat log events (#390).
//
// The repeat timer itself lives in the vendored keyboard view and is not reachable
// from this package. What IS reachable, and what the issue actually asks for, is the
// pair of lines a reader greps for: a start, and a stop carrying the tick count and
// what stopped it.
import XCTest
@testable import DictusCore

final class KeyRepeatLogEventTests: XCTestCase {

    func testKeyRepeatStartedIsDebugKeyboard() {
        let event = LogEvent.keyRepeatStarted
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.name, "keyRepeatStarted")
    }

    func testKeyRepeatStoppedIsDebugKeyboard() {
        let event = LogEvent.keyRepeatStopped(ticks: 12, reason: "touch")
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.name, "keyRepeatStopped")
    }

    func testKeyRepeatStoppedCarriesTickCountAndReason() {
        let event = LogEvent.keyRepeatStopped(ticks: 12, reason: "windowDetached")
        XCTAssertEqual(event.message, "ticks=12 reason=windowDetached")
    }

    /// The two lines have to be findable by name in an exported log, because that is
    /// how they are read: `grep keyRepeat`.
    func testFormattedOutputIsGreppableAndCarriesTheTickCount() {
        let started = LogEvent.keyRepeatStarted.formatted()
        XCTAssertTrue(started.contains("keyRepeatStarted"))
        XCTAssertTrue(started.contains("[keyboard]"))

        let stopped = LogEvent.keyRepeatStopped(ticks: 347, reason: "viewDeallocated").formatted()
        XCTAssertTrue(stopped.contains("keyRepeatStopped"))
        XCTAssertTrue(stopped.contains("[keyboard]"))
        XCTAssertTrue(stopped.contains("ticks=347"))
        XCTAssertTrue(stopped.contains("reason=viewDeallocated"))
    }

    /// A runaway is only diagnosable if the stop line can say the timer was still
    /// firing after the view was gone, so the unknown tick count has to survive
    /// formatting rather than being clamped away.
    func testKeyRepeatStoppedAcceptsAnUnknownTickCount() {
        let event = LogEvent.keyRepeatStopped(ticks: -1, reason: "viewDeallocated")
        XCTAssertEqual(event.message, "ticks=-1 reason=viewDeallocated")
    }

    /// Neither case can name a key or a character -- the same rule
    /// `keyboardTextInserted` follows.
    func testKeyRepeatEventsCarryNoKeyOrCharacter() {
        XCTAssertEqual(LogEvent.keyRepeatStarted.message, "")
        let stopped = LogEvent.keyRepeatStopped(ticks: 3, reason: "touch").message
        XCTAssertFalse(stopped.contains("key="))
        XCTAssertFalse(stopped.contains("character="))
    }
}
