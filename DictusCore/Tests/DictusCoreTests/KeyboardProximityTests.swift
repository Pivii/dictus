// DictusCore/Tests/DictusCoreTests/KeyboardProximityTests.swift
// Pins the proximity model the keyboard's C++ scorer installs (#321).
//
// Two jobs. First, QWERTZ's three umlaut keys must have positions at all and score as
// near misses against their physical neighbours. Second — the expensive half — AZERTY and
// QWERTY pairwise costs must not move: the geometry used to be hardcoded in C++ and is
// now computed here, so the expected values below are hand-derived from the formula
// (`min(1, hypot / 2.5)` over the historical coordinates), not copied from an
// implementation run. A silent shift in those numbers changes every French correction.
import XCTest
@testable import DictusCore

final class KeyboardProximityTests: XCTestCase {

    /// Distances are floats and the geometry involves 10/11; compare at 1e-5.
    private let tolerance: Float = 0.00001

    // MARK: - Coverage: every letter key of every layout has a position

    func testAzertyCoversTwentySixLetters() {
        let characters = KeyboardProximity.keyPositions(for: .azerty).map(\.character)
        XCTAssertEqual(characters.count, 26)
        XCTAssertEqual(Set(characters).count, 26, "no letter twice")
        XCTAssertEqual(String(characters), "azertyuiopqsdfghjklmwxcvbn")
    }

    func testQwertyCoversTwentySixLetters() {
        let characters = KeyboardProximity.keyPositions(for: .qwerty).map(\.character)
        XCTAssertEqual(characters.count, 26)
        XCTAssertEqual(Set(characters).count, 26, "no letter twice")
        XCTAssertEqual(String(characters), "qwertyuiopasdfghjklzxcvbnm")
    }

    func testQwertzCoversTwentySixLettersPlusTheThreeUmlauts() {
        let characters = KeyboardProximity.keyPositions(for: .qwertz).map(\.character)
        XCTAssertEqual(characters.count, 29)
        XCTAssertEqual(String(characters),
                       "qwertzuiop\u{00FC}asdfghjkl\u{00F6}\u{00E4}yxcvbnm")
    }

    /// The model reads its key sequence from the rows the keyboard renders, so the two
    /// cannot drift apart (the trap #151 called out: a copy in the extension is untestable).
    func testQwertzSequenceMatchesTheRenderedRows() {
        let fromLayoutData = QWERTZLayout.lowercasedLettersRows.flatMap { $0 }
        let fromModel = KeyboardProximity.keyPositions(for: .qwertz).map { String($0.character) }
        XCTAssertEqual(fromModel, fromLayoutData)
    }

    func testQwertySequenceMatchesTheRenderedRows() {
        let fromLayoutData = QWERTYLayout.lettersRows.prefix(3).flatMap { $0 }.map { $0.lowercased() }
        let fromModel = KeyboardProximity.keyPositions(for: .qwerty).map { String($0.character) }
        XCTAssertEqual(fromModel, fromLayoutData)
    }

    // MARK: - AZERTY: unchanged (#321 criterion — a regression here is silent)

    func testAzertyKeyCentresAreUnchanged() {
        assertPosition(.azerty, "a", x: 0, y: 0)
        assertPosition(.azerty, "z", x: 1, y: 0)
        assertPosition(.azerty, "p", x: 9, y: 0)
        assertPosition(.azerty, "q", x: 0.25, y: 1)
        assertPosition(.azerty, "m", x: 9.25, y: 1)
        assertPosition(.azerty, "w", x: 0.75, y: 2)
        assertPosition(.azerty, "n", x: 5.75, y: 2)
    }

    func testAzertyPairwiseCostsAreUnchanged() {
        let table = KeyboardProximity.costTable(for: .azerty)
        // Adjacent on the same row: one key width / 2.5.
        assertCost(table, "a", "z", 1.0 / 2.5)
        assertCost(table, "e", "r", 1.0 / 2.5)
        // Row 0 to row 1, staggered by 0.25.
        assertCost(table, "a", "q", (0.25 * 0.25 + 1).squareRoot() / 2.5)
        assertCost(table, "z", "s", (0.25 * 0.25 + 1).squareRoot() / 2.5)
        // Row 1 to row 2, staggered by 0.5.
        assertCost(table, "q", "w", (0.5 * 0.5 + 1).squareRoot() / 2.5)
        // Far apart: clamped.
        assertCost(table, "a", "p", 1.0)
        assertCost(table, "a", "n", 1.0)
        // Same key.
        assertCost(table, "a", "a", 0)
    }

    // MARK: - QWERTY: unchanged (#321 criterion)

    func testQwertyKeyCentresAreUnchanged() {
        assertPosition(.qwerty, "q", x: 0, y: 0)
        assertPosition(.qwerty, "p", x: 9, y: 0)
        assertPosition(.qwerty, "a", x: 0.25, y: 1)
        assertPosition(.qwerty, "l", x: 8.25, y: 1)
        assertPosition(.qwerty, "z", x: 0.75, y: 2)
        assertPosition(.qwerty, "m", x: 6.75, y: 2)
    }

