// DictusCore/Tests/DictusCoreTests/HTTPRangeResumeTests.swift
// The decision a resumed model download makes when the server answers (issue #449).
import XCTest
@testable import DictusCore

final class HTTPRangeResumeTests: XCTestCase {

    // MARK: - Content-Range parsing

    func testParsesAFullySpecifiedRange() {
        let range = HTTPRangeResume.parseContentRange("bytes 0-1/445187200")
        XCTAssertEqual(range, HTTPContentRange(start: 0, end: 1, total: 445_187_200))
        XCTAssertEqual(range?.length, 2)
    }

    func testParsesAMidFileRangeMatchingTheLiveRepository() {
        // Transcribed from a real response, 2026-09-01:
        //   curl -H "Range: bytes=1000000-1000010" .../Encoder.mlmodelc/weights/weight.bin
        let range = HTTPRangeResume.parseContentRange("bytes 1000000-1000010/445187200")
        XCTAssertEqual(range?.start, 1_000_000)
        XCTAssertEqual(range?.end, 1_000_010)
        XCTAssertEqual(range?.length, 11)
    }

    func testParsesAnUnknownTotal() {
        XCTAssertEqual(
            HTTPRangeResume.parseContentRange("bytes 10-19/*"),
            HTTPContentRange(start: 10, end: 19, total: nil)
        )
    }

    func testToleratesSurroundingWhitespace() {
        XCTAssertEqual(HTTPRangeResume.parseContentRange("  bytes 0-9/10  ")?.end, 9)
    }

    func testRejectsAUnitThatIsNotBytes() {
        XCTAssertNil(HTTPRangeResume.parseContentRange("items 0-9/10"))
    }

    func testRejectsTheUnsatisfiedForm() {
        // `bytes */1234` is what a 416 carries. It names no span, so nothing can be
        // appended on the strength of it.
        XCTAssertNil(HTTPRangeResume.parseContentRange("bytes */1234"))
    }

    func testRejectsMalformedHeaders() {
        for header in ["", "bytes", "bytes 0-9", "bytes 0-9/", "bytes a-b/10", "bytes 9-0/10"] {
            XCTAssertNil(HTTPRangeResume.parseContentRange(header), "should reject \(header)")
        }
    }

    func testRejectsATotalThatDoesNotCoverItsOwnSpan() {
        XCTAssertNil(HTTPRangeResume.parseContentRange("bytes 0-99/10"))
    }

    // MARK: - Range header

    func testBuildsOpenEndedAndClosedRangeHeaders() {
        XCTAssertEqual(HTTPRangeResume.rangeHeaderValue(start: 0), "bytes=0-")
        XCTAssertEqual(
            HTTPRangeResume.rangeHeaderValue(start: 33_554_432, end: 67_108_863),
            "bytes=33554432-67108863"
        )
    }

    // MARK: - The decision

    func testAppendsWhenTheServerHonoursTheExactOffset() {
        let decision = HTTPRangeResume.decide(
            statusCode: 206,
            contentRangeHeader: "bytes 33554432-67108863/445187200",
            expectedStart: 33_554_432,
            expectedTotal: 445_187_200
        )
        XCTAssertEqual(decision, .appendFrom(33_554_432))
    }

    func testRestartsWhenTheServerIgnoresTheRange() {
        // A 200 means the whole resource is in this body: either ranges are unsupported,
        // or `If-Range` no longer matches. Either way the partial is stale.
        let decision = HTTPRangeResume.decide(
            statusCode: 200,
            contentRangeHeader: nil,
            expectedStart: 33_554_432,
            expectedTotal: 445_187_200
        )
        XCTAssertEqual(decision, .restartFromZero(reason: "http200-range-ignored"))
    }

    func testRejectsA206ThatStartsSomewhereElse() {
        // The failure this whole type exists for: appending these bytes would produce a
        // file of the right length made of the wrong content.
        let decision = HTTPRangeResume.decide(
            statusCode: 206,
            contentRangeHeader: "bytes 0-33554431/445187200",
            expectedStart: 33_554_432,
            expectedTotal: 445_187_200
        )
        XCTAssertEqual(decision, .reject(reason: "206-start-0-expected-33554432"))
    }

    func testRestartsWhenTheResourceChangedSize() {
        let decision = HTTPRangeResume.decide(
            statusCode: 206,
            contentRangeHeader: "bytes 100-199/999",
            expectedStart: 100,
            expectedTotal: 445_187_200
        )
        XCTAssertEqual(decision, .restartFromZero(reason: "206-total-999-expected-445187200"))
    }

    func testAcceptsA206WhoseTotalIsUnknownToUs() {
        let decision = HTTPRangeResume.decide(
            statusCode: 206,
            contentRangeHeader: "bytes 100-199/999",
            expectedStart: 100,
            expectedTotal: nil
        )
        XCTAssertEqual(decision, .appendFrom(100))
    }

    func testRejectsA206WithNoContentRange() {
        let decision = HTTPRangeResume.decide(
            statusCode: 206,
            contentRangeHeader: nil,
            expectedStart: 0,
            expectedTotal: 10
        )
        XCTAssertEqual(decision, .reject(reason: "206-without-content-range"))
    }

    func testRejectsA206WithAnUnparsableContentRange() {
        let decision = HTTPRangeResume.decide(
            statusCode: 206,
            contentRangeHeader: "bytes */445187200",
            expectedStart: 0,
            expectedTotal: 445_187_200
        )
        XCTAssertEqual(decision, .reject(reason: "206-unparsable-content-range"))
    }

    func testRestartsOnRangeNotSatisfiable() {
        let decision = HTTPRangeResume.decide(
            statusCode: 416,
            contentRangeHeader: "bytes */10",
            expectedStart: 1000,
            expectedTotal: 10
        )
        XCTAssertEqual(decision, .restartFromZero(reason: "http416-range-not-satisfiable"))
    }

    func testRejectsEverythingElseNamingTheStatus() {
        XCTAssertEqual(
            HTTPRangeResume.decide(
                statusCode: 403,
                contentRangeHeader: nil,
                expectedStart: 0,
                expectedTotal: nil
            ),
            .reject(reason: "http403")
        )
    }
}
