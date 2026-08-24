// DictusCore/Sources/DictusCore/Polish/AppleFoundationModelsPolishEngine.swift
#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// The round-1 polish engine. Wraps Apple's on-device Foundation Model with a
/// per `(task, language)` `LanguageModelSession` cache so the system prompt is
/// baked at session creation, not retransmitted with every call.
///
/// Availability is gated by `PolishAvailability.isAppleFMAvailable` upstream —
/// `PolishService` instantiates this engine only when Apple Intelligence is
/// usable. The cache bound is derived rather than written down: 4 languages ×
/// 2 per-language polish modes + 1 language-agnostic Auto session (#239) + one
/// language-agnostic session per Smart Mode (#79).
@available(iOS 26.0, macOS 26.0, *)
public final class AppleFoundationModelsPolishEngine: PolishEngineProtocol, Sendable {

    public let identifier = "apple-fm"
    private let cache = SessionCache(capacity: sessionCacheCapacity)

    /// One session per prompt this build can send.
    ///
    /// Sized rather than guessed because an under-sized cache is invisible: it
    /// evicts a warmed session and the next dictation silently pays for a cold one.
    static let sessionCacheCapacity =
        SupportedLanguage.allCases.count * 2 + 1 + SmartModeCatalogue.builtIns.count

    /// Optional instructions override. `nil` in the app (uses the shipping
    /// prompts via `Self.instructions`); the eval harness injects a candidate
    /// prompt here to A/B against the baseline without recompiling — the session
    /// wrapper and stateless lifecycle stay identical, only the system prompt
    /// changes.
    private let instructionsOverride: (@Sendable (PolishTask, SupportedLanguage) -> String)?

    public init() {
        self.instructionsOverride = nil
    }

    public init(instructionsOverride: @escaping @Sendable (PolishTask, SupportedLanguage) -> String) {
        self.instructionsOverride = instructionsOverride
    }

    private func resolvedInstructions(task: PolishTask, language: SupportedLanguage) -> String {
        instructionsOverride?(task, language) ?? Self.instructions(for: task, language: language)
    }

    /// Normalize the session-cache language for a task. A task whose prompt is
    /// written once for every input language — `.auto` (#239) and every Smart Mode
    /// (#79) — must not vary its session key with the caller-supplied placeholder
    /// language, otherwise a `prewarm` and the `polish` that follows it could miss
    /// each other and the warm session would be wasted. `.english` is an arbitrary
    /// canonical filler; `instructions(for:language:)` ignores it for those tasks.
    ///
    /// A translation mode names its target inside its own instructions, so its
    /// sessions stay separate through the identifier rather than through this.
    private static func sessionLanguage(for task: PolishTask,
                                        requested: SupportedLanguage) -> SupportedLanguage {
        task.hasLanguageAgnosticPrompt ? .english : requested
    }

