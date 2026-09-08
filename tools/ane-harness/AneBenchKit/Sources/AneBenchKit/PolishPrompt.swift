// tools/ane-harness/Sources/AneBenchKit/PolishPrompt.swift
//
// THROWAWAY — #268 D2.
//
// The measurement is only worth taking on the real prompt. #268 asks for
// "the real `PolishNaturalPromptFR` system message plus the `3-long` fixture —
// 1,704 tokens of prefill", and every byte of that is reachable from DictusCore
// rather than transcribed here: the instructions through the one entry point
// both shipping engines use, the fixture from a copy of the harness fixture
// file, and the pre-pass because that is what runs before the engine sees the
// text.
import Foundation
import DictusCore

public struct PolishPrompt: Sendable {
    /// Resolved per-(mode, language) instructions — the system message.
    public let system: String
    /// The Input/"Polished output:" user turn, over pre-passed text.
    public let user: String
    /// Which fixture the user turn was built from.
    public let fixtureID: String
    /// The mode the pipeline resolved for this fixture, printed alongside the
    /// numbers so the report says which instruction set was measured.
    public let mode: String

    /// Build the prompt for a fixture id in the bundled copy of `seed.json`.
    ///
    /// Throws rather than falling back to a hardcoded string: a prompt that is
    /// almost the shipping one produces a number that looks like an answer and
    /// is not one. For the same reason the mode is resolved through
    /// `PolishPipeline.mode` instead of assumed to be `.natural` — a Parakeet
    /// fixture whose detected language differs from its target resolves to
    /// `.repair`, whose instructions are less than half the length, and measuring
    /// prefill on the wrong instruction set would measure the wrong prompt.
    /// (`3-long`, the fixture D2 uses, resolves to `.natural`.)
    @available(iOS 26.0, macOS 26.0, *)
    public static func resolved(fixtureID: String = "3-long") throws -> PolishPrompt {
        guard let url = Bundle.module.url(forResource: "seed", withExtension: "json") else {
            throw PromptError.fixturesMissing
        }
        let fixtures = try JSONDecoder().decode([SeedFixture].self, from: Data(contentsOf: url))
        guard let fixture = fixtures.first(where: { $0.id == fixtureID }) else {
            throw PromptError.noSuchFixture(fixtureID)
        }
        guard let language = SupportedLanguage(rawValue: fixture.lang) else {
            throw PromptError.unsupportedLanguage(fixture.lang)
        }
        let preprocessed = VerbalPunctuationPrepass.apply(fixture.raw, language: language)
        guard let detected = PolishPipeline.detectLanguage(in: preprocessed) else {
            throw PromptError.languageUndetected(fixture.id)
        }
        // A task, not a bare mode, since #79 turned both the instruction dispatch
        // and the user turn into properties of one value. This file predates that
        // change and had not been rebuilt through it — its manifest cannot even
        // load without `../.deps/Anemll`, which `setup.sh` clones — so the two call
        // sites below are corrected together with #518's framing change rather
        // than left stale under a comment claiming they match what ships.
        let task = PolishTask.polish(PolishPipeline.mode(sttEngine: fixture.speechEngine,
                                                         detected: detected,
                                                         target: language))
        return PolishPrompt(
            system: AppleFoundationModelsPolishEngine.instructions(for: task, language: language),
            // Byte-identical to what the shipping engine sends, because it is the
            // same call: `AppleFoundationModelsPolishEngine.polish` composes its
            // user turn through `PolishTask.userTurn(raw:)` too. This used to be a
            // hand copy of that string, and #518 changed the framing — a hand copy
            // would have gone on measuring prefill on a prompt no build sends.
            user: task.userTurn(raw: preprocessed),
            fixtureID: fixture.id,
            mode: task.identifier
        )
    }

    /// Only the fields this harness reads. `polish-harness`'s own `Fixture` has
    /// the expectations too; scoring is not what D2 is for.
    private struct SeedFixture: Decodable {
        let id: String
        let raw: String
        let lang: String
        let sttEngine: String?

        /// Matches `polish-harness`'s `Fixture`: Parakeet unless stated.
        var speechEngine: SpeechEngine { sttEngine == "WK" ? .whisperKit : .parakeet }
    }

    public enum PromptError: Error, CustomStringConvertible {
        case fixturesMissing
        case noSuchFixture(String)
        case unsupportedLanguage(String)
        case languageUndetected(String)

        public var description: String {
            switch self {
            case .fixturesMissing:
                return "seed.json is not in the bundle — run tools/ane-harness/setup.sh"
            case .noSuchFixture(let id):
                return "no fixture with id \(id) in seed.json"
            case .unsupportedLanguage(let code):
                return "fixture language \(code) has no per-language polish prompt"
            case .languageUndetected(let id):
                return "language detection returned nil for \(id) — the pipeline would "
                     + "skip the engine, so there is no prompt to measure"
            }
        }
    }
}
