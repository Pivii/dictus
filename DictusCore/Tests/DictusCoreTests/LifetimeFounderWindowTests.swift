// DictusCore/Tests/DictusCoreTests/LifetimeFounderWindowTests.swift
// The founder-window line must retire itself when the window closes (#350).
//
// The build outlives the window: App Store Connect moves the price to 79,99 €
// on the announced day, but a user who has not updated keeps running the build
// that announced it. A stale line contradicting the price above it is worse
// than no line.
import XCTest
@testable import DictusCore

final class LifetimeFounderWindowTests: XCTestCase {

    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        super.setUp()
        // Fixed zone so every day boundary below is the same on any machine,
        // and so the daylight-saving case is a real 25-hour day.
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(
            DateComponents(
                calendar: calendar, timeZone: calendar.timeZone,
                year: year, month: month, day: day, hour: hour, minute: minute
            ).date
        )
    }

    func testNothingIsAnnouncedWhileTheWindowIsUnscheduled() {
        XCTAssertNil(LifetimeFounderWindow.announcedEnd(end: nil, now: Date(), calendar: calendar))
    }

    func testTheLineShowsWellBeforeTheDeadline() throws {
        let end = try date(2026, 9, 12)
        let now = try date(2026, 8, 20, 14, 30)
        XCTAssertEqual(LifetimeFounderWindow.announcedEnd(end: end, now: now, calendar: calendar), end)
    }

    func testTheLineStillShowsAtTheStartOfTheNamedDay() throws {
        // "jusqu'au 12 septembre" promises the offer stands ON 12 September.
        let end = try date(2026, 9, 12)
        XCTAssertEqual(LifetimeFounderWindow.announcedEnd(end: end, now: end, calendar: calendar), end)
    }

    func testTheLineStillShowsInTheLastMinuteOfTheNamedDay() throws {
        // The boundary the constant's recipe makes easy to get wrong: it holds
        // the START of the named day, so comparing against it directly would
        // retire the line a full day early.
        let end = try date(2026, 9, 12)
        let now = try date(2026, 9, 12, 23, 59)
        XCTAssertEqual(LifetimeFounderWindow.announcedEnd(end: end, now: now, calendar: calendar), end)
    }

    func testTheLineRetiresAtMidnightAfterTheNamedDay() throws {
        let end = try date(2026, 9, 12)
        let now = try date(2026, 9, 13)
        XCTAssertNil(LifetimeFounderWindow.announcedEnd(end: end, now: now, calendar: calendar))
    }

    func testTheLineStaysRetiredLongAfterTheWindow() throws {
        let end = try date(2026, 9, 12)
        let now = try date(2027, 3, 1)
        XCTAssertNil(LifetimeFounderWindow.announcedEnd(end: end, now: now, calendar: calendar))
    }

    func testAnEndSetMidDayStillCoversThatWholeDay() throws {
        // The recipe yields midnight, but nothing stops a date carrying a time.
        // The window is a day, not an instant, so an afternoon value must not
        // retire the line that same evening.
        let end = try date(2026, 9, 12, 15, 0)
        let now = try date(2026, 9, 12, 22, 0)
        XCTAssertEqual(LifetimeFounderWindow.announcedEnd(end: end, now: now, calendar: calendar), end)
    }

    func testTheDayBoundaryFollowsTheCalendarAcrossADaylightSavingChange() throws {
        // 25 October 2026 is 25 hours long in Europe/Paris. Adding 86 400
        // seconds instead of one calendar day would retire the line an hour
        // before the day is over.
        let end = try date(2026, 10, 25)
        let now = try date(2026, 10, 25, 23, 30)
        XCTAssertEqual(LifetimeFounderWindow.announcedEnd(end: end, now: now, calendar: calendar), end)
    }
}
