// DictusCore/Sources/DictusCore/Polish/PolishContextBudget.swift
import Foundation

/// Verdict of the pre-call context check (#270): does one polish call fit
/// inside its engine's context window?
///
/// Returned by `PolishEngineProtocol.contextFit(...)` so the pipeline can refuse
/// an oversized call WITHOUT knowing any engine's numbers — the ceiling belongs
/// to the backend, not to the transform around it. Engines with no ceiling
/// (`PassthroughPolishEngine`, and any future streaming backend) never return
/// `.exceeds`.
public enum PolishContextFit: Sendable, Equatable {
    /// The engine has no ceiling, or the estimate fits under it.
    case fits
    /// The estimate exceeds the ceiling. Carries both numbers so logs and
    /// metrics can say *how far* over, which is what tells a "one long
    /// dictation" apart from "our estimate is systematically wrong".
    case exceeds(estimatedTokens: Int, budgetTokens: Int)
}

/// The context ceiling of a polish backend, and the cheap estimator that
/// decides whether one call fits under it (#270).
///
/// WHY this exists: Apple's on-device model has a single context window that
/// covers **instructions + input + generated output together**. Overflow throws
/// `exceededContextWindowSize` mid-call, which `PolishPipeline` could only
/// record as a generic `.engineFailed` — indistinguishable from a crash or a
/// timeout. Estimating first turns a silent, unattributable failure into an
/// explicit, named refusal.
///
/// Lives here rather than inside `AppleFoundationModelsPolishEngine` because
/// that type is behind `#if canImport(FoundationModels)`; the budget arithmetic
/// is plain Swift and must stay unit-testable on every toolchain.
public struct PolishContextBudget: Sendable, Equatable {

    /// Total tokens the window holds — instructions, input and output together.
    public let contextWindowTokens: Int

    /// Tokens the backend spends on framing we do not control or measure: the
    /// engine's own Input/Output prompt wrapper plus whatever chat template the
    /// session prepends (role headers, BOS).
    public let scaffoldingTokens: Int

    /// Output allowance, as a multiple of the estimated input size.
    ///
    /// This is the term that carries the uncertainty, and the one the
    /// measurement reshaped. The overflow does not happen on prefill — it
    /// happens **during generation**, fifteen to twenty seconds into the call.
    /// On a successful call the model emits about 0.5 tokens per input token;
    /// on a failing one it runs away and emits past 2.3×. Which of the two
    /// happens is not knowable in advance, so the reserve is not "the expected
    /// output" — it is the lever that sets where a call stops being worth
    /// making. See `appleFoundationModels` for the data it was set from.
    public let outputReserveRatio: Double

    /// Multiplier applied to the whole estimate before comparing it to the
    /// window.
    ///
    /// The character-per-token ratios below were measured on fluent,
    /// common-word prose. Real STT output is messier — proper nouns, digits,
    /// mistranscribed fragments — and all of those tokenize less efficiently
    /// than the sentences we measured. This margin covers that gap and nothing
    /// else; the generation-length uncertainty lives in `outputReserveRatio`,
    /// where it belongs and where it can be retuned on its own.
    ///
    /// WHY the two are kept separate and both modest: the errors are not
    /// symmetric, but neither is catastrophic. Under-estimating lets the engine
    /// throw, which lands on exactly today's behaviour — the user still gets
    /// the deterministic floor, we just lose the named reason. Over-estimating
    /// refuses a call that might have worked, taking polish away from a
    /// dictation that works today. And no static estimate can eliminate the
    /// throw: generation length is the model's choice, so the `.engineFailed`
    /// path stays the backstop it always was.
    public let safetyMargin: Double

    public init(contextWindowTokens: Int,
                scaffoldingTokens: Int,
                outputReserveRatio: Double,
                safetyMargin: Double) {
        self.contextWindowTokens = contextWindowTokens
        self.scaffoldingTokens = scaffoldingTokens
        self.outputReserveRatio = outputReserveRatio
        self.safetyMargin = safetyMargin
    }

