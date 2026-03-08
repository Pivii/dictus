// DictusKeyboard/Models/KeyDefinition.swift
import Foundation

/// A single key on the keyboard.
enum KeyType {
    case character   // Regular letter or symbol
    case shift       // Shift / caps lock
    case delete      // Backspace
    case space       // Space bar
    case returnKey   // Return / Enter
    case globe       // Switch keyboard
    case layerSwitch // 123 / ABC toggle
    case mic         // Dictation trigger
    case symbolToggle // #+= toggle on number layer
    case emoji        // Emoji / next keyboard cycling button (replaces globe visually)
    case accentAdaptive // Context-sensitive apostrophe/accent key (AZERTY row 3)
}

struct KeyDefinition: Identifiable {
    let id = UUID()
    let label: String          // Display label
    let output: String?        // Character to insert (nil for special keys)
    let type: KeyType
    let widthMultiplier: CGFloat  // 1.0 = standard letter key width

    init(
        _ label: String,
        output: String? = nil,
        type: KeyType = .character,
        width: CGFloat = 1.0
    ) {
        self.label = label
        self.output = output ?? label
        self.type = type
        self.widthMultiplier = width
    }
}