    public func polish(raw: String,
                       targetLanguage: SupportedLanguage,
                       task: PolishTask) async throws -> String {
        let key = SessionKey(
            task: task.identifier,
            language: Self.sessionLanguage(for: task, requested: targetLanguage)
        )
        // A session lives exactly one polish call. `prewarm()` (fired at
        // recording start) leaves a fresh, warmed session in the cache; we use
        // it here on a cache hit, or create one if no prewarm ran, and drop it
        // afterward so the NEXT call never inherits this turn.
        //
        // WHY this matters: `LanguageModelSession` is stateful — every
        // `respond()` is appended to a transcript the session re-prefills on
        // each subsequent call. Reusing one session across dictations made
        // latency grow turn-after-turn and would eventually throw
        // `exceededContextWindowSize` (4096-token ceiling). Polish is a
        // stateless transform, so we keep at most `instructions + 1 input`.
        let session = await cache.session(
            for: key,
            instructions: resolvedInstructions(task: task, language: targetLanguage)
        )
        // Wrap the input with explicit Input/Output framing. Without this Apple
        // FM treats the raw as a conversational turn and emits chat-reply
        // acknowledgements ("I'll polish it for you") instead of the polished
        // text. The trailing marker biases the model toward continuing the
        // transform rather than starting a chat reply.
        //
        // Both halves come off the task since #79. They used to be hardcoded to the
        // polish wording, and asking the model to produce notes under an instruction
        // that says "polish" is self-defeating.
        let prompt = task.userTurn(raw: raw)
        // The drop names the session it is dropping (#315). `respond()` suspends
        // for four to five seconds, and the captures on that issue show two
        // dictations chaining inside a single second — so the next recording's
        // `prewarm()` can install a warmed replacement under this same key while
        // this call is still suspended. Dropping by key alone on resume would
        // evict that replacement and waste the prewarm on every chained
        // dictation. See `SessionCache.dropIfStillCurrent`.
        //
        // It is also awaited on both exits rather than deferred into an
        // unstructured `Task`, so the drop cannot outlive the call that owns it.
        // That part is ordering; the identity check above is what closes the
        // window, and neither substitutes for the other.
        do {
            let response = try await session.respond(to: prompt)
            await cache.dropIfStillCurrent(key, session: session)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            await cache.dropIfStillCurrent(key, session: session)
            throw error
        }
    }

    /// Create a FRESH session for `(task, targetLanguage)` and prewarm it.
    /// Called from `PolishService.prewarm()` at app launch and at the start
    /// of every recording (#141). The service passes `.natural` for the
    /// per-language path, `.auto` in Auto-detect mode (#239), and the armed Smart
    /// Mode when there is one (#79) so the warmed instructions match the ones
    /// `polish()` will use. Dropping any existing session first guarantees we warm a
    /// virgin session (instructions only, zero accumulated transcript) — the
    /// prerequisite for the stateless invariant in `polish()`.
    public func prewarm(task: PolishTask, targetLanguage: SupportedLanguage) async {
        let language = Self.sessionLanguage(for: task, requested: targetLanguage)
        let key = SessionKey(task: task.identifier, language: language)
        await cache.drop(key)
        let session = await cache.session(
            for: key,
            instructions: resolvedInstructions(task: task, language: language)
        )
        session.prewarm()
    }

    // MARK: - Context ceiling (#270)

    /// The window this engine has to fit into. See `PolishContextBudget` for
    /// how the numbers were measured; the ceiling itself is the same 4096-token
    /// one the session lifecycle above already had to work around.
    public static let contextBudget = PolishContextBudget.appleFoundationModels

    /// Price the call before making it: the RESOLVED instructions for
    /// `(task, targetLanguage)` — which is what the session was or will be
    /// created with, including any harness override — plus the input, plus a
    /// reserve for the generated output. Instruction length varies by a factor
    /// of two across the prompt set, and the measurement showed instructions
    /// and input trade one-for-one inside the window, so a fixed instruction
    /// allowance would under-estimate exactly where it matters most.
    /// The arguments below are the ones `polish()` itself passes to
    /// `resolvedInstructions`, so what is priced is exactly what is sent.
    public func contextFit(input: String,
                           targetLanguage: SupportedLanguage,
                           task: PolishTask) -> PolishContextFit {
        Self.contextBudget.fit(
            instructions: resolvedInstructions(task: task, language: targetLanguage),
            input: input
        )
    }

    // MARK: - Failure classification (#315)

