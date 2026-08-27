// DictusCore/Tests/DictusCoreTests/LanguageProfileTests.swift
// Regression tests asserting that each shipped LanguageProfile holds the same
// data that was previously hardcoded inside AOSPTrieEngine and SupportedLanguage.
//
// These are pure data-equality tests: they DO NOT exercise the autocorrect
// algorithm. Algorithm tests live in OverrideLookupTests, AccentExpanderTests,
// and ContractionExpanderTests. Together, they prove the LanguageProfile
// migration is byte-identical for fr/en/es.
import XCTest
@testable import DictusCore

final class LanguageProfileTests: XCTestCase {

    // MARK: - SupportedLanguage → profile binding

    func test_supportedLanguage_french_resolvesToFrenchProfile() {
        XCTAssertEqual(SupportedLanguage.french.profile.code, "fr")
    }

    func test_supportedLanguage_english_resolvesToEnglishProfile() {
        XCTAssertEqual(SupportedLanguage.english.profile.code, "en")
    }

    func test_supportedLanguage_spanish_resolvesToSpanishProfile() {
        XCTAssertEqual(SupportedLanguage.spanish.profile.code, "es")
    }

    // MARK: - Profile fields match SupportedLanguage's pre-existing API

    func test_frenchProfile_displayFieldsMatchEnum() {
        let p = SupportedLanguage.french.profile
        XCTAssertEqual(p.displayName, "Fran\u{00E7}ais")
        XCTAssertEqual(p.shortCode, "FR")
        XCTAssertEqual(p.defaultLayout, .azerty)
        XCTAssertEqual(p.spaceName, "espace")
        XCTAssertEqual(p.returnName, "retour")
    }

    func test_englishProfile_displayFieldsMatchEnum() {
        let p = SupportedLanguage.english.profile
        XCTAssertEqual(p.displayName, "English")
        XCTAssertEqual(p.shortCode, "EN")
        XCTAssertEqual(p.defaultLayout, .qwerty)
        XCTAssertEqual(p.spaceName, "space")
        XCTAssertEqual(p.returnName, "return")
    }

    func test_spanishProfile_displayFieldsMatchEnum() {
        let p = SupportedLanguage.spanish.profile
        XCTAssertEqual(p.displayName, "Espa\u{00F1}ol")
        XCTAssertEqual(p.shortCode, "ES")
        XCTAssertEqual(p.defaultLayout, .qwerty)
        XCTAssertEqual(p.spaceName, "espacio")
        XCTAssertEqual(p.returnName, "intro")
    }

    // MARK: - Profile fields match SupportedLanguage's existing accessors

    /// The enum's `displayName`, `shortCode`, etc. are still the public API
    /// that callers (SettingsView, KeyboardLayouts) use. The profile must
    /// agree with the enum field-for-field.
    func test_allLanguages_profileFieldsAgreeWithEnumAccessors() {
        for lang in SupportedLanguage.allCases {
            let p = lang.profile
            XCTAssertEqual(p.code, lang.rawValue, "code mismatch for \(lang)")
            XCTAssertEqual(p.displayName, lang.displayName, "displayName mismatch for \(lang)")
            XCTAssertEqual(p.shortCode, lang.shortCode, "shortCode mismatch for \(lang)")
            XCTAssertEqual(p.defaultLayout, lang.defaultLayout, "defaultLayout mismatch for \(lang)")
            XCTAssertEqual(p.spaceName, lang.spaceName, "spaceName mismatch for \(lang)")
            XCTAssertEqual(p.returnName, lang.returnName, "returnName mismatch for \(lang)")
        }
    }

    // MARK: - Override map exact-equality (regression: byte-for-byte vs. legacy hardcoded data)

    /// The legacy AOSPTrieEngine.languageOverrides["fr"] dict, pinned here so
    /// the test fails loudly if anyone changes one without intent.
    private static let legacyFrenchOverrides: [String: String] = [
        "ca": "\u{00E7}a",
        "tres": "tr\u{00E8}s",
        "apres": "apr\u{00E8}s",
        "deja": "d\u{00E9}j\u{00E0}",
        "ete": "\u{00E9}t\u{00E9}",
        "etre": "\u{00EA}tre",
        "voila": "voil\u{00E0}",
        "bientot": "bient\u{00F4}t",
        "plutot": "plut\u{00F4}t",
        "probleme": "probl\u{00E8}me",
        "systeme": "syst\u{00E8}me",
        "etait": "\u{00E9}tait",
        "etaient": "\u{00E9}taient",
        "evenement": "\u{00E9}v\u{00E9}nement",
        // Added for #222: missed-apostrophe contractions colliding with
        // rare-but-real dictionary words ("lai" poem, "lest" ballast).
        "lai": "l'ai",
        "lest": "l'est",
    ]

