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
    /// French defaults to AZERTY; English and Spanish to QWERTY; German to QWERTZ (#151).
    ///
    /// This is the layout a user gets when they *select* the language. It does not
    /// rewrite a layout already stored: a German user who installed before #151 keeps
    /// QWERTY until they select German again. Nobody's keyboard changes shape on update.
    public var defaultLayout: LayoutType {
        switch self {
        case .french: return .azerty
        case .english, .spanish: return .qwerty
        case .german: return .qwertz
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

    /// Makes `language` the active keyboard language.
    ///
    /// Writes the language AND that language's `defaultLayout`, because the two
    /// are still welded together: picking English forces QWERTY. Decoupling them
    /// is #272 — until then this is the one place the pair is written, so the
    /// coupling is visible instead of being duplicated at each call site.
    ///
    /// WHY here and not in the picker view: #241 moved language selection from the
    /// toolbar into the keyboard panel, and the same two writes have to happen
    /// wherever selection ends up living. In DictusCore they are also testable —
    /// the keyboard extension target has no test bundle.
    public static func activate(_ language: SupportedLanguage) {
        AppGroup.defaults.set(language.rawValue, forKey: SharedKeys.language)
        AppGroup.defaults.set(language.defaultLayout.rawValue, forKey: SharedKeys.keyboardLayout)
    }
}