    /// Map what `session.respond(...)` threw onto a stable slug.
    ///
    /// This is the whole point of #315: a failure that arrives in 4 ms while
    /// availability reads `available` has to say which of Apple's nine
    /// `GenerationError` cases it was. Two of them can plausibly throw that
    /// fast without the model running — `rateLimited` and `concurrentRequests` —
    /// and they point at opposite culprits: a quota Apple applies to us, or two
    /// of our own calls overlapping. The exported reason is what tells them
    /// apart.
    ///
    /// Deliberately reads nothing out of the error but its case. The attached
    /// `Context.debugDescription` can quote the prompt, i.e. the user's
    /// dictation, and this value travels into a shared export.
    public func failureReason(for error: Error) -> PolishFailureReason {
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
        // `GenerationError` ships with library evolution, so a future OS can add
        // a case this build has never heard of. It lands in the catch-all with
        // its type name rather than failing to compile against a newer SDK.
        @unknown default: return .other(error)
        }
    }

    // MARK: - Instruction routing

    /// Returns the system prompt for `(task, language)`. All four supported
    /// languages have a dedicated prompt in BOTH Natural and Repair modes
    /// (FR + EN tested against real dictation; ES + DE authored on-paper,
    /// pending native-speaker validation per ADR 0003). The English fallback
    /// survives in the dispatch only as the documented behaviour for any
    /// future language added without a dedicated prompt — see
    /// `docs/agents/language-onboarding.md` §"Polish prompt".
    /// `.auto` mode (#239) ignores `language` entirely: one language-agnostic
    /// prompt covers every auto-detected input language.
    ///
    /// A Smart Mode (#79) carries its own instructions on its record, so this
    /// dispatch does not grow a case per mode — adding Email is a catalogue row and
    /// a prompt file, and nothing here moves.
    public static func instructions(for task: PolishTask,
                                    language: SupportedLanguage) -> String {
        let glossary = PolishGlossary.promptBlock
        if let smartMode = task.smartMode {
            return smartMode.prompt.instructions
        }
        // Exhaustive over `PolishMode` below, so the `?? .natural` is unreachable:
        // `smartMode` and `polishMode` are the two halves of the same enum.
        switch (task.polishMode ?? .natural, language) {
        case (.auto, _):
            return PolishAutoPrompt.instructions(glossary: glossary)
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
        case (.repair, .spanish):
            return PolishRepairPromptES.instructions(glossary: glossary)
        case (.repair, .german):
            return PolishRepairPromptDE.instructions(glossary: glossary)
        }
    }
}

// MARK: - Session cache

@available(iOS 26.0, macOS 26.0, *)
private struct SessionKey: Hashable, Sendable {
    /// `PolishTask.identifier` — "natural", "auto", "smart.notes", … A string since
    /// #79, because a Smart Mode is a record and has no enum case to key on.
    let task: String
    let language: SupportedLanguage
}

/// Per-`(task, language)` `LanguageModelSession` cache with naive LRU eviction.
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

    /// Remove the session for `key` (if any), whatever it is. Used by
    /// `prewarm()`, which is deliberately installing a replacement and so has no
    /// reason to care what it displaces. Freeing a session releases only its
    /// small instruction KV-cache — the model weights stay resident in memory,
    /// shared across sessions, so re-creating a session when the model is
    /// already warm is cheap.
    func drop(_ key: SessionKey) {
        sessions.removeValue(forKey: key)
        lru.removeAll { $0 == key }
    }

    /// Remove the session for `key` only while it is still `session`.
    ///
    /// WHY this exists (#315): `polish()` suspends inside `respond()` for four
    /// to five seconds, and the captures on that issue show two dictations
    /// chaining inside a single second. So the next recording's `prewarm()` can
    /// drop S1 and install a warmed S2 under the same key *while the first call
    /// is still suspended*. An unconditional drop on resume then evicts S2, the
    /// next call takes a cache miss and builds a cold session, and the prewarm
    /// is wasted on every chained dictation.
    ///
    /// Ordering the drop does not help: the window is the removal itself, not
    /// when it is scheduled. Only checking what is being removed does.
    ///
    /// Identity, not equality: `LanguageModelSession` is a class, and two
    /// sessions built from the same instructions are equally valid and still
    /// distinct objects — which is exactly the case that has to be told apart.
    func dropIfStillCurrent(_ key: SessionKey, session: LanguageModelSession) {
        guard sessions[key] === session else { return }
        drop(key)
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
