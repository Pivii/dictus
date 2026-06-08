// DictusCore/Sources/DictusCore/Polish/AppleFoundationModelsPolishEngine.swift
#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// The round-1 polish engine. Wraps Apple's on-device Foundation Model with a
/// per `(mode, language)` `LanguageModelSession` cache so the system prompt is
/// baked at session creation, not retransmitted with every call.
///
/// Availability is gated by `PolishAvailability.isAppleFMAvailable` upstream —
/// `PolishCoordinator` instantiates this engine only when Apple Intelligence is
/// usable. The cache has a small bound (8) because round 1 supports at most
/// 4 languages × 2 modes = 8 combinations.
@available(iOS 26.0, macOS 26.0, *)
public final class AppleFoundationModelsPolishEngine: PolishEngineProtocol, Sendable {

    public let identifier = "apple-fm"
    private let cache = SessionCache(capacity: 8)

    /// Optional instructions override. `nil` in the app (uses the shipping
    /// prompts via `Self.instructions`); the eval harness injects a candidate
    /// prompt here to A/B against the baseline without recompiling — the session
    /// wrapper and stateless lifecycle stay identical, only the system prompt
    /// changes.
    private let instructionsOverride: (@Sendable (PolishMode, SupportedLanguage) -> String)?

    public init() {
        self.instructionsOverride = nil
    }

    public init(instructionsOverride: @escaping @Sendable (PolishMode, SupportedLanguage) -> String) {
        self.instructionsOverride = instructionsOverride
    }

    private func resolvedInstructions(mode: PolishMode, language: SupportedLanguage) -> String {
        instructionsOverride?(mode, language) ?? Self.instructions(for: mode, language: language)
    }

    public func polish(raw: String,
                       targetLanguage: SupportedLanguage,
                       mode: PolishMode) async throws -> String {
        let key = SessionKey(mode: mode, language: targetLanguage)
        // A session lives exactly one polish call. `prewarm()` (fired at
        // recording start) leaves a fresh, warmed session in the cache; we use
        // it here on a cache hit, or create one if no prewarm ran. The `defer`
        // drops it afterward so the NEXT call never inherits this turn.
        //
        // WHY this matters: `LanguageModelSession` is stateful — every
        // `respond()` is appended to a transcript the session re-prefills on
        // each subsequent call. Reusing one session across dictations made
        // latency grow turn-after-turn and would eventually throw
        // `exceededContextWindowSize` (4096-token ceiling). Polish is a
        // stateless transform, so we keep at most `instructions + 1 input`.
        let session = await cache.session(
            for: key,
            instructions: resolvedInstructions(mode: mode, language: targetLanguage)
        )
        defer { Task { await cache.drop(key) } }
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

    /// Create a FRESH Natural session for `targetLanguage` and prewarm it.
    /// Called from `PolishCoordinator.prewarm()` at app launch and at the start
    /// of every recording (#141). Dropping any existing session first guarantees
    /// we warm a virgin session (instructions only, zero accumulated transcript)
    /// — the prerequisite for the stateless invariant in `polish()`.
    public func prewarm(targetLanguage: SupportedLanguage) async {
        let key = SessionKey(mode: .natural, language: targetLanguage)
        await cache.drop(key)
        let session = await cache.session(
            for: key,
            instructions: resolvedInstructions(mode: .natural, language: targetLanguage)
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
    public static func instructions(for mode: PolishMode,
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

@available(iOS 26.0, macOS 26.0, *)
private struct SessionKey: Hashable, Sendable {
    let mode: PolishMode
    let language: SupportedLanguage
}

/// Per-`(mode, language)` `LanguageModelSession` cache with naive LRU eviction.
/// Sessions hold compiled instruction state — keeping them around avoids the
/// per-call cost of rebuilding the system prompt.
@available(iOS 26.0, macOS 26.0, *)
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

    /// Remove the session for `key` (if any). Used to enforce the one-session-
    /// per-call lifecycle: `polish()` drops after `respond()`, `prewarm()` drops
    /// before recreating. Freeing a session releases only its small instruction
    /// KV-cache — the model weights stay resident in memory, shared across
    /// sessions, so re-creating a session when the model is already warm is cheap.
    func drop(_ key: SessionKey) {
        sessions.removeValue(forKey: key)
        lru.removeAll { $0 == key }
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
