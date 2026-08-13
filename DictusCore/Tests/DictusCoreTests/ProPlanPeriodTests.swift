// DictusCore/Tests/DictusCoreTests/ProPlanPeriodTests.swift
// A price may only claim a period it actually has (#350).
//
// The rule guards against a false price rather than a vague one: "39,99 €/mois"
// on a six-month plan reads as a third of what it charges.
import XCTest
@testable import DictusCore

final class ProPlanPeriodTests: XCTestCase {

    func testTheTwoPlansDictusSellsAreLabelled() {
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .month, value: 1), .monthly)
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .year, value: 1), .yearly)
    }

    func testANonConsumableCarriesNoPeriod() {
        // No subscription at all — the lifetime. `value` is meaningless here
        // and must not be able to conjure a suffix.
        XCTAssertEqual(ProPlanPeriod.resolve(unit: nil, value: 0), .unlabelled)
        XCTAssertEqual(ProPlanPeriod.resolve(unit: nil, value: 1), .unlabelled)
    }

    func testAMultiMonthPlanIsNotLabelledPerMonth() {
        // App Store Connect sells 2, 3 and 6 month durations. Labelling any of
        // them "/mois" would advertise a fraction of the real charge.
        for months in [2, 3, 6] {
            XCTAssertEqual(
                ProPlanPeriod.resolve(unit: .month, value: months),
                .unlabelled,
                "a \(months)-month plan must not be labelled per month"
            )
        }
    }

    func testAMultiYearPlanIsNotLabelledPerYear() {
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .year, value: 2), .unlabelled)
    }

    func testUnitsDictusDoesNotSellCarryNoPeriod() {
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .day, value: 1), .unlabelled)
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .week, value: 1), .unlabelled)
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .unknown, value: 1), .unlabelled)
    }

    func testAZeroOrNegativeLengthCarriesNoPeriod() {
        // Not reachable through StoreKit, but the rule must not depend on that.
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .month, value: 0), .unlabelled)
        XCTAssertEqual(ProPlanPeriod.resolve(unit: .year, value: -1), .unlabelled)
    }
}
