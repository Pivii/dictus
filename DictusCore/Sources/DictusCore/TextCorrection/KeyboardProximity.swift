// DictusCore/Sources/DictusCore/TextCorrection/KeyboardProximity.swift
// Key geometry per layout, and the pairwise proximity costs the keyboard's C++ scorer
// reads to score a typo as a near miss rather than as an unrelated character.
import Foundation

/// Where each key sits on a layout, and how much it costs the trie scorer to substitute
/// one key for another.
///
/// WHY this lives in DictusCore and not in the C++ that consumes it:
/// the geometry is data and the formula runs **once per dictionary load**, not per
/// keystroke — so moving both here costs nothing at runtime and buys the only executable
/// coverage this repo has (`swift test` builds this package alone; the keyboard target has
/// no test bundle). The scorer's hot loop stays in C++ and reads the finished table.
///
/// WHY it had to move for German (#321): the C++ stored `float[26][26]` indexed by
/// `c - 'a'`. There was no slot for ü, ö or ä — QWERTZ's three extra keys were not
/// mis-scored, they were unrepresentable, and QWERTZ borrowed the QWERTY table where
/// y and z sit in each other's places.
public enum KeyboardProximity {

    /// Divisor turning a key-unit euclidean distance into a cost in [0, 1]: keys 2.5 key
    /// widths apart or more score 1.0, the same as unrelated. Frozen — it scales every
    /// proximity cost in every layout.
    public static let distanceNormalizer: Double = 2.5

    /// A key and its centre, in key-width units. `x` counts from the left edge of the row
    /// block, `y` is the row index (0 = top letter row).
    public struct KeyPosition: Sendable, Equatable {
        public let character: Character
        public let x: Double
        public let y: Double
    }

    /// The key centres of `layout`, in row order then left-to-right.
    public static func keyPositions(for layout: LayoutType) -> [KeyPosition] {
        rows(for: layout).enumerated().flatMap { rowIndex, row -> [KeyPosition] in
            let width = keyWidth(forKeyCount: row.keys.count)
            return row.keys.enumerated().map { keyIndex, character in
                // Centre of the key: its left edge plus half a key, shifted so that a
                // plain 10-key row places its keys at x = 0…9 (the coordinates the
                // AZERTY and QWERTY tables have always used).
                KeyPosition(
                    character: character,
                    x: row.xOffset + (Double(keyIndex) + 0.5) * width - 0.5,
                    y: Double(rowIndex)
                )
            }
        }
    }

    /// Pairwise proximity costs for `layout`, ready to install in the scorer.
    public static func costTable(for layout: LayoutType) -> ProximityCostTable {
        let positions = keyPositions(for: layout)
        let characters = positions.compactMap { $0.character.singleUTF16CodeUnit }
        // compactMap above would silently shorten the table if a key were not one code
        // unit; the geometry below indexes positions, so bail to a neutral table instead.
        guard characters.count == positions.count else {
            return ProximityCostTable(characters: [], distances: [])
        }

        var distances = [Float](repeating: 1.0, count: positions.count * positions.count)
        for (i, from) in positions.enumerated() {
            for (j, to) in positions.enumerated() {
                distances[i * positions.count + j] = i == j ? 0 : cost(from: from, to: to)
            }
        }
        return ProximityCostTable(characters: characters, distances: distances)
    }

    /// Cost between two key centres: euclidean distance in key widths, normalized and
    /// clamped to 1.0.
    static func cost(from: KeyPosition, to: KeyPosition) -> Float {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return Float(min(1.0, (dx * dx + dy * dy).squareRoot() / distanceNormalizer))
    }

    // MARK: - Layout geometry

    /// One letter row as the proximity model sees it. Modifier and bottom-row keys are
    /// absent: the scorer only ever asks about letters.
    private struct KeyRow {
        let keys: [Character]
        /// Units the row's first key edge sits right of the row block's left edge.
        let xOffset: Double
    }

