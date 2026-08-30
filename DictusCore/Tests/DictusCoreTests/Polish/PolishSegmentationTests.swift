// DictusCore/Tests/DictusCoreTests/Polish/PolishSegmentationTests.swift
import XCTest
@testable import DictusCore

final class PolishSegmentationTests: XCTestCase {

    func testOneBulletIsOneSegment() {
        let output = """
        - Relancer l'agence
        - Prévoir un plan B
        """
        XCTAssertEqual(PolishSegmentation.segments(of: output),
                       ["Relancer l'agence", "Prévoir un plan B"])
    }

    /// The marker is not text. Leaving `- ` on would inflate every segment's
    /// character count by two, and the minimum-length threshold is measured in
    /// characters of actual language.
    func testEveryListMarkerShapeIsStripped() {
        for marker in ["-", "–", "—", "*", "•", "·", "1.", "2)", "12."] {
            XCTAssertEqual(PolishSegmentation.segments(of: "\(marker) Appeler Marion"),
                           ["Appeler Marion"], "marker \(marker)")
        }
    }

    /// Only ONE marker comes off: a second dash is content, e.g. a dash opening a
    /// quotation or an em-dash aside.
    func testOnlyTheFirstMarkerIsStripped() {
        XCTAssertEqual(PolishSegmentation.segments(of: "- — et là il a dit non"),
                       ["— et là il a dit non"])
    }

    /// A number that is not followed by `.` or `)` is a figure the speaker gave,
    /// not an ordinal.
    func testALeadingFigureIsNotMistakenForAnOrdinal() {
        XCTAssertEqual(PolishSegmentation.segments(of: "8000 euros restants"),
                       ["8000 euros restants"])
    }

    func testBlankLinesAndSurroundingWhitespaceAreDropped() {
        XCTAssertEqual(PolishSegmentation.segments(of: "\n  - Un  \n\n   \n- Deux\n"),
                       ["Un", "Deux"])
    }

    /// Free polish returns one continuous passage. It has exactly one segment, and
    /// that is what makes the per-segment check a no-op for it.
    func testAContinuousPassageIsASingleSegment() {
        let passage = "Salut, je voulais te dire que le rendez-vous de mardi est décalé à jeudi."
        XCTAssertEqual(PolishSegmentation.segments(of: passage), [passage])
    }
}
