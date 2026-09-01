// DictusCore/Tests/DictusCoreTests/PremiumFlagsDebugOverrideTests.swift
// The debug-only entitlement override, and the one place it is read (issue #460).
//
// The whole suite is `#if DEBUG` because the thing it tests is: in a Release build the
// property does not exist, and neither does its key. Tests only ever run in Debug, so
// this costs nothing and states the boundary where it can be read.
//
// These tests mutate the real App Group suite, so setUp/tearDown remove both keys.
#if DEBUG
import XCTest
@testable import DictusCore

final class PremiumFlagsDebugOverrideTests: XCTestCase {

    private var defaults: UserDefaults { AppGroup.defaults }

    private let keys = [SharedKeys.debugProEntitlementForced, SharedKeys.proActive]

    override func setUp() {
        super.setUp()
        keys.forEach { defaults.removeObject(forKey: $0) }
        // The per-feature toggles are half of `FeatureGate.isAvailable`, and another
        // suite in this process may have removed them. Seeding is what happens at every
        // app launch and is idempotent, so this is the state a device is actually in
        // rather than a fixture.
        ProStatusManager.seedFeatureTogglesIfNeeded()
    }

    override func tearDown() {
        keys.forEach { defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testTheOverrideIsOffUntilSomebodyTurnsItOn() {
        XCTAssertFalse(PremiumFlags.debugProEntitlementForced)
        XCTAssertFalse(FeatureGate.isProActive)
    }

    /// One source of truth: the flag is read in `ProStatusManager.isProActiveStatic`, so
    /// every gate downstream of it changes together. `FeatureGate` is the one the Smart
    /// Mode fan reaches through, and the keyboard's toolbar reads the static directly.
    func testForcingEntitlementReachesEveryGateThroughOneRead() {
        PremiumFlags.debugProEntitlementForced = true

        XCTAssertTrue(ProStatusManager.isProActiveStatic)
        XCTAssertTrue(FeatureGate.isProActive)
        XCTAssertTrue(FeatureGate.isKeyboardFeatureAvailable(.smartMode))
    }

    /// The point of it: the surface #460 hides comes back for the maintainer, without
    /// the paywall coming back with it. The flag grants an entitlement; it does not put
    /// anything on sale, and the fan it reopens is the ordinary one rather than the
    /// upgrade one — asserted against a hidden paywall so nobody later "fixes" this
    /// into a paywall switch.
    ///
    /// `paywallVisible` is passed as a literal and never read from `PremiumFlags` here:
    /// this is a statement about the override, and reading the shipped constant would
    /// turn it into a test that fails on the day the paywall legitimately opens.
    func testForcingEntitlementReopensTheFanWithoutOpeningThePaywall() {
        PremiumFlags.debugProEntitlementForced = true
        ProStatusManager.seedFeatureTogglesIfNeeded()

        XCTAssertEqual(SmartModeEntitlement.current, .entitled)
        XCTAssertEqual(
            SmartModeSurface.fanEntryPoint(
                reason: SmartModeEntitlement.current.unavailableReason,
                paywallVisible: false
            ),
            .open
        )
    }

    /// Turning it off puts the user back where they were, with nothing left behind.
    func testTurningItOffRestoresTheStoredStatus() {
        PremiumFlags.debugProEntitlementForced = true
        PremiumFlags.debugProEntitlementForced = false

        XCTAssertFalse(FeatureGate.isProActive)
        XCTAssertEqual(SmartModeEntitlement.current, .notSubscribed)
    }
}
#endif
