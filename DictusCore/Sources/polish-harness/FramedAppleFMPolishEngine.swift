// DictusCore/Sources/polish-harness/FramedAppleFMPolishEngine.swift
//
// Harness-only engine for #79. Identical to `AppleFoundationModelsPolishEngine`
// in every respect that the measurement depends on — same Apple Foundation
// Model, same `LanguageModelSession(instructions:)` wrapper, same one-call
// stateless lifecycle, same `PolishPipeline` around it — with ONE difference:
// the USER turn is supplied by the caller instead of being hardcoded.
//
// WHY this exists. The shipping engine hardcodes its user turn as
// "Polish this text. Output only the polished version, nothing else." That
// framing is correct for free polish and wrong for a Smart Mode: #79 says so
// itself — "asking the model to produce notes under an instruction that says
// 'polish' is self-defeating" — and lists making the framing per-mode as an
// engine change the feature has to make. `--instructions` overrides the SYSTEM
// prompt only, so without this file the harness can only measure an Email
// prompt underneath an instruction that says "polish", and round 2 produced
// direct evidence that the mismatch matters (the model emitted "voici la
// version polie du texte" and collapsed the register lift back toward free
// polish). Measuring the confound is cheaper than arguing about it.
//
// It deliberately does NOT touch the shipping engine: the Smart Modes pipeline
// is being built on another branch, and this is a measurement, not a step
// toward shipping. Whatever framing wins here is a finding for that branch to
// implement, not code it can import.
//
// Lives in the `polish-harness` target only — macOS-only, excluded from every
// app target and from CI.

#if os(macOS)
import Foundation
import DictusCore
#if canImport(FoundationModels)
import FoundationModels

/// Apple FM with a caller-supplied system prompt AND a caller-supplied user
/// turn. `{{INPUT}}` in the framing template is replaced by the (already
/// newline-encoded) text the pipeline hands over; a template without the
/// placeholder gets the text appended after a blank line, so a one-line
/// framing file still works.
@available(macOS 26.0, *)
struct FramedAppleFMPolishEngine: PolishEngineProtocol {

    let identifier = "apple-fm"

    private let instructions: String
    private let framing: String

    /// The shipping engine's framing, quoted so a run can A/B against it
    /// explicitly rather than by omitting a flag.
    ///
    /// Built from `PolishTask` rather than typed out, since #518: this constant is
    /// the "baseline" side of every framing A/B, and a baseline that has drifted
    /// from what ships measures nothing. The placeholder is substituted for the raw
    /// exactly where `userTurn` puts it.
    static let shippingFraming = PolishTask.natural.userTurn(raw: "{{INPUT}}")

    init(instructions: String, framing: String) {
        self.instructions = instructions
        self.framing = framing
    }

    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                task: PolishTask) async throws -> String {
        // One session per call, dropped on return — the same stateless
        // invariant the shipping engine maintains through its cache, reached
        // here by not having a cache at all. The harness makes one call at a
        // time, so there is nothing to reuse and nothing to race.
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: userTurn(raw: raw))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func userTurn(raw: String) -> String {
        guard framing.contains("{{INPUT}}") else { return framing + "\n\n" + raw }
        return framing.replacingOccurrences(of: "{{INPUT}}", with: raw)
    }

    /// Priced against the same budget as the shipping engine, on the strings
    /// this engine actually sends — instructions plus the FRAMED input, not the
    /// bare input. A framing template is prompt too.
    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    task: PolishTask) -> PolishContextFit {
        AppleFoundationModelsPolishEngine.contextBudget.fit(
            instructions: instructions,
            input: userTurn(raw: input)
        )
    }

    func failureReason(for error: Error) -> PolishFailureReason {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return .other(error)
        }
        switch generationError {
        case .exceededContextWindowSize: return .exceededContextWindowSize
        case .assetsUnavailable: return .assetsUnavailable
        case .guardrailViolation: return .guardrailViolation
        case .unsupportedGuide: return .unsupportedGuide
        case .unsupportedLanguageOrLocale: return .unsupportedLanguageOrLocale
        case .decodingFailure: return .decodingFailure
        case .rateLimited: return .rateLimited
        case .concurrentRequests: return .concurrentRequests
        case .refusal: return .refusal
        @unknown default: return .other(error)
        }
    }
}
#endif
#endif
