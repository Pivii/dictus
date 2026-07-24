// DictusCore/Tests/DictusCoreTests/ProGatingTests.swift
// Tests for Pro feature gating resolution (ProFeature, FeatureGate,
// ProStatusManager) -- issue #55.
//
// Pro status is driven entirely by the StoreKit-backed proActive flag in
// App Group UserDefaults: no flag means free tier.
//
// These tests mutate the real App Group suite, so setUp/tearDown remove
// every Pro-related key to avoid polluting other tests or later runs.
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
        SharedKeys.vocabularyEnabled
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

    // MARK: - FeatureGate

    func testFreeTierByDefault() {
        // No proActive flag, no purchase: everything locked.
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        XCTAssertFalse(FeatureGate.isProActive)
        for feature in ProFeature.allCases {
            XCTAssertFalse(FeatureGate.isAvailable(feature), "\(feature) should be locked on free tier")
        }
    }

    func testAllFeaturesAvailableWhenPro() {
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        defaults.set(true, forKey: SharedKeys.proActive)
        XCTAssertTrue(FeatureGate.isProActive)
        for feature in ProFeature.allCases {
            XCTAssertTrue(FeatureGate.isAvailable(feature), "\(feature) should be available when Pro")
        }
    }

    func testDisabledToggleLocksOnlyThatFeature() {
        defaults.set(true, forKey: SharedKeys.proActive)
        for feature in ProFeature.allCases {
            defaults.set(true, forKey: feature.settingsKey)
        }
        defaults.set(false, forKey: ProFeature.smartMode.settingsKey)
        XCTAssertFalse(FeatureGate.isAvailable(.smartMode))
        XCTAssertTrue(FeatureGate.isAvailable(.history))
        XCTAssertTrue(FeatureGate.isAvailable(.vocabulary))
    }

    func testKeyboardGateMirrorsMainGate() {
        defaults.set(true, forKey: SharedKeys.proActive)
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
    func testInitDefaultsToFreeTier() {
        XCTAssertFalse(ProStatusManager().isProActive)
    }

    @MainActor
    func testInitReadsProActiveKey() {
        defaults.set(true, forKey: SharedKeys.proActive)
        XCTAssertTrue(ProStatusManager().isProActive)
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
    func testSetProActivePersistsToAppGroup() {
        let manager = ProStatusManager()
        manager.setProActive(true)
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.proActive))
        XCTAssertTrue(manager.isProActive)

        manager.setProActive(false)
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.proActive))
        XCTAssertFalse(manager.isProActive)
    }

    func testStaticReadMirrorsProActiveKey() {
        XCTAssertFalse(ProStatusManager.isProActiveStatic)
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
