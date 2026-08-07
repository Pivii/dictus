// DictusCore/Sources/DictusCore/KeyCaseTransform.swift
// Case transformation for keyboard keys, where Unicode's one-to-many uppercase
// mappings would otherwise turn one key into two characters.
import Foundation

/// Uppercasing for keyboard keys and long-press candidates.
///
/// WHY not `String.uppercased()` at the call sites:
/// `uppercased()` implements Unicode's *full* case mapping, in which a few characters
/// uppercase to more than one character — `"\u{00DF}".uppercased() == "SS"`. A key is
/// one character by construction: the long-press popup renders the string as a single
/// key and the bridge inserts it verbatim, so `SS` drew one key that typed two letters
/// (#322). This namespace keeps the transformation one character in, one character out.
///
/// The mapping is a property of the character, not of the keyboard showing it, so it
/// stays layout- and language-agnostic: no caller passes a language in.
public enum KeyCaseTransform {

    /// Single-character uppercase forms for the characters whose Unicode uppercase
    /// mapping is one-to-many.
    ///
    /// ß → ẞ (U+1E9E LATIN CAPITAL LETTER SHARP S): Unicode has carried the capital
    /// sharp s since 5.1 and German orthography has permitted it since the 2017 spelling
    /// reform, and it is what iOS itself offers on shift plus long-press `s`. Unicode
    /// still maps ß to `SS` for compatibility with the historical rule, which is why the
    /// intended capital has to be spelled out here.
    private static let singleCharacterUppercase: [Character: Character] = [
        "\u{00DF}": "\u{1E9E}"   // ß → ẞ
    ]

    /// The uppercase form of a key, never longer than the key it came from.
    ///
    /// One-to-one mappings (é → É, ä → Ä, ñ → Ñ …) go straight through `uppercased()`,
    /// which is what every accent candidate but ß uses. A character whose uppercase would
    /// be longer takes its declared single-character capital, and is otherwise left as it
    /// is: a lowercase glyph on a shifted page is a cosmetic surprise, whereas two
    /// characters out of one key is wrong text.
    ///
    /// WHY counting `Character`s rather than unicode scalars: a grapheme cluster is what
    /// renders as one key and inserts as one glyph. `ǰ` uppercases to `J` plus a combining
    /// caron — two scalars, one grapheme — and passing that through is correct.
    public static func uppercased(_ key: String) -> String {
        var result = ""
        for character in key {
            let uppercasedCharacter = character.uppercased()
            if uppercasedCharacter.count == 1 {
                result += uppercasedCharacter
            } else if let single = singleCharacterUppercase[character] {
                result.append(single)
            } else {
                result.append(character)
            }
        }
        return result
    }
}
