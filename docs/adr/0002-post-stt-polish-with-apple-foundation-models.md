# 0002 — Post-STT polish layer with Apple Foundation Models at round 1

- **Date:** 2026-05-12
- **Status:** Accepted
- **Context:** Issue #141 (local LLM transcription polish). Sibling to #79 (Smart Mode, premium reformulation). Partially unblocks #90 (Parakeet language enforcement), #115 (verbal punctuation), #109 (German autocorrect quality).

## Decision

Introduce a synchronous **polish layer** between STT final output and App Group injection in DictusApp. The layer is off by default, gated by a single global toggle in Settings, and hidden entirely on devices where Apple Foundation Models is unavailable.

At round 1 the only backend is **Apple Foundation Models** (iOS 26+, Apple Intelligence enabled, A17 Pro / M-series hardware). An OSS fallback for baseline devices is deferred to a round 2 decision driven by round 1 measurements.

Polish runs in two prompt variants selected at runtime by `NLLanguageRecognizer`:

- **Light mode (Mode A):** content-words preserved. Allowed operations are limited to punctuation, capitalization (including German noun rule), accent insertion, spoken-number and spoken-date conversion to digits (no further formatting — `cinq mars` → `5 mars`, not `05/03`), verbal punctuation commands (`virgule` → `,`), apostrophe/space typography, and single-letter typo fixes. Forbidden: filler removal, repetition cleanup, word reordering, synonym substitution, tone change, clarifying additions, structural grammar rewrites.
- **Repair mode (Mode B):** triggered when the language detected on raw STT output differs from the target language. Allowed to substitute words to reconstruct user intent in the target language while preserving loanwords and proper nouns. Active only on Parakeet (Whisper respects the target language upstream).

When `NLLanguageRecognizer` returns no language with usable confidence, polish is skipped entirely and the raw STT text passes through.

Runtime is wrapped by a **length-ratio guardrail**: polished output is rejected (raw written instead, event logged) when its character-length ratio to raw falls outside `[0.5, 2.0]` in Light mode or `[0.3, 3.0]` in Repair mode.

A static **PolishGlossary** of ~20-30 domain terms is injected into every prompt as context.

Languages wired at round 1: French, English, Spanish, German (subset of `SupportedLanguage` ∩ Apple FM supported languages).

Sessions are cached per `(mode, language)` tuple (max 8) with mode-and-language-specific instructions baked in; the session matching the user's current target language is prewarmed at `applicationDidFinishLaunching`. A polish call in flight is cancelled when a new dictation starts.

Metrics for each polish invocation (engine, mode, target language, detected language, input/output character count, latency, outcome) are emitted to `os_log` and surfaced in a hidden debug screen in DictusApp Settings.

No latency cap at round 1: full distribution is measured before any time-based abort policy is introduced.

## Why

**The faithfulness contract is the boundary that prevents polish from becoming a second Smart Mode.** Without it, every prompt iteration drifts a little further from STT and a little closer to reformulation, until polish and Smart Mode #79 become indistinguishable. The 20-line operations table makes the boundary auditable: a polish change that doesn't fit a row of the table is a bug, not a feature, and belongs in #79.

**Repair mode is the explicit exception to word-faithfulness, scoped narrowly to STT failures.** Parakeet's strongest weakness today is its inability to respect the language picker — a French user mixing two English words can get a transcript that is plausible English nonsense. With strict word-faithful polish we would correct the punctuation of nonsense and inject it. With Repair mode we reconstruct what the user probably meant in French. The contract shifts from "preserve user's exact STT-output words" to "preserve user's intent." This is a real semantic shift and the place where polish accepts a hallucination risk.

**The skip-on-gibberish rule protects trust.** The worst case is not Parakeet hallucinating in the wrong language — it is Parakeet emitting low-quality output from bad audio that Repair mode then "rebuilds" into plausible French the user never said. By skipping polish entirely when raw text has no detectable language with usable confidence, we keep visibly broken text broken (the user can re-dictate) instead of inserting invisible falsehoods.

