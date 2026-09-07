// DictusCore/Tests/DictusCoreTests/Vocabulary/VocabularyReplacerTests.swift
// The matching rules #80 names, one test each.
import XCTest
@testable import DictusCore

final class VocabularyReplacerTests: XCTestCase {

    private func entry(_ term: String, _ variants: [String], enabled: Bool = true) -> VocabularyEntry {
        guard let entry = VocabularyEntry(term: term, variants: variants, isEnabled: enabled) else {
            XCTFail("entry \(term) should be constructible")
            return VocabularyEntry(term: "fallback")! // swiftlint:disable:this force_unwrapping
        }
        return entry
    }

    // MARK: - The pre-registered bar

    func testAnEmptyVocabularyReturnsTheTranscriptUntouched() {
        let raw = "On a déployé sur Kubernetes hier soir, sans incident."
        XCTAssertEqual(VocabularyReplacer.apply(raw, entries: []), raw)
    }

    func testAVocabularyWithNoVariantsReturnsTheTranscriptUntouched() {
        // The case decision 7 exists for: the entry is not useless, but its work
        // happens in the glossary, not here.
        let raw = "On a déployé sur Kubernetes hier soir."
        XCTAssertEqual(VocabularyReplacer.apply(raw, entries: [entry("Kubernetes", [])]), raw)
    }

    func testADisabledEntryDoesNothing() {
        let raw = "on passe sur cubernetes demain"
        let entries = [entry("Kubernetes", ["cubernetes"], enabled: false)]
        XCTAssertEqual(VocabularyReplacer.apply(raw, entries: entries), raw)
    }

    // MARK: - Word boundaries

    func testAVariantIsReplacedMidSentence() {
        let result = VocabularyReplacer.apply(
            "on passe sur cubernetes demain", entries: [entry("Kubernetes", ["cubernetes"])]
        )
        XCTAssertEqual(result, "on passe sur Kubernetes demain")
    }

