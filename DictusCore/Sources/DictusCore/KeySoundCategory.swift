// DictusCore/Sources/DictusCore/KeySoundCategory.swift
// The three key-click categories the keyboard plays, and the system sound each maps to.
import Foundation

/// Which of the three iOS keyboard clicks a key produces.
///
/// The split into letter / delete / modifier comes from giellakbd-ios and matches what
/// Apple's own keyboard does: typing sounds different from deleting, which sounds
/// different from a layer switch.
///
/// Lives in DictusCore rather than DictusKeyboard so the identifiers are unit-testable —
/// the keyboard extension target has no test bundle. Same reasoning as `KeyboardAreaMode`
/// and `LayoutType`. The keyboard target keeps the other half of the decision: which
/// category a given key belongs to (`KeySound.category(for:)`).
public enum KeySoundCategory: String, Equatable, CaseIterable, Sendable {
    /// Character insertion — letters, digits, punctuation, the adaptive accent key.
    case letter
    /// Backspace, including each tick of an accelerated repeat.
    case delete
    /// Everything that is not text: shift, the symbol layers, space, return, emoji, globe.
    case modifier

    /// AudioServices system sound identifier for this category.
    ///
    /// `UInt32` rather than `SystemSoundID` so DictusCore stays free of AudioToolbox;
    /// `SystemSoundID` is a type alias for `UInt32`, so call sites pass this straight to
    /// `AudioServicesPlaySystemSound`. That API respects the hardware silent switch
    /// natively, which is why the keyboard uses it rather than an audio player.
    public var systemSoundID: UInt32 {
        switch self {
        case .letter: return 1104
        case .delete: return 1155
        case .modifier: return 1156
        }
    }
}
