// DictusKeyboard/KeySoundPolicy.swift
// Which click a key produces, decided without performing the key's action.

import DictusCore

extension KeySound {
    /// The click `key` produces, or nil for keys that stay silent.
    ///
    /// WHY this exists (#286): the click used to be emitted from inside the fourteen
    /// `DictusKeyboardBridge` handlers that `didTriggerKey()` reaches, so it could only
    /// happen at the moment the key's action ran — touch-up for every letter, while the
    /// haptic had already fired on touch-down. Splitting "what does this key sound like"
    /// from "do what this key does" lets the touch layer play the click on finger contact,
    /// in step with the haptic, for keys that act on release just as much as for keys
    /// that act on contact.
    ///
    /// The table below reproduces exactly what each handler played before the split. It
    /// is a timing change, not a sound-design change: no key gained, lost or swapped a
    /// category here.
    static func category(for key: KeyDefinition) -> KeySoundCategory? {
        switch key.type {
        case .input(let character, _):
            // The emoji toggle is an `.input` key carrying the smiley rather than a type
            // of its own, and it opens a picker instead of typing — it clicked like a
            // modifier, not like a letter. `didTriggerKey` tells the two apart the same way.
            return character == KeyboardLayouts.emojiKeyGlyph ? .modifier : .letter

        case .comma, .fullStop, .tab:
            // Routed through handleInputKey, so they clicked like the letters they insert.
            return .letter

        case .backspace:
            return .delete

        case .shift, .symbols, .shiftSymbols, .spacebar, .returnkey, .keyboard,
             .keyboardMode, .splitKeyboard, .normalKeyboard,
             .sideKeyboardLeft, .sideKeyboardRight:
            return .modifier

        case .spacer, .caps:
            // Spacer is a layout element and caps is reached through double-tap shift;
            // neither ever played a sound.
            return nil
        }
    }
}
