// DictusCore/Sources/DictusCore/SupportedLanguage.swift
// Type-safe language representation shared between DictusApp and DictusKeyboard.
import Foundation

/// Languages supported by Dictus for transcription, autocorrect, and predictions.
///
/// WHY an enum instead of raw strings:
/// Language codes were previously scattered as "fr"/"en" string literals across
/// SettingsView, KeyboardViewController, TextPredictionEngine, and TranscriptionService.
/// A single enum prevents typos, centralizes display names and layout defaults,
/// and makes adding new languages a one-place change.
public enum SupportedLanguage: String, CaseIterable, Codable, Sendable {
    case french = "fr"
    case english = "en"
    case spanish = "es"
    case german = "de"

    /// Localized display name for settings UI.
    public var displayName: String {
        switch self {
        case .french: return "Fran\u{00E7}ais"
        case .english: return "English"
        case .spanish: return "Espa\u{00F1}ol"
        case .german: return "Deutsch"
        }
    }

    /// Two-letter uppercase code for the keyboard toolbar language switcher.
    public var shortCode: String { rawValue.uppercased() }

    /// Default keyboard layout for this language.
    /// French defaults to AZERTY; English, Spanish, and German default to QWERTY.
    /// (German QWERTZ is deferred to follow-up issue #151.)
    public var defaultLayout: LayoutType {
        switch self {
        case .french: return .azerty
        case .english, .spanish, .german: return .qwerty
        }
    }

    /// Spacebar label matching each language's convention.
    public var spaceName: String {
        switch self {
        case .french: return "espace"
        case .english: return "space"
        case .spanish: return "espacio"
        case .german: return "Leertaste"
        }
    }

    /// Return key label matching each language's convention.
    public var returnName: String {
        switch self {
        case .french: return "retour"
        case .english: return "return"
        case .spanish: return "intro"
        case .german: return "Eingabe"
        }
    }

    /// Reads the active language from App Group, defaulting to French.
    public static var active: SupportedLanguage {
        guard let raw = AppGroup.defaults.string(forKey: SharedKeys.language),
              let lang = SupportedLanguage(rawValue: raw) else {
            return .french
        }
        return lang
    }

    /// Cycles to the next language in order: fr -> en -> es -> fr.
    /// Used by the keyboard toolbar language switcher on tap.
    public func next() -> SupportedLanguage {
        let all = SupportedLanguage.allCases
        guard let idx = all.firstIndex(of: self) else { return .french }
        return all[(idx + 1) % all.count]
    }
}
