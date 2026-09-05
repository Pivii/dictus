// DictusCore/Tests/DictusCoreTests/PolishedTextChannelTests.swift
// Tests for the pair the keyboard leaves behind: what it produced, and where it went
// (#495).

import XCTest
@testable import DictusCore

final class PolishedTextChannelTests: XCTestCase {

    /// A suite of its own: these tests write the same keys the keyboard writes, and the
    /// shared App Group suite is live state on a developer machine.
    private let suiteName = "dictus.tests.polishedTextChannel"
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Round trip

    func testAnInsertedTextIsReadBackAsInserted() {
        PolishedTextChannel.record(.inserted("Hello there. "), in: defaults)

        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .inserted("Hello there. "))
    }

    /// The case #495 exists for: the generation succeeded, the insertion was refused,
    /// and the text is still the dictation's only copy.
    func testARefusedTextIsReadBackAsRefusedAndNotAsNothing() {
        PolishedTextChannel.record(.refused("Okay, and so there I'm going to do the famous test"), in: defaults)

        XCTAssertEqual(
            PolishedTextChannel.read(from: defaults),
            .refused("Okay, and so there I'm going to do the famous test")
        )
    }

    func testNothingIsReadBackAsNothing() {
        PolishedTextChannel.record(.nothing, in: defaults)

        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .nothing)
    }

    func testAnEmptyChannelReadsAsNothing() {
        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .nothing)
    }

    // MARK: - The flag can never speak on its own

    /// Recording `.nothing` over a previous answer takes the flag with it. Left behind,
    /// it would claim an insertion for whatever text landed next.
    func testRecordingNothingClearsAPreviousInsertion() {
        PolishedTextChannel.record(.inserted("typed"), in: defaults)
        PolishedTextChannel.record(.nothing, in: defaults)

        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .nothing)
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.lastPolishedWasInserted))
    }

    func testClearTakesBothHalves() {
        PolishedTextChannel.record(.inserted("typed"), in: defaults)
        PolishedTextChannel.clear(in: defaults)

        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .nothing)
        XCTAssertNil(defaults.string(forKey: SharedKeys.lastPolishedTranscription))
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.lastPolishedWasInserted))
    }

    /// The defensive half of the rule, forced by writing the keys apart the way only a
    /// bug could: a flag with no text beside it says nothing at all.
    func testAFlagLeftBehindWithNoTextCannotClaimAnInsertion() {
        defaults.set(true, forKey: SharedKeys.lastPolishedWasInserted)

        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .nothing)
    }

    /// And the mirror: a text whose flag went missing is read as refused, never as
    /// inserted. The channel fails towards "the document did not get this".
    func testATextWithNoFlagIsReadAsRefused() {
        defaults.set("orphan", forKey: SharedKeys.lastPolishedTranscription)

        XCTAssertEqual(PolishedTextChannel.read(from: defaults), .refused("orphan"))
    }

    // MARK: - The log vocabulary

    func testTheThreeEndingsCarryTheThreeLabels() {
        XCTAssertEqual(PolishedTextChannel.Ending.inserted("a").logOutcome, "inserted")
        XCTAssertEqual(PolishedTextChannel.Ending.refused("a").logOutcome, "refused-with-text")
        XCTAssertEqual(PolishedTextChannel.Ending.nothing.logOutcome, "not-inserted")
    }

    /// `outcome=inserted` must never appear for a dictation nothing typed. That field
    /// is the instrument that diagnosed #467.
    func testOnlyAnInsertionIsLabelledInserted() {
        for ending in [PolishedTextChannel.Ending.refused("a"), .nothing] {
            XCTAssertNotEqual(ending.logOutcome, "inserted", "\(ending) claimed an insertion")
        }
    }

    /// The labels have to survive the greps already used on these captures: neither old
    /// label may match the new one, in either direction.
    func testTheNewLabelIsDisjointFromTheOldOnes() {
        let refused = PolishedTextChannel.Ending.refused("a").logOutcome
        XCTAssertFalse(refused.contains("not-inserted"))
        XCTAssertFalse(refused.contains("inserted"))
    }

    // MARK: - The text, typed or not

    func testTheProducedTextIsReadableWhicheverWayItEnded() {
        XCTAssertEqual(PolishedTextChannel.Ending.inserted("a").text, "a")
        XCTAssertEqual(PolishedTextChannel.Ending.refused("a").text, "a")
        XCTAssertNil(PolishedTextChannel.Ending.nothing.text)
    }
}
