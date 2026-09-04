// DictusCore/Tests/DictusCoreTests/Polish/SmartModeStoreTests.swift
// The armed mode and the pinned list, in the App Group (issue #79).
//
// These tests mutate the real App Group suite, so setUp/tearDown remove both keys.
import XCTest
@testable import DictusCore

final class SmartModeStoreTests: XCTestCase {

    private var defaults: UserDefaults { AppGroup.defaults }

    private let keys = [
        SharedKeys.smartModeArmed, SharedKeys.smartModePinned, SharedKeys.smartModeSkipAnnounced
    ]

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

    /// A read that starts a dictation does, but only for a condition that can never
    /// lift on its own. An identifier no mode answers to is one of those.
    func testResolveArmedModeClearsAnIdentifierThisBuildDoesNotKnow() {
        defaults.set("translate.klingon", forKey: SharedKeys.smartModeArmed)
        let resolution = SmartModeStore.resolveArmedMode()
        XCTAssertNil(resolution.mode)
        XCTAssertNil(SmartModeStore.armedIdentifier)
        // No notice: there is no mode to name and no choice of the user's to explain.
        XCTAssertNil(resolution.skipped)
    }

    /// A recoverable outage must not cost the user their setting: a model still
    /// downloading would otherwise silently forget what they armed. The rule lives
    /// on the reason, where it can be checked without an unavailable engine to
    /// simulate.
    func testOnlyDefinitiveReasonsMayClearTheSetting() {
        let mustNotDisarm: [SmartModeUnavailableReason] = [
            .appleIntelligenceNotEnabled, .modelNotReady, .engineRefusing
        ]
        for reason in mustNotDisarm {
            XCTAssertTrue(reason.isRecoverable, "\(reason.slug) must not clear the setting")
        }
        let mayDisarm: [SmartModeUnavailableReason] = [.deviceNotEligible, .osTooOld, .sdkMissing]
        for reason in mayDisarm {
            XCTAssertFalse(reason.isRecoverable, "\(reason.slug) should clear the setting")
        }
    }

    func testResolveArmedModeIsANoOpWhenNothingIsArmed() {
        let resolution = SmartModeStore.resolveArmedMode()
        XCTAssertNil(resolution.mode)
        XCTAssertNil(resolution.skipped)
        XCTAssertNil(SmartModeStore.armedIdentifier)
    }

    // MARK: - The silent fallback (#423)

    /// The contract #423 adds, and the one assertion that holds on any machine:
    /// **either the armed mode runs, or the user is told which one did not.** What
    /// this host's Apple Intelligence and entitlement happen to say decides which
    /// branch, and neither of them may produce silence.
    func testAnArmedModeEitherRunsOrProducesANotice() {
        SmartModeStore.arm(SmartModeCatalogue.notes)
        let resolution = SmartModeStore.resolveArmedMode()
        if let mode = resolution.mode {
            XCTAssertEqual(mode.id, SmartModeCatalogue.notesIdentifier)
            XCTAssertNil(resolution.skipped, "a mode that ran was not skipped")
        } else {
            XCTAssertEqual(resolution.skipped?.modeIdentifier, SmartModeCatalogue.notesIdentifier)
            XCTAssertEqual(resolution.skipped?.modeDisplayName, SmartModeCatalogue.notes.displayName)
        }
    }

    /// The notice fires once. The state behind it can last weeks, and a sentence on
    /// every dictation forever is how a notice becomes noise.
    func testASkipIsAnnouncedOncePerStateRatherThanOnEveryDictation() {
        let notice = SmartModeSkipNotice(
            modeIdentifier: "notes", modeDisplayName: "List", reason: .switchedOff
        )
        XCTAssertFalse(SmartModeStore.hasAnnouncedSkip(notice))
        SmartModeStore.noteSkipAnnounced(notice)
        XCTAssertTrue(SmartModeStore.hasAnnouncedSkip(notice))
    }

    /// A different reason for the same mode is a new thing to say.
    func testTheSameModeFailingForANewReasonIsAnnouncedAgain() {
        let switchedOff = SmartModeSkipNotice(
            modeIdentifier: "notes", modeDisplayName: "List", reason: .switchedOff
        )
        SmartModeStore.noteSkipAnnounced(switchedOff)
        let appleIntelligenceOff = SmartModeSkipNotice(
            modeIdentifier: "notes", modeDisplayName: "List", reason: .appleIntelligenceNotEnabled
        )
        XCTAssertFalse(SmartModeStore.hasAnnouncedSkip(appleIntelligenceOff))
    }

    /// And so is a different mode failing for the same one.
    func testADifferentModeIsAnnouncedAgain() {
        SmartModeStore.noteSkipAnnounced(SmartModeSkipNotice(
            modeIdentifier: "notes", modeDisplayName: "List", reason: .notSubscribed
        ))
        XCTAssertFalse(SmartModeStore.hasAnnouncedSkip(SmartModeSkipNotice(
            modeIdentifier: "translate.en", modeDisplayName: "\u{2192} EN", reason: .notSubscribed
        )))
    }

    /// Arming is the state changing, so the user is owed the sentence again.
    func testArmingForgetsWhatTheUserWasToldAboutASkip() {
        let notice = SmartModeSkipNotice(
            modeIdentifier: "notes", modeDisplayName: "List", reason: .switchedOff
        )
        SmartModeStore.noteSkipAnnounced(notice)
        SmartModeStore.arm(SmartModeCatalogue.translate(to: .english))
        XCTAssertFalse(SmartModeStore.hasAnnouncedSkip(notice))
    }

    func testDisarmingForgetsItToo() {
        let notice = SmartModeSkipNotice(
            modeIdentifier: "notes", modeDisplayName: "List", reason: .switchedOff
        )
        SmartModeStore.noteSkipAnnounced(notice)
        SmartModeStore.disarm()
        XCTAssertFalse(SmartModeStore.hasAnnouncedSkip(notice))
    }

    /// The notice has to survive the App Group trip, because the process that
    /// resolves it is not the process that says it.
    func testASkipNoticeRoundTripsThroughItsCoding() throws {
        let notice = SmartModeSkipNotice(
            modeIdentifier: "translate.en", modeDisplayName: "\u{2192} EN", reason: .other("newThing")
        )
        let decoded = try JSONDecoder().decode(
            SmartModeSkipNotice.self, from: JSONEncoder().encode(notice)
        )
        XCTAssertEqual(decoded, notice)
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

    /// The order has to survive the trip through the catalogue, not just the store.
    /// It did not: `pinnedModes` filtered the catalogue, so it answered in catalogue
    /// order and the assertion above passed anyway. Block B draws the fan from
    /// `pinnedModes`, so that divergence was a fan ignoring the user's arrangement.
    func testPinnedOrderSurvivesResolutionThroughTheCatalogue() {
        SmartModeStore.setPinned(["translate.de", "notes"])
        XCTAssertEqual(SmartModeCatalogue.pinnedModes.map(\.id), ["translate.de", "notes"])

        SmartModeStore.setPinned(["notes", "translate.de"])
        XCTAssertEqual(SmartModeCatalogue.pinnedModes.map(\.id), ["notes", "translate.de"])
    }

    func testAPinnedIdentifierThisBuildDoesNotShipCostsOnlyItsOwnEntry() {
        SmartModeStore.setPinned(["translate.klingon", "notes"])
        XCTAssertEqual(SmartModeCatalogue.pinnedModes.map(\.id), ["notes"])
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