**Apple FM only at round 1 is a measurement decision, not a product decision.** The free polish feature is supposed to ship to baseline devices (iPhone 12+) too. Apple FM excludes most of that range. Shipping FM-only permanently would contradict the stated baseline commitment. But choosing the OSS backend (llama.cpp via LocalLLMClient, MLX, Core ML) blind — without knowing what quality bar Apple FM sets, what latency budget polish actually needs, or how often Repair mode fires in real use — is a guess. Round 1 generates the data. Round 2 picks the OSS backend with that data in hand, and the `PolishEngineProtocol` abstraction lets a second implementation plug in without rearchitecting.

**Pre-injection synchronous placement is the only option that gives clean A/B measurement.** The user's stated goal for this round is to compare on-device latency and quality with and without polish. Inline-replace (inject raw then patch with polished) mixes two latencies the user perceives differently and would force keyboard-extension changes. Two-stage overlay display would slow down injection in the toggle-on path purely for didactic value. Pre-injection gives "polish on" = `STT + polish` and "polish off" = `STT`, with the difference being exactly the polish cost.

**No latency cap at round 1 is a measurement decision.** A 500ms cap (the AC in the issue) would blind us to the right-tail of the latency distribution. We need to know whether the p95 is 400ms or 4000ms before deciding what a reasonable cap is. Cancellation on new dictation prevents the user-visible "queue of doom" scenario without skewing the measurement.

**The length-ratio guardrail is intentionally minimal.** A more thorough check (content-words sequence comparison after normalization and stopword removal) would require a per-language list of verbal-punctuation tokens, a per-language number parser to handle the allowed `vingt trois` → `23` conversion, and a stopword list per language. That is an entire sub-feature. The ratio check is ~10 lines of code and catches the actual failure mode it's designed for: catastrophic over- or under-generation. Subtle word substitution (`chat` → `rat`) is left to be caught visually in the debug logs during round 1; if it proves to be a real failure mode we will harden the guardrail with that data.

## Alternatives considered

**Ship polish as Apple FM only, permanently (no OSS fallback planned).** Rejected because it contradicts the baseline-device commitment in the issue's product discussion. Acceptable for round 1 *measurement*; unacceptable as the end state.

**Inline-replace placement (inject raw immediately, patch with polish in background).** Rejected for round 1 because it (i) muddies the latency comparison the user wants to do, (ii) requires keyboard-extension changes for the patch path, (iii) creates a visible "glitch" when polish substantively edits the text, eroding trust. May be reconsidered later if data shows polish latency is too visible for the toggle-on path.

**Two-stage overlay display (show raw, then polish, then inject).** Rejected: adds perceived latency before injection without giving the user actionable control. Polish either runs or doesn't; making the user watch it is theater.

**One unified prompt with conditional mode logic.** Rejected: Apple Foundation Models is a small (~3B) model and follows branched conditional rules in a system prompt poorly. Two distinct prompts (`polishLight*`, `polishRepair*`) keep each rule set focused and let the two modes evolve independently.

**Strict content-words guardrail.** Rejected for round 1 because making it correct requires per-language verbal-punctuation tables and number parsers, which is its own feature. The length-ratio fallback is sufficient for round 1 measurement; we will tighten it if data justifies it.

**Toggle visible but disabled on non-FM devices.** Rejected: the explanation ("requires Apple Intelligence on a recent iPhone Pro") is technical, generates support questions, and is temporary — once the OSS round 2 lands, the toggle will work for everyone. Better to hide than to dangle.

