// DictusCore/Tests/DictusCoreTests/Polish/PolishAutoPromptTests.swift
import XCTest
@testable import DictusCore

/// Contract checks on the language-agnostic Auto-mode prompt (#239) and its
/// routing. The prompt's actual polishing quality is evaluated with the
/// off-device harness (`polish-harness`, fixtures/auto.json) — these tests
/// only pin the structural invariants that must never regress.
final class PolishAutoPromptTests: XCTestCase {

    func testAutoPromptStatesTheAutoDetectContract() {
        let prompt = PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        // The maintainer-locked contract: English-written prompt, announces
        // that the input language was auto-detected, forbids translation.
        XCTAssertTrue(prompt.contains("AUTO-DETECTED"))
        XCTAssertTrue(prompt.contains("NEVER translate"))
        XCTAssertTrue(prompt.contains("Do NOT translate"))
        // Newline-marker rule must be present — the encode/decode pass stays
        // on in auto mode.
        XCTAssertTrue(prompt.contains(PolishPostpass.newlineMarker))
    }

    func testAutoPromptEmbedsGlossary() {
        let prompt = PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        for term in PolishGlossary.terms {
            XCTAssertTrue(prompt.contains(term), "glossary term \(term) missing from auto prompt")
        }
    }

    #if canImport(FoundationModels)
    /// The `(mode, language)` dispatch must ignore the language in `.auto`
    /// mode: one prompt for every auto-detected input language.
    @available(iOS 26.0, macOS 26.0, *)
    func testEngineRoutesAutoModeToTheSamePromptForEveryLanguage() {
        let reference = AppleFoundationModelsPolishEngine.instructions(for: .auto, language: .english)
        for language in SupportedLanguage.allCases {
            XCTAssertEqual(
                AppleFoundationModelsPolishEngine.instructions(for: .auto, language: language),
                reference,
                "auto prompt must not vary with the placeholder language"
            )
        }
        XCTAssertEqual(
            reference,
            PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        )
        // And it must be distinct from every per-language prompt.
        for language in SupportedLanguage.allCases {
            XCTAssertNotEqual(
                reference,
                AppleFoundationModelsPolishEngine.instructions(for: .natural, language: language)
            )
        }
    }
    #endif
}
