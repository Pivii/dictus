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
    /// Since #272 this is a *default*, not a rule: it seeds the layout of a language the
    /// user has never given one, and it keeps applying while they never do. The moment they
    /// pick a layout for that language, their choice wins and this stops being consulted —
    /// see `KeyboardLayoutPreference`. Nobody's keyboard changes shape on update.
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
    /// Writes the language and nothing else about the layout (#272): the layout the user
    /// now types on is whatever they chose for this language, or its default while they
    /// never chose one. Before #272 this overwrote the layout with `defaultLayout`, which
    /// is exactly what made "English autocorrect on an AZERTY keyboard" unreachable.
    ///
    /// WHY here and not in the picker view: #241 moved language selection from the
    /// toolbar into the keyboard panel, and the same write has to happen wherever
    /// selection ends up living. In DictusCore it is also testable — the keyboard
    /// extension target has no test bundle.
    public static func activate(_ language: SupportedLanguage) {
        // Before the language moves: the #272 migration freezes the stored layout under
        // whichever language is active *at that moment*, and that has to be the one the
        // user has been typing on, not the one they are switching to.
        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        AppGroup.defaults.set(language.rawValue, forKey: SharedKeys.language)
        // The mirror describes the active language's layout, so it is computed after the
        // switch — see `KeyboardLayoutPreference.mirrorToLegacyKey`.
        KeyboardLayoutPreference.mirrorToLegacyKey(KeyboardLayoutPreference.layout(for: language))
    }
}
