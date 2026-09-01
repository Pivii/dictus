// DictusCore/Tests/DictusCoreTests/Polish/SmartModeDiscoveryTests.swift
// When the toolbar still teaches the long-press gesture (issues #79, #460).
//
// These tests mutate the real App Group suite, so setUp/tearDown remove the key.
import XCTest
@testable import DictusCore

final class SmartModeDiscoveryTests: XCTestCase {

    private var defaults: UserDefaults { AppGroup.defaults }

    override func setUp() {
        super.setUp()
        defaults.removeObject(forKey: SharedKeys.smartModeGestureUsed)
    }

    override func tearDown() {
        defaults.removeObject(forKey: SharedKeys.smartModeGestureUsed)
        super.tearDown()
    }

    func testTheHintIsOfferedToSomeoneWhoHasNeverUsedTheGesture() {
        XCTAssertTrue(SmartModeDiscovery.offersHint(deviceCanRunModes: true, fanIsReachable: true))
    }

    /// It taught what it had to teach.
    func testTheHintRetiresOnceTheGestureHasBeenUsed() {
        SmartModeDiscovery.noteGestureUsed()
        XCTAssertTrue(SmartModeDiscovery.hasUsedGesture)
        XCTAssertFalse(SmartModeDiscovery.offersHint(deviceCanRunModes: true, fanIsReachable: true))
    }

    /// Most of the installed base cannot run Smart Modes at all, and teaching them a
    /// gesture whose every outcome is a disabled row is worse than silence.
    func testTheHintNeverAppearsOnADeviceThatCannotRunModes() {
        XCTAssertFalse(SmartModeDiscovery.offersHint(deviceCanRunModes: false, fanIsReachable: true))
    }

    /// #460: with the paywall hidden, the long press opens nothing. An instruction for a
    /// gesture with no outcome is worse than the advertisement the fan used to show —
    /// it is an instruction that appears not to work.
    func testTheHintIsWithheldWhenTheFanCannotBeOpened() {
        XCTAssertFalse(SmartModeDiscovery.offersHint(deviceCanRunModes: true, fanIsReachable: false))
    }
}
