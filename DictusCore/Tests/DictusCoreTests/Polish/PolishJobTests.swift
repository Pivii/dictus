// DictusCore/Tests/DictusCoreTests/Polish/PolishJobTests.swift
// Which language's typography the post-pass applies (issue #79).
import XCTest
@testable import DictusCore

final class PolishJobTests: XCTestCase {

    private func job(_ task: PolishTask,
                     _ promptLanguage: SupportedLanguage,
                     agnostic: Bool) -> PolishJob {
        PolishJob(task: task, promptLanguage: promptLanguage, languageAgnosticPath: agnostic)
    }

    // MARK: - The free polish, unchanged by #79

    func testPerLanguagePolishAppliesTheTargetsTypography() {
        XCTAssertEqual(job(.natural, .french, agnostic: false).typographyLanguage, .french)
        XCTAssertEqual(job(.repair, .german, agnostic: false).typographyLanguage, .german)
    }

    /// On the auto path the output language is unknown, so per-language typography
    /// stays off — regexes tuned for the four tested languages would mangle e.g. CJK
    /// full-width punctuation (#239).
    func testAutoModeAppliesNoTypography() {
        XCTAssertNil(job(.auto, .french, agnostic: true).typographyLanguage)
    }

    // MARK: - Smart Modes

    /// Translation is the case the old `mode == .auto` branch could not express: the
    /// post-pass keys on the OUTPUT language, which is the target, not the input.
    func testTranslationAppliesItsTargetsTypographyOnEitherPath() {
        let toFrench = PolishTask.smart(SmartModeCatalogue.translate(to: .french))
        XCTAssertEqual(job(toFrench, .english, agnostic: false).typographyLanguage, .french)
        XCTAssertEqual(job(toFrench, .german, agnostic: true).typographyLanguage, .french)
    }

    /// A mode that keeps the speaker's language follows the path it runs on, exactly
    /// as the free polish does.
    func testNotesFollowsThePathItRunsOn() {
        let notes = PolishTask.smart(SmartModeCatalogue.notes)
        XCTAssertEqual(job(notes, .french, agnostic: false).typographyLanguage, .french)
        XCTAssertNil(job(notes, .french, agnostic: true).typographyLanguage)
    }

    func testThePromptLanguageIsCarriedThroughUnchanged() {
        XCTAssertEqual(job(.natural, .spanish, agnostic: false).promptLanguage, .spanish)
        let toEnglish = PolishTask.smart(SmartModeCatalogue.translate(to: .english))
        XCTAssertEqual(job(toEnglish, .spanish, agnostic: false).promptLanguage, .spanish)
    }
}
