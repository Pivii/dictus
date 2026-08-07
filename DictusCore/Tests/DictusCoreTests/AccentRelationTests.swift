// DictusCore/Tests/DictusCoreTests/AccentRelationTests.swift
// Pins the accent-cost table the keyboard's C++ scorer consumes (#321). The C++ side is
// a pure lookup into the pairs enumerated here, so these assertions cover the relation
// itself — what is related to what, at what cost — for every language Dictus ships.
import XCTest
@testable import DictusCore

final class AccentRelationTests: XCTestCase {

    // MARK: - German umlauts (the gap #321 closes)

    func testUmlautsRelateToTheirBaseLetters() {
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00E4}"), "a")   // ä
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00F6}"), "o")   // ö
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00FC}"), "u")   // ü
    }

    func testUmlautSubstitutionIsCheapInBothDirections() {
        // `uber` for `über` and `über` for `uber` must both score as a near substitution.
        for (accented, base) in [("\u{00E4}", "a"), ("\u{00F6}", "o"), ("\u{00FC}", "u")] {
            guard let accentedChar = accented.first, let baseChar = base.first else {
                return XCTFail("bad fixture")
            }
            XCTAssertEqual(AccentRelation.cost(from: baseChar, to: accentedChar),
                           AccentRelation.baseToAccentCost, "\(base) → \(accented)")
            XCTAssertEqual(AccentRelation.cost(from: accentedChar, to: baseChar),
                           AccentRelation.baseToAccentCost, "\(accented) → \(base)")
        }
    }

    func testUmlautRelatesToTheOtherAccentsOfItsBase() {
        // ä and à share `a`, ü and ù share `u` — accent-to-accent, not unrelated.
        XCTAssertEqual(AccentRelation.cost(from: "\u{00E4}", to: "\u{00E0}"),
                       AccentRelation.accentToAccentCost)          // ä ↔ à
        XCTAssertEqual(AccentRelation.cost(from: "\u{00FC}", to: "\u{00F9}"),
                       AccentRelation.accentToAccentCost)          // ü ↔ ù
        XCTAssertEqual(AccentRelation.cost(from: "\u{00F6}", to: "\u{00F4}"),
                       AccentRelation.accentToAccentCost)          // ö ↔ ô
    }

    // MARK: - The ß decision (#321): deliberately out of this table

    /// `ß` relates to `ss`, a one-to-two relation this one-to-one table cannot express.
    /// It is handled by `germanProfile.collapseRules` instead. If this test fails, someone
    /// added ß to the accent map — read the reasoning on `AccentRelation.baseLetters` first.
    func testEszettIsNotAnAccentOfS() {
        XCTAssertNil(AccentRelation.baseLetter(of: "\u{00DF}"))
        XCTAssertNil(AccentRelation.cost(from: "\u{00DF}", to: "s"))
        XCTAssertNil(AccentRelation.cost(from: "s", to: "\u{00DF}"))
    }

    func testEszettIsCoveredByTheGermanCollapseRules() {
        // Where the ss ↔ ß relation actually lives, so excluding it above loses nothing.
        XCTAssertTrue(germanProfile.collapseRules.contains { $0.from == "ss" && $0.to == "\u{00DF}" })
    }

    // MARK: - French and Spanish: frozen (#321 criterion — no regression)

    /// Every relation that shipped before the umlauts were added, spelled out. A change
    /// here moves every correction in French or Spanish, silently.
    func testFrenchAndSpanishRelationsAreUnchanged() {
        let frozen: [Character: Character] = [
            "\u{00E9}": "e", "\u{00E8}": "e", "\u{00EA}": "e", "\u{00EB}": "e",
            "\u{00E0}": "a", "\u{00E2}": "a",
            "\u{00F9}": "u", "\u{00FB}": "u",
            "\u{00F4}": "o",
            "\u{00EE}": "i", "\u{00EF}": "i",
            "\u{00E7}": "c"
        ]
        for (accented, base) in frozen {
            XCTAssertEqual(AccentRelation.baseLetter(of: accented), base,
                           "\(accented) must stay a variant of \(base)")
        }
    }

    func testTheTableHoldsExactlyTheFrozenSetPlusThreeUmlauts() {
        // Guards against a fourth entry sneaking in unremarked — including the Spanish
        // acutes (á í ó ú ñ), which are absent today and out of scope for #321.
        XCTAssertEqual(AccentRelation.baseLetters.count, 15)
        XCTAssertNil(AccentRelation.baseLetter(of: "\u{00E1}"))     // á — still absent
        XCTAssertNil(AccentRelation.baseLetter(of: "\u{00F1}"))     // ñ — still absent
    }

    func testFrenchCostsAreUnchanged() {
        XCTAssertEqual(AccentRelation.cost(from: "e", to: "\u{00E9}"), 0.15)   // e → é
        XCTAssertEqual(AccentRelation.cost(from: "\u{00E9}", to: "e"), 0.15)   // é → e
        XCTAssertEqual(AccentRelation.cost(from: "\u{00E9}", to: "\u{00E8}"), 0.2)  // é → è
        XCTAssertEqual(AccentRelation.cost(from: "\u{00E7}", to: "c"), 0.15)   // ç → c
    }

    func testCostConstantsAreUnchanged() {
        XCTAssertEqual(AccentRelation.baseToAccentCost, 0.15)
        XCTAssertEqual(AccentRelation.accentToAccentCost, 0.2)
    }

    // MARK: - Unrelated characters

    func testUnrelatedCharactersHaveNoAccentCost() {
        XCTAssertNil(AccentRelation.cost(from: "a", to: "b"))
        XCTAssertNil(AccentRelation.cost(from: "\u{00FC}", to: "p"))       // ü vs p: proximity's job
        XCTAssertNil(AccentRelation.cost(from: "\u{00E9}", to: "\u{00E0}"))  // é vs à: different bases
        XCTAssertNil(AccentRelation.cost(from: "z", to: "\u{00E9}"))       // z has no accents
    }

    func testIdenticalCharactersCostNothing() {
        XCTAssertEqual(AccentRelation.cost(from: "\u{00FC}", to: "\u{00FC}"), 0)
        XCTAssertEqual(AccentRelation.cost(from: "a", to: "a"), 0)
    }

    // MARK: - The flattened pairs handed to C++

    func testCostPairsAgreeWithCostForEveryPair() {
        let pairs = AccentRelation.costPairs
        XCTAssertEqual(pairs.from.count, pairs.count)
        XCTAssertEqual(pairs.to.count, pairs.count)
        for index in 0..<pairs.count {
            guard let from = Unicode.Scalar(pairs.from[index]),
                  let to = Unicode.Scalar(pairs.to[index]) else {
                return XCTFail("pair \(index) is not a scalar")
            }
            XCTAssertEqual(AccentRelation.cost(from: Character(from), to: Character(to)),
                           pairs.costs[index],
                           "pair \(index): \(Character(from)) → \(Character(to))")
        }
    }

    func testCostPairsContainNoUnrelatedPairAndNoIdentityPair() {
        let pairs = AccentRelation.costPairs
        for index in 0..<pairs.count {
            XCTAssertNotEqual(pairs.from[index], pairs.to[index], "identity pair at \(index)")
            XCTAssertGreaterThan(pairs.costs[index], 0)
        }
    }

    func testCostPairsCoverBothDirectionsOfEveryRelation() {
        let pairs = AccentRelation.costPairs
        let seen = Set(zip(pairs.from, pairs.to).map { [$0, $1] })
        for (accented, base) in AccentRelation.baseLetters {
            guard let accentedScalar = AccentRelation.scalarValue(accented),
                  let baseScalar = AccentRelation.scalarValue(base) else {
                return XCTFail("unmappable entry \(accented)")
            }
            XCTAssertTrue(seen.contains([accentedScalar, baseScalar]), "\(accented) → \(base)")
            XCTAssertTrue(seen.contains([baseScalar, accentedScalar]), "\(base) → \(accented)")
        }
    }

    /// The enumeration is deterministic: the buffers handed to C++ must not depend on
    /// dictionary iteration order, or two runs would install different tables.
    func testCostPairsAreStableAcrossCalls() {
        XCTAssertEqual(AccentRelation.costPairs, AccentRelation.costPairs)
    }

    func testCostPairsPackIntoBuffersOfMatchingSize() {
        let pairs = AccentRelation.costPairs
        XCTAssertEqual(pairs.fromData.count, pairs.count * 2)      // UInt16
        XCTAssertEqual(pairs.toData.count, pairs.count * 2)
        XCTAssertEqual(pairs.costsData.count, pairs.count * 4)     // Float
    }
}
