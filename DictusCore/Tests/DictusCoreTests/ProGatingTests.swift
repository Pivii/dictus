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

    /// What `key` looks like to a process that never called `register(defaults:)` --
    /// which is to say, to DictusKeyboard (#401).
    ///
    /// `persistentDomain(forName:)` returns only values that were actually stored, so a
    /// registered-but-unpersisted default is invisible to it, exactly as it is invisible
    /// to the extension. Reading through `AppGroup.defaults` cannot make that
    /// distinction: registration is process-wide, so once anything in this process has
    /// registered a key, every `UserDefaults` instance on the suite reports it.
    private func valueVisibleToAnotherProcess(forKey key: String) -> Bool? {
        UserDefaults.standard.persistentDomain(forName: AppGroup.identifier)?[key] as? Bool
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
    func testInitSeedsFeatureTogglesIntoAppGroupStorage() {
        _ = ProStatusManager()
        for feature in ProFeature.allCases {
            XCTAssertTrue(defaults.bool(forKey: feature.settingsKey),
                          "\(feature) toggle should default to true after init")
            XCTAssertEqual(valueVisibleToAnotherProcess(forKey: feature.settingsKey), true,
                           "\(feature) toggle must be stored, not merely registered: the "
                           + "keyboard extension never runs this init (#401)")
        }
    }

    // MARK: - Feature toggle seeding (#401)

    /// The regression test for #401, and the case the rest of this file does not cover:
    /// every other test writes the feature keys explicitly, which is precisely the state
    /// the bug does not occur in.
    ///
    /// A subscriber who never opens the Settings toggle. The app launches, the keyboard
    /// reads the key with no registration of its own, and must get the same `true`.
    @MainActor
    func testUnToggledFeatureReachesTheKeyboardAfterAppLaunch() {
        defaults.set(true, forKey: SharedKeys.proActive)

        // The app launching. Nothing touches the Smart Mode toggle.
        _ = ProStatusManager()

        XCTAssertEqual(valueVisibleToAnotherProcess(forKey: SharedKeys.smartModeEnabled), true,
                       "the keyboard reads storage, not this process's registration domain")
        XCTAssertTrue(FeatureGate.isKeyboardFeatureAvailable(.smartMode),
                      "a subscriber who never opened the toggle must get an unlocked fan")
    }

    /// Criterion: the keyboard and DictusApp return the same answer for the same key,
    /// with no registration in the keyboard process.
    @MainActor
    func testAppAndKeyboardAgreeOnUnToggledFeatures() {
        defaults.set(true, forKey: SharedKeys.proActive)
        _ = ProStatusManager()

        for feature in ProFeature.allCases {
            XCTAssertEqual(valueVisibleToAnotherProcess(forKey: feature.settingsKey) ?? false,
                           FeatureGate.isAvailable(feature),
                           "\(feature) reads differently in the two processes")
        }
    }

    /// Seed, never assign. `SubscriptionManager.updateProStatus()` runs on every launch,
    /// so this is the launch-after-launch case: a feature the user deliberately turned
    /// off must stay off.
    @MainActor
    func testSeedingNeverRevivesADeliberatelyDisabledFeature() {
        defaults.set(true, forKey: SharedKeys.proActive)
        _ = ProStatusManager()

        // The user turns Smart Mode off in Settings.
        defaults.set(false, forKey: ProFeature.smartMode.settingsKey)

        // Two more launches, each with its entitlement refresh.
        _ = ProStatusManager()
        _ = ProStatusManager()

        XCTAssertEqual(valueVisibleToAnotherProcess(forKey: SharedKeys.smartModeEnabled), false)
        XCTAssertFalse(FeatureGate.isAvailable(.smartMode))
        XCTAssertFalse(FeatureGate.isKeyboardFeatureAvailable(.smartMode))
        // The features they left alone are untouched.
        XCTAssertTrue(FeatureGate.isAvailable(.history))
        XCTAssertTrue(FeatureGate.isAvailable(.vocabulary))
    }

    /// The seeding is callable on its own -- the keyboard never constructs the manager,
    /// so the migration must not be welded to the initialiser's other work.
    func testSeedingIsIdempotent() {
        ProStatusManager.seedFeatureTogglesIfNeeded()
        defaults.set(false, forKey: ProFeature.vocabulary.settingsKey)
        ProStatusManager.seedFeatureTogglesIfNeeded()

        XCTAssertEqual(valueVisibleToAnotherProcess(forKey: SharedKeys.vocabularyEnabled), false)
        XCTAssertEqual(valueVisibleToAnotherProcess(forKey: SharedKeys.smartModeEnabled), true)
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
