// DictusCore/Tests/DictusCoreTests/Polish/SmartModeSurfaceTests.swift
// While the paywall is hidden the Smart Mode surface is absent, not locked (issue #460).
import XCTest
@testable import DictusCore

final class SmartModeSurfaceTests: XCTestCase {

    /// Every reason the fan can be refused for, so the tables below are exhaustive by
    /// construction rather than by whoever last edited them.
    private static let everyReason: [SmartModeUnavailableReason] = [
        .appleIntelligenceNotEnabled,
        .modelNotReady,
        .deviceNotEligible,
        .osTooOld,
        .sdkMissing,
        .engineRefusing,
        .other("somethingNew"),
        .notSubscribed,
        .switchedOff
    ]

    // MARK: - The entry point

    /// The defect, stated as a test: with nothing to sell, the long press opens nothing.
    func testTheFanIsHiddenForANonSubscriberWhileThePaywallIsDown() {
        XCTAssertEqual(
            SmartModeSurface.fanEntryPoint(reason: .notSubscribed, paywallVisible: false),
            .hidden
        )
    }

    /// A gate, not a deletion. Raising the flag restores #404's fan exactly, and this
    /// is the assertion that says so.
    func testRaisingTheFlagRestoresTheUpgradeFan() {
        XCTAssertEqual(
            SmartModeSurface.fanEntryPoint(reason: .notSubscribed, paywallVisible: true),
            .upgrade
        )
    }

    /// The contract's first settled question. A subscriber who switched Smart Modes off
    /// is entitled; the flag is about not advertising a product that cannot be bought,
    /// and it is not about them. What #423 gave them is untouched, both ways up.
    func testASubscriberWhoSwitchedSmartModesOffKeepsTheirFan() {
        XCTAssertEqual(
            SmartModeSurface.fanEntryPoint(reason: .switchedOff, paywallVisible: false), .open
        )
        XCTAssertEqual(
            SmartModeSurface.fanEntryPoint(reason: .switchedOff, paywallVisible: true), .open
        )
        XCTAssertFalse(SmartModeSurface.sellsPro(reason: .switchedOff, paywallVisible: true))
        XCTAssertFalse(SmartModeSurface.sellsPro(reason: .switchedOff, paywallVisible: false))
    }

    /// Apple Intelligence being off has nothing to do with a subscription. Hiding those
    /// fans would replace an actionable sentence with silence, on a device where the
    /// user could fix it in one trip to Settings.
    func testOnlyTheSubscriptionReasonIsEverHidden() {
        for reason in Self.everyReason where reason != .notSubscribed {
            XCTAssertEqual(
                SmartModeSurface.fanEntryPoint(reason: reason, paywallVisible: false), .open,
                "\(reason.slug) should still open its fan while the paywall is hidden"
            )
            XCTAssertEqual(
                SmartModeSurface.fanEntryPoint(reason: reason, paywallVisible: true), .open,
                "\(reason.slug) should open an ordinary fan, not an upgrade one"
            )
        }
    }

    /// An armable fan is an ordinary fan whatever the flag says: there is no reason to
    /// refuse and nothing to sell.
    func testNoReasonMeansAnOrdinaryFan() {
        XCTAssertEqual(SmartModeSurface.fanEntryPoint(reason: nil, paywallVisible: false), .open)
        XCTAssertEqual(SmartModeSurface.fanEntryPoint(reason: nil, paywallVisible: true), .open)
    }

    // MARK: - What may be said

    /// The acceptance criterion, at the point every "Dictus Pro" sentence in the
    /// keyboard now passes through: with the flag down, nothing sells Pro to anyone.
    func testNothingSellsProWhileThePaywallIsHidden() {
        for reason in Self.everyReason {
            XCTAssertFalse(
                SmartModeSurface.sellsPro(reason: reason, paywallVisible: false),
                "\(reason.slug) advertises Dictus Pro while the paywall is hidden"
            )
        }
        XCTAssertFalse(SmartModeSurface.sellsPro(reason: nil, paywallVisible: false))
    }

    /// And with the flag up, exactly one reason does — the same one #404's row is for.
    func testOnlyTheUnsubscribedUserIsSoldAnything() {
        for reason in Self.everyReason {
            XCTAssertEqual(
                SmartModeSurface.sellsPro(reason: reason, paywallVisible: true),
                reason == .notSubscribed,
                "\(reason.slug) disagrees with #404 about who is being sold a subscription"
            )
        }
        XCTAssertFalse(SmartModeSurface.sellsPro(reason: nil, paywallVisible: true))
    }

    /// The two questions are one answer seen twice, and the fan reads them as such: the
    /// row it draws and the sentence under it must never disagree about whether a
    /// subscription is on offer.
    func testTheUpgradeFanIsExactlyTheFanThatSellsPro() {
        for reason in Self.everyReason {
            for visible in [true, false] {
                let entryPoint = SmartModeSurface.fanEntryPoint(
                    reason: reason, paywallVisible: visible
                )
                XCTAssertEqual(
                    entryPoint == .upgrade,
                    SmartModeSurface.sellsPro(reason: reason, paywallVisible: visible),
                    "\(reason.slug)/paywallVisible=\(visible): the row and the sentence disagree"
                )
            }
        }
    }
}
