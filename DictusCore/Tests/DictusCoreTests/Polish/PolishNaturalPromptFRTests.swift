// DictusCore/Tests/DictusCoreTests/Polish/PolishNaturalPromptFRTests.swift
import XCTest
@testable import DictusCore

/// Contract checks on the French Natural prompt (ADR 0003, recalibrated in #439).
/// The prompt's actual polishing quality is measured off-device with
/// `polish-harness` (`fixtures/longform-fr.json`, bars in
/// `docs/research/439-natural-contract/bars.md`) — these tests only pin the
/// structural clauses that must never silently disappear.
final class PolishNaturalPromptFRTests: XCTestCase {

    private var prompt: String {
        PolishNaturalPromptFR.instructions(glossary: PolishGlossary.promptBlock)
    }

    /// Rule 8 stays exactly as ADR 0003 shipped it. #439 measured that widening
    /// it changes nothing — Apple FM does not detect a homophone that reads as
    /// fluent French, 0/5 even alone in one sentence — and the words would be
    /// paid for in input headroom, since instructions share the window with the
    /// input (#270). This pins the decision, not just the text.
    func testRuleEightIsNotWidened() {
        XCTAssertTrue(prompt.contains("ASR error repair"))
        XCTAssertTrue(prompt.contains("off-language fragment"))
        XCTAssertFalse(prompt.contains("Repair IN PLACE"))
        XCTAssertFalse(prompt.contains("homophone"))
    }

    /// #439 C. Deletion was only implied by the Preserve list; the measured run
    /// dropped `en calcul` mid-sentence and still passed every gate.
    func testForbiddenListBansDeletingMeaningfulWords() {
        XCTAssertTrue(prompt.contains("Do NOT delete words that carry meaning"))
        // The three rules that ARE allowed to touch a word stay named, so the ban
        // cannot be read as forbidding filler and stutter removal.
        XCTAssertTrue(prompt.contains("Rules 6 and 7 (stutters, fillers)"))
    }

    /// The Preserve entries #439 added by name. `machin` is the word the run
    /// substituted with `machine`; `cela` is the form the one repair reached for.
    func testPreserveListNamesThePlaceholderWordsAndSpokenForms() {
        XCTAssertTrue(prompt.contains("`machin`"))
        XCTAssertTrue(prompt.contains("NEVER `cela`"))
    }

    /// #439's scope fence: line breaks belong to #437 and this prompt must not
    /// have gained the licence to emit them.
    func testNewlineMarkerBanSurvives() {
        XCTAssertTrue(prompt.contains(PolishPostpass.newlineMarker))
        XCTAssertTrue(prompt.contains("Do NOT add `\(PolishPostpass.newlineMarker)` markers where none existed"))
    }

    /// The six segments #439 scores are held out of the prompt on purpose: an
    /// example that names one of them would make its measurement worthless.
    func testTheMeasuredRepairsAreNotTaughtByExample() {
        for segment in ["salle à tante", "salle d'attente", "répète le comptable",
                        "les zappais", "le cas honnête", "ses morceaux",
                        "Apple Store", "en calcul", "déborder"] {
            XCTAssertFalse(prompt.contains(segment),
                           "\(segment) is a #439 fixture segment and must stay out of the prompt")
        }
    }

    func testPromptEmbedsGlossary() {
        for term in PolishGlossary.terms {
            XCTAssertTrue(prompt.contains(term), "glossary term \(term) missing from the FR prompt")
        }
    }
}
