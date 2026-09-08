// DictusCore/Sources/DictusCore/Polish/PolishEngineProtocol.swift
import Foundation

/// Pluggable polish backend.
///
/// Round 1 has one production implementation (`AppleFoundationModelsPolishEngine`
/// in DictusApp). `PassthroughPolishEngine` exists to validate the wiring on
/// devices without Apple Foundation Models and during early development.
public protocol PolishEngineProtocol: Sendable {
    /// Stable identifier for metrics (e.g. "apple-fm", "passthrough").
    var identifier: String { get }

    /// Whether running this engine is a wait the user should be told about (#267).
    ///
    /// The dictation status moves to `.processing` -- new overlay animation, new
    /// footer label, new Dynamic Island treatment -- for the duration of the engine
    /// call. That is worth doing for a backend that takes seconds and worth
    /// suppressing for one that does not: announcing a stage that ends before the
    /// eye lands on it is a flicker, not information.
    ///
    /// Default implementation returns `true`: a real backend generates text and
    /// generation takes time, so a new engine gets the stage without opting in.
    var announcesProcessingStage: Bool { get }

    /// Run `task` over `raw` STT output, with instructions resolved for
    /// `targetLanguage`. Throws on cancellation or backend failure — the pipeline
    /// records an `engineFailed` metric, and the caller falls back to the raw text
    /// for the free polish or inserts nothing for a Smart Mode (#79).
    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                task: PolishTask) async throws -> String

    /// Warm up backend state for `(task, targetLanguage)` (e.g. preload
    /// weights, prime the session with the matching instructions). Called at
    /// app launch and at recording start by `PolishService`, which passes
    /// `.natural` on the per-language path, `.auto` in Auto-detect mode
    /// (#239), and the armed Smart Mode when there is one (#79). Default
    /// implementation is a no-op for engines that have nothing to warm.
    func prewarm(task: PolishTask, targetLanguage: SupportedLanguage) async

    /// Whether a `polish(raw:targetLanguage:task:)` call with this exact input
    /// would fit inside the backend's context window (#270).
    ///
    /// Asked by `PolishPipeline` immediately before the call, so an overflow is
    /// an explicit, named refusal instead of a mid-call throw the pipeline can
    /// only record as a generic engine failure. The engine answers because the
    /// ceiling is a property of the backend — its window size, its system
    /// prompt for `(task, targetLanguage)`, its prompt scaffolding. No caller
    /// hardcodes a number.
    ///
    /// `input` is the string that will be passed as `raw`, i.e. already through
    /// the newline-marker encode — the markers cost tokens too.
    ///
    /// Default implementation returns `.fits`: an engine with no ceiling is
    /// valid and stays unaffected.
    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    task: PolishTask) -> PolishContextFit

    /// Whether this backend can read a transcript made of `countedCodes` — the
    /// `NLLanguage` raw codes the language mix counted (#490).
    ///
    /// Asked by `PolishPipeline` before the call, for the same reason `contextFit`
    /// is: a refusal the backend was always going to make is worth making here,
    /// named, and for free. Apple Foundation Models classifies the user turn and
    /// refuses in 3 to 22 ms on a language outside its set; asking first turns that
    /// round trip into a local verdict the surface can explain.
    ///
    /// The engine answers because the readable set is a property of the backend —
    /// Apple publishes `SystemLanguageModel.default.supportedLanguages`, a future
    /// backend would publish something else, and no caller hardcodes a list.
    ///
    /// Default implementation returns `.unknown`: an engine that publishes no list
    /// is valid and stays unaffected, because `.unknown` never refuses.
    func inputLanguageSupport(countedCodes: Set<String>) -> PolishInputLanguageSupport

    /// Name the failure `error` — thrown by this engine's own `polish(...)` —
    /// so an engine failure stops being one opaque bucket (#315).
    ///
    /// WHY the engine answers rather than the pipeline: the error is an SDK
    /// type. Apple's `LanguageModelSession.GenerationError` lives behind
    /// `#if canImport(FoundationModels)` AND behind an iOS/macOS 26 availability
    /// gate, so a pipeline that classified it would have to import the framework
    /// and carry that gate — onto the off-device harness and every test with it.
    /// Only the engine that threw can see what it threw; the transform around it
    /// stays backend-agnostic, exactly as `contextFit` above already arranges
    /// for the context ceiling.
    ///
    /// Default implementation returns `.other(error)`: an engine that classifies
    /// nothing still reports an identifiable reason.
    func failureReason(for error: Error) -> PolishFailureReason
}

public extension PolishEngineProtocol {
    var announcesProcessingStage: Bool { true }

    func prewarm(task: PolishTask, targetLanguage: SupportedLanguage) async {}

    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    task: PolishTask) -> PolishContextFit { .fits }

    func inputLanguageSupport(countedCodes: Set<String>) -> PolishInputLanguageSupport { .unknown }

    func failureReason(for error: Error) -> PolishFailureReason { .other(error) }
}
