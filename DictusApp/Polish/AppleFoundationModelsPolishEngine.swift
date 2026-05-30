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
        // Wrap the input with explicit Input/Output framing. Without this Apple
        // FM treats the raw as a conversational turn and emits chat-reply
        // acknowledgements ("I'll polish it for you") instead of the polished
        // text. The trailing "Polished output:" marker biases the model toward
        // continuing the transform rather than starting a chat reply.
        let prompt = """
        Polish this text. Output only the polished version, nothing else.

        Input:
        \(raw)

        Polished output:
        """
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create (if needed) and prewarm the Natural session for `targetLanguage`.
    /// Called from `PolishCoordinator.prewarm()` at app launch.
    func prewarm(targetLanguage: SupportedLanguage) async {
        let session = await cache.session(
            for: SessionKey(mode: .natural, language: targetLanguage),
            instructions: Self.instructions(for: .natural, language: targetLanguage)
        )
        session.prewarm()
    }

    // MARK: - Instruction routing

    /// Returns the system prompt for `(mode, language)`. All four supported
    /// languages have a dedicated Natural prompt (FR + EN tested against
    /// real dictation; ES + DE authored on-paper, pending native-speaker
    /// validation per ADR 0003). Repair mode still falls back to English
    /// for ES + DE — see `docs/agents/language-onboarding.md` §"Polish
    /// prompt" for the procedure to add Repair prompts.
    static func instructions(for mode: PolishMode,
                             language: SupportedLanguage) -> String {
        let glossary = PolishGlossary.promptBlock
        switch (mode, language) {
        case (.natural, .french):
            return PolishNaturalPromptFR.instructions(glossary: glossary)
        case (.natural, .english):
            return PolishNaturalPromptEN.instructions(glossary: glossary)
        case (.natural, .spanish):
            return PolishNaturalPromptES.instructions(glossary: glossary)
        case (.natural, .german):
            return PolishNaturalPromptDE.instructions(glossary: glossary)
        case (.repair, .french):
            return PolishRepairPromptFR.instructions(glossary: glossary)
        case (.repair, .english):
            return PolishRepairPromptEN.instructions(glossary: glossary)
        case (.repair, .spanish), (.repair, .german):
            // English Repair fallback for languages without a dedicated prompt.
            return PolishRepairPromptEN.instructions(glossary: glossary)
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
