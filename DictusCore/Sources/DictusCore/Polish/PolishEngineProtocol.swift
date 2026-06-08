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

    /// Warm up backend state for `targetLanguage` (e.g. preload weights, prime
    /// the Light-mode session). Called at app launch by `PolishCoordinator`.
    /// Default implementation is a no-op for engines that have nothing to warm.
    func prewarm(targetLanguage: SupportedLanguage) async
}

public extension PolishEngineProtocol {
    func prewarm(targetLanguage: SupportedLanguage) async {}
}
