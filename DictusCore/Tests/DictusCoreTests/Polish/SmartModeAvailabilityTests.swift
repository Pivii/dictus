// DictusCore/Tests/DictusCoreTests/Polish/SmartModeAvailabilityTests.swift
// The arming policy: fail early, before the user speaks (issue #79).
import XCTest
@testable import DictusCore

final class SmartModeAvailabilityTests: XCTestCase {

    private func armability(_ state: PolishAvailabilityState,
                            refusing: Bool = false) -> SmartModeArmability {
        SmartModeAvailability.armability(engineState: state, engineIsRefusing: refusing)
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
        XCTAssertFalse(SmartModeUnavailableReason.other("x").isRecoverable)
    }

    func testOtherCarriesApplesOwnWordingIntoTheSlug() {
        XCTAssertEqual(SmartModeUnavailableReason.other("newThing").slug, "other:newThing")
    }
}
