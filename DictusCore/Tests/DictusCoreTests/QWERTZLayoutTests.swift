// DictusCore/Tests/DictusCoreTests/QWERTZLayoutTests.swift
// Pins the German QWERTZ rows (#151). The keyboard target builds its KeyDefinitions
// from this data, so these assertions cover what actually renders.
import XCTest
@testable import DictusCore

final class QWERTZLayoutTests: XCTestCase {

    // MARK: - Key sequences (shifted page)

    func testShiftedRowsAreTheGermanSequenceInOrder() {
        XCTAssertEqual(QWERTZLayout.lettersRows[0],
                       ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "\u{00DC}"])
        XCTAssertEqual(QWERTZLayout.lettersRows[1],
                       ["A", "S", "D", "F", "G", "H", "J", "K", "L", "\u{00D6}", "\u{00C4}"])
        XCTAssertEqual(QWERTZLayout.lettersRows[2],
                       ["Y", "X", "C", "V", "B", "N", "M"])
    }

    // MARK: - Key sequences (normal page)

    func testNormalRowsAreTheSameSequenceLowercased() {
        XCTAssertEqual(QWERTZLayout.lowercasedLettersRows[0],
                       ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "\u{00FC}"])
        XCTAssertEqual(QWERTZLayout.lowercasedLettersRows[1],
                       ["a", "s", "d", "f", "g", "h", "j", "k", "l", "\u{00F6}", "\u{00E4}"])
        XCTAssertEqual(QWERTZLayout.lowercasedLettersRows[2],
                       ["y", "x", "c", "v", "b", "n", "m"])
    }

    func testThreeLetterRows() {
        XCTAssertEqual(QWERTZLayout.lettersRows.count, 3)
        XCTAssertEqual(QWERTZLayout.lowercasedLettersRows.count, 3)
    }

    // MARK: - Y/Z swap (what makes it QWERTZ)

    func testZSitsInTheTopRowAndYInTheBottomRow() {
        XCTAssertEqual(QWERTZLayout.lettersRows[0][5], "Z")
        XCTAssertEqual(QWERTZLayout.lettersRows[2][0], "Y")
    }

    // MARK: - Row unit widths (the 11/11/10 asymmetry IS the spec)

    /// Rows 1 and 2 carry 11 units where every other row totals 10. The renderer
    /// normalizes each row against its own total, so those rows render narrower keys.
    /// Padding them back to 10 would push ü/ä off the edge — hence a test, not a comment.
    func testRowsOneAndTwoTotalElevenUnitsAndRowThreeTotalsTen() {
        XCTAssertEqual(QWERTZLayout.rowUnitWidths, [11, 11, 10])
    }

    func testRowsOneAndTwoCarryElevenKeys() {
        XCTAssertEqual(QWERTZLayout.lettersRows[0].count, 11)
        XCTAssertEqual(QWERTZLayout.lettersRows[1].count, 11)
    }

    func testRowThreeCarriesSevenLetterKeys() {
        // Shift and delete are added by the keyboard target at 1.5 units each.
        XCTAssertEqual(QWERTZLayout.lettersRows[2].count, 7)
        XCTAssertEqual(QWERTZLayout.flankKeyUnitWidth, 1.5)
    }

    // MARK: - Umlauts and eszett

    func testUmlautsCloseTheirRows() {
        XCTAssertEqual(QWERTZLayout.lettersRows[0].last, "\u{00DC}")            // Ü
        XCTAssertEqual(QWERTZLayout.lettersRows[1].suffix(2),
                       ["\u{00D6}", "\u{00C4}"])                                // Ö Ä
    }

    /// Neither iOS nor the AOSP-derived keyboards give ß a key; it is a long-press
    /// on `s`, wired through `AccentedCharacters.mappings`.
    func testNoDedicatedEszettKey() {
        let allKeys = QWERTZLayout.lettersRows.flatMap { $0 }
            + QWERTZLayout.lowercasedLettersRows.flatMap { $0 }
        XCTAssertFalse(allKeys.contains("\u{00DF}"), "ß must not have a key of its own.")
    }

    func testEszettIsReachableByLongPressOnS() {
        XCTAssertEqual(AccentedCharacters.mappings["s"], ["\u{00DF}"])
    }

    // MARK: - Data conventions

    func testLettersRowsAreStoredUppercase() {
        // Same convention as QWERTYLayout: uppercase data, lowercased for the normal page.
        for key in QWERTZLayout.lettersRows.flatMap({ $0 }) {
            XCTAssertEqual(key, key.uppercased(), "Key '\(key)' should be uppercase in layout data")
        }
    }
}