    /// Width of one key in a row of `count` keys, in the shared 10-unit row space.
    ///
    /// Rows of 10 keys or fewer keep unit-wide keys, which is what the AZERTY and QWERTY
    /// coordinates have always assumed. QWERTZ's 11-key rows render in the same width as
    /// every other row (`QWERTZLayout.rowUnitWidths` — the renderer normalizes each row
    /// against its own unit total), so their keys are 10/11 of a unit and every key on
    /// those rows sits slightly left of where its QWERTY counterpart would: the geometry
    /// shift #321 asks to model.
    private static func keyWidth(forKeyCount count: Int) -> Double {
        10.0 / Double(max(10, count))
    }

    private static func rows(for layout: LayoutType) -> [KeyRow] {
        switch layout {
        case .azerty:
            // AZERTY row data lives in the keyboard target (`KeyboardLayouts.azerty`), not
            // in DictusCore, so unlike the other two this sequence is declared here.
            // Moving it is a layout refactor and out of scope for #321.
            return [
                KeyRow(keys: Array("azertyuiop"), xOffset: 0),
                KeyRow(keys: Array("qsdfghjklm"), xOffset: 0.25),
                KeyRow(keys: Array("wxcvbn"), xOffset: 0.75)
            ]
        case .qwerty:
            // Sequence read from the layout data the keyboard renders, so the proximity
            // model cannot drift from the keys that actually exist.
            let letterRows = QWERTYLayout.lettersRows.prefix(3).map(letters)
            let offsets: [Double] = [0, 0.25, 0.75]
            return zip(letterRows, offsets).map { KeyRow(keys: $0, xOffset: $1) }
        case .qwertz:
            // Rows 0 and 1 carry 11 keys and start flush with the row block: ü closes the
            // top row, ö and ä the home row. Row 2 keeps the same 0.75 offset the other
            // layouts use, so the three stay comparable — no layout models the shift and
            // delete keys flanking that row.
            let letterRows = QWERTZLayout.lowercasedLettersRows.map(letters)
            let offsets: [Double] = [0, 0, 0.75]
            return zip(letterRows, offsets).map { KeyRow(keys: $0, xOffset: $1) }
        }
    }

    /// The single-letter key labels of a layout row, lowercased. Drops anything that is
    /// not one letter (`"globe"`, `"123"`), which the scorer never asks about.
    private static func letters(_ row: [String]) -> [Character] {
        row.compactMap { label in
            let lowered = label.lowercased()
            guard lowered.count == 1, let character = lowered.first, character.isLetter else {
                return nil
            }
            return character
        }
    }
}

/// Pairwise proximity costs for one layout, as the flat buffers the scorer installs.
///
/// WHY a finished table rather than the key positions: the C++ then holds no formula of
/// its own, so the numbers a test pins here are exactly the numbers the scorer scores with.
public struct ProximityCostTable: Sendable, Equatable {
    /// The layout's keys, as UTF-16 code units, in table row/column order.
    public let characters: [UInt16]
    /// `characters.count * characters.count` costs, row-major.
    public let distances: [Float]

    /// Number of keys the table covers.
    public var count: Int { characters.count }

    /// Cost of substituting `from` for `to` on this layout.
    /// Returns 1.0 — "unrelated" — when either key is absent from the layout, which is
    /// what a long-press-only character (ü on QWERTY) correctly gets: it has no position.
    public func cost(from: Character, to: Character) -> Float {
        guard let fromUnit = from.singleUTF16CodeUnit,
              let toUnit = to.singleUTF16CodeUnit,
              let row = characters.firstIndex(of: fromUnit),
              let column = characters.firstIndex(of: toUnit) else { return 1.0 }
        return distances[row * count + column]
    }

    public var charactersData: Data { characters.withUnsafeBufferPointer { Data(buffer: $0) } }
    public var distancesData: Data { distances.withUnsafeBufferPointer { Data(buffer: $0) } }
}
