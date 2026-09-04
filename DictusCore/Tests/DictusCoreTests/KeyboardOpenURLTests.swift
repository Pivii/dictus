// DictusCore/Tests/DictusCoreTests/KeyboardOpenURLTests.swift
// The keyboard-to-app screen request, both ends of it (issues #241, #404).
import XCTest
@testable import DictusCore

final class KeyboardOpenURLTests: XCTestCase {

    /// The point of the type: the keyboard builds and the app parses, and this target
    /// is the only place both halves exist at once. #404 is the bill for them being two
    /// strings — the keyboard sent `intent=pro` faithfully and the app had no `open`
    /// route at all, so the one row in the fan that leads anywhere led nowhere useful.
    func testEveryIntentSurvivesTheRoundTrip() throws {
        for intent in KeyboardOpenIntent.allCases {
            let url = try XCTUnwrap(KeyboardOpenURL.url(intent: intent), intent.rawValue)
            XCTAssertEqual(KeyboardOpenURL.intent(from: url), intent)
        }
    }

    func testTheProIntentIsTheOneThePaywallRoutesOn() throws {
        let url = try XCTUnwrap(KeyboardOpenURL.url(intent: .pro))
        XCTAssertEqual(url.absoluteString, "dictus://open?source=keyboard&intent=pro")
    }

    /// The scheme is public, so a screen request is only ours when we sent it — the
    /// same rule `KeyboardDictationURL` applies for the same reason.
    func testAUrlWithoutTheKeyboardSourceIsNotOurs() throws {
        let url = try XCTUnwrap(URL(string: "dictus://open?intent=pro"))
        XCTAssertNil(KeyboardOpenURL.intent(from: url))
    }

    /// And a dictation URL is not a screen request. Keeping the two vocabularies apart
    /// is what stops a paywall reaching `ColdStartLaunch`, whose job is deciding the
    /// first frame of a dictation.
    func testDictationURLsAreNotScreenRequests() throws {
        for raw in [
            "dictus://dictate?source=keyboard",
            "dictus://dictate?source=keyboard&intent=prepare",
            "dictus://stop"
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(KeyboardOpenURL.intent(from: url), raw)
        }
    }

    func testScreenRequestsAreNotDictations() throws {
        for intent in KeyboardOpenIntent.allCases {
            let url = try XCTUnwrap(KeyboardOpenURL.url(intent: intent))
            XCTAssertNil(KeyboardDictationURL.intent(from: url), intent.rawValue)
        }
    }

    /// An intent a future build sends and this one has never heard of reads as nil,
    /// which routes nowhere rather than routing wrongly.
    func testAnUnknownIntentIsRefusedRatherThanGuessed() throws {
        let url = try XCTUnwrap(URL(string: "dictus://open?source=keyboard&intent=history"))
        XCTAssertNil(KeyboardOpenURL.intent(from: url))
    }
}
