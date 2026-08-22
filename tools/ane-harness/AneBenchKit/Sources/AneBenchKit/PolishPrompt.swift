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

    /// Build the prompt for a fixture id in the bundled copy of `seed.json`.
    ///
    /// Throws rather than falling back to a hardcoded string: a prompt that is
    /// almost the shipping one produces a number that looks like an answer and
    /// is not one.
    @available(iOS 26.0, macOS 26.0, *)
    public static func natural(fixtureID: String = "3-long") throws -> PolishPrompt {
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
        return PolishPrompt(
            system: AppleFoundationModelsPolishEngine.instructions(for: .natural, language: language),
            // Byte-identical to `AppleFoundationModelsPolishEngine.polish`, which
            // builds this string inline, and to `LocalHTTPPolishEngine.userTurn`,
            // which the off-device spike measured through.
            user: """
            Polish this text. Output only the polished version, nothing else.

            Input:
            \(preprocessed)

            Polished output:
            """,
            fixtureID: fixture.id
        )
    }

    /// Only the fields this harness reads. `polish-harness`'s own `Fixture` has
    /// the expectations too; scoring is not what D2 is for.
    private struct SeedFixture: Decodable {
        let id: String
        let raw: String
        let lang: String
    }

    public enum PromptError: Error, CustomStringConvertible {
        case fixturesMissing
        case noSuchFixture(String)
        case unsupportedLanguage(String)

        public var description: String {
            switch self {
            case .fixturesMissing:
                return "seed.json is not in the bundle — run tools/ane-harness/setup.sh"
            case .noSuchFixture(let id):
                return "no fixture with id \(id) in seed.json"
            case .unsupportedLanguage(let code):
                return "fixture language \(code) has no per-language polish prompt"
            }
        }
    }
}