**Latency cap of 500ms (per the issue's AC).** Rejected for round 1 because measurement requires seeing the full distribution. The AC will be revisited with data; it is not a binding spec until then.

**Per-language toggles.** Rejected: one decision per user, languages are gated server-side by Apple FM's `supportedLanguages` anyway. Per-language UX may be reconsidered if data shows quality differs sharply between languages.

## Consequences

**Positive.**
- The polish layer is shippable to Apple Intelligence devices behind a measurement-grade toggle and instrumentation. Quality and latency data accumulate from week 1.
- `PolishEngineProtocol` in DictusCore is a clean seam for round 2's OSS backend. Adding `LlamaCppPolishEngine` later is additive, not surgical.
- The faithful contract is documented in code-adjacent prose. New maintainers reading the prompts understand the line that must not be crossed.
- `#115` (verbal punctuation) and `#90` (Parakeet language enforcement) are addressed as a side-effect of the polish layer instead of as bespoke pipelines.
- Repair mode is the first time Dictus actively repairs an STT hallucination instead of routing around it. If quality holds, this becomes a primitive that other features can lean on.

**Negative.**
- Baseline-device users (iPhone 12-14, non-Pro iPhone 15, older iPad) see nothing related to polish until round 2 ships an OSS path. This is by design but is a user-visible gap.
- Repair mode introduces a real hallucination risk on the worst-quality inputs. The skip-on-gibberish heuristic and the length-ratio guardrail are first lines of defense; they will leak subtle cases that show up only in logs.
- Per-language prompt tuning is sequential work. Spanish and German ship at round 1 with prompts that have not been validated against native-speaker output. Quality there will be reactive to community feedback (cf. #109 dynamics).
- The PolishGlossary is a maintainer-curated artefact that competes with `LanguageProfile.overrides` and #80 custom vocab for the same conceptual space. The three-mechanism distinction is documented but is a learning curve for new contributors.

**Reversibility.**
The whole layer is reversible: a single feature flag in App Group preferences turns it off globally. The protocol abstraction means swapping Apple FM for an OSS backend is a per-implementation change, not a layer-wide rewrite. The faithful contract shift (Mode B's intent-bridged stance) is harder to walk back once users rely on Mode B behavior, but is gated behind language-detection differences and is invisible to users who never trigger Parakeet hallucinations.

## Implementation notes

- Protocol and shared types in `DictusCore/Polish/`: `PolishEngineProtocol`, `PolishMode`, `PolishGlossary`, `PolishGuardrail`, `PolishMetrics`.
- Implementation in `DictusApp/Polish/`: `AppleFoundationModelsPolishEngine`, `PolishPromptBuilder` (per mode × language), `PolishCoordinator` (orchestration), `PolishDebugView`.
- Toggle persisted in App Group via a new `SharedKeys` entry. Read at runtime by `PolishCoordinator`. Toggle UI lives in DictusApp Settings under the existing transcription section, label "Polir la transcription" / "Polish transcription". Hidden if `SystemLanguageModel.default.availability != .available`. Debug override flag (build setting or hidden gesture) shows the toggle on dev devices regardless.
- `PolishCoordinator` orchestrates: receive raw text + target language + engine identity → `NLLanguageRecognizer` on raw → choose mode (skip if gibberish) → fetch or create cached session → call engine → apply guardrail → emit metrics → return polished or raw.
- Sessions cached in a `[PolishMode × SupportedLanguage: LanguageModelSession]` dictionary in `AppleFoundationModelsPolishEngine`. Created lazily on first use of each combo. Prewarm called on the `(light, currentTargetLanguage)` session at app launch.
- Cancellation: `PolishCoordinator` holds a reference to the in-flight `Task`; a new dictation starting in DictusApp calls `task.cancel()` on the previous polish before the new one begins. Apple FM session `respond(to:)` is cancellable via Swift task cancellation.
- Glossary content evolves by PR; initial seed list to be determined at first-implementation time, sourced from terms observed mistranscribed during development.
- Round 2 trigger: after enough on-device A/B usage to characterize p50/p95 latency, Mode B trigger rate, and rejection rate by guardrail. Threshold for "enough" is not pre-defined; reviewer judgement based on log volume.
