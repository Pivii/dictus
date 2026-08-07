// DictusCore/Tests/DictusCoreTests/KeyCaseTransformTests.swift
import XCTest
@testable import DictusCore

/// The transformation the shifted/capslock long-press popup applies to its candidates
/// (`KeyboardView.longpressKeys(for:)`). The keyboard target has no test bundle, which is
/// why the transformation lives in DictusCore — these tests measure what the popup renders
/// and, since the selected candidate is inserted verbatim, what gets typed.
final class KeyCaseTransformTests: XCTestCase {

    // MARK: - The ß case (#322)

    /// The bug: `"ß".uppercased()` is `"SS"`, so the popup drew one key that typed two letters.
    func testSharpSUppercasesToCapitalSharpS() {
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00DF}"), "\u{1E9E}")
        XCTAssertNotEqual(KeyCaseTransform.uppercased("\u{00DF}"), "SS")
    }

    /// One key in, one key out — what the popup renders and what the bridge inserts.
    func testSharpSUppercaseIsASingleCharacter() {
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00DF}").count, 1)
    }

    /// The capital sharp s is already uppercase and must survive the transformation.
    func testCapitalSharpSIsUnchanged() {
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{1E9E}"), "\u{1E9E}")
    }

    /// The unshifted path is untouched: the popup shows the mapping as declared.
    /// `AccentedCharacterTests` and `QWERTZLayoutTests` pin the mapping itself; this
    /// restates it here so the unshifted half of #322 is visible in one place.
    func testUnshiftedSharpSComesStraightFromTheMapping() {
        XCTAssertEqual(AccentedCharacters.accents(for: "s"), ["\u{00DF}"])
    }

    // MARK: - The general rule

    /// Every long-press candidate the keyboard can show, whatever the layout or language:
    /// its uppercase form is exactly one character. This is the invariant the popup depends
    /// on, and the one `uppercased()` alone breaks for ß.
    func testEveryAccentCandidateUppercasesToASingleCharacter() {
        for (baseKey, candidates) in AccentedCharacters.mappings {
            for candidate in candidates {
                let uppercased = KeyCaseTransform.uppercased(candidate)
                XCTAssertEqual(uppercased.count, 1,
                               "long-press \(baseKey): '\(candidate)' uppercased to '\(uppercased)'")
            }
        }
    }

    /// A one-to-many uppercase with no declared single-character capital keeps its character
    /// rather than growing: `ŉ` (U+0149) would otherwise become `ʼN`, two characters.
    /// Cosmetically wrong beats textually wrong.
    func testOneToManyWithoutASingleCharacterCapitalIsLeftAlone() {
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{0149}"), "\u{0149}")
    }

    // MARK: - Unchanged for every other candidate

    /// French accents, the reason the transformation exists in the first place.
    func testFrenchAccentsUppercaseAsBefore() {
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00E9}"), "\u{00C9}")   // é → É
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00E8}"), "\u{00C8}")   // è → È
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00EA}"), "\u{00CA}")   // ê → Ê
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00EB}"), "\u{00CB}")   // ë → Ë
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00E0}"), "\u{00C0}")   // à → À
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00F4}"), "\u{00D4}")   // ô → Ô
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00E7}"), "\u{00C7}")   // ç → Ç
    }

    /// Spanish acute and n-tilde (#82/#83), and the German umlauts (#109/#151).
    func testSpanishAndGermanCandidatesUppercaseAsBefore() {
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00F1}"), "\u{00D1}")   // ñ → Ñ
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00E1}"), "\u{00C1}")   // á → Á
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00E4}"), "\u{00C4}")   // ä → Ä
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00F6}"), "\u{00D6}")   // ö → Ö
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{00FC}"), "\u{00DC}")   // ü → Ü
    }

    /// Anything with a one-to-one mapping still matches plain `uppercased()`, so no accent
    /// candidate changed behaviour except ß.
    func testMatchesPlainUppercasedForEveryOneToOneCandidate() {
        for candidates in AccentedCharacters.mappings.values {
            for candidate in candidates where candidate.uppercased().count == 1 {
                XCTAssertEqual(KeyCaseTransform.uppercased(candidate), candidate.uppercased())
            }
        }
    }

    /// Characters with no case (the AZERTY adaptive key's apostrophe, digits, the emoji key
    /// glyph) pass through untouched — the popup transform runs over whatever the page holds.
    func testCaselessCharactersAreUnchanged() {
        XCTAssertEqual(KeyCaseTransform.uppercased("'"), "'")
        XCTAssertEqual(KeyCaseTransform.uppercased("1"), "1")
        XCTAssertEqual(KeyCaseTransform.uppercased("\u{1F600}"), "\u{1F600}")
    }

    func testEmptyStringIsUnchanged() {
        XCTAssertEqual(KeyCaseTransform.uppercased(""), "")
    }
}
