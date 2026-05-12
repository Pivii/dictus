// DictusApp/Polish/AppleFoundationModelsPolishEngine.swift
#if canImport(FoundationModels)
import Foundation
import FoundationModels
import DictusCore

/// The round-1 polish engine. Wraps Apple's on-device Foundation Model with a
/// per `(mode, language)` `LanguageModelSession` cache so the system prompt is
/// baked at session creation, not retransmitted with every call.
///
/// Availability is gated by `PolishAvailability.isAppleFMAvailable` upstream —
/// `PolishCoordinator` instantiates this engine only when Apple Intelligence is
/// usable. The cache has a small bound (8) because round 1 supports at most
/// 4 languages × 2 modes = 8 combinations.
@available(iOS 26.0, *)
final class AppleFoundationModelsPolishEngine: PolishEngineProtocol, Sendable {

    let identifier = "apple-fm"
    private let cache = SessionCache(capacity: 8)

    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                mode: PolishMode) async throws -> String {
        let session = await cache.session(
            for: SessionKey(mode: mode, language: targetLanguage),
            instructions: Self.instructions(for: mode, language: targetLanguage)
        )
        let response = try await session.respond(to: raw)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create (if needed) and prewarm the Light session for `targetLanguage`.
    /// Called from `PolishCoordinator.prewarm()` at app launch.
    func prewarm(targetLanguage: SupportedLanguage) async {
        let session = await cache.session(
            for: SessionKey(mode: .light, language: targetLanguage),
            instructions: Self.instructions(for: .light, language: targetLanguage)
        )
        session.prewarm()
    }

    // MARK: - Instruction routing

    /// Returns the system prompt for `(mode, language)`. Steps 6 and 7 fill in
    /// Repair FR/EN and Light/Repair ES/DE — for now, unsupported combinations
    /// fall back to the closest available English prompt so the engine still
    /// produces *some* output during incremental rollout.
    static func instructions(for mode: PolishMode,
                             language: SupportedLanguage) -> String {
        let glossary = PolishGlossary.promptBlock
        switch (mode, language) {
        case (.light, .french):
            return PolishLightPromptFR.instructions(glossary: glossary)
        case (.light, .english):
            return PolishLightPromptEN.instructions(glossary: glossary)
        case (.light, .spanish), (.light, .german):
            // Step 7 — falling back to English Light keeps the wiring valid.
            return PolishLightPromptEN.instructions(glossary: glossary)
        case (.repair, _):
            // Step 6 / 7 — fall back to English Light to keep behavior bounded.
            return PolishLightPromptEN.instructions(glossary: glossary)
        }
    }
}

// MARK: - Session cache

@available(iOS 26.0, *)
private struct SessionKey: Hashable, Sendable {
    let mode: PolishMode
    let language: SupportedLanguage
}

/// Per-`(mode, language)` `LanguageModelSession` cache with naive LRU eviction.
/// Sessions hold compiled instruction state — keeping them around avoids the
/// per-call cost of rebuilding the system prompt.
@available(iOS 26.0, *)
private actor SessionCache {

    private var sessions: [SessionKey: LanguageModelSession] = [:]
    private var lru: [SessionKey] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    func session(for key: SessionKey, instructions: String) -> LanguageModelSession {
        if let existing = sessions[key] {
            touch(key)
            return existing
        }
        let session = LanguageModelSession(instructions: instructions)
        sessions[key] = session
        lru.append(key)
        evictIfNeeded()
        return session
    }

    private func touch(_ key: SessionKey) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func evictIfNeeded() {
        while sessions.count > capacity, let oldest = lru.first {
            sessions.removeValue(forKey: oldest)
            lru.removeFirst()
        }
    }
}
#endif
