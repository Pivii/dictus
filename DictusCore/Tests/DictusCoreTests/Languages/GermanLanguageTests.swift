// DictusCore/Tests/DictusCoreTests/Languages/GermanLanguageTests.swift
// First per-language test file (per locked decision #10 of issue #110).
// Pins the German profile data and exercises the algorithm helpers against it.
import XCTest
@testable import DictusCore

final class GermanLanguageTests: XCTestCase {

    // MARK: - Profile data snapshot

    func test_germanProfile_displayFields() {
        let p = germanProfile
        XCTAssertEqual(p.code, "de")
        XCTAssertEqual(p.displayName, "Deutsch")
        XCTAssertEqual(p.shortCode, "DE")
        XCTAssertEqual(p.defaultLayout, .qwertz,
                       "German selects QWERTZ — the layout iOS ships as its default German keyboard.")
        XCTAssertEqual(p.spaceName, "Leertaste")
        XCTAssertEqual(p.returnName, "Eingabe")
    }

    func test_supportedLanguage_german_resolvesToGermanProfile() {
        XCTAssertEqual(SupportedLanguage.german.profile.code, "de")
    }

    func test_supportedLanguage_german_enumAccessorsAgreeWithProfile() {
        let lang = SupportedLanguage.german
        let p = lang.profile
        XCTAssertEqual(p.code, lang.rawValue)
        XCTAssertEqual(p.displayName, lang.displayName)
        XCTAssertEqual(p.shortCode, lang.shortCode)
        XCTAssertEqual(p.defaultLayout, lang.defaultLayout)
        XCTAssertEqual(p.spaceName, lang.spaceName)
        XCTAssertEqual(p.returnName, lang.returnName)
    }

    // MARK: - Override map (empty per ADR 0001)

    func test_germanProfile_overridesIsEmptyPerADR0001() {
        XCTAssertTrue(germanProfile.overrides.isEmpty,
                      "German ships with empty overrides per ADR 0001 — populated post-launch from native-speaker feedback on issue #109.")
    }

    func test_german_applyOverride_returnsNilForCommonInputs() {
        // No overrides means every input falls through to the trie/accent pipeline.
        XCTAssertNil(applyOverride(profile: germanProfile, word: "schon"))
        XCTAssertNil(applyOverride(profile: germanProfile, word: "uber"))
        XCTAssertNil(applyOverride(profile: germanProfile, word: "madchen"))
        XCTAssertNil(applyOverride(profile: germanProfile, word: "strasse"))
        XCTAssertNil(applyOverride(profile: germanProfile, word: "ich"))
    }

    // MARK: - Accent map (ä, ö, ü, ß)

    func test_germanProfile_accentMapMatchesSpec() {
        // ß intentionally absent from accentMap (single-char substitution can't
        // model `ss → ß`). It's handled via collapseRules below.
        XCTAssertEqual(germanProfile.accentMap, [
            "a": ["\u{00E4}"],   // ä
            "o": ["\u{00F6}"],   // ö
            "u": ["\u{00FC}"],   // ü
        ])
    }

    func test_germanProfile_collapseRulesIncludeUmlautersatzAndEszett() {
        // Order matters for diagnostics, not for algorithm correctness — the
        // expander tries each rule independently. Rule set kept small and
        // well-documented because false positives are silent regressions.
        let rules = germanProfile.collapseRules.map { ($0.from, $0.to) }
        XCTAssertEqual(rules.count, 4)
        XCTAssertTrue(rules.contains(where: { $0 == ("ae", "\u{00E4}") }))
        XCTAssertTrue(rules.contains(where: { $0 == ("oe", "\u{00F6}") }))
        XCTAssertTrue(rules.contains(where: { $0 == ("ue", "\u{00FC}") }))
        XCTAssertTrue(rules.contains(where: { $0 == ("ss", "\u{00DF}") }))
    }

    func test_german_expandAccents_tuerCollapsesToTuer() {
        // The motivating case: without the `ue → ü` rule, the trie's
        // edit-distance fallback returns `tier` (animal). With the rule,
        // `tuer` correctly collapses to `tür`.
        let provider = MockFrequencyProvider(frequencies: [
            "t\u{00FC}r": 30_000   // tür
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "tuer", provider: provider),
            "t\u{00FC}r"
        )
    }

    func test_german_expandAccents_aeCollapsesForMaedchen() {
        let provider = MockFrequencyProvider(frequencies: [
            "m\u{00E4}dchen": 47_058   // mädchen
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "maedchen", provider: provider),
            "m\u{00E4}dchen"
        )
    }

    func test_german_expandAccents_oeCollapsesForKoennen() {
        let provider = MockFrequencyProvider(frequencies: [
            "k\u{00F6}nnen": 60_000   // können
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "koennen", provider: provider),
            "k\u{00F6}nnen"
        )
    }

