// DictusCore/Sources/DictusCore/KeyboardLayoutData.swift
// Shared keyboard layout data accessible by both DictusApp and DictusKeyboard.
import Foundation

/// Keyboard layout type persisted to App Group so both targets agree on the active layout.
///
/// WHY this lives in DictusCore:
/// Both the main app (settings UI) and the keyboard extension need to read/write the
/// layout preference. Putting the enum and its persistence logic in the shared framework
/// prevents each target from defining its own incompatible version.
/// WHY the raw values are frozen:
/// The raw string is what sits in App Group UserDefaults on every installed device.
/// Renaming a case renames the persisted value, and every keyboard already holding
/// the old string would silently fall back to AZERTY on the next launch.
public enum LayoutType: String, Codable, Sendable, CaseIterable {
    case azerty
    case qwerty
    case qwertz

    /// Label shown wherever a layout is named in the UI (Settings picker, keyboard panel).
    ///
    /// WHY not `rawValue.uppercased()`: the Settings picker and the keyboard panel used to
    /// spell their labels independently, so a new layout meant editing both. Naming them
    /// once here means adding a case is the whole change (#151).
    public var displayName: String {
        switch self {
        case .azerty: return "AZERTY"
        case .qwerty: return "QWERTY"
        case .qwertz: return "QWERTZ"
        }
    }

    /// The layout the keyboard is currently drawing: the active language's layout.
    ///
    /// Since #272 the layout is stored per dictionary language, so "the active layout" is a
    /// resolution of two values rather than one stored string. Every consumer — the grid
    /// builder, the trie's proximity map, the spacebar neighbours, the emoji picker — keeps
    /// reading it here; only what backs it changed. See `KeyboardLayoutPreference`.
    public static var active: LayoutType {
        KeyboardLayoutPreference.layout(for: .active)
    }
}

/// QWERTY letter layout as raw string arrays.
///
/// WHY string arrays instead of KeyDefinition:
/// KeyDefinition lives in DictusKeyboard and carries UI-specific properties (widthMultiplier,
/// KeyType). DictusCore shouldn't depend on UI types. The keyboard target converts these
/// strings to KeyDefinition at the view layer. This also makes the layout data easily testable.
public enum QWERTYLayout {
    /// Four rows of key labels.
    /// - Row 0: 10 letter keys (Q through P)
    /// - Row 1: 9 letter keys (A through L)
    /// - Row 2: 7 letter keys (Z through M) — shift and delete are added by keyboard target
    /// - Row 3: 5 bottom row placeholders — actual rendering handled by keyboard target
    public static let lettersRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
        ["globe", "123", "mic", "space", "return"]
    ]
}

/// QWERTZ letter layout as raw string arrays — the German layout (#151).
///
/// Rows, in order: `Q W E R T Z U I O P Ü` / `A S D F G H J K L Ö Ä` / `Y X C V B N M`.
/// That is the layout iOS ships as its *default* German keyboard and the one the
/// AOSP-derived open-source keyboards build: ü closes the top row, ö and ä close the
/// home row. Apple's second German entry (labelled "QWERTZ" in iOS settings) hides the
/// umlauts behind a long-press to keep the remaining keys wider; Dictus does not ship
/// that variant — if it is ever wanted it is a separate layout, not a change to this one.
///
/// There is no dedicated ß on either platform. It stays a long-press on `s`
/// (`AccentedCharacters.mappings`).
///
/// WHY the rows live here and not only in `KeyboardLayouts` (DictusKeyboard):
/// the keyboard extension has no test target — `swift test` builds this package alone —
/// so row data declared only in the extension cannot be pinned by a test. The keyboard
/// builds its `KeyDefinition`s from these arrays, which keeps the test measuring what
/// actually renders instead of a copy.
public enum QWERTZLayout {
    /// Unit width of the shift and delete keys flanking row 3 — the same 1.5 the other
    /// layouts use. Declared here, and read by the keyboard, so `rowUnitWidths` below is
    /// derived from the value the renderer uses rather than restating it.
    public static let flankKeyUnitWidth: Double = 1.5

    /// The three letter rows, uppercase (the shifted page). Matches the `QWERTYLayout`
    /// convention: layout data stores uppercase, the keyboard lowercases for the normal page.
    /// Row 3 holds letters only — shift and delete are added by the keyboard target.
    public static let lettersRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "\u{00DC}"],   // …P Ü
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", "\u{00D6}", "\u{00C4}"],   // …L Ö Ä
        ["Y", "X", "C", "V", "B", "N", "M"]
    ]

    /// The same three rows lowercased — the normal (unshifted) page.
    public static var lowercasedLettersRows: [[String]] {
        lettersRows.map { row in row.map { $0.lowercased() } }
    }

    /// Total unit width of each letter row as rendered.
    ///
    /// Rows 1 and 2 total **11** where every other row in every layout totals 10. That
    /// asymmetry is the specification, not an oversight: the renderer normalizes each row
    /// against its own unit total (`KeyboardView.sizeForItemAt`), so the umlaut rows simply
    /// render slightly narrower keys — exactly what iOS and Android do. Padding them back
    /// to 10 with spacers would push the umlauts off the edge of the row.
    public static let rowUnitWidths: [Double] = [
        Double(lettersRows[0].count),                                  // 11 input keys
        Double(lettersRows[1].count),                                  // 11 input keys
        flankKeyUnitWidth * 2 + Double(lettersRows[2].count)           // shift + 7 + delete = 10
    ]
}
