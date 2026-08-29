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

    /// #239 device-test fix: the prompt carries the multilingual spoken-command
    /// vocabulary (backup layer for fr/en, only layer for es/de and beyond).
    /// Bare sentence-period words stay excluded (#185).
    func testAutoPromptListsVerbalCommandVocabulary() {
        let prompt = PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        for command in ["point d'exclamation", "retour à la ligne",
                        "exclamation mark", "new line",
                        "signo de exclamación", "nueva línea",
                        "Ausrufezeichen", "neue Zeile"] {
            XCTAssertTrue(prompt.contains(command), "missing spoken command \(command)")
        }
        XCTAssertFalse(prompt.contains("`point` →"), "bare French 'point' must stay excluded (#185)")
        XCTAssertFalse(prompt.contains("`period`"), "bare English 'period' must stay excluded (#185)")
        XCTAssertFalse(prompt.contains("`punto` →"), "bare Spanish 'punto' must stay excluded (#185)")
        XCTAssertFalse(prompt.contains("`Punkt`"), "bare German 'Punkt' must stay excluded (#185)")
    }

    /// #439. This prompt carries no ASR-repair rule, and that is now a measured
    /// decision rather than an oversight: all six defects the issue lists came
    /// through here, and adding the rule moved none of them (0-1 of 6, before and
    /// after). Its words would be paid for in input headroom on the longest prompt
    /// this build sends, so they are not spent. If a future engine can do the
    /// repair, this test is the thing to delete first.
    func testAutoPromptDoesNotCarryASRRepair() {
        let prompt = PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        XCTAssertFalse(prompt.contains("ASR error repair"))
        XCTAssertFalse(prompt.contains("Repair IN PLACE"))
        // The clauses a repair rule would sit next to and could undermine.
        XCTAssertTrue(prompt.contains("NEVER translate"))
        XCTAssertTrue(prompt.contains("Do NOT translate"))
    }

    /// #439 C, and the scope fence it shares with #437: content may not be dropped,
    /// and this round must not have handed the model line breaks.
    func testAutoPromptBansDeletionAndStillBansNewMarkers() {
        let prompt = PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        XCTAssertTrue(prompt.contains("Do NOT delete words that carry meaning"))
        XCTAssertTrue(prompt.contains("Do NOT add `\(PolishPostpass.newlineMarker)` markers where none existed"))
    }

    /// The deletion ban must except rule 4, and it matters MORE here than on the
    /// per-language path.
    ///
    /// `PolishService.polishTargeted` runs `VerbalPunctuationPrepass` in code before
    /// the model sees the text, so on the four supported languages `virgule` is
    /// already a comma and a contradictory ban is inert. The auto path has no such
    /// floor: `PolishPipeline.autoPreprocess` returns the raw UNCHANGED when
    /// detection lands outside those four, which is exactly the input this prompt
    /// exists for. Rule 4 is then the only mechanism, and a ban promising that every
    /// noun in the input survives tells the model to keep the command word.
    func testAutoPromptDeletionBanExceptsTheVerbalPunctuationRule() {
        let prompt = PolishAutoPrompt.instructions(glossary: PolishGlossary.promptBlock)
        XCTAssertTrue(prompt.contains("Rules 4, 5 and 6 are the only licence to remove a word"))
        XCTAssertTrue(prompt.contains("rule 4 removes a spoken punctuation command"))
        XCTAssertTrue(prompt.contains("the speaker DICTATED appears in the output"))
        // The old wording, which promised the opposite of rule 4.
        XCTAssertFalse(prompt.contains("Rules 5 and 6 (stutters, hesitation fillers) are the only licence"))
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
