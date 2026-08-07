// DictusCore/Tests/DictusCoreTests/FrenchAdaptiveKeyTests.swift
// The AZERTY row-3 adaptive key: its French behaviour, and the language guard that keeps
// it from surfacing French accents to the other languages now reachable on AZERTY (#272).
import XCTest
@testable import DictusCore

final class FrenchAdaptiveKeyTests: XCTestCase {

    // MARK: - French behaviour (unchanged by #272)

    func testLabelShowsTheDefaultAccentAfterAVowel() {
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "e", language: .french), "\u{00E9}")
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "a", language: .french), "\u{00E0}")
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "u", language: .french), "\u{00F9}")
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "i", language: .french), "\u{00EE}")
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "o", language: .french), "\u{00F4}")
    }

    func testLabelShowsApostropheAfterAConsonant() {
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "l", language: .french), "'")
    }

    func testLabelShowsApostropheAfterTheQuBigram() {
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "u", precedingChar: "q", language: .french), "'")
        XCTAssertFalse(FrenchAdaptiveKey.shouldReplace(afterTyping: "u", precedingChar: "q", language: .french))
        XCTAssertNil(FrenchAdaptiveKey.vowel(afterTyping: "u", precedingChar: "q", language: .french))
    }

    func testLabelPreservesTheCaseOfTheTypedVowel() {
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "E", language: .french), "\u{00C9}")
    }

    func testShouldReplaceOnlyAfterAVowel() {
        XCTAssertTrue(FrenchAdaptiveKey.shouldReplace(afterTyping: "e", language: .french))
        XCTAssertFalse(FrenchAdaptiveKey.shouldReplace(afterTyping: "l", language: .french))
        XCTAssertFalse(FrenchAdaptiveKey.shouldReplace(afterTyping: nil, language: .french))
    }

    func testVowelReportsTheBaseVowel() {
        XCTAssertEqual(FrenchAdaptiveKey.vowel(afterTyping: "E", language: .french), "e")
        XCTAssertNil(FrenchAdaptiveKey.vowel(afterTyping: "l", language: .french))
    }

    // MARK: - Language guard (#272)

    /// Decoupling the layout from the dictionary language makes English/Spanish/German on
    /// AZERTY reachable. On those keyboards the key is what it is labelled: an apostrophe.
    func testTheKeyIsAPlainApostropheOutsideFrench() {
        for language in SupportedLanguage.allCases where language != .french {
            for typed in ["e", "a", "u", "i", "o", "E", "l", nil] {
                XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: typed, language: language), "'",
                               "\(language.rawValue) must not get a French accent after \(typed ?? "nil")")
                XCTAssertFalse(FrenchAdaptiveKey.shouldReplace(afterTyping: typed, language: language),
                               "\(language.rawValue) must never replace the character it just typed")
                XCTAssertNil(FrenchAdaptiveKey.vowel(afterTyping: typed, language: language))
            }
        }
    }

    /// The guard reads the active language by default, which is how the keyboard bridge
    /// calls it — one language switch is enough to change the key's behaviour.
    func testTheGuardFollowsTheActiveLanguageByDefault() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        // Restore rather than clear: the suite is shared with every other test class,
        // and clearing would hand them a different language than they started with.
        let previousLanguage = defaults?.string(forKey: SharedKeys.language)
        defer {
            if let previousLanguage {
                defaults?.set(previousLanguage, forKey: SharedKeys.language)
            } else {
                defaults?.removeObject(forKey: SharedKeys.language)
            }
        }

        defaults?.set(SupportedLanguage.french.rawValue, forKey: SharedKeys.language)
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "e"), "\u{00E9}")

        defaults?.set(SupportedLanguage.english.rawValue, forKey: SharedKeys.language)
        XCTAssertEqual(FrenchAdaptiveKey.label(afterTyping: "e"), "'")
    }
}
