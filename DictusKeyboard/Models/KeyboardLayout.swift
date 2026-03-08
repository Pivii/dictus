// DictusKeyboard/Models/KeyboardLayout.swift
import Foundation
import DictusCore

/// Defines keyboard layouts (AZERTY and QWERTY) matching iOS native French keyboard.
///
/// WHY two separate static arrays instead of one computed property:
/// The layout data is constant — only the selection between them changes at runtime.
/// Using static lets avoids re-creating KeyDefinition arrays on every frame during
/// SwiftUI redraws. The dynamic selection happens only in `currentLettersRows()`.
enum KeyboardLayout {

    // MARK: - AZERTY Letters layer (default for French users)

    static let lettersRows: [[KeyDefinition]] = [
        // Row 1: top letter row
        ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"].map {
            KeyDefinition($0, output: $0.lowercased())
        },
        // Row 2: home row
        ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"].map {
            KeyDefinition($0, output: $0.lowercased())
        },
        // Row 3: bottom letter row with shift, adaptive accent key, and delete.
        // The adaptive accent key sits between N and delete — it shows apostrophe
        // by default, switching to the most common accent after typing a vowel.
        [
            KeyDefinition("shift", type: .shift, width: 1.5),
            KeyDefinition("W", output: "w"),
            KeyDefinition("X", output: "x"),
            KeyDefinition("C", output: "c"),
            KeyDefinition("V", output: "v"),
            KeyDefinition("B", output: "b"),
            KeyDefinition("N", output: "n"),
            KeyDefinition("'", type: .accentAdaptive, width: 1.0),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: bottom function row.
        // Emoji replaces globe (emoji icon instead of globe icon, same advanceToNextInputMode behavior).
        // Mic removed from layout — it lives in the toolbar (Plan 03-02).
        // Mic's width redistributed to space bar for a wider touch target.
        [
            KeyDefinition("emoji", type: .emoji, width: 1.2),
            KeyDefinition("123", type: .layerSwitch, width: 1.2),
            KeyDefinition("space", output: " ", type: .space, width: 4.5),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]

    // MARK: - QWERTY Letters layer (when user selects QWERTY in settings)

    /// QWERTY layout converted from DictusCore's QWERTYLayout string arrays to KeyDefinitions.
    /// Row 4 has no mic key -- the mic button lives in the toolbar (Plan 03-02).
    /// The mic key's width is redistributed to the space bar for a wider touch target.
    static let qwertyLettersRows: [[KeyDefinition]] = [
        // Row 1: top letter row
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"].map {
            KeyDefinition($0, output: $0.lowercased())
        },
        // Row 2: home row
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"].map {
            KeyDefinition($0, output: $0.lowercased())
        },
        // Row 3: bottom letter row with shift and delete
        [
            KeyDefinition("shift", type: .shift, width: 1.5),
            KeyDefinition("Z", output: "z"),
            KeyDefinition("X", output: "x"),
            KeyDefinition("C", output: "c"),
            KeyDefinition("V", output: "v"),
            KeyDefinition("B", output: "b"),
            KeyDefinition("N", output: "n"),
            KeyDefinition("M", output: "m"),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: bottom function row (no mic -- mic is in toolbar per Plan 03-02)
        // Emoji replaces globe — same as AZERTY. No adaptive accent key on QWERTY (Apple convention).
        [
            KeyDefinition("emoji", type: .emoji, width: 1.2),
            KeyDefinition("123", type: .layerSwitch, width: 1.2),
            KeyDefinition("space", output: " ", type: .space, width: 5.7),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]

    // MARK: - Dynamic Layout Selection

    /// Returns the correct letter rows based on the user's layout preference in App Group.
    ///
    /// WHY a static function instead of a computed property:
    /// This reads from UserDefaults on every call (to pick up preference changes without
    /// requiring a restart). Making it a function signals to callers that there's a side
    /// effect (I/O) happening, unlike a property which implies a lightweight computation.
    static func currentLettersRows() -> [[KeyDefinition]] {
        switch LayoutType.active {
        case .qwerty:
            return qwertyLettersRows
        case .azerty:
            return lettersRows
        }
    }

    // MARK: - Numbers layer
    // Note: Mic key is intentionally absent from numbers/symbols layers,
    // matching native iOS behavior where the mic is letters-layer only.

    static let numbersRows: [[KeyDefinition]] = [
        // Row 1: numbers
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map {
            KeyDefinition($0)
        },
        // Row 2: common symbols
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""].map {
            KeyDefinition($0)
        },
        // Row 3: more symbols + toggle + delete
        [
            KeyDefinition("#+=", type: .symbolToggle, width: 1.5),
            KeyDefinition(".", output: "."),
            KeyDefinition(",", output: ","),
            KeyDefinition("?", output: "?"),
            KeyDefinition("!", output: "!"),
            KeyDefinition("'", output: "'"),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: back to letters + space + return (no mic — letters only)
        // Emoji replaces globe for consistency across all layers.
        [
            KeyDefinition("ABC", type: .layerSwitch, width: 1.2),
            KeyDefinition("emoji", type: .emoji, width: 1.2),
            KeyDefinition("space", output: " ", type: .space, width: 4.7),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]

    // MARK: - Symbols layer (accessed via #+= on numbers layer)

    static let symbolsRows: [[KeyDefinition]] = [
        // Row 1: brackets and math
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map {
            KeyDefinition($0)
        },
        // Row 2: special characters
        ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "·"].map {
            KeyDefinition($0)
        },
        // Row 3: toggle back + more + delete
        [
            KeyDefinition("123", type: .symbolToggle, width: 1.5),
            KeyDefinition(".", output: "."),
            KeyDefinition(",", output: ","),
            KeyDefinition("?", output: "?"),
            KeyDefinition("!", output: "!"),
            KeyDefinition("'", output: "'"),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: same as numbers — emoji replaces globe
        [
            KeyDefinition("ABC", type: .layerSwitch, width: 1.2),
            KeyDefinition("emoji", type: .emoji, width: 1.2),
            KeyDefinition("space", output: " ", type: .space, width: 4.7),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]
}
