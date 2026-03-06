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
}
