// DictusCore/Sources/DictusCore/Languages/Spanish.swift
// Spanish language profile. Mirrors the data previously hardcoded in
// AOSPTrieEngine and SupportedLanguage. Override map empty per ADR 0001.
import Foundation

/// Spanish (`es`).
public let spanishProfile = LanguageProfile(
    code: "es",
    displayName: "Espa\u{00F1}ol",
    shortCode: "ES",
    defaultLayout: .qwerty,
    spaceName: "espacio",
    returnName: "intro",
    overrides: [:],
    accentMap: [
        "a": ["\u{00E1}"],                  // á
        "e": ["\u{00E9}"],                  // é
        "i": ["\u{00ED}"],                  // í
        "o": ["\u{00F3}"],                  // ó
        "u": ["\u{00FA}", "\u{00FC}"],      // ú, ü
        "n": ["\u{00F1}"]                  // ñ
    ],
    contractionPrefixes: []
)