    func test_german_expandAccents_ueDoesNotFalsePositiveOnBauer() {
        // `bauer` (farmer) contains `ue` but is itself a valid German word.
        // No `baür` exists, so no incorrect correction can fire.
        let provider = MockFrequencyProvider(frequencies: [
            "bauer": 5_000,   // valid German word
            // No "baür" entry — confirms the substitution candidate isn't real.
        ])
        XCTAssertNil(expandAccents(profile: germanProfile, word: "bauer", provider: provider))
    }

    func test_german_expandAccents_uberCorrectsToUmlaut() {
        // "uber" not in dict → any matching accented variant wins.
        let provider = MockFrequencyProvider(frequencies: [
            "\u{00FC}ber": 60_000   // über
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "uber", provider: provider),
            "\u{00FC}ber"
        )
    }

    func test_german_expandAccents_schonCorrectsToUmlaut() {
        let provider = MockFrequencyProvider(frequencies: [
            "sch\u{00F6}n": 50_000   // schön
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "schon", provider: provider),
            "sch\u{00F6}n"
        )
    }

    func test_german_expandAccents_madchenCorrectsToUmlaut() {
        let provider = MockFrequencyProvider(frequencies: [
            "m\u{00E4}dchen": 25_000   // mädchen
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "madchen", provider: provider),
            "m\u{00E4}dchen"
        )
    }

    func test_german_expandAccents_strasseCollapsesToEszett() {
        // German `ss → ß` is implemented via collapseRules: the algorithm finds
        // each `ss` occurrence and tries the substitution. `strasse` has one
        // `ss` at position 4-5; substituting yields `straße`, which matches
        // the dictionary at high frequency.
        let provider = MockFrequencyProvider(frequencies: [
            "stra\u{00DF}e": 40_000   // straße
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "strasse", provider: provider),
            "stra\u{00DF}e"
        )
    }

    func test_german_expandAccents_weissCollapsesToWeiss() {
        let provider = MockFrequencyProvider(frequencies: [
            "wei\u{00DF}": 60_000   // weiß
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "weiss", provider: provider),
            "wei\u{00DF}"
        )
    }

    func test_german_expandAccents_grossCollapsesToGross() {
        let provider = MockFrequencyProvider(frequencies: [
            "gro\u{00DF}": 50_000   // groß
        ])
        XCTAssertEqual(
            expandAccents(profile: germanProfile, word: "gross", provider: provider),
            "gro\u{00DF}"
        )
    }

    func test_german_expandAccents_5xDominanceProtectsValidUnaccentedSsWord() {
        // `muss` (1st/3rd-person singular of "müssen") is a valid German word
        // post-1996 spelling reform. The pre-reform `muß` may be in old corpora
        // but `muss` dominates in modern text — the 5x rule keeps `muss` intact.
        let provider = MockFrequencyProvider(frequencies: [
            "muss": 60_000,
            "mu\u{00DF}": 9_000,   // muß (pre-reform), 0.15x — well below 5x threshold
        ])
        XCTAssertNil(expandAccents(profile: germanProfile, word: "muss", provider: provider),
                     "5x dominance must protect modern `muss` against archaic `muß`.")
    }

    func test_german_expandAccents_returnsNilWhenCollapseTargetAbsent() {
        // No `weiß` in dict → `weiss` stays as-is.
        let provider = MockFrequencyProvider(frequencies: [:])
        XCTAssertNil(expandAccents(profile: germanProfile, word: "weiss", provider: provider))
    }

    func test_german_expandAccents_5xDominanceProtectsValidUnaccentedWords() {
        // If the unaccented form is itself in the dict and the umlaut form is only
        // ~3x more common, the 5x rule keeps the input unchanged.
        let provider = MockFrequencyProvider(frequencies: [
            "schon": 10_000,                 // valid German word ("already")
            "sch\u{00F6}n": 30_000,          // schön ("beautiful") — only 3x
        ])
        XCTAssertNil(expandAccents(profile: germanProfile, word: "schon", provider: provider),
                     "5x dominance rule must protect 'schon' (already) when 'schön' is not 5x more frequent.")
    }

    func test_german_expandAccents_returnsNilWhenNoMatch() {
        let provider = MockFrequencyProvider(frequencies: [:])
        XCTAssertNil(expandAccents(profile: germanProfile, word: "uber", provider: provider))
    }

    // MARK: - Contractions (empty)

    func test_germanProfile_hasNoContractionPrefixes() {
        XCTAssertTrue(germanProfile.contractionPrefixes.isEmpty,
                      "German `geht's`/`gibt's` style contractions are rare and not curated for first ship.")
    }

    func test_german_expandContractions_returnsNilForAnyInput() {
        let provider = MockFrequencyProvider(frequencies: [
            "geht": 50_000,
            "gibt": 50_000,
        ])
        XCTAssertNil(expandContractions(profile: germanProfile, word: "gehts", provider: provider))
        XCTAssertNil(expandContractions(profile: germanProfile, word: "gibts", provider: provider))
    }
}
