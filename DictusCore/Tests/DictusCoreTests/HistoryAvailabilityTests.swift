// DictusCore/Tests/DictusCoreTests/HistoryAvailabilityTests.swift
// The history's Pro gate (#70, corrected 2026-08-28).
//
// WHY these matter more than the usual policy test: nobody can be a subscriber
// until #215 opens the paywall, so the entitled direction of this feature cannot be
// reached on a device or on a simulator at all. These are the only place both
// answers are exercised before the paywall exists.
import XCTest
@testable import DictusCore

final class HistoryAvailabilityTests: XCTestCase {

    // MARK: - The entry point

    func testASubscriberGetsTheHistory() {
        XCTAssertEqual(
            HistoryAvailability.entryPoint(isEntitled: true, paywallVisible: false), .open
        )
        XCTAssertEqual(
            HistoryAvailability.entryPoint(isEntitled: true, paywallVisible: true), .open
        )
    }

    func testAnUnreachablePaywallHidesTheEntryPointEntirely() {
        XCTAssertEqual(
            HistoryAvailability.entryPoint(isEntitled: false, paywallVisible: false), .hidden,
            "#236: while the paywall is hidden the app must look like there is no "
                + "subscription at all. A lock leading nowhere is the one place that breaks it."
        )
    }

    func testAReachablePaywallMarksTheEntryPointRatherThanRemovingIt() {
        XCTAssertEqual(
            HistoryAvailability.entryPoint(isEntitled: false, paywallVisible: true), .locked,
            "#395 marks a locked feature rather than dropping it, so it can be "
                + "screenshotted for review and found by someone who subscribes."
        )
    }

    func testTheEntryPointIsHiddenTodayForEveryoneWhoIsNotEntitled() {
        // Pins the shipping state rather than the policy: `paywallVisible` is false,
        // so today nobody sees a lock. When #215 flips it this test is what says the
        // locked branch has started being reachable.
        XCTAssertFalse(PremiumFlags.paywallVisible)
        XCTAssertEqual(
            HistoryAvailability.entryPoint(isEntitled: false,
                                           paywallVisible: PremiumFlags.paywallVisible),
            .hidden
        )
    }

    // MARK: - The way out stays open

    func testALapsedSubscriberCanStillReachTheirData() {
        XCTAssertTrue(
            HistoryAvailability.clearRowIsVisible(isEntitled: false, hasSavedRecords: true),
            "A lapsed entitlement must never stand between the user and deleting a "
                + "plaintext record of everything they have dictated."
        )
    }

    func testASubscriberSeesTheRowEvenWithNothingSaved() {
        XCTAssertTrue(
            HistoryAvailability.clearRowIsVisible(isEntitled: true, hasSavedRecords: false)
        )
    }

    func testTheRowIsHiddenForSomeoneWhoNeverHadTheFeature() {
        XCTAssertFalse(
            HistoryAvailability.clearRowIsVisible(isEntitled: false, hasSavedRecords: false),
            "Nothing to delete and no entitlement: the row would only advertise a "
                + "feature #236 says must not be visible yet."
        )
    }

    // MARK: - Which entitlement is being asked about

    func testTheGateIsTheHistoryFeatureAndNotProStatusAlone() {
        // `isEntitled` goes through `FeatureGate.isAvailable(.history)`, so a
        // subscriber who switched History off in Settings is honoured — the same
        // choice `SmartModeAvailability.isEntitled` makes. This pins the key the
        // toggle and the gate share; a rename that broke it would otherwise leave
        // the gate reading a key nothing writes.
        XCTAssertEqual(ProFeature.history.settingsKey, SharedKeys.historyEnabled)
    }
}
