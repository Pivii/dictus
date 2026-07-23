// DictusCore/Tests/DictusCoreTests/ProGatingTests.swift
// Tests for Pro feature gating resolution (ProFeature, ProConfig, FeatureGate,
// ProStatusManager) -- issue #55.
//
// These tests mutate the real App Group UserDefaults suite, so setUp/tearDown
// remove every Pro-related key to avoid polluting other tests or later runs.
// swift test builds in Debug, so the #if DEBUG force-free-tier paths are active.
import XCTest
@testable import DictusCore

final class ProGatingTests: XCTestCase {

    private var defaults: UserDefaults {
        AppGroup.defaults
    }

    private let proKeys = [
        SharedKeys.proActive,
        SharedKeys.smartModeEnabled,
        SharedKeys.historyEnabled,
        SharedKeys.vocabularyEnabled,
        SharedKeys.debugForceFreeTier,
    ]

    override func setUp() {
        super.setUp()
        proKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        proKeys.forEach { defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - ProFeature

    func testProFeatureHasExactlyThreeCases() {
        XCTAssertEqual(ProFeature.allCases.count, 3)
    }

    func testSettingsKeyMapping() {
        XCTAssertEqual(ProFeature.smartMode.settingsKey, SharedKeys.smartModeEnabled)
        XCTAssertEqual(ProFeature.history.settingsKey, SharedKeys.historyEnabled)
        XCTAssertEqual(ProFeature.vocabulary.settingsKey, SharedKeys.vocabularyEnabled)
    }

    func testDisplayMetadataNonEmpty() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.displayName.isEmpty)
            XCTAssertFalse(feature.icon.isEmpty)
            XCTAssertFalse(feature.paywallDescription.isEmpty)
            XCTAssertFalse(feature.paywallDescriptionFR.isEmpty)
        }
    }

    // MARK: - ProConfig

    /// Intentional guard: flipping isBeta to false (the App Store paywall
    /// release) must be a conscious decision that updates this test too.
    func testBetaPeriodIsActive() {
        XCTAssertTrue(ProConfig.isBeta)
    }

    func testEffectiveBetaMatchesIsBetaByDefault() {
        XCTAssertEqual(ProConfig.effectiveBeta, ProConfig.isBeta)
    }

    func testEffectiveBetaFalseWhenForceFreeTier() {
        defaults.set(true, forKey: SharedKeys.debugForceFreeTier)
        XCTAssertFalse(ProConfig.effectiveBeta)
    }

    // MARK: - FeatureGate

    func testAllFeaturesAvailableDuringBeta() {
        // registerDefaults hasn't run (no ProStatusManager init) -- set the
        // per-feature toggles explicitly; the assertion target is the
        // resolution logic, not the default registration.
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        XCTAssertTrue(FeatureGate.isProActive)
        for feature in ProFeature.allCases {
            XCTAssertTrue(FeatureGate.isAvailable(feature), "\(feature) should be available during beta")
        }
    }

    func testAllFeaturesLockedWhenForcedFreeTier() {
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        defaults.set(true, forKey: SharedKeys.debugForceFreeTier)
        XCTAssertFalse(FeatureGate.isProActive)
        for feature in ProFeature.allCases {
            XCTAssertFalse(FeatureGate.isAvailable(feature), "\(feature) should be locked on free tier")
        }
    }

    func testFeaturesAvailableAgainWhenProPurchasedUnderForcedFreeTier() {
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        defaults.set(true, forKey: SharedKeys.debugForceFreeTier)
        defaults.set(true, forKey: SharedKeys.proActive)
        XCTAssertTrue(FeatureGate.isProActive)
        for feature in ProFeature.allCases {
            XCTAssertTrue(FeatureGate.isAvailable(feature))
        }
    }

    func testDisabledToggleLocksOnlyThatFeature() {
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        defaults.set(false, forKey: ProFeature.smartMode.settingsKey)
        XCTAssertFalse(FeatureGate.isAvailable(.smartMode))
        XCTAssertTrue(FeatureGate.isAvailable(.history))
        XCTAssertTrue(FeatureGate.isAvailable(.vocabulary))
    }

    func testKeyboardGateMirrorsMainGate() {
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        for feature in ProFeature.allCases {
            XCTAssertEqual(
                FeatureGate.isKeyboardFeatureAvailable(feature),
                FeatureGate.isAvailable(feature)
            )
        }
    }

    // MARK: - ProStatusManager

    @MainActor
    func testInitDuringBetaIsProActive() {
        let manager = ProStatusManager()
        XCTAssertTrue(manager.isProActive)
    }

    @MainActor
    func testInitRegistersFeatureToggleDefaults() {
        _ = ProStatusManager()
        for feature in ProFeature.allCases {
            XCTAssertTrue(defaults.bool(forKey: feature.settingsKey),
                          "\(feature) toggle should default to true after init")
        }
    }

    @MainActor
    func testInitUnderForcedFreeTierReadsProActiveKey() {
        defaults.set(true, forKey: SharedKeys.debugForceFreeTier)
        XCTAssertFalse(ProStatusManager().isProActive)

        defaults.set(true, forKey: SharedKeys.proActive)
        XCTAssertTrue(ProStatusManager().isProActive)
    }

    @MainActor
    func testSetProActivePersistsToAppGroup() {
        let manager = ProStatusManager()
        manager.setProActive(true)
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.proActive))

        manager.setProActive(false)
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.proActive))
    }

    @MainActor
    func testSetProActiveFalseDuringBetaStaysActive() {
        let manager = ProStatusManager()
        manager.setProActive(false)
        // isProActive = active || ProConfig.isBeta -- beta keeps it unlocked.
        XCTAssertTrue(manager.isProActive)
    }

    @MainActor
    func testSetProActiveUnderForcedFreeTierTracksExactValue() {
        defaults.set(true, forKey: SharedKeys.debugForceFreeTier)
        let manager = ProStatusManager()
        manager.setProActive(true)
        XCTAssertTrue(manager.isProActive)
        manager.setProActive(false)
        XCTAssertFalse(manager.isProActive)
    }

    func testStaticReadMirrorsGatingMatrix() {
        // Beta, no keys set.
        XCTAssertTrue(ProStatusManager.isProActiveStatic)

        // Forced free tier, not purchased.
        defaults.set(true, forKey: SharedKeys.debugForceFreeTier)
        XCTAssertFalse(ProStatusManager.isProActiveStatic)

        // Forced free tier, purchased.
        defaults.set(true, forKey: SharedKeys.proActive)
        XCTAssertTrue(ProStatusManager.isProActiveStatic)
    }

    // MARK: - LogEvent.subscriptionError

    func testSubscriptionErrorEventMetadata() {
        let event = LogEvent.subscriptionError(action: "purchase", error: "cancelled")
        XCTAssertEqual(event.subsystem, .lifecycle)
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.name, "subscriptionError")
        XCTAssertEqual(event.message, "action=purchase error=cancelled")
    }
}
