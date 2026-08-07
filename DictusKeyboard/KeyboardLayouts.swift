// DictusKeyboard/KeyboardLayouts.swift
// AZERTY, QWERTY and QWERTZ layout definitions in giellakbd-ios KeyboardDefinition format.
// Supports French, English, Spanish and German with language-aware labels.

import UIKit
import DictusCore

/// Constructs KeyboardDefinition objects for all supported layouts.
///
/// These layouts are built programmatically (not from JSON) using the same KeyDefinition
/// types as the vendored giellakbd-ios codebase. Each layout includes 5 pages:
/// normal, shifted, capslock (same visual as shifted), symbols1 (numbers), symbols2 (symbols).
///
/// Bottom row on letter pages: [123] [emoji] [space] [return] -- emoji key added in Phase 20.
/// Globe key is provided by iOS below third-party keyboards -- not part of our layout.
enum KeyboardLayouts {

    /// Glyph carried by the emoji-picker toggle key.
    ///
    /// The toggle has no `KeyType` of its own — it is an `.input` key whose character is
    /// the smiley, and everything downstream tells it apart from a typed character by
    /// comparing against this glyph. Naming it once keeps those comparisons in step
    /// (`DictusKeyboardBridge.didTriggerKey`, `editsDocument`, `KeySound.category(for:)`).
    static let emojiKeyGlyph = "\u{1F600}"

    // MARK: - Public API

