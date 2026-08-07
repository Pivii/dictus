// DictusCore/Sources/DictusCore/TextCorrection/AccentRelation.swift
// The accent-cost table the keyboard's C++ scorer reads: which accented letters
// relate to which base letter, and what substituting one for the other costs.
import Foundation

/// Which accented characters count as a near-miss for which base letter, and how cheap
/// that substitution is when the trie scorer walks candidates.
///
/// WHY this lives in DictusCore and not in the C++ scorer that consumes it:
/// the table is data, and the keyboard target has no test bundle — `swift test` builds
/// this package alone. Declared here it is pinned by tests; consumed from here the C++
/// has one source of truth instead of a copy (the same reasoning that put the QWERTZ
/// rows in `KeyboardLayoutData`, #151). The cost table is built once per dictionary
/// load and handed across the bridge, so nothing about this moves the scorer's hot loop.
///
/// WHY it matters: without an entry, two spellings of the same word are *unrelated*
/// characters to the scorer. German shipped that way — `über` and `uber` scored as far
/// apart as `über` and `xber` (#321).
public enum AccentRelation {

    /// Cost of substituting a base letter for one of its accented forms, or the reverse
    /// (`e` ↔ `é`, `u` ↔ `ü`). Cheap: the two spellings are the same word to a typist.
    public static let baseToAccentCost: Float = 0.15

    /// Cost of substituting one accent for another of the same base (`é` ↔ `è`).
    /// Slightly dearer than base ↔ accent: the user typed *an* accent, just not that one.
    public static let accentToAccentCost: Float = 0.2

    /// Accented character → the base letter it is a variant of.
    ///
    /// French and Spanish entries are frozen as they shipped: changing one silently moves
    /// every correction in those languages. The three umlauts were added for German (#321).
    ///
    /// WHY `ß` (U+00DF) is deliberately absent — the decision this table is asked to
    /// record: `ß` is not an accent of `s`, it is a ligature whose written equivalent is
    /// `ss`. That is a one-to-two relation and this table expresses one-to-one
    /// substitution only. Mapping `ß` → `s` here would make the relation *look* handled
    /// while `heisst` → `heißt` still needs a deletion the accent path cannot supply, and
    /// it would make `s` → `ß` cheap everywhere in a language whose most frequent
    /// consonant is `s` — a silent over-correction risk for a case it would not fix.
    /// The `ss` → `ß` relation is modelled where a length change *can* be expressed:
    /// `germanProfile.collapseRules` (see `expandAccents`).
    public static let baseLetters: [Character: Character] = [
        // French / Spanish — frozen.
        "\u{00E9}": "e",        // é
        "\u{00E8}": "e",        // è
        "\u{00EA}": "e",        // ê
        "\u{00EB}": "e",        // ë
        "\u{00E0}": "a",        // à
        "\u{00E2}": "a",        // â
        "\u{00F9}": "u",        // ù
        "\u{00FB}": "u",        // û
        "\u{00F4}": "o",        // ô
        "\u{00EE}": "i",        // î
        "\u{00EF}": "i",        // ï
        "\u{00E7}": "c",        // ç
        // German umlauts (#321).
        "\u{00E4}": "a",        // ä
        "\u{00F6}": "o",        // ö
        "\u{00FC}": "u"         // ü
    ]

    /// The base letter `character` is an accented form of, or `nil` if it is not one.
    public static func baseLetter(of character: Character) -> Character? {
        baseLetters[character]
    }

    /// Substitution cost between two characters when they are accent-related,
    /// or `nil` when they are not — the caller then falls back to keyboard proximity.
    ///
    /// The three cases, in the order the scorer applies them:
    ///   1. base ↔ one of its accents (`u` ↔ `ü`) → `baseToAccentCost`
    ///   2. two accents of the same base (`é` ↔ `è`) → `accentToAccentCost`
    ///   3. anything else → `nil`
    public static func cost(from: Character, to: Character) -> Float? {
        if from == to { return 0 }

        let baseFrom = baseLetter(of: from)
        let baseTo = baseLetter(of: to)

        // Base letter to one of its accent variants, either direction.
        if baseFrom == nil, isBaseLetter(from), baseTo == from { return baseToAccentCost }
        if baseTo == nil, isBaseLetter(to), baseFrom == to { return baseToAccentCost }

        // Two accents sharing a base.
        if let baseFrom, let baseTo, baseFrom == baseTo { return accentToAccentCost }

        return nil
    }

    /// Every accent-related ordered pair, flattened for the C++ scorer.
    ///
    /// WHY enumerate pairs rather than ship the base map and let C++ re-derive them:
    /// re-deriving means the three-case precedence above exists twice, in two languages,
    /// and drifts. Enumerated here, the C++ side is a pure lookup with no rules of its own.
    /// The set is ~60 pairs — built once per dictionary load.
    public static var costPairs: AccentCostPairs {
        // Every character the table can relate: the accented forms and their bases.
        let related = Set(baseLetters.keys).union(baseLetters.values)
        let ordered = related.sorted { (scalarValue($0) ?? 0) < (scalarValue($1) ?? 0) }

        var from: [UInt16] = []
        var to: [UInt16] = []
        var costs: [Float] = []
        for a in ordered {
            for b in ordered where a != b {
                guard let cost = cost(from: a, to: b),
                      let scalarA = scalarValue(a),
                      let scalarB = scalarValue(b) else { continue }
                from.append(scalarA)
                to.append(scalarB)
                costs.append(cost)
            }
        }
        return AccentCostPairs(from: from, to: to, costs: costs)
    }

    /// True for the unaccented ASCII lowercase letters a base letter can be.
    private static func isBaseLetter(_ character: Character) -> Bool {
        character.isASCII && character.isLowercase
    }

    /// The single UTF-16 code unit of `character`, or `nil` if it is not one code unit.
    /// Every character in this table is in the Latin-1 supplement, so `nil` never happens
    /// in practice — but returning it keeps the packing free of force unwraps.
    static func scalarValue(_ character: Character) -> UInt16? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first, scalar.value <= 0xFFFF else {
            return nil
        }
        return UInt16(scalar.value)
    }
}

/// Accent-related character pairs and their substitution costs, as three parallel arrays.
///
/// WHY parallel arrays of plain scalars: they cross into C++ as raw byte buffers, which
/// keeps the bridge free of per-entry object boxing and of any struct-layout agreement
/// between the two languages.
public struct AccentCostPairs: Sendable, Equatable {
    /// Substituted-from characters, as UTF-16 code units.
    public let from: [UInt16]
    /// Substituted-to characters, as UTF-16 code units.
    public let to: [UInt16]
    /// Cost of each pair, in the same order.
    public let costs: [Float]

    /// Number of pairs. The three arrays always agree on it.
    public var count: Int { costs.count }

    public var fromData: Data { from.withUnsafeBufferPointer { Data(buffer: $0) } }
    public var toData: Data { to.withUnsafeBufferPointer { Data(buffer: $0) } }
    public var costsData: Data { costs.withUnsafeBufferPointer { Data(buffer: $0) } }
}
