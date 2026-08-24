// DictusCore/Tests/DictusCoreTests/Polish/SmartModeAvailabilityTests.swift
// The arming policy: fail early, before the user speaks (issue #79).
import XCTest
@testable import DictusCore

final class SmartModeAvailabilityTests: XCTestCase {

    private func armability(_ state: PolishAvailabilityState,
                            refusing: Bool = false,
                            entitled: Bool = true) -> SmartModeArmability {
        SmartModeAvailability.armability(
            engineState: state, engineIsRefusing: refusing, isEntitled: entitled
        )
    }

    func testModesAreArmableOnlyWhenAppleFoundationModelsIsAvailable() {
        XCTAssertEqual(armability(.available), .armable)
    }

    /// Every unavailability Apple can report has to come back as a reason the user
    /// can read, never as a silent refusal after they have already spoken.
    func testEveryUnavailableStateProducesAReadableReason() {
        let states: [PolishAvailabilityState] = [
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .deviceNotEligible,
            .osTooOld,
            .sdkMissing,
            .other("somethingNew")
        ]
        for state in states {
            let result = armability(state)
            XCTAssertFalse(result.isArmable, "\(state) should not be armable")
            guard let reason = result.reason else {
                return XCTFail("\(state) produced no reason")
            }
            XCTAssertFalse(reason.slug.isEmpty)
            XCTAssertFalse(reason.englishDescription.isEmpty)
        }
    }

    func testEachStateMapsToItsOwnReason() {
        XCTAssertEqual(armability(.appleIntelligenceNotEnabled).reason, .appleIntelligenceNotEnabled)
        XCTAssertEqual(armability(.modelNotReady).reason, .modelNotReady)
        XCTAssertEqual(armability(.deviceNotEligible).reason, .deviceNotEligible)
        XCTAssertEqual(armability(.osTooOld).reason, .osTooOld)
        XCTAssertEqual(armability(.sdkMissing).reason, .sdkMissing)
        XCTAssertEqual(armability(.other("x")).reason, .other("x"))
    }

    /// The #315 latch refuses arming, but only on a device that could otherwise run
    /// the engine — a device that cannot is told that, not told to wait.
    func testARefusingEngineBlocksArmingOnlyWhenTheDeviceIsOtherwiseCapable() {
        XCTAssertEqual(armability(.available, refusing: true).reason, .engineRefusing)
        XCTAssertEqual(armability(.deviceNotEligible, refusing: true).reason, .deviceNotEligible)
    }

    func testRecoverableReasonsAreTheOnesTheUserCanDoSomethingAbout() {
        XCTAssertTrue(SmartModeUnavailableReason.appleIntelligenceNotEnabled.isRecoverable)
        XCTAssertTrue(SmartModeUnavailableReason.modelNotReady.isRecoverable)
        XCTAssertTrue(SmartModeUnavailableReason.engineRefusing.isRecoverable)
        XCTAssertFalse(SmartModeUnavailableReason.deviceNotEligible.isRecoverable)
        XCTAssertFalse(SmartModeUnavailableReason.osTooOld.isRecoverable)
        XCTAssertFalse(SmartModeUnavailableReason.sdkMissing.isRecoverable)
    }

    /// `.other` is where every reason this build does not recognise lands, including
    /// `@unknown default` — a state Apple adds after we ship. It used to be
    /// classified definitive, which meant `resolveArmedMode()` would disarm on it:
    /// one transient future state and the user's setting is gone for good, with
    /// nothing to restore it when the condition lifts. Found reviewing PR #389.
    func testAnUnrecognisedReasonNeverClearsTheUsersArmedMode() {
        XCTAssertTrue(SmartModeUnavailableReason.other("someFutureAppleState").isRecoverable)
        XCTAssertTrue(SmartModeUnavailableReason.other("unknown").isRecoverable)
    }

    func testOtherCarriesApplesOwnWordingIntoTheSlug() {
        XCTAssertEqual(SmartModeUnavailableReason.other("newThing").slug, "other:newThing")
    }

    // MARK: - Pro entitlement (#392)

    func testACapableDeviceWithoutASubscriptionIsNotArmable() {
        XCTAssertEqual(armability(.available, entitled: false).reason, .notSubscribed)
    }

