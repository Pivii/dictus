// DictusCore/Sources/DictusCore/Polish/PassthroughPolishEngine.swift
import Foundation

/// Validates the wiring of `PolishCoordinator` end-to-end without depending on any
/// real backend. Sleeps 100 ms and returns the input unchanged. Used at round 1
/// before `AppleFoundationModelsPolishEngine` is wired (step 5) and as a permanent
/// fallback on devices where Apple FM is unavailable.
public final class PassthroughPolishEngine: PolishEngineProtocol {
    public let identifier = "passthrough"

    public init() {}

    public func polish(raw: String,
                       targetLanguage: SupportedLanguage,
                       mode: PolishMode) async throws -> String {
        try await Task.sleep(nanoseconds: 100_000_000)
        try Task.checkCancellation()
        return raw
    }
}
