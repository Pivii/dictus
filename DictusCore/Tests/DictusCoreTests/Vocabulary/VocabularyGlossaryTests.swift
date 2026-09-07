// DictusCore/Tests/DictusCoreTests/Vocabulary/VocabularyGlossaryTests.swift
// Decision 7, and the pre-registered bar that guards it (#80).
import XCTest
@testable import DictusCore

final class VocabularyGlossaryTests: XCTestCase {

    /// **The pre-registered bar.** A user with an empty vocabulary must not be able
    /// to tell this feature shipped, and the prompt is the surface where that would
    /// leak first: one extra separator in the glossary block changes every prompt in
    /// the repo and therefore every polish output.
    func testWithNoUserTermsTheActiveBlockIsByteIdenticalToTheStaticOne() {
        XCTAssertEqual(PolishGlossary.block(for: PolishGlossary.terms), PolishGlossary.promptBlock)
    }

    func testTheStaticBlockStillReadsExactlyAsItAlwaysHas() {
        // Spelled out rather than derived, so a change to the formatter cannot make
        // this test agree with itself.
        XCTAssertEqual(
            PolishGlossary.promptBlock,
            "Spell these terms exactly as written: Dictus, WhisperKit, Parakeet v3, "
            + "FluidAudio, GitHub, TestFlight, iOS, App Store, Argmax, Apple Intelligence."
        )
    }

    func testUserTermsAreAppendedAfterTheCuratedOnes() {
        let block = PolishGlossary.block(for: PolishGlossary.terms + ["Kubernetes", "Systeko"])
        XCTAssertTrue(block.hasPrefix("Spell these terms exactly as written: Dictus, "))
        XCTAssertTrue(block.hasSuffix("Apple Intelligence, Kubernetes, Systeko."))
        for term in PolishGlossary.terms {
            XCTAssertTrue(block.contains(term), "curated term \(term) must survive")
        }
    }

    /// Decision 7 in one assertion: a term with no variants is not inert, because it
    /// reaches the prompt even though it triggers no replacement.
    func testATermWithNoVariantsStillReachesThePrompt() {
        guard let entry = VocabularyEntry(term: "Systeko") else {
            return XCTFail("entry should be constructible")
        }
        XCTAssertEqual(VocabularyReplacer.apply("on livre systeko demain", entries: [entry]),
                       "on livre systeko demain")
        XCTAssertTrue(PolishGlossary.block(for: [entry.term]).contains("Systeko"))
    }

    /// `corrected` is the gate both consumers go through, and its identity branch is
    /// what makes the bar hold at runtime rather than only in a formatter.
    func testCorrectedHandsBackItsInputWhenNothingIsStored() {
        let raw = "Le déploiement est passé sans incident."
        XCTAssertEqual(CustomVocabulary.corrected(raw, entries: []), raw)
    }

    func testCorrectedAppliesTheVocabularyWhenEntriesArePassedIn() {
        guard let entry = VocabularyEntry(term: "Kubernetes", variants: ["cubernetes"]) else {
            return XCTFail("entry should be constructible")
        }
        XCTAssertEqual(
            CustomVocabulary.corrected("on déploie sur cubernetes", entries: [entry]),
            "on déploie sur Kubernetes"
        )
    }

    func testTheVocabularyGateIsTheProFeatureToggleAndNotJustTheSubscription() {
        // Same shape as `HistoryAvailability.isEntitled`: a subscriber who switched
        // the feature off in Settings has said what they want.
        XCTAssertEqual(ProFeature.vocabulary.settingsKey, SharedKeys.vocabularyEnabled)
        XCTAssertEqual(
            VocabularyAvailability.isEntitled, FeatureGate.isAvailable(.vocabulary)
        )
    }
}
