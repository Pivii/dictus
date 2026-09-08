// DictusCore/Tests/DictusCoreTests/Polish/PolishGuardrailCorpusReplayTests.swift
// The #414 corpus replay, and the counting rule behind its numbers.
//
// WHY this suite reaches out of the test bundle and into `docs/research/`: the
// numbers that decided the overlap floor were measured on hand-labelled corpora
// committed there, and `polish-harness guardrail` — the tool that prints them — is a
// macOS executable that needs a human to run it. A threshold whose evidence only
// exists in a command nobody runs is a threshold that drifts. This replays the same
// corpora through the same shipping code on every `swift test`.
//
// It resolves the repo from `#filePath` rather than copying the corpora into test
// resources, following `DictationErrorCopyTests` and `SmartModeProCopyTests`: a copy
// would drift, and drift is the failure being checked for.
import XCTest
@testable import DictusCore

final class PolishGuardrailCorpusReplayTests: XCTestCase {

    // MARK: - The counting rule (#414, decided 2026-09-07)

    /// A rejection is charged to a check only when it is a rejection the **user would
    /// otherwise have seen**.
    ///
    /// Pierre's decision, in his words on the issue: *"a rejection that never reaches
    /// the user is not a false rejection. It is a second lock on a door the first lock
    /// already closed, and counting it twice inflates the measured cost of the check."*
    /// He wrote it about the corpus's bilingual and wrong-language outputs — the
    /// 48-of-57 rule — which `detectedLanguageMatches` refuses upstream.
    ///
    /// It is applied here to both upstream checks rather than only to the language
    /// one, because the argument does not distinguish them: the two #466 device
    /// captures of an Apple FM preamble are refused by `PolishPrefixAlignment` on the
    /// contract they were captured under, so refusing them again costs a user
    /// nothing. **That extension is not in the issue text**, which predates #466's
    /// check reaching this corpus; it is written here so it is arguable rather than
    /// buried, and `testTheCountingRuleExcludesOnlyOutputsAnotherCheckRefuses` pins
    /// exactly which outputs it removes.
    private func countsAsFalseRejection(_ item: Case) -> Bool {
        item.language == "sameLanguage"
            && !(item.prefixApplies && (item.prefix ?? "aligned") != "aligned")
    }

    // MARK: - The replay

    /// **The acceptance criterion, executable.** Anchors OR overlap — the verdict the
    /// pipeline actually reaches on a contract with `requiresGroundedNames` — refuses
    /// every labelled fabrication but one, and refuses nothing a user would have kept.
    func testTheUnionRefusesEveryFabricationButTheKnownMiss() throws {
        let corpus = try load()
        var missed: [String] = []
        var falselyRejected: [String] = []
        var counted = 0

        for item in corpus where item.groundingApplies {
            let refuses = !PolishGrounding.ungroundedAnchors(
                in: item.output, input: item.preprocessed, languageCode: item.expectedLang
            ).isEmpty || !PolishGrounding.acceptsSegmentOverlap(
                polished: item.output, raw: item.preprocessed
            )
            if item.grounding == "fabricated" {
                if !refuses { missed.append(item.label) }
            } else if countsAsFalseRejection(item) {
                counted += 1
                if refuses { falselyRejected.append(item.label) }
            }
        }

        XCTAssertEqual(falselyRejected, [], "the floor may not cost a user an output they would have kept")
        XCTAssertEqual(
            missed, ["live-2026-08-27:Z1-sophie-reoccurrence#1"],
            "Z1 ships knowingly open (#414); any OTHER miss is a regression, and Z1 "
                + "disappearing from this list means the gap closed — update the issue"
        )
        XCTAssertGreaterThan(counted, 300, "guard against a replay that passes on an empty corpus")
    }

    /// The floor is 0.15 because 0.25 costs a measured false rejection, and that trade
    /// was declined. The alternative is replayed rather than described, so the cost
    /// stays a number.
    func testTheDeclinedHigherFloorCostsAMeasuredFalseRejection() throws {
        let corpus = try load()
        let stricter = PolishSegmentOverlapThresholds(floor: 0.25, minimumContentWords: 3)
        let falselyRejected = corpus
            .filter { $0.groundingApplies && $0.grounding != "fabricated" && countsAsFalseRejection($0) }
            .filter { !PolishGrounding.acceptsSegmentOverlap(
                polished: $0.output, raw: $0.preprocessed, thresholds: stricter
            ) }
            .map(\.label)
        XCTAssertFalse(
            falselyRejected.isEmpty,
            "if 0.25 has become free, the declined trade is worth re-taking (#414)"
        )
    }

    /// What the counting rule removes, named. Without this the rule could quietly grow
    /// to cover whatever a future threshold finds inconvenient.
    func testTheCountingRuleExcludesOnlyOutputsAnotherCheckRefuses() throws {
        let corpus = try load()
        for item in corpus where item.groundingApplies && item.grounding != "fabricated" {
            guard !countsAsFalseRejection(item) else { continue }
            let refusedUpstream = !PolishGuardrail.detectedLanguageMatches(
                polished: item.output, inputLanguageCode: item.expectedLang
            ) || (item.prefixApplies && !PolishPrefixAlignment.accepts(
                polished: item.output, raw: item.preprocessed
            ))
            XCTAssertTrue(
                refusedUpstream,
                "\(item.label) is excluded from the count but no shipped check refuses it"
            )
        }
    }

    // MARK: - Reading the corpora

    /// One hand-labelled output. A structural subset of the harness's `GuardrailCase`
    /// — that type lives in an executable target this bundle cannot import, and
    /// duplicating five fields is cheaper than making the harness a library.
    private struct Case: Decodable {
        let source: String
        let fixture: String
        let run: Int
        let task: String
        let inputLang: String
        let expectedLang: String
        let language: String
        let grounding: String
        let prefix: String?
        let raw: String
        let output: String

        var label: String { "\(source):\(fixture)#\(run)" }

        /// The pipeline compares against the pre-passed text, not the literal raw.
        var preprocessed: String {
            guard let language = SupportedLanguage(rawValue: inputLang) else { return raw }
            return VerbalPunctuationPrepass.apply(raw, language: language)
        }

        /// Where `requiresGroundedNames` is true: not a translation, not repair.
        var groundingApplies: Bool {
            !task.hasPrefix("smart.translate.") && task != "polish.repair"
        }

        /// Where `requiresAlignedPrefix` is true: the free polish only.
        var prefixApplies: Bool { task == "polish" || task.hasPrefix("polish.") }
    }

    private func load(file: StaticString = #filePath, line: UInt = #line) throws -> [Case] {
        let directory = repoRoot().appendingPathComponent("docs/research/413-414-guardrail")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertFalse(names.isEmpty, "no corpus found at \(directory.path)", file: file, line: line)
        let decoder = JSONDecoder()
        return try names.flatMap { name -> [Case] in
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return try decoder.decode([Case].self, from: data)
        }
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
