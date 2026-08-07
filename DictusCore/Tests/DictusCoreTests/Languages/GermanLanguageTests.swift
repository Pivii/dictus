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

    // MARK: - Umlautersatz on the trie's real frequency scale (issue #326)

    /// Raw corpus counts taken verbatim from `DictusKeyboard/Resources/de_frequency.json`
    /// as it shipped before #326, plus the corpus maximum that anchors the
    /// normalization. The exact numbers matter: the whole point of these tests
    /// is that the dominance rule behaves differently on raw counts than on the
    /// values the trie stores, and inventing round numbers hides that.
    private static let germanCorpusMaxFrequency = 5_890_279  // "ich"
    private static let germanUmlautersatzCorpusCounts: [String: Int] = [
        "fuer": 712, "f\u{00FC}r": 735_252,          // für
        "schoen": 90, "sch\u{00F6}n": 106_669,       // schön
        "koennen": 180, "k\u{00F6}nnen": 240_905,    // können
    ]

    func test_logNormalizedProvider_reproducesTheFrequencyTheDeviceLogged() {
        // #321's device log printed `TRIE-CANDIDATES word="feur" winner="für"(freq=56787)`.
        // Recomputing 56787 from the raw corpus count of `für` is what identifies
        // the scale the 5x dominance rule is actually comparing on: the trie
        // stores `65535 * ln(1+freq) / ln(1+max)`, not the corpus count.
        let provider = LogNormalizedFrequencyProvider(
            rawFrequencies: Self.germanUmlautersatzCorpusCounts,
            maxFrequency: Self.germanCorpusMaxFrequency
        )
        XCTAssertEqual(provider.frequency(of: "f\u{00FC}r"), 56_787)
        XCTAssertEqual(provider.frequency(of: "fuer"), 27_617)
    }

    func test_german_expandAccents_umlautersatzFails_whenTheAsciiFormIsInTheDictionary() {
        // The pre-#326 device behaviour, reproduced. In raw corpus counts these
        // pairs clear the 5x bar by three orders of magnitude (1033x, 1185x,
        // 1338x). Stored, they are 2.06x, 2.57x and 2.38x — all under 5x, so
        // `expandAccents` returns nil and the engine falls through to the
        // valid-word guard, which logs `AUTOCORRECT-SKIP reason=already-valid`.
        //
        // This is why the fix is to curate these forms out of the dictionary
        // rather than to reorder the guard: with the ASCII form present, no
        // ordering change reaches a correction. Clearing 5x in stored space needs
        // the target to be roughly the input raised to the fifth power, which
        // nothing inside a 40K corpus reaches.
        let provider = LogNormalizedFrequencyProvider(
            rawFrequencies: Self.germanUmlautersatzCorpusCounts,
            maxFrequency: Self.germanCorpusMaxFrequency
        )
        XCTAssertNil(expandAccents(profile: germanProfile, word: "fuer", provider: provider))
        XCTAssertNil(expandAccents(profile: germanProfile, word: "schoen", provider: provider))
        XCTAssertNil(expandAccents(profile: germanProfile, word: "koennen", provider: provider))
    }

    func test_german_expandAccents_umlautersatzCorrects_whenTheAsciiFormIsCuratedOut() {
        // The post-#326 dictionary: `scripts/curate_de_dictionary.py` drops the
        // transliterations, so `expandAccents` takes its `input frequency == 0`
        // branch and returns the umlaut form without consulting the dominance
        // rule at all. Same provider, same scale, same corpus counts for the
        // umlaut words — only the ASCII entries are gone.
        var counts = Self.germanUmlautersatzCorpusCounts
        for ascii in ["fuer", "schoen", "koennen"] {
            counts.removeValue(forKey: ascii)
        }
        let provider = LogNormalizedFrequencyProvider(
            rawFrequencies: counts,
            maxFrequency: Self.germanCorpusMaxFrequency
        )
        XCTAssertEqual(expandAccents(profile: germanProfile, word: "fuer", provider: provider), "f\u{00FC}r")
        XCTAssertEqual(expandAccents(profile: germanProfile, word: "schoen", provider: provider), "sch\u{00F6}n")
        XCTAssertEqual(expandAccents(profile: germanProfile, word: "koennen", provider: provider), "k\u{00F6}nnen")
    }

    // MARK: - The shipped German dictionary (issue #326)

    /// Reads `DictusKeyboard/Resources/de_frequency.json` out of the source tree.
    ///
    /// WHY not `Bundle.module` the way `FrequencyDictionaryTests` does: those two
    /// tests exercise the loader against a hand-written fixture, whereas these
    /// guard the artifact the keyboard actually ships. A 600 KiB copy under
    /// `Fixtures/` would be a second file free to drift from the real one, which
    /// is the exact failure mode being guarded. `swift test` runs from this
    /// source tree, so `#filePath` reaches the real resource.
    private func shippedGermanFrequencies() throws -> [String: Int] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Languages/
            .deletingLastPathComponent()   // DictusCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // DictusCore/
            .deletingLastPathComponent()   // repo root
        let url = repoRoot.appendingPathComponent("DictusKeyboard/Resources/de_frequency.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    func test_shippedGermanDictionary_containsNoUmlautersatzForms() throws {
        // Every entry here is a transliteration, not a German word in any context,
        // and each one blocked its own correction until #326. Regenerating the
        // dictionary must keep dropping them — if the corpus or the curation rule
        // changes and one comes back, autocorrect silently stops firing for it.
        let frequencies = try shippedGermanFrequencies()
        for word in ["fuer", "koennen", "ueber", "muessen", "wuerde", "moechte",
                     "waere", "zurueck", "natuerlich", "haette", "gehoert", "schoen",
                     "tuer", "maedchen"] {
            XCTAssertNil(frequencies[word],
                         "\(word) is German Umlautersatz, not a word — curation must drop it (issue #326).")
        }
    }

    func test_shippedGermanDictionary_keepsRealWordsContainingAeOeUe() throws {
        // The counterpart guard. These are real German words that happen to
        // contain `ae`, `oe` or `ue` as a genuine letter sequence. They survive
        // curation on the 5x rule alone, without a second heuristic: their
        // collapsed forms (`baür`, `feür`, `zünander`, `pöt`, `stür`) are not
        // words and are absent from the corpus, so no umlaut variant is found.
        let frequencies = try shippedGermanFrequencies()
        for word in ["bauer", "bauern", "feuer", "zueinander", "poet", "steuer",
                     "abenteuer", "treue", "frauen", "michael", "israel"] {
            XCTAssertNotNil(frequencies[word],
                            "\(word) is a real German word — curation must not drop it (issue #326).")
        }
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
