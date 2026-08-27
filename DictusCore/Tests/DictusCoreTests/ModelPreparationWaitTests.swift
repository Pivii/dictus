import XCTest
@testable import DictusCore

/// Issue #432: the preparation screen never said how long a first Turbo compile takes,
/// so a three and a half minute wait looked exactly like a hang. These tests hold the
/// decisions that turn a measurement into a sentence.
final class ModelPreparationWaitTests: XCTestCase {

    private let turbo632 = "openai_whisper-large-v3-v20240930_turbo_632MB"
    private let turbo954 = "openai_whisper-large-v3_turbo_954MB"

    // MARK: - What the two measured models say

    /// The whole point of the issue, stated as the number the user reads. 236s is the
    /// slowest of the four cold readings; rounded up it is four minutes.
    func testTurboAnnouncesFourMinutes() {
        XCTAssertEqual(ModelPreparationWait.forModel(turbo632), .minutes(4))
    }

    /// The gap the copy has to carry: Medium is ready in 32s and must not be described
    /// in the same words as a model that takes four minutes.
    func testMediumAnnouncesUnderAMinuteRatherThanAFigure() {
        XCTAssertEqual(ModelPreparationWait.forModel("openai_whisper-medium"), .brief)
    }

    /// Everything nobody has timed says "once" and nothing else. Inventing a duration
    /// for a model we have never watched compile would re-create the issue with the
    /// app's own words as the evidence.
    func testUnmeasuredModelsAnnounceNoDuration() {
        for identifier in ["openai_whisper-small", "openai_whisper-small_216MB",
                           "parakeet-tdt-0.6b-v3", "openai_whisper-tiny", turbo954] {
            XCTAssertEqual(
                ModelPreparationWait.forModel(identifier),
                .unmeasured,
                "\(identifier) has no measured first preparation and must not claim one"
            )
        }
    }

    /// A model left over from an older build resolves to nothing in the catalogue. That
    /// is the case most likely to reach this screen with no entry behind it, and it
    /// must still produce a sentence rather than a crash or a blank.
    func testAnUnknownIdentifierIsUnmeasuredRatherThanAbsent() {
        XCTAssertEqual(ModelPreparationWait.forModel("openai_whisper-from-a-future-build"), .unmeasured)
        XCTAssertEqual(ModelPreparationWait.forModel(""), .unmeasured)
    }

    /// Every entry in the catalogue has to land in a bucket, because the view switches
    /// on this exhaustively and a model with no answer would show no line at all.
    func testEveryCatalogueEntryResolvesToABucket() {
        for model in ModelInfo.allIncludingDeprecated {
            let wait = ModelPreparationWait.forModel(model.identifier)
            if let seconds = model.firstPreparationSeconds {
                XCTAssertNotEqual(
                    wait, .unmeasured,
                    "\(model.identifier) declares \(seconds)s but announces no wait"
                )
            } else {
                XCTAssertEqual(
                    wait, .unmeasured,
                    "\(model.identifier) declares no measurement but announces a wait"
                )
            }
        }
    }

    // MARK: - Rounding

    /// Rounding is up, never down. A wait that ends early costs nothing; one that runs
    /// past the figure the app printed re-creates the doubt the figure was there to
    /// remove. 236s is 3 minutes 56, and the user is told four.
    func testMinutesRoundUp() {
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(236), .minutes(4))
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(181), .minutes(4))
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(180), .minutes(3))
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(179), .minutes(3))
    }

    /// The copy says "about %lld minutes" with no plural rule behind it, so a 1 would
    /// ship "about 1 minutes". Nothing in the catalogue sits near this seam today; the
    /// floor is what stops a 70-second model added later from finding it.
    func testTheCopyCanNeverBeHandedASingleMinute() {
        for seconds in [60, 61, 90, 119, 120] {
            guard case .minutes(let minutes) = ModelPreparationWait.forMeasuredSeconds(seconds) else {
                XCTFail("\(seconds)s should be announced in minutes")
                return
            }
            XCTAssertGreaterThanOrEqual(minutes, ModelPreparationWait.minimumNamedMinutes)
        }
    }

    /// The seam between naming a figure and saying "under a minute", asserted from both
    /// sides so moving the threshold is a deliberate act.
    func testTheBriefThresholdIsAMinute() {
        XCTAssertEqual(ModelPreparationWait.briefThresholdSeconds, 60)
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(59), .brief)
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(60), .minutes(2))
    }

    /// Zero seconds is not a measurement of a Core ML compile, it is a typo. Treat it
    /// as no reading rather than as an instant preparation.
    func testANonPositiveReadingIsNotAMeasurement() {
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(nil), .unmeasured)
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(0), .unmeasured)
        XCTAssertEqual(ModelPreparationWait.forMeasuredSeconds(-1), .unmeasured)
    }
}
