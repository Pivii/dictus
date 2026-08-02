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

    /// Polish `raw` STT output in `targetLanguage` under the given `mode`.
    /// Throws on cancellation or backend failure — the coordinator falls back
    /// to the raw text and emits an `engineFailed` metric.
    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                mode: PolishMode) async throws -> String

    /// Warm up backend state for `(mode, targetLanguage)` (e.g. preload
    /// weights, prime the session with the matching instructions). Called at
    /// app launch and at recording start by `PolishCoordinator`, which passes
    /// `.natural` on the per-language path and `.auto` in Auto-detect mode
    /// (#239). Default implementation is a no-op for engines that have
    /// nothing to warm.
    func prewarm(mode: PolishMode, targetLanguage: SupportedLanguage) async

    /// Whether a `polish(raw:targetLanguage:mode:)` call with this exact input
    /// would fit inside the backend's context window (#270).
    ///
    /// Asked by `PolishPipeline` immediately before the call, so an overflow is
    /// an explicit, named refusal instead of a mid-call throw the pipeline can
    /// only record as a generic engine failure. The engine answers because the
    /// ceiling is a property of the backend — its window size, its system
    /// prompt for `(mode, targetLanguage)`, its prompt scaffolding. No caller
    /// hardcodes a number.
    ///
    /// `input` is the string that will be passed as `raw`, i.e. already through
    /// the newline-marker encode — the markers cost tokens too.
    ///
    /// Default implementation returns `.fits`: an engine with no ceiling is
    /// valid and stays unaffected.
    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    mode: PolishMode) -> PolishContextFit
}

public extension PolishEngineProtocol {
    func prewarm(mode: PolishMode, targetLanguage: SupportedLanguage) async {}

    func contextFit(input: String,
                    targetLanguage: SupportedLanguage,
                    mode: PolishMode) -> PolishContextFit { .fits }
}
