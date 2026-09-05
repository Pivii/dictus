import XCTest
@testable import DictusCore

/// The rule that answers a record tap arriving during a model load (#484).
///
/// The bug this replaces was a button that swallowed twelve taps in silence, so the tests
/// that matter are the ones that pin *which* taps get a screen and which are handed to the
/// coordinator — including the three statuses #458 says must never be covered.
final class RecordTapRoutingTests: XCTestCase {

    private func decide(
        _ status: DictationStatus,
        downloaded: Bool = true,
        load: ModelLoadState = .loading
    ) -> RecordTapRouting.Decision {
        RecordTapRouting.decide(
            dictationStatus: status,
            isModelDownloaded: downloaded,
            loadState: load
        )
    }

    // MARK: - The bug

    /// Home. `MainTabView` covers the tabs with `RecordingView` for every status but `.idle`,
    /// so a Home tap is always this one.
    func testAnIdleTapDuringALoadPresentsInsteadOfStarting() {
        XCTAssertEqual(decide(.idle), .presentPreparation)
    }

    /// The start-again mic on the result screen — the second entry point, and the one the
    /// gate's `status != .idle` would have refused. `.ready` is a finished dictation the user
    /// is choosing to leave; `.failed` is the cold-start refusal they are retrying.
    func testTheResultScreenTapPresentsToo() {
        XCTAssertEqual(decide(.ready), .presentPreparation)
        XCTAssertEqual(decide(.failed), .presentPreparation)
    }

    // MARK: - #458: a running dictation is never covered

    func testALiveDictationIsNeverGivenAPreparationScreen() {
        for status in [DictationStatus.recording, .transcribing, .processing] {
            XCTAssertEqual(
                decide(status), .startDictation,
                "\(status.rawValue) is a dictation still running — #458 forbids covering it"
            )
        }
    }

    /// The refusal list is the coordinator's own, not a second one written here. If
    /// `canStartNewDictation` ever changes its mind about a status, this notices.
    func testTheRefusalListIsTheCoordinatorsList() {
        for status in DictationStatus.allCases {
            let mayStart = ColdStartResolutionPolicy.canStartNewDictation(from: status)
            XCTAssertEqual(
                decide(status), mayStart ? .presentPreparation : .startDictation,
                "\(status.rawValue) routes differently from the dictation it would have started"
            )
        }
    }

    // MARK: - Everything that is not a load

    /// The ordinary path. Nothing about this issue may touch a tap made with a ready model.
    func testAReadyModelStartsDictationAsBefore() {
        for status in DictationStatus.allCases {
            XCTAssertEqual(decide(status, load: .ready), .startDictation)
            XCTAssertEqual(decide(status, load: .idle), .startDictation)
        }
    }

    /// No model on disk is an error the coordinator words, not a wait. A preparation screen
    /// here would name a model that can never become ready, on a screen with no exit (#428).
    func testNoModelDownloadedFallsThroughToTheCoordinatorsError() {
        XCTAssertEqual(decide(.idle, downloaded: false), .startDictation)
        XCTAssertEqual(decide(.ready, downloaded: false), .startDictation)
    }
}
