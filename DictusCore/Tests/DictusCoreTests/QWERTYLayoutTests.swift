// DictusCore/Tests/DictusCoreTests/QWERTYLayoutTests.swift
import XCTest
@testable import DictusCore

final class QWERTYLayoutTests: XCTestCase {

    func testQWERTYLettersRowsHasFourRows() {
        XCTAssertEqual(QWERTYLayout.lettersRows.count, 4)
    }

    func testRow1Has10Keys() {
        let row1 = QWERTYLayout.lettersRows[0]
        XCTAssertEqual(row1.count, 10)
        XCTAssertEqual(row1, ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"])
    }

    func testRow2Has9Keys() {
        let row2 = QWERTYLayout.lettersRows[1]
        XCTAssertEqual(row2.count, 9)
        XCTAssertEqual(row2, ["A", "S", "D", "F", "G", "H", "J", "K", "L"])
    }

    func testRow3Has7LetterKeys() {
        // Row 3 contains only letter keys — special keys (shift, delete) are added by the keyboard target
        let row3 = QWERTYLayout.lettersRows[2]
        XCTAssertEqual(row3.count, 7)
        XCTAssertEqual(row3, ["Z", "X", "C", "V", "B", "N", "M"])
    }

    func testRow4Has5BottomRowKeys() {
        // Row 4 defines bottom row key labels — actual rendering is handled by the keyboard target
        let row4 = QWERTYLayout.lettersRows[3]
        XCTAssertEqual(row4.count, 5)
    }

    func testAllLetterKeysAreUppercase() {
        // Layout stores uppercase labels — the keyboard target lowercases output as needed
        let allKeys = QWERTYLayout.lettersRows.flatMap { $0 }
        let letterKeys = allKeys.filter { $0.count == 1 && $0.first?.isLetter == true }
        for key in letterKeys {
            XCTAssertEqual(key, key.uppercased(), "Key '\(key)' should be uppercase in layout data")
        }
    }
}
