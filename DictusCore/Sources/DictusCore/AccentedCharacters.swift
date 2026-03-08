// DictusCore/Sources/DictusCore/AccentedCharacters.swift
// French accented character mappings for long-press popups on the keyboard.
import Foundation

/// Accented character variants for French AZERTY keyboard long-press popups.
///
/// WHY precomposed Unicode characters (e.g., \u{00E9}) instead of combining characters:
/// Combining characters (e.g., "e" + combining acute \u{0301}) can cause string comparison
/// issues and display inconsistencies. Precomposed forms are single code points that render
/// identically everywhere. This is how iOS system keyboards store accented characters.
public enum AccentedCharacters {

    /// Maps a base letter (lowercase) to its accented variants.
    /// Covers all French AZERTY accented characters plus n-tilde (standard on iOS keyboards).
    public static let mappings: [String: [String]] = [
        "e": ["\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}"],  // e acute, grave, circumflex, diaeresis
        "a": ["\u{00E0}", "\u{00E2}", "\u{00E4}"],              // a grave, circumflex, diaeresis
        "u": ["\u{00F9}", "\u{00FB}", "\u{00FC}"],              // u grave, circumflex, diaeresis
        "i": ["\u{00EE}", "\u{00EF}"],                          // i circumflex, diaeresis
        "o": ["\u{00F4}", "\u{00F6}"],                          // o circumflex, diaeresis
        "c": ["\u{00E7}"],                                      // c cedilla
        "y": ["\u{00FF}"],                                      // y diaeresis
        "n": ["\u{00F1}"]                                       // n tilde
    ]

    /// Returns accented variants for a given key, or nil if no accents exist.
    /// Lookup is case-insensitive: "E" and "e" return the same result.
    ///
    /// WHY case-insensitive:
    /// The keyboard layout stores uppercase labels ("E") but the user may be typing
    /// in either case. The accented variants are always lowercase — the keyboard target
    /// applies case transformation based on shift state.
    public static func accents(for key: String) -> [String]? {
        return mappings[key.lowercased()]
    }

    // MARK: - Adaptive accent key support

    /// Default accent per vowel (most common in French).
    /// Used by the adaptive accent key on AZERTY row 3.
    public static let defaultAccents: [String: String] = [
        "e": "\u{00E9}",  // e-acute (most common French accent)
        "a": "\u{00E0}",  // a-grave
        "u": "\u{00F9}",  // u-grave
        "i": "\u{00EE}",  // i-circumflex
        "o": "\u{00F4}",  // o-circumflex
    ]

    /// Returns what the adaptive key should display based on the last typed character.
    /// After a vowel: shows the most common accent for that vowel.
    /// Otherwise: shows apostrophe (').
    ///
    /// WHY apostrophe as default:
    /// In French, the apostrophe is the most common non-letter character after space.
    /// It appears in "l'", "d'", "n'", "j'", "c'", "s'" etc. Having it one tap away
    /// on the letters layer eliminates the 3-tap layer switch currently needed.
    public static func adaptiveKeyLabel(afterTyping lastChar: String?) -> String {
        guard let lastChar = lastChar?.lowercased() else { return "'" }
        if let accent = defaultAccents[lastChar] { return accent }
        return "'"
    }

    /// Returns the base vowel that triggered the adaptive key's accent display.
    /// Used to determine which accent variants to show on long-press.
    /// Returns nil when the adaptive key is showing apostrophe (no long-press popup needed).
    public static func adaptiveKeyVowel(afterTyping lastChar: String?) -> String? {
        guard let lastChar = lastChar?.lowercased() else { return nil }
        return defaultAccents[lastChar] != nil ? lastChar : nil
    }
}