    func testQwertyPairwiseCostsAreUnchanged() {
        let table = KeyboardProximity.costTable(for: .qwerty)
        assertCost(table, "q", "w", 1.0 / 2.5)
        assertCost(table, "a", "s", 1.0 / 2.5)
        assertCost(table, "q", "a", (0.25 * 0.25 + 1).squareRoot() / 2.5)
        assertCost(table, "a", "z", (0.5 * 0.5 + 1).squareRoot() / 2.5)
        assertCost(table, "q", "p", 1.0)
        assertCost(table, "q", "q", 0)
    }

    /// The two layouts share 26 keys but not their arrangement — this guards against a
    /// refactor that accidentally builds one from the other.
    func testAzertyAndQwertyDisagreeWhereTheLayoutsDiffer() {
        let azerty = KeyboardProximity.costTable(for: .azerty)
        let qwerty = KeyboardProximity.costTable(for: .qwerty)
        // `a` and `q` swap rows between the two, so `a`–`e` is a near miss on AZERTY
        // (adjacent but one) and unrelated on QWERTY.
        XCTAssertLessThan(azerty.cost(from: "a", to: "e"), qwerty.cost(from: "a", to: "e"))
    }

    // MARK: - QWERTZ: the three umlaut keys (#321)

    func testQwertzUmlautKeysHavePositions() {
        // Rows 0 and 1 carry 11 keys in a 10-unit row: keys are 10/11 wide.
        let width = 10.0 / 11.0
        assertPosition(.qwertz, "q", x: 0.5 * width - 0.5, y: 0)
        assertPosition(.qwertz, "p", x: 9.5 * width - 0.5, y: 0)
        assertPosition(.qwertz, "\u{00FC}", x: 10.5 * width - 0.5, y: 0)      // ü
        assertPosition(.qwertz, "l", x: 8.5 * width - 0.5, y: 1)
        assertPosition(.qwertz, "\u{00F6}", x: 9.5 * width - 0.5, y: 1)       // ö
        assertPosition(.qwertz, "\u{00E4}", x: 10.5 * width - 0.5, y: 1)      // ä
    }

    /// The acceptance criterion, stated as the scorer sees it.
    func testUmlautToItsNeighbourIsMateriallyCheaperThanToAFarKey() {
        let table = KeyboardProximity.costTable(for: .qwertz)
        let neighbour = table.cost(from: "\u{00FC}", to: "p")      // ü and p are adjacent
        let farKey = table.cost(from: "\u{00FC}", to: "q")         // opposite end of the row

        XCTAssertEqual(farKey, 1.0, "ü to q must be unrelated")
        XCTAssertLessThan(neighbour, 0.4)
        XCTAssertLessThan(neighbour, farKey / 2, "not materially cheaper")
    }

    func testQwertzUmlautNeighbourCosts() {
        let table = KeyboardProximity.costTable(for: .qwertz)
        let width = 10.0 / 11.0
        let sameRowStep = Float(width / 2.5)

        // The three mistypes on the manual test list, each between physical neighbours.
        assertCost(table, "\u{00FC}", "p", Double(sameRowStep))                      // ü / p
        assertCost(table, "\u{00F6}", "l", Double(sameRowStep))                      // ö / l
        assertCost(table, "\u{00E4}", "\u{00F6}", Double(sameRowStep))               // ä / ö
        // ü and ä both close their row, so ä sits directly under ü: one row, no column shift.
        assertCost(table, "\u{00FC}", "\u{00E4}", 1.0 / 2.5)
        // ö is one key left on the row below ü: one row and one key away.
        assertCost(table, "\u{00FC}", "\u{00F6}", (width * width + 1).squareRoot() / 2.5)
    }

    /// Symmetry matters: the scorer asks in whichever direction the trie walk hits.
    func testCostsAreSymmetric() {
        for layout in LayoutType.allCases {
            let positions = KeyboardProximity.keyPositions(for: layout)
            let table = KeyboardProximity.costTable(for: layout)
            for from in positions {
                for to in positions {
                    XCTAssertEqual(table.cost(from: from.character, to: to.character),
                                   table.cost(from: to.character, to: from.character),
                                   accuracy: tolerance,
                                   "\(layout) \(from.character)/\(to.character)")
                }
            }
        }
    }

    // MARK: - Keys the layout does not have

    /// A German on QWERTY reaches ü by long-press, so it has no position and no proximity
    /// relation — the accent path (`AccentRelation`) is what carries that case.
    func testUmlautsAreAbsentFromLayoutsThatHaveNoUmlautKey() {
        for layout in [LayoutType.azerty, .qwerty] {
            let table = KeyboardProximity.costTable(for: layout)
            XCTAssertEqual(table.cost(from: "\u{00FC}", to: "u"), 1.0, "\(layout)")
            XCTAssertEqual(table.cost(from: "\u{00F6}", to: "o"), 1.0, "\(layout)")
            XCTAssertEqual(table.cost(from: "\u{00E4}", to: "a"), 1.0, "\(layout)")
        }
    }