    func testAVariantIsReplacedAtTheStartAndAtTheEnd() {
        let entries = [entry("Kubernetes", ["cubernetes"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("cubernetes est prêt", entries: entries),
            "Kubernetes est prêt"
        )
        XCTAssertEqual(
            VocabularyReplacer.apply("on déploie sur cubernetes", entries: entries),
            "on déploie sur Kubernetes"
        )
    }

    /// The false-positive case the corpus also carries: a variant that is a
    /// substring of an unrelated, correctly spelled word must not fire.
    func testAVariantInsideALongerWordIsNotReplaced() {
        let entries = [entry("Ampli", ["ampli"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("il a acheté un amplificateur", entries: entries),
            "il a acheté un amplificateur"
        )
    }

    func testAnApostropheIsAWordBoundary() {
        // French elision: `l'ampli` has to offer a boundary before the term, or the
        // feature is useless in the language most of the corpus is dictated in.
        let entries = [entry("Ampli", ["ampli"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("branche l'ampli", entries: entries),
            "branche l'Ampli"
        )
    }

    func testPunctuationAroundAVariantIsPreserved() {
        let entries = [entry("Kubernetes", ["cubernetes"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("cubernetes, puis cubernetes.", entries: entries),
            "Kubernetes, puis Kubernetes."
        )
    }

    // MARK: - Case

    func testMatchingIsCaseInsensitiveAndOutputIsTheCanonicalSpelling() {
        let entries = [entry("Kubernetes", ["cubernetes"])]
        for input in ["cubernetes", "Cubernetes", "CUBERNETES", "CuBeRnEtEs"] {
            XCTAssertEqual(
                VocabularyReplacer.apply(input, entries: entries), "Kubernetes",
                "\(input) should normalise to the canonical spelling"
            )
        }
    }

    func testAccentsAreNotFoldedAway() {
        // Case-insensitive is not accent-insensitive. `é` and `e` are different
        // letters, and a user who wrote one meant it.
        let entries = [entry("Café Noir", ["cafe noir"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("un café noir", entries: entries), "un café noir"
        )
        XCTAssertEqual(
            VocabularyReplacer.apply("un cafe noir", entries: entries), "un Café Noir"
        )
    }

    // MARK: - Scripts without spaces

    func testJapaneseVariantsMatchWithoutWordBoundaries() {
        // Hiragana and Katakana: no spaces anywhere, so requiring `\b` would mean
        // never matching.
        let entries = [entry("東京", ["とうきょう"]), entry("コンピューター", ["こんぴゅーたー"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("明日とうきょうへ行く", entries: entries), "明日東京へ行く"
        )
        XCTAssertEqual(
            VocabularyReplacer.apply("こんぴゅーたーを買った", entries: entries), "コンピューターを買った"
        )
    }

    func testChineseVariantsMatchWithoutWordBoundaries() {
        let entries = [entry("北京", ["北亰"])]
        XCTAssertEqual(VocabularyReplacer.apply("我去北亰了", entries: entries), "我去北京了")
    }

    func testKoreanVariantsMatchWithoutWordBoundaries() {
        let entries = [entry("서울", ["서울시"])]
        XCTAssertEqual(VocabularyReplacer.apply("내일서울시에간다", entries: entries), "내일서울에간다")
    }

    func testThaiVariantsMatchWithoutWordBoundaries() {
        let entries = [entry("กรุงเทพ", ["กรุงเทพฯ"])]
        XCTAssertEqual(
            VocabularyReplacer.apply("ไปกรุงเทพฯพรุ่งนี้", entries: entries), "ไปกรุงเทพพรุ่งนี้"
        )
    }

    func testEveryNonSpacedScriptIsRecognisedAndLatinIsNot() {
        for character in ["あ", "ア", "ｱ", "中", "한", "ᄀ", "ก"] {
            XCTAssertTrue(
                VocabularyReplacer.isNonSpacedScript(character.first),
                "\(character) should be a non-spaced script"
            )
        }
        for character in ["a", "é", "Ω", "д", "1"] {
            XCTAssertFalse(
                VocabularyReplacer.isNonSpacedScript(character.first),
                "\(character) should not be a non-spaced script"
            )
        }
    }

    // MARK: - Overlapping variants

    func testTheLongestVariantWinsWhateverTheStorageOrder() {
        let short = entry("Claude", ["clode"])
        let long = entry("Claude Code", ["clode code"])
        let expected = "j'ouvre Claude Code ce soir"
        XCTAssertEqual(
            VocabularyReplacer.apply("j'ouvre clode code ce soir", entries: [short, long]),
            expected
        )
        XCTAssertEqual(
            VocabularyReplacer.apply("j'ouvre clode code ce soir", entries: [long, short]),
            expected, "the result must not depend on the order the file happens to hold"
        )
    }

    func testTheSameVariantClaimedTwiceResolvesTheSameWayInBothOrders() {
        let first = entry("Alpha", ["alfa"])
        let second = entry("Beta", ["alfa"])
        XCTAssertEqual(
            VocabularyReplacer.apply("dis alfa", entries: [first, second]),
            VocabularyReplacer.apply("dis alfa", entries: [second, first])
        )
    }

    // MARK: - Idempotence

    func testApplyingTwiceEqualsApplyingOnce() {
        let entries = [
            entry("Kubernetes", ["cubernetes", "kubernetès"]),
            entry("Claude Code", ["clode code", "cloud code"]),
            entry("東京", ["とうきょう"])
        ]
        let raw = "cloud code puis cubernetes, et とうきょう, encore clode code."
        let once = VocabularyReplacer.apply(raw, entries: entries)
        XCTAssertEqual(VocabularyReplacer.apply(once, entries: entries), once)
    }

    func testAVariantThatWouldReappearInsideItsOwnTermIsDropped() {
        // Without the rule-build filter this cycles: `東京` → `東京都` → `東京都都`.
        let entries = [entry("東京都", ["東京"])]
        let once = VocabularyReplacer.apply("明日東京へ行く", entries: entries)
        XCTAssertEqual(once, "明日東京へ行く", "the variant lives inside its own term, so it is inert")
        XCTAssertEqual(VocabularyReplacer.apply(once, entries: entries), once)
    }

    func testTwoEntriesThatWouldSwapAreBothDropped() {
        // `foo → bar` and `bar → foo` would flip the text on every application.
        let entries = [entry("bar", ["foo"]), entry("foo", ["bar"])]
        let raw = "foo bar"
        let once = VocabularyReplacer.apply(raw, entries: entries)
        XCTAssertEqual(once, raw)
        XCTAssertEqual(VocabularyReplacer.apply(once, entries: entries), once)
    }

    func testAVariantIdenticalToItsTermIsInert() {
        // Byte-identical: dropped by `VocabularyEntry`, because replacing a string
        // with itself is the definition of a no-op.
        let entries = [entry("Dictus", ["Dictus"])]
        XCTAssertEqual(entries[0].variants, [])
        XCTAssertEqual(VocabularyReplacer.apply("Dictus", entries: entries), "Dictus")
    }

    func testAVariantDifferingOnlyByCaseNormalisesTheSpellingAndIsAFixedPoint() {
        // The commonest mangling of all: the engine writes a proper noun lowercase.
        // The rule matches its own term, which is a fixed point rather than a cycle.
        let entries = [entry("Ampli", ["ampli"])]
        let once = VocabularyReplacer.apply("branche l'ampli", entries: entries)
        XCTAssertEqual(once, "branche l'Ampli")
        XCTAssertEqual(VocabularyReplacer.apply(once, entries: entries), once)
    }

    // MARK: - Scale

    func testTwoHundredEntriesReplaceCorrectly() {
        let entries = (0..<VocabularyStore.maxEntries).compactMap {
            VocabularyEntry(term: "Term\($0)", variants: ["variant\($0)"])
        }
        XCTAssertEqual(entries.count, VocabularyStore.maxEntries)
        let raw = "on dit variant0 puis variant199 et variant42"
        XCTAssertEqual(
            VocabularyReplacer.apply(raw, entries: entries),
            "on dit Term0 puis Term199 et Term42"
        )
    }
}
