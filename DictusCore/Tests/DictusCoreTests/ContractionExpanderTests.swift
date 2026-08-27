// DictusCore/Tests/DictusCoreTests/ContractionExpanderTests.swift
// Algorithm-level regression tests for expandContractions.
// Confirms the apostrophe-prefix splitting behavior previously inside
// AOSPTrieEngine.contractionExpansion is preserved when driven by a
// LanguageProfile + FrequencyProvider.
import XCTest
@testable import DictusCore

final class ContractionExpanderTests: XCTestCase {

    // MARK: - French 1-character prefixes

    func test_french_lhomme_splitsToLApostropheHomme() {
        let provider = MockFrequencyProvider(frequencies: ["homme": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "lhomme",
            provider: provider
        )
        XCTAssertEqual(result, "l'homme")
    }

    func test_french_capitalizedCest_splitsAndLowercasesPrefix() {
        // Algorithm lowercases internally; case restoration happens upstream.
        let provider = MockFrequencyProvider(frequencies: ["est": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "Cest",
            provider: provider
        )
        XCTAssertEqual(result, "c'est")
    }

    func test_french_jai_splitsToJApostropheAi() {
        let provider = MockFrequencyProvider(frequencies: ["ai": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "jai",
            provider: provider
        )
        XCTAssertEqual(result, "j'ai")
    }

    func test_french_napparait_splitsToNApostropheApparait() {
        let provider = MockFrequencyProvider(frequencies: ["apparait": 500])
        let result = expandContractions(
            profile: frenchProfile,
            word: "napparait",
            provider: provider
        )
        XCTAssertEqual(result, "n'apparait")
    }

    // MARK: - French 2-character prefix (qu')

    func test_french_quelle_splitsToQuApostropheElle_whenSuffixExists() {
        let provider = MockFrequencyProvider(frequencies: ["elle": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "quelle",
            provider: provider
        )
        // 1-char prefix "q'" doesn't exist as a real prefix, so the algorithm
        // falls through to the 2-char "qu'" prefix and splits on that.
        XCTAssertEqual(result, "qu'elle")
    }

    func test_french_quil_splitsToQuApostropheIl() {
        let provider = MockFrequencyProvider(frequencies: ["il": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "quil",
            provider: provider
        )
        XCTAssertEqual(result, "qu'il")
    }

    // MARK: - Accent fallback on the suffix (Cetait → c'était)

    func test_french_cetait_expandsWithAccentedSuffix() {
        // "etait" is not in the dictionary (missing accents), but "était" is.
        // The expander must fall back to accent expansion of the suffix
        // instead of giving up (which let the trie destroy the prefix:
        // "Cetait" → "Était").
        let provider = MockFrequencyProvider(frequencies: ["était": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "Cetait",
            provider: provider
        )
        XCTAssertEqual(result, "c'était")
    }

    func test_french_quetait_expandsTwoCharPrefixWithAccentedSuffix() {
        let provider = MockFrequencyProvider(frequencies: ["était": 1000])
        let result = expandContractions(
            profile: frenchProfile,
            word: "quetait",
            provider: provider
        )
        XCTAssertEqual(result, "qu'était")
    }

    func test_french_directSuffixWinsOverAccentFallback() {
        // When the unaccented suffix IS a dictionary word, the direct path
        // returns it — the accent fallback never runs.
        let provider = MockFrequencyProvider(frequencies: ["est": 1000, "ést": 5])
        let result = expandContractions(
            profile: frenchProfile,
            word: "Cest",
            provider: provider
        )
        XCTAssertEqual(result, "c'est")
    }

    func test_french_accentFallback_returnsNilForGarbageSuffix() {
        // No accent variant of "xyz" exists — expansion still fails cleanly.
        let provider = MockFrequencyProvider(frequencies: ["était": 1000])
        XCTAssertNil(expandContractions(
            profile: frenchProfile,
            word: "cxyz",
            provider: provider
        ))
    }

    // MARK: - Negative cases

    func test_french_returnsNil_whenSuffixNotInDictionary() {
        let provider = MockFrequencyProvider(frequencies: [:])
        XCTAssertNil(expandContractions(
            profile: frenchProfile,
            word: "lxyz",
            provider: provider
        ))
    }

    func test_french_returnsNil_forShortInput() {
        let provider = MockFrequencyProvider(frequencies: ["a": 1000])
        // Word too short (< 2 chars) — algorithm short-circuits.
        XCTAssertNil(expandContractions(
            profile: frenchProfile,
            word: "l",
            provider: provider
        ))
    }

    func test_french_returnsNil_whenProviderNotReady() {
        let provider = MockFrequencyProvider(isReady: false, frequencies: ["homme": 1000])
        XCTAssertNil(expandContractions(
            profile: frenchProfile,
            word: "lhomme",
            provider: provider
        ))
    }

    // MARK: - English / Spanish (no contraction prefixes)

    func test_english_returnsNil_becauseNoContractionPrefixes() {
        let provider = MockFrequencyProvider(frequencies: ["a": 1000, "ai": 1000])
        XCTAssertNil(expandContractions(
            profile: englishProfile,
            word: "lai",
            provider: provider
        ))
    }

    func test_spanish_returnsNil_becauseNoContractionPrefixes() {
        let provider = MockFrequencyProvider(frequencies: ["amigo": 1000])
        XCTAssertNil(expandContractions(
            profile: spanishProfile,
            word: "lamigo",
            provider: provider
        ))
    }

    // MARK: - Prefix precedence (1-char before 2-char)

    /// `quelle` has both a candidate 1-char prefix (`q'`, not in our list)
    /// and a 2-char prefix (`qu'`, in our list). Algorithm tries 1-char first,
    /// fails because `q'` isn't a registered prefix, then tries 2-char.
    /// Verified by the `quelle` case above. This test confirms the inverse:
    /// when both could match, shorter wins.
    func test_french_lai_picksOneCharPrefixOverTwoChar() {
        // "lai" matches "l'" (1-char, "ai" exists) — shorter prefix wins.
        // Even though "la'i" doesn't make sense, "l'ai" does.
        let provider = MockFrequencyProvider(frequencies: ["ai": 1000, "i": 0])
        let result = expandContractions(
            profile: frenchProfile,
            word: "lai",
            provider: provider
        )
        XCTAssertEqual(result, "l'ai")
    }
}
