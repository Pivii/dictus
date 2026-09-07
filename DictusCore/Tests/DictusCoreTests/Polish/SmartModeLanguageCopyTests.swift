// DictusCore/Tests/DictusCoreTests/Polish/SmartModeLanguageCopyTests.swift
// The sentence a Smart Mode shows when the dictated language is one the model
// cannot read (#490), pinned on both surfaces and in both catalogues.

import XCTest
@testable import DictusCore

/// #490 asks for one sentence in three places at once: the keyboard toolbar, the
/// app's failure screen, and the string catalogues that translate them. Nothing
/// compiles the three together — the two targets have no test bundle and a catalogue
/// is data — so this reads the repo, the way `SmartModeProCopyTests` does for #460.
///
/// What it defends is not the wording. It is that the wording exists on **both**
/// surfaces (a keyboard dictation and an in-app one hit different call sites), that
/// it is keyed on the outcome rather than on Apple's ambiguous slug, and that it does
/// not tell the user to retry something that will fail identically.
final class SmartModeLanguageCopyTests: XCTestCase {

    /// The English source string, as both call sites write it and as the catalogues
    /// key it. The `%@` form is what Xcode's extractor produces from the two
    /// interpolations.
    private static let sentence =
        "Apple Intelligence does not support the dictated language"
    private static let catalogueKey =
        "%@: Apple Intelligence does not support the dictated language (%@)."

    private static let keyboardSource = "DictusKeyboard/KeyboardPolishCoordinator.swift"
    private static let appSource = "DictusApp/DictationHandoff.swift"

    // MARK: - Both surfaces say it

    func testBothSurfacesCarryTheSentence() throws {
        for path in [Self.keyboardSource, Self.appSource] {
            let source = try source(at: path)
            XCTAssertTrue(
                source.contains(Self.sentence),
                "\(path) does not name the dictated language when a Smart Mode is refused for it"
            )
        }
    }

    /// The branch has to be on the outcome. #518 measured
    /// `unsupportedLanguageOrLocale` arriving from plain French — a language Apple
    /// does read — so a surface keyed on that slug would tell a French speaker their
    /// own language is unsupported, and the log would agree with it.
    func testBothSurfacesKeyTheSentenceOnTheOutcomeAndNotOnApplesSlug() throws {
        for path in [Self.keyboardSource, Self.appSource] {
            let source = try source(at: path)
            let branch = try XCTUnwrap(
                source.range(of: "PolishMetrics.Outcome.unsupportedInputLanguage.rawValue"),
                "\(path) does not branch on the outcome"
            )
            let sentence = try XCTUnwrap(source.range(of: Self.sentence))
            XCTAssertLessThan(
                branch.lowerBound, sentence.lowerBound,
                "\(path) reaches the sentence before establishing which refusal it is"
            )
            // The slug may appear in a comment explaining why it is NOT the key; it
            // may not appear as a comparison.
            XCTAssertFalse(
                source.contains("== \"unsupportedLanguageOrLocale\""),
                "\(path) compares Apple's slug, which #518 proved cannot separate the two causes"
            )
        }
    }

    /// The one refusal with a knowable cause and no remedy. "Try again" here would be
    /// an instruction to repeat a failure: Apple classifies the user turn before
    /// generating, so the same words in the same language are refused every time.
    func testTheSentenceDoesNotInviteARetry() throws {
        for candidate in try catalogueValues() {
            XCTAssertFalse(
                candidate.lowercased().contains("try again"),
                "the language refusal invites a retry that cannot succeed: \(candidate)"
            )
            XCTAssertFalse(
                candidate.lowercased().contains("réessa"),
                "the language refusal invites a retry that cannot succeed: \(candidate)"
            )
        }
    }

    // MARK: - Both catalogues translate it

    /// Every UI language the app ships. `Dictus.xcodeproj` declares `knownRegions =
    /// (en, fr, Base)`; the keyboard's catalogue carries `fr` against the English
    /// source, the app's carries `en` and `fr`. A sentence added to one and not the
    /// other reaches a French user in English.
    func testEveryUILanguageTranslatesTheSentence() throws {
        for (path, expected) in [
            ("DictusKeyboard/Localizable.xcstrings", Set(["fr"])),
            ("DictusApp/Localizable.xcstrings", Set(["en", "fr"]))
        ] {
            let entry = try XCTUnwrap(catalogue(at: path)[Self.catalogueKey],
                                      "\(path) has no entry for the language refusal")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), expected, "in \(path)")
        }
    }

    /// The French sentence names the language and stays inside the toolbar's two
    /// `.caption` lines, which fit roughly 100 characters (#313 sized the slot at
    /// two lines for exactly this reason).
    func testTheFrenchSentenceFitsTheToolbarAndNamesTheLanguage() throws {
        let french = try XCTUnwrap(
            catalogueValue(path: "DictusKeyboard/Localizable.xcstrings", language: "fr")
        )
        XCTAssertTrue(french.contains("%@"), "the French sentence drops a placeholder")
        // "→ EN" and "tchèque" substituted, the longest realistic rendering.
        let rendered = french
            .replacingOccurrences(of: "%@", with: "→ EN", options: [], range: french.range(of: "%@"))
            .replacingOccurrences(of: "%@", with: "tchèque")
        XCTAssertLessThan(rendered.count, 100, "too long for two .caption lines: \(rendered)")
        XCTAssertFalse(french.contains("—"), "no em dashes in user-facing copy")
    }

    // MARK: - Reading the repo

    private func catalogueValues() throws -> [String] {
        try ["DictusKeyboard/Localizable.xcstrings", "DictusApp/Localizable.xcstrings"]
            .flatMap { path -> [String] in
                guard let entry = try catalogue(at: path)[Self.catalogueKey],
                      let localizations = entry["localizations"] as? [String: Any] else { return [] }
                return localizations.values.compactMap {
                    (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                }
            } + [Self.catalogueKey]
    }

    private func catalogueValue(path: String, language: String) throws -> String? {
        let entry = try catalogue(at: path)[Self.catalogueKey]
        let localizations = entry?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    private func catalogue(at path: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent(path))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["strings"] as? [String: [String: Any]]) ?? [:]
    }

    private func source(at path: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Polish
            .deletingLastPathComponent()  // DictusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // DictusCore
            .deletingLastPathComponent()  // repo root
    }
}