    /// Apple's on-device Foundation Model, as used by
    /// `AppleFoundationModelsPolishEngine`.
    ///
    /// MEASURED, not assumed (#270, 2026-08-01, macOS 26.5.1, Apple
    /// Intelligence on): a session was given a one-word instruction and
    /// increasingly long inputs with `maximumResponseTokens: 1`, and the
    /// largest input that did not throw `exceededContextWindowSize` was
    /// binary-searched. The window came out at 4096 tokens — the number the
    /// engine's own comments already documented — and the same probe produced
    /// the characters-per-token ratios below.
    ///
    /// A second run confirmed instructions and input really do share one pool:
    /// swapping the one-word instruction for a 5000-character one (~977 tokens)
    /// cost 4800 characters of French input (~972 tokens). Instruction text and
    /// input text are interchangeable inside the window, one token for one
    /// token — which is why the estimate has to price the resolved prompt.
    ///
    /// A third run drove the real French Natural prompt through the real engine
    /// at increasing input lengths, repeated per length, on varied French
    /// dictation text. It found no clean threshold, and that result is the most
    /// important thing on this page:
    ///
    ///     3 000 chars  ok / ok / ok
    ///     3 600 chars  threw / ok / ok
    ///     4 150 chars  ok / ok / ok / threw
    ///     4 400 chars  ok / threw
    ///     4 700 chars  ok / ok
    ///     5 000 chars  threw / ok
    ///     5 200 chars  threw / threw
    ///
    /// Two things follow, and both shape the numbers below.
    ///
    /// **The failure is probabilistic, not a cliff.** The same input can throw
    /// on one call and succeed on the next, because the model sometimes runs
    /// away during generation. Its probability climbs steeply with input length
    /// but never becomes a clean line. So no static estimate can eliminate the
    /// throw, and this guard does not pretend to: the `.engineFailed` path
    /// stays exactly the backstop it always was, for the runaway that happens
    /// under any threshold.
    ///
    /// **Above ~4 500 characters the call is not worth making anyway.** Every
    /// successful run in the sweep returned about 2 300 characters regardless
    /// of how much went in — the model truncates rather than polishing the
    /// whole text. Against `PolishGuardrail`'s 0.5 length-ratio floor in
    /// Natural mode, a 4 700-character input polished down to 2 300 is rejected
    /// on arrival. Past that point the engine call costs ten seconds to produce
    /// something the pipeline will throw away.
    ///
    /// The constants therefore put the refusal at ~4 160 characters for the
    /// French Natural prompt (~690 words, ~4½ minutes of speech), which is
    /// where the two curves meet: below it the call usually succeeds and the
    /// output is usable, above it neither holds reliably.
    public static let appleFoundationModels = PolishContextBudget(
        contextWindowTokens: 4096,
        // The engine's wrapper ("Polish this text… Input: … Polished output:")
        // is ~25 tokens; the session's chat template adds a few dozen more.
        scaffoldingTokens: 64,
        outputReserveRatio: 1.8,
        safetyMargin: 1.15
    )

    // MARK: - Fit

    /// Estimated total token cost of one call: instructions + scaffolding +
    /// input + the output reserve, all multiplied by the safety margin.
    public func estimatedTokens(instructions: String, input: String) -> Int {
        let inputTokens = Self.estimatedTokens(in: input)
        let outputReserve = Int((Double(inputTokens) * outputReserveRatio).rounded(.up))
        let subtotal = Self.estimatedTokens(in: instructions)
            + scaffoldingTokens
            + inputTokens
            + outputReserve
        return Int((Double(subtotal) * safetyMargin).rounded(.up))
    }

    /// Whether one call fits. `instructions` must be the **resolved** system
    /// prompt for the mode and language actually being run — the prompts differ
    /// by a factor of two in length (the language-agnostic Auto prompt is the
    /// longest, the English Repair prompt the shortest), so a fixed allowance
    /// would under-estimate on exactly the modes with the most to lose.
    public func fit(instructions: String, input: String) -> PolishContextFit {
        let total = estimatedTokens(instructions: instructions, input: input)
        guard total > contextWindowTokens else { return .fits }
        return .exceeds(estimatedTokens: total, budgetTokens: contextWindowTokens)
    }

    // MARK: - Estimator

    /// Characters per token for alphabetic scripts.
    ///
    /// MEASURED against the real model (see `appleFoundationModels`): French
    /// 4.94, English 5.12, German 5.42 characters per token on fluent prose.
    /// The lowest of the three is used, so the estimate is already the
    /// least favourable of our four Latin-script languages before the safety
    /// margin applies.
    private static let latinCharsPerToken = 4.9

    /// Tokens per ideographic character (Han, Kana, Hangul).
    ///
    /// MEASURED at 1.80 characters per token — i.e. 0.56 tokens per character,
    /// roughly nine times denser per character than Latin script. Auto-detect
    /// mode (#239) accepts the whole long tail of languages, so a single
    /// Latin-tuned ratio would badly under-count a Chinese or Japanese
    /// dictation. Rounded up to 0.6.
    private static let tokensPerIdeographicChar = 0.6

    /// Cheap, deliberately approximate token count for `text`.
    ///
    /// One pass over the Unicode scalars, splitting them into ideographic and
    /// everything-else and applying the measured ratio to each. No tokenizer,
    /// no allocation, no table lookup — this runs on every dictation, and a
    /// costly estimator would tax the common case to protect the rare one.
    /// Exactness is not the goal: `fit(instructions:input:)` only ever compares
    /// the result against a ceiling that already carries a safety margin.
    public static func estimatedTokens(in text: String) -> Int {
        var alphabetic = 0
        var ideographic = 0
        for scalar in text.unicodeScalars {
            if isIdeographic(scalar) {
                ideographic += 1
            } else {
                alphabetic += 1
            }
        }
        let tokens = Double(alphabetic) / latinCharsPerToken
            + Double(ideographic) * tokensPerIdeographicChar
        return Int(tokens.rounded(.up))
    }

    /// Han ideographs, Japanese kana, Hangul and the CJK punctuation/full-width
    /// blocks that travel with them. Deliberately a short list of ranges rather
    /// than a `CharacterSet`: the check runs per scalar on every dictation, and
    /// range comparisons cost nothing.
    private static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F,   // CJK symbols and punctuation
             0x3040...0x30FF,   // Hiragana + Katakana
             0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xAC00...0xD7AF,   // Hangul syllables
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFF00...0xFFEF,   // Half-width and full-width forms
             0x20000...0x2FA1F: // CJK Unified Ideographs Extensions B–F
            return true
        default:
            return false
        }
    }
}
