// DictusCore/Sources/DictusCore/KeyboardMode.swift
// Shared keyboard mode enum accessible by both DictusApp and DictusKeyboard.
import Foundation

/// Keyboard mode persisted to App Group so both targets agree on the active mode.
///
/// WHY this lives in DictusCore:
/// Both the main app (settings UI, onboarding) and the keyboard extension need to read/write
/// the keyboard mode preference. Putting the enum and its persistence logic in the shared
/// framework prevents each target from defining its own incompatible version.
///
/// WHY three modes:
/// - `.micro`: Minimal layout — large mic button + minimal keys for dictation-first users
/// - `.emojiMicro`: Micro layout with emoji access — for users who also send emoji frequently
/// - `.full`: Full AZERTY/QWERTY keyboard — traditional typing experience with mic in toolbar
///
/// WHY CaseIterable:
/// The settings UI and onboarding need to iterate all modes to display a mode picker.
public enum KeyboardMode: String, CaseIterable, Codable {
    case micro
    case emojiMicro
    case full

    /// Reads the active keyboard mode from App Group UserDefaults, defaulting to `.full`.
    ///
    /// WHY `.full` as default:
    /// Existing users already have the full keyboard. Switching them to micro mode on update
    /// would be disruptive. New users choose their mode during onboarding.
    public static var active: KeyboardMode {
        guard let raw = AppGroup.defaults.string(forKey: SharedKeys.keyboardMode),
              let mode = KeyboardMode(rawValue: raw) else {
            return .full
        }
        return mode
    }

    /// User-facing display name for settings and onboarding UI.
    /// French is the primary language (see CLAUDE.md).
    public var displayName: String {
        switch self {
        case .micro: return "Micro"
        case .emojiMicro: return "Emoji+"
        case .full: return "Complet"
        }
    }
}