    /// AZERTY layout (default for French).
    static func azerty(lang: SupportedLanguage = .active, needsGlobe: Bool) -> KeyboardDefinition {
        return KeyboardDefinition(
            name: lang.displayName,
            locale: lang.rawValue,
            spaceName: lang.spaceName,
            returnName: lang.returnName,
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: azertyNormal(lang: lang, needsGlobe: needsGlobe),
                shifted: azertyShifted(lang: lang, needsGlobe: needsGlobe),
                symbols1: numbersPage(lang: lang, needsGlobe: needsGlobe),
                symbols2: symbolsPage(lang: lang, needsGlobe: needsGlobe)
            )
        )
    }

    /// QWERTY layout (default for English and Spanish).
    static func qwerty(lang: SupportedLanguage = .active, needsGlobe: Bool) -> KeyboardDefinition {
        return KeyboardDefinition(
            name: lang.displayName + (lang == .french ? " (QWERTY)" : ""),
            locale: lang.rawValue,
            spaceName: lang.spaceName,
            returnName: lang.returnName,
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: qwertyNormal(lang: lang, needsGlobe: needsGlobe),
                shifted: qwertyShifted(lang: lang, needsGlobe: needsGlobe),
                symbols1: numbersPage(lang: lang, needsGlobe: needsGlobe),
                symbols2: symbolsPage(lang: lang, needsGlobe: needsGlobe)
            )
        )
    }

    /// QWERTZ layout (default for German).
    ///
    /// Rows 1 and 2 carry 11 keys where the other two layouts carry 10: ü closes the top
    /// row, ö and ä close the home row. That is the layout iOS ships as its default German
    /// keyboard and the one the AOSP-derived keyboards build. The row data itself lives in
    /// `DictusCore.QWERTZLayout` so it can be covered by tests — the keyboard target has no
    /// test bundle.
    static func qwertz(lang: SupportedLanguage = .active, needsGlobe: Bool) -> KeyboardDefinition {
        return KeyboardDefinition(
            name: lang.displayName + (lang == .german ? "" : " (QWERTZ)"),
            locale: lang.rawValue,
            spaceName: lang.spaceName,
            returnName: lang.returnName,
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: qwertzNormal(lang: lang, needsGlobe: needsGlobe),
                shifted: qwertzShifted(lang: lang, needsGlobe: needsGlobe),
                symbols1: numbersPage(lang: lang, needsGlobe: needsGlobe),
                symbols2: symbolsPage(lang: lang, needsGlobe: needsGlobe)
            )
        )
    }

    /// Returns the layout matching the user's App Group preferences.
    ///
    /// - Parameter needsGlobe: pass `UIInputViewController.needsInputModeSwitchKey`. When true
    ///   (iPad, older iPhones) a next-keyboard globe is added; when false (recent iPhones where
    ///   the system draws its own globe) the layout is unchanged. Required by App Store
    ///   Guideline 4.4.1.
    static func current(needsGlobe: Bool) -> KeyboardDefinition {
        let lang = SupportedLanguage.active
        switch LayoutType.active {
        case .azerty: return azerty(lang: lang, needsGlobe: needsGlobe)
        case .qwerty: return qwerty(lang: lang, needsGlobe: needsGlobe)
        case .qwertz: return qwertz(lang: lang, needsGlobe: needsGlobe)
        }
    }

    // MARK: - AZERTY Letter Pages

    private static func azertyNormal(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        [
            // Row 1: 10 keys
            inputRow("a", "z", "e", "r", "t", "y", "u", "i", "o", "p"),
            // Row 2: 10 keys
            inputRow("q", "s", "d", "f", "g", "h", "j", "k", "l", "m"),
            // Row 3: shift + 6 letters + accent key + delete = 9 items (10 units)
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("w"), key("x"), key("c"), key("v"), key("b"), key("n"),
                KeyDefinition(type: .input(key: "'", alternate: "accent")),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1))
            ],
            // Row 4: 123 + emoji + space + return
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    private static func azertyShifted(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        [
            // Row 1: uppercase
            inputRow("A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"),
            // Row 2: uppercase
            inputRow("Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"),
            // Row 3: shift (filled state handled by KeyView) + uppercase letters + accent key + delete
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("W"), key("X"), key("C"), key("V"), key("B"), key("N"),
                KeyDefinition(type: .input(key: "'", alternate: "accent")),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1))
            ],
            // Row 4: same as normal
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    // MARK: - QWERTY Letter Pages

    private static func qwertyNormal(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        [
            // Row 1: 10 keys = 10 units
            inputRow("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
            // Row 2: 9 keys with side spacers = 10 units (matches Apple QWERTY centering)
            [
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                key("a"), key("s"), key("d"), key("f"), key("g"), key("h"), key("j"), key("k"), key("l"),
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1))
            ],
            // Row 3: shift + 7 letters + delete = 10 units
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("z"), key("x"), key("c"), key("v"), key("b"), key("n"), key("m"),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1))
            ],
            // Row 4: unified bottom row (123 + emoji + space + return)
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    private static func qwertyShifted(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        [
            inputRow("Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"),
            [
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                key("A"), key("S"), key("D"), key("F"), key("G"), key("H"), key("J"), key("K"), key("L"),
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1))
            ],
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("Z"), key("X"), key("C"), key("V"), key("B"), key("N"), key("M"),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1))
            ],
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    // MARK: - QWERTZ Letter Pages

    private static func qwertzNormal(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        qwertzPage(rows: QWERTZLayout.lowercasedLettersRows, lang: lang, needsGlobe: needsGlobe)
    }

    private static func qwertzShifted(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        qwertzPage(rows: QWERTZLayout.lettersRows, lang: lang, needsGlobe: needsGlobe)
    }

    /// Builds a QWERTZ letter page from the three letter rows of `QWERTZLayout`.
    ///
    /// WHY one builder for both cases, unlike AZERTY and QWERTY: those two spell their
    /// normal and shifted rows out twice because the rows differ in more than case (the
    /// AZERTY accent key, the QWERTY spacers). QWERTZ has neither, so the pages differ
    /// only by which of the two arrays is passed in.
    ///
    /// Rows 1 and 2 total 11 units against 10 everywhere else. That is deliberate: the
    /// renderer normalizes each row against its own unit total (`KeyboardView`), so the
    /// umlaut rows render slightly narrower keys — what iOS and Android both do. Do NOT
    /// pad them to 10 with spacers; that would push ü/ä off the edge of the row.
    private static func qwertzPage(rows: [[String]],
                                   lang: SupportedLanguage,
                                   needsGlobe: Bool) -> [[KeyDefinition]] {
        let flankSize = CGSize(width: QWERTZLayout.flankKeyUnitWidth, height: 1)
        return [
            // Row 1: 11 keys = 11 units (…o p ü)
            rows[0].map { key($0) },
            // Row 2: 11 keys = 11 units (…k l ö ä)
            rows[1].map { key($0) },
            // Row 3: shift + 7 letters + delete = 10 units
            [KeyDefinition(type: .shift, size: flankSize)]
                + rows[2].map { key($0) }
                + [KeyDefinition(type: .backspace, size: flankSize)],
            // Row 4: unified bottom row (123 + emoji + space + return)
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    // MARK: - Numbers Page (symbols1)

    private static func numbersPage(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        [
            // Row 1: digits
            inputRow("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
            // Row 2: common punctuation and symbols
            inputRow("-", "/", ":", ";", "(", ")", "\u{20AC}", "&", "@", "\""),
            // Row 3: #+= toggle + punctuation + delete
            [
                KeyDefinition(type: .shiftSymbols, size: CGSize(width: 1.5, height: 1)),
                // #+= and delete keep width 1.5 (identical to shift/delete on the letter pages).
                // The 5 punctuation keys are widened to 1.2 with small 0.5 end spacers so the
                // row totals 10 units and the cluster sits tighter -- matching Apple.
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                punct("."), punct(","), punct("?"), punct("!"), punct("'"),
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1))
            ],
            // Row 4: unified bottom row (ABC + emoji + space + return)
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    // MARK: - Symbols Page (symbols2)

    private static func symbolsPage(lang: SupportedLanguage, needsGlobe: Bool) -> [[KeyDefinition]] {
        [
            // Row 1: brackets and math
            inputRow("[", "]", "{", "}", "#", "%", "^", "*", "+", "="),
            // Row 2: special characters
            inputRow("_", "\\", "|", "~", "<", ">", "$", "\u{00A3}", "\u{00A5}", "\u{00B7}"),
            // Row 3: 123 toggle + punctuation + delete
            [
                KeyDefinition(type: .shiftSymbols, size: CGSize(width: 1.5, height: 1)),
                // #+= and delete keep width 1.5 (identical to shift/delete on the letter pages).
                // The 5 punctuation keys are widened to 1.2 with small 0.5 end spacers so the
                // row totals 10 units and the cluster sits tighter -- matching Apple.
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                punct("."), punct(","), punct("?"), punct("!"), punct("'"),
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1))
            ],
            // Row 4: unified bottom row (ABC + emoji + space + return)
            bottomRow(lang: lang, needsGlobe: needsGlobe)
        ]
    }

    // MARK: - Bottom Rows

    /// Next-keyboard (globe) key. Rendered as a globe icon and wired to
    /// `advanceToNextInputMode()` by the vendored KeyView/bridge. Inserted only when the
    /// system does not already provide its own globe (`needsInputModeSwitchKey == true`).
    private static func globeKey() -> KeyDefinition {
        KeyDefinition(type: .keyboard, size: CGSize(width: 1.0, height: 1))
    }

    /// Bottom row, IDENTICAL across the letters and symbols pages so nothing resizes when the
    /// user toggles 123/ABC (Apple parity). The `.symbols` key auto-labels "123" on letter
    /// pages and "ABC" on symbol pages, and the emoji key stays present on every page.
    ///
    /// [(🌐 1.0w) 123/ABC 1.5w] [emoji 1.5w] [space 5.0w/4.0w] [return 2.0w] = 10 units.
    /// 123/ABC and emoji share the same small width; only the space bar changes width, shrinking
    /// by 1.0 when the globe is prepended (needsInputModeSwitchKey, App Store 4.4.1).
    private static func bottomRow(lang: SupportedLanguage, needsGlobe: Bool) -> [KeyDefinition] {
        var row: [KeyDefinition] = needsGlobe ? [globeKey()] : []
        row.append(contentsOf: [
            KeyDefinition(type: .symbols, size: CGSize(width: 1.5, height: 1)),
            KeyDefinition(type: .input(key: emojiKeyGlyph, alternate: nil), size: CGSize(width: 1.5, height: 1)),
            KeyDefinition(type: .spacebar(name: lang.spaceName), size: CGSize(width: needsGlobe ? 4.0 : 5.0, height: 1)),
            KeyDefinition(type: .returnkey(name: lang.returnName), size: CGSize(width: 2.0, height: 1))
        ])
        return row
    }

    // MARK: - Long Press Accents

    /// Long-press accent data shared across all languages.
    /// Includes French accents (grave, circumflex, diaeresis) and Spanish accents (acute).
    private static let longPressData: [String: [String]] = {
        var longPress: [String: [String]] = [:]
        for (baseKey, accents) in AccentedCharacters.mappings {
            longPress[baseKey] = accents
        }
        return longPress
    }()

    // MARK: - Helper Functions

    /// Create a standard 1x1 input key.
    private static func key(_ char: String) -> KeyDefinition {
        KeyDefinition(type: .input(key: char, alternate: nil))
    }

    /// Create a slightly wider (1.2) punctuation input key for the symbols pages' row 3,
    /// so the 5 keys sit tighter together like Apple's keyboard.
    private static func punct(_ char: String) -> KeyDefinition {
        KeyDefinition(type: .input(key: char, alternate: nil), size: CGSize(width: 1.2, height: 1))
    }

    /// Create a row of standard input keys from variadic strings.
    private static func inputRow(_ keys: String...) -> [KeyDefinition] {
        keys.map { KeyDefinition(type: .input(key: $0, alternate: nil)) }
    }
}