    /// The ordering that keeps the paywall honest (#79): a device that cannot run
    /// the engine is told *that*, not sold a subscription it could never use. Getting
    /// this backwards is the misleading-metadata rejection #79 warns about.
    func testCapabilityIsNamedBeforeEntitlement() {
        for state in [PolishAvailabilityState.deviceNotEligible, .osTooOld, .sdkMissing] {
            XCTAssertEqual(
                armability(state, entitled: false).reason,
                SmartModeUnavailableReason(matching: state),
                "\(state) must name the capability, not the subscription"
            )
        }
    }

    /// A lapsed subscription must not erase which mode the user armed — they
    /// resubscribe and it is still there. That is `isRecoverable`'s whole job in
    /// `SmartModeStore.resolveArmedMode()`.
    func testNotSubscribedIsRecoverableSoItNeverDisarms() {
        XCTAssertTrue(SmartModeUnavailableReason.notSubscribed.isRecoverable)
    }

    func testNotSubscribedHasItsOwnSlugAndSentence() {
        XCTAssertEqual(SmartModeUnavailableReason.notSubscribed.slug, "notSubscribed")
        XCTAssertNotEqual(
            SmartModeUnavailableReason.notSubscribed.englishDescription,
            SmartModeUnavailableReason.deviceNotEligible.englishDescription,
            "\"not entitled\" and \"not capable\" are two different people"
        )
    }

    // MARK: - Capability, as the paywall asks it

    /// `deviceIsCapable` answers a different question from `deviceCanRunModes`: an
    /// iPhone 15 Pro with Apple Intelligence switched off is capable, an iPhone 13 is
    /// not. The paywall needs the first; the disarm rule needs the second.
    func testCapabilitySplitsOnDefinitiveReasonsOnly() {
        let capable: [PolishAvailabilityState] = [
            .available, .appleIntelligenceNotEnabled, .modelNotReady, .other("new")
        ]
        for state in capable {
            let result = armability(state)
            let isCapable = result.reason.map(\.isRecoverable) ?? true
            XCTAssertTrue(isCapable, "\(state) describes a configuration, not hardware")
        }
        for state in [PolishAvailabilityState.deviceNotEligible, .osTooOld, .sdkMissing] {
            let result = armability(state)
            XCTAssertEqual(result.reason?.isRecoverable, false, "\(state) is definitive")
        }
    }

    /// Only Smart Mode is gated on the hardware, and the other two Pro features must
    /// stay sellable on every device — that is what makes #79's "sell Pro to
    /// everyone" decision work.
    func testOnlySmartModeRequiresAppleIntelligence() {
        XCTAssertTrue(ProFeature.smartMode.requiresAppleIntelligence)
        XCTAssertFalse(ProFeature.history.requiresAppleIntelligence)
        XCTAssertFalse(ProFeature.vocabulary.requiresAppleIntelligence)

        XCTAssertTrue(ProFeature.history.isSupportedByThisDevice)
        XCTAssertTrue(ProFeature.vocabulary.isSupportedByThisDevice)
        XCTAssertNil(ProFeature.history.unsupportedNotice)
    }

    /// The notice and the capability answer cannot disagree: a card marked
    /// unsupported on a supported device, or the reverse, is the defect this whole
    /// filter exists to prevent.
    func testTheNoticeAppearsExactlyWhenTheFeatureIsUnsupported() {
        for feature in ProFeature.allCases {
            XCTAssertEqual(
                feature.unsupportedNotice == nil,
                feature.isSupportedByThisDevice,
                "\(feature.rawValue)'s notice disagrees with its capability"
            )
        }
    }
}

private extension SmartModeUnavailableReason {
    /// The reason a given engine state maps to, for the ordering test above.
    init(matching state: PolishAvailabilityState) {
        switch state {
        case .deviceNotEligible: self = .deviceNotEligible
        case .osTooOld: self = .osTooOld
        case .sdkMissing: self = .sdkMissing
        case .appleIntelligenceNotEnabled: self = .appleIntelligenceNotEnabled
        case .modelNotReady: self = .modelNotReady
        case .other(let detail): self = .other(detail)
        case .available: self = .notSubscribed
        }
    }
}
