// DictusCore/Tests/DictusCoreTests/Polish/SmartModeStoreTests.swift
// The armed mode and the pinned list, in the App Group (issue #79).
//
// These tests mutate the real App Group suite, so setUp/tearDown remove both keys.
import XCTest
@testable import DictusCore

final class SmartModeStoreTests: XCTestCase {

    private var defaults: UserDefaults { AppGroup.defaults }

    private let keys = [SharedKeys.smartModeArmed, SharedKeys.smartModePinned]

    override func setUp() {
        super.setUp()
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Arming

    func testNothingIsArmedByDefault() {
        XCTAssertNil(SmartModeStore.armedIdentifier)
        XCTAssertNil(SmartModeStore.armedMode)
    }

    /// The mode is sticky: what is written is what a later read finds, which is the
    /// whole of "survives keyboard and app restarts" that this layer can promise.
    func testArmingPersistsTheIdentifierAndResolvesBackToTheRecord() {
        SmartModeStore.arm(SmartModeCatalogue.notes)
        XCTAssertEqual(SmartModeStore.armedIdentifier, "notes")
        XCTAssertEqual(SmartModeStore.armedMode?.id, "notes")
        XCTAssertEqual(SmartModeStore.armedMode?.contract.outputLanguage, .sameAsInput)
    }

    func testArmingReplacesRatherThanStacks() {
        SmartModeStore.arm(SmartModeCatalogue.notes)
        SmartModeStore.arm(SmartModeCatalogue.translate(to: .english))
        XCTAssertEqual(SmartModeStore.armedIdentifier, "translate.en")
    }

    /// Selecting Normal clears it. Normal is the absence of a mode, not a mode.
    func testDisarmingClearsTheStoredIdentifier() {
        SmartModeStore.arm(SmartModeCatalogue.translate(to: .german))
        SmartModeStore.disarm()
        XCTAssertNil(SmartModeStore.armedIdentifier)
        XCTAssertNil(SmartModeStore.armedMode)
        XCTAssertNil(defaults.string(forKey: SharedKeys.smartModeArmed))
    }

    /// A read that draws a screen must not change what is stored.
    func testArmedModeDoesNotDisarmOnAnUnknownIdentifier() {
        defaults.set("translate.klingon", forKey: SharedKeys.smartModeArmed)
        XCTAssertNil(SmartModeStore.armedMode)
        XCTAssertEqual(SmartModeStore.armedIdentifier, "translate.klingon")
    }

    /// A read that starts a dictation does: the stored state has to match the Normal
    /// the user is actually getting.
    func testResolveArmedModeClearsAnIdentifierThisBuildDoesNotKnow() {
        defaults.set("translate.klingon", forKey: SharedKeys.smartModeArmed)
        XCTAssertNil(SmartModeStore.resolveArmedMode())
        XCTAssertNil(SmartModeStore.armedIdentifier)
    }

    func testResolveArmedModeIsANoOpWhenNothingIsArmed() {
        XCTAssertNil(SmartModeStore.resolveArmedMode())
        XCTAssertNil(SmartModeStore.armedIdentifier)
    }

    // MARK: - Pinning

    /// Absent means "never chosen", which seeds; an empty array is a real choice.
    func testPinnedSeedsWhenTheUserHasNeverChosen() {
        XCTAssertEqual(SmartModeStore.pinnedIdentifiers, SmartModeCatalogue.defaultPinnedIdentifiers)
    }

    func testAnEmptyPinnedListIsHonouredRatherThanReseeded() {
        SmartModeStore.setPinned([])
        XCTAssertEqual(SmartModeStore.pinnedIdentifiers, [])
        XCTAssertTrue(SmartModeCatalogue.pinnedModes.isEmpty)
    }

    func testPinnedOrderIsPreserved() {
        SmartModeStore.setPinned(["translate.de", "notes"])
        XCTAssertEqual(SmartModeStore.pinnedIdentifiers, ["translate.de", "notes"])
    }

    func testPinnedIsCappedAtWhatTheFanCanDraw() {
        let everything = SmartModeCatalogue.builtIns.map(\.id)
        XCTAssertGreaterThan(everything.count, SmartModeCatalogue.maximumPinnedModes)
        SmartModeStore.setPinned(everything)
        XCTAssertEqual(
            SmartModeStore.pinnedIdentifiers.count, SmartModeCatalogue.maximumPinnedModes
        )
    }

    func testCatalogueStampsThePinnedFlagFromTheStore() {
        SmartModeStore.setPinned(["notes"])
        let notes = SmartModeCatalogue.all.first { $0.id == "notes" }
        let translate = SmartModeCatalogue.all.first { $0.id == "translate.en" }
        XCTAssertEqual(notes?.isPinned, true)
        XCTAssertEqual(translate?.isPinned, false)
        XCTAssertEqual(SmartModeCatalogue.pinnedModes.map(\.id), ["notes"])
    }

    func testResetPinnedReturnsToTheSeed() {
        SmartModeStore.setPinned([])
        SmartModeStore.resetPinned()
        XCTAssertEqual(SmartModeStore.pinnedIdentifiers, SmartModeCatalogue.defaultPinnedIdentifiers)
    }
}
