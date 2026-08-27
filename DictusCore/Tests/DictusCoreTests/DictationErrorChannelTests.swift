// DictusCore/Tests/DictusCoreTests/DictationErrorChannelTests.swift
// The failure-reason channel: that reading it leaves it alone, and that a new dictation
// is the only thing that takes it away (#320).
//
// The non-destructive read is the part that cannot be checked from either target: it is a
// property of the pair of readers, and the keyboard extension is the one thing in this
// repo nothing ever executes in CI. The test that matters is the one below that reads
// twice.
import XCTest
@testable import DictusCore

final class DictationErrorChannelTests: XCTestCase {

    /// A real message, used as a payload. The channel does not care what a message says —
    /// it carries a resolved `String`, and #313 is what decides what that string is — but
    /// naming a sentence the product actually produces is what caught the previous
    /// fixture: a hardcoded French literal that no call site writes any more.
    private let aFailure = "Le micro ne répond plus. Fermez Dictus puis rouvrez-le."


    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    override func setUp() {
        super.setUp()
        defaults?.removeObject(forKey: SharedKeys.lastError)
    }

    override func tearDown() {
        defaults?.removeObject(forKey: SharedKeys.lastError)
        super.tearDown()
    }

    // MARK: - Round trip

    func testNothingIsStoredOnAFreshAppGroup() {
        XCTAssertNil(DictationErrorChannel.current)
    }

    func testARecordedReasonReadsBack() {
        DictationErrorChannel.record(aFailure)

        XCTAssertEqual(DictationErrorChannel.current, aFailure)
    }

    /// The app writes through the channel; anything reading the shared key directly —
    /// a diagnostic dump, a future surface — has to see the same value.
    func testTheReasonLandsOnTheSharedKey() {
        DictationErrorChannel.record(aFailure)

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.lastError), aFailure)
    }

    func testOneReasonAtATime() {
        DictationErrorChannel.record(aFailure)
        DictationErrorChannel.record("Dictation could not start. Tap the microphone again.")

        XCTAssertEqual(DictationErrorChannel.current,
                       "Dictation could not start. Tap the microphone again.",
                       "The channel holds the current reason, not a history")
    }

    // MARK: - The read does not consume (#320)

    /// The bug this issue exists for: the keyboard read the key and removed it in the same
    /// breath, so the app's failure screen had nothing left to show and asserted a cause it
    /// had not established.
    func testReadingTwiceReturnsTheSameReason() {
        DictationErrorChannel.record(aFailure)

        let firstSurface = DictationErrorChannel.current
        let secondSurface = DictationErrorChannel.current

        XCTAssertEqual(firstSurface, aFailure)
        XCTAssertEqual(secondSurface, firstSurface,
                       "Neither surface may consume the reason on behalf of the other")
    }

    func testReadingLeavesTheSharedKeyInPlace() {
        DictationErrorChannel.record(aFailure)

        _ = DictationErrorChannel.current

        XCTAssertNotNil(defaults?.object(forKey: SharedKeys.lastError),
                        "A read must not remove the key")
    }

    // MARK: - Invalidation

    func testClearingRemovesTheReason() {
        DictationErrorChannel.record(aFailure)

        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.current)
        XCTAssertNil(defaults?.object(forKey: SharedKeys.lastError),
                     "Clearing removes the key rather than storing an empty string")
    }

    func testClearingWithNothingStoredIsHarmless() {
        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.current)
    }

    /// What a new dictation does, in order: clear, then fail again. The second failure's
    /// reason is the one that survives, and a failure that records nothing leaves nothing.
    func testANewAttemptDoesNotResurfaceThePreviousReason() {
        DictationErrorChannel.record(aFailure)

        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.current,
                     "A `.failed` with no reason recorded must not show the previous attempt's")
    }
}
