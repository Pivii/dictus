// DictusCore/Tests/DictusCoreTests/AccentRelationTests.swift
// Pins the accent-cost table the keyboard's C++ scorer consumes (#321, #327). The C++ side is
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

    // MARK: - Spanish acutes and ñ (the gap #327 closes)

    func testSpanishAccentsRelateToTheirBaseLetters() {
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00E1}"), "a")   // á
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00ED}"), "i")   // í
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00F3}"), "o")   // ó
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00FA}"), "u")   // ú
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00F1}"), "n")   // ñ
        // The two Spanish characters that were covered by accident, via French and German.
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00E9}"), "e")   // é
        XCTAssertEqual(AccentRelation.baseLetter(of: "\u{00FC}"), "u")   // ü
    }

    func testSpanishSubstitutionIsCheapInBothDirections() {
        // `manana` for `mañana` and the reverse must both score as a near substitution.
        let spanish = [("\u{00E1}", "a"), ("\u{00ED}", "i"), ("\u{00F3}", "o"),
                       ("\u{00FA}", "u"), ("\u{00F1}", "n")]
        for (accented, base) in spanish {
            guard let accentedChar = accented.first, let baseChar = base.first else {
                return XCTFail("bad fixture")
            }
            XCTAssertEqual(AccentRelation.cost(from: baseChar, to: accentedChar),
                           AccentRelation.baseToAccentCost, "\(base) → \(accented)")
            XCTAssertEqual(AccentRelation.cost(from: accentedChar, to: baseChar),
                           AccentRelation.baseToAccentCost, "\(accented) → \(base)")
        }
    }

    func testSpanishAccentRelatesToTheOtherAccentsOfItsBase() {
        // á, à and ä share `a`; ú, ù and ü share `u` — accent-to-accent, not unrelated.
        XCTAssertEqual(AccentRelation.cost(from: "\u{00E1}", to: "\u{00E0}"),
                       AccentRelation.accentToAccentCost)          // á ↔ à
        XCTAssertEqual(AccentRelation.cost(from: "\u{00E1}", to: "\u{00E4}"),
                       AccentRelation.accentToAccentCost)          // á ↔ ä
        XCTAssertEqual(AccentRelation.cost(from: "\u{00FA}", to: "\u{00FC}"),
                       AccentRelation.accentToAccentCost)          // ú ↔ ü
        XCTAssertEqual(AccentRelation.cost(from: "\u{00F3}", to: "\u{00F4}"),
                       AccentRelation.accentToAccentCost)          // ó ↔ ô
        XCTAssertEqual(AccentRelation.cost(from: "\u{00ED}", to: "\u{00EF}"),
                       AccentRelation.accentToAccentCost)          // í ↔ ï
    }

    /// `ñ` is the only entry whose base letter carries no other accent, so it must relate
    /// to `n` and to nothing else — a cheap `n` ↔ `ñ` must not leak into `n` ↔ anything.
    func testEnyeRelatesOnlyToItsBase() {
        XCTAssertEqual(AccentRelation.cost(from: "n", to: "\u{00F1}"),
                       AccentRelation.baseToAccentCost)
        XCTAssertNil(AccentRelation.cost(from: "\u{00F1}", to: "m"))
        XCTAssertNil(AccentRelation.cost(from: "\u{00F1}", to: "\u{00E1}"))   // different bases
    }

    // MARK: - The both-valid-pairs decision (#327): cost table only

    /// #327 chose the cost table alone (option 1) over the cost table plus a rule for the
    /// pairs that are two valid Spanish words. This pins the half of that decision this
    /// package can execute: the relation exists for those pairs, at the ordinary cost, with
    /// nothing special-cased. What stops `si` correcting to `sí` is the valid-word guard in
    /// `TextPredictionEngine.autocorrect`, which returns before the scorer that reads this
    /// table ever runs. Reading between two valid spellings needs context — #114 owns it.
    /// If this test fails, someone added a Spanish-specific rule here; read the reasoning
    /// on `AccentRelation.baseLetters` first.
    func testAmbiguousBothValidPairsCarryTheOrdinaryCostAndNoSpecialCase() {
        // si/sí, mas/más, esta/está, ano/año — the differing character of each pair.
        XCTAssertEqual(AccentRelation.cost(from: "i", to: "\u{00ED}"), 0.15)
        XCTAssertEqual(AccentRelation.cost(from: "a", to: "\u{00E1}"), 0.15)
        XCTAssertEqual(AccentRelation.cost(from: "n", to: "\u{00F1}"), 0.15)
    }

    /// The generative accent path, the one that *does* run before the valid-word guard,
    /// has covered every Spanish accent since the language shipped. #327 changed nothing
    /// there; this records that the two tables now agree on which characters exist.
    func testSpanishAccentMapAndCostTableAgree() {
        for (base, accents) in spanishProfile.accentMap {
            for accent in accents {
                XCTAssertEqual(AccentRelation.baseLetter(of: accent), base,
                               "\(accent) is offered for \(base) but relates elsewhere")
            }
        }
    }

    // MARK: - French, German and English: frozen (#327 criterion — no regression)

    /// Every relation that shipped before the Spanish characters were added, spelled out.
    /// A change here moves every correction in French or German, silently.
    func testFrenchAndGermanRelationsAreUnchanged() {
        let frozen: [Character: Character] = [
            "\u{00E9}": "e", "\u{00E8}": "e", "\u{00EA}": "e", "\u{00EB}": "e",
            "\u{00E0}": "a", "\u{00E2}": "a",
            "\u{00F9}": "u", "\u{00FB}": "u",
            "\u{00F4}": "o",
            "\u{00EE}": "i", "\u{00EF}": "i",
            "\u{00E7}": "c",
            "\u{00E4}": "a", "\u{00F6}": "o", "\u{00FC}": "u"       // umlauts, #321
        ]
        for (accented, base) in frozen {
            XCTAssertEqual(AccentRelation.baseLetter(of: accented), base,
                           "\(accented) must stay a variant of \(base)")
        }
    }

    /// Was `testTheTableHoldsExactlyTheFrozenSetPlusThreeUmlauts`, which pinned the Spanish
    /// characters as *absent* — out of scope for #321 and recorded as a known gap rather
    /// than an oversight. #327 closed the gap, so the pin flips: the same test now records
    /// that they are covered, and what is still not.
    func testTheTableHoldsExactlyTheFrenchSetPlusUmlautsAndSpanish() {
        XCTAssertEqual(AccentRelation.baseLetters.count, 20)
        XCTAssertNotNil(AccentRelation.baseLetter(of: "\u{00E1}"))  // á — covered since #327
        XCTAssertNotNil(AccentRelation.baseLetter(of: "\u{00F1}"))  // ñ — covered since #327
        // What is still absent, and which language would want it. This is the record the
        // next onboarding reads before assuming its characters are covered.
        let absent = ["\u{00E3}", "\u{00F5}",                       // ã õ — Portuguese
                      "\u{00E5}", "\u{00E6}", "\u{00F8}",           // å æ ø — Scandinavian
                      "\u{00FD}",                                   // ý — Czech, Icelandic
                      "\u{00DF}"]                                   // ß — German, deliberately
        for entry in absent {
            guard let character = entry.first else { return XCTFail("bad fixture") }
            XCTAssertNil(AccentRelation.baseLetter(of: character), "\(entry) is not covered")
        }
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
            guard let accentedUnit = accented.singleUTF16CodeUnit,
                  let baseUnit = base.singleUTF16CodeUnit else {
                return XCTFail("unmappable entry \(accented)")
            }
            XCTAssertTrue(seen.contains([accentedUnit, baseUnit]), "\(accented) → \(base)")
            XCTAssertTrue(seen.contains([baseUnit, accentedUnit]), "\(base) → \(accented)")
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