    func testNonLetterCharactersAreUnrelated() {
        let table = KeyboardProximity.costTable(for: .qwertz)
        XCTAssertEqual(table.cost(from: "1", to: "q"), 1.0)
        XCTAssertEqual(table.cost(from: "-", to: "p"), 1.0)
        XCTAssertEqual(table.cost(from: "\u{00DF}", to: "s"), 1.0)   // ß has no key (#151)
    }

    // MARK: - The buffers handed to C++

    func testTableBuffersAreSquareAndCorrectlySized() {
        for layout in LayoutType.allCases {
            let table = KeyboardProximity.costTable(for: layout)
            XCTAssertEqual(table.distances.count, table.count * table.count, "\(layout)")
            XCTAssertEqual(table.charactersData.count, table.count * 2, "\(layout)")       // UInt16
            XCTAssertEqual(table.distancesData.count, table.count * table.count * 4, "\(layout)")
        }
    }

    func testEveryCostIsInRange() {
        for layout in LayoutType.allCases {
            for distance in KeyboardProximity.costTable(for: layout).distances {
                XCTAssertGreaterThanOrEqual(distance, 0, "\(layout)")
                XCTAssertLessThanOrEqual(distance, 1, "\(layout)")
            }
        }
    }

    func testDiagonalIsZero() {
        for layout in LayoutType.allCases {
            let table = KeyboardProximity.costTable(for: layout)
            for index in 0..<table.count {
                XCTAssertEqual(table.distances[index * table.count + index], 0, "\(layout)")
            }
        }
    }

    func testNormalizerIsUnchanged() {
        XCTAssertEqual(KeyboardProximity.distanceNormalizer, 2.5)
    }

    // MARK: - The number row must never reach this model (#331)

    /// The digit row is injected in `KeyboardLayouts` (DictusKeyboard), so it is invisible
    /// here and `1` can never become a substitution candidate for `q`.
    ///
    /// This test guards the shortcut someone will eventually be tempted by: prepending the
    /// digits to `QWERTYLayout.lettersRows` instead. `rows(for: .qwerty)` takes
    /// `lettersRows.prefix(3)`, so that change would silently drop the real bottom letter row
    /// — `zxcvbnm` would lose its positions and every correction involving those seven keys
    /// would change. It compiles, it renders, and nothing else in the repo would notice.
    ///
    /// The flag is toggled for real rather than mocked, because the point is that the model
    /// does not read it: a version of this that stubbed the preference would pass over
    /// exactly the mistake it exists to catch.
    func testTheCostTableIsIdenticalWithTheNumberRowOnAndOff() {
        let wasEnabled = NumberRowPreference.isEnabled
        defer { NumberRowPreference.setEnabled(wasEnabled) }

        for layout in LayoutType.allCases {
            NumberRowPreference.setEnabled(false)
            let off = KeyboardProximity.costTable(for: layout)

            NumberRowPreference.setEnabled(true)
            let on = KeyboardProximity.costTable(for: layout)

            XCTAssertEqual(on, off, "\(layout.rawValue) proximity costs moved with the number row")
        }
    }

    /// The specific casualty of the prefix(3) trap, named so a failure reads as itself
    /// rather than as "some table changed".
    func testTheBottomLetterRowKeepsItsPositionsWithTheNumberRowOn() {
        let wasEnabled = NumberRowPreference.isEnabled
        defer { NumberRowPreference.setEnabled(wasEnabled) }
        NumberRowPreference.setEnabled(true)

        for (layout, bottomRow) in [(LayoutType.qwerty, "zxcvbnm"),
                                    (LayoutType.qwertz, "yxcvbnm"),
                                    (LayoutType.azerty, "wxcvbn")] {
            let characters = KeyboardProximity.keyPositions(for: layout).map(\.character)
            for letter in bottomRow {
                XCTAssertTrue(characters.contains(letter),
                              "\(layout.rawValue) lost '\(letter)' from its bottom letter row")
            }
        }
        XCTAssertFalse(KeyboardProximity.keyPositions(for: .qwerty).contains { $0.character == "1" },
                       "A digit must never hold a position in the proximity model")
    }

    // MARK: - Helpers

    private func assertPosition(
        _ layout: LayoutType, _ character: Character, x: Double, y: Double,
        line: UInt = #line
    ) {
        guard let position = KeyboardProximity.keyPositions(for: layout)
            .first(where: { $0.character == character }) else {
            return XCTFail("\(layout) has no key '\(character)'", line: line)
        }
        XCTAssertEqual(position.x, x, accuracy: 0.00001, "x of '\(character)'", line: line)
        XCTAssertEqual(position.y, y, accuracy: 0.00001, "y of '\(character)'", line: line)
    }

    private func assertCost(
        _ table: ProximityCostTable, _ from: Character, _ to: Character, _ expected: Double,
        line: UInt = #line
    ) {
        XCTAssertEqual(table.cost(from: from, to: to), Float(expected), accuracy: tolerance,
                       "cost '\(from)' → '\(to)'", line: line)
    }
}