    private static let legacyEnglishOverrides: [String: String] = [
        "im": "i'm",
        "ive": "i've",
        "dont": "don't",
        "doesnt": "doesn't",
        "didnt": "didn't",
        "cant": "can't",
        "couldnt": "couldn't",
        "wouldnt": "wouldn't",
        "shouldnt": "shouldn't",
        "wasnt": "wasn't",
        "isnt": "isn't",
        "arent": "aren't",
        "werent": "weren't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hadnt": "hadn't",
        "youre": "you're",
        "youve": "you've",
        "youll": "you'll",
        "youd": "you'd",
        "theyre": "they're",
        "theyve": "they've",
        "theyll": "they'll",
        "theyd": "they'd",
        "weve": "we've",
        "hes": "he's",
        "shes": "she's",
        "itll": "it'll",
        "thats": "that's",
        "thatll": "that'll",
        "whats": "what's",
        "whos": "who's",
        "wholl": "who'll",
        "theres": "there's",
        "heres": "here's",
    ]

    func test_frenchProfile_overridesMatchLegacyData() {
        XCTAssertEqual(frenchProfile.overrides, Self.legacyFrenchOverrides)
    }

    func test_englishProfile_overridesMatchLegacyData() {
        XCTAssertEqual(englishProfile.overrides, Self.legacyEnglishOverrides)
    }

    func test_spanishProfile_overridesIsEmptyPerADR0001() {
        XCTAssertTrue(spanishProfile.overrides.isEmpty,
                      "Spanish ships with empty overrides per ADR 0001 — populated post-launch from feedback.")
    }

    // MARK: - Accent map exact-equality

    func test_frenchProfile_accentMapMatchesLegacyData() {
        XCTAssertEqual(frenchProfile.accentMap, [
            "e": ["\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}"],
            "a": ["\u{00E0}", "\u{00E2}"],
            "i": ["\u{00EE}", "\u{00EF}"],
            "o": ["\u{00F4}"],
            "u": ["\u{00F9}", "\u{00FB}", "\u{00FC}"],
            "c": ["\u{00E7}"],
        ])
    }

    func test_spanishProfile_accentMapMatchesLegacyData() {
        XCTAssertEqual(spanishProfile.accentMap, [
            "a": ["\u{00E1}"],
            "e": ["\u{00E9}"],
            "i": ["\u{00ED}"],
            "o": ["\u{00F3}"],
            "u": ["\u{00FA}", "\u{00FC}"],
            "n": ["\u{00F1}"],
        ])
    }

    func test_englishProfile_accentMapIsEmpty() {
        XCTAssertTrue(englishProfile.accentMap.isEmpty,
                      "English has no diacritics handled by AccentExpander.")
    }

    // MARK: - Contraction prefixes

    func test_frenchProfile_contractionPrefixesMatchLegacyData() {
        // Order doesn't matter (set equality); algorithm sorts internally.
        XCTAssertEqual(
            Set(frenchProfile.contractionPrefixes),
            Set(["l'", "d'", "c'", "j'", "n'", "s'", "m'", "t'", "qu'"])
        )
    }

    func test_englishProfile_hasNoContractionPrefixes() {
        XCTAssertTrue(englishProfile.contractionPrefixes.isEmpty,
                      "English contractions are handled via the override map, not prefix splitting.")
    }

    func test_spanishProfile_hasNoContractionPrefixes() {
        XCTAssertTrue(spanishProfile.contractionPrefixes.isEmpty)
    }

    // MARK: - Collapse rules (length-changing substring substitutions)

    func test_frenchProfile_hasNoCollapseRules() {
        XCTAssertTrue(frenchProfile.collapseRules.isEmpty)
    }

    func test_englishProfile_hasNoCollapseRules() {
        XCTAssertTrue(englishProfile.collapseRules.isEmpty)
    }

    func test_spanishProfile_hasNoCollapseRules() {
        XCTAssertTrue(spanishProfile.collapseRules.isEmpty)
    }
}
