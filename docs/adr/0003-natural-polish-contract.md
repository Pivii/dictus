# 0003 — Natural polish contract replaces Light at round 1

- **Date:** 2026-05-30
- **Status:** Accepted
- **Context:** Continuation of issue #141 after round-4 testing. Supersedes the Light contract from ADR 0002 §"Light mode". Repair mode (ADR 0002 §"Repair mode") is unchanged.

## Decision

Rename `PolishMode.light` → `PolishMode.natural`. Rewrite the prompts at `(.natural, language)` for the four supported languages (French, English, Spanish, German) against a new contract — the **Natural contract** — that authorises a small set of behaviours the Light contract explicitly forbade.

The Natural contract:

**Allowed operations (the model MUST do these):**
1. Add or fix punctuation. Apply language-specific typographic spacing (FR NBSP before `? ! ; :`; ES inverted `¿?` / `¡!`; EN/DE no leading space).
2. Capitalize sentence starts (including after `<<NL>>` markers) and proper nouns. Apply language-specific capitalization rules (German nouns, French/Spanish accents).
3. Convert spoken numbers to digits and spoken dates to natural form (no numeric date formats).
4. Substitute verbal punctuation commands (`virgule` → `,`, `point d'interrogation` → `?`, etc.).
5. Preserve `<<NL>>` markers character-for-character at the same position.
6. **Remove same-word back-to-back duplicates** that are clearly involuntary stutters (`comme comme` → `comme`).
7. **Remove gratuitous oral fillers** (`euh`, `hum`; sentence-end `tu vois`; repeated `en fait`) while keeping transition words (`voilà`, `bon`, `donc`).
8. **Repair ASR hallucinations** when a segment is clearly incoherent (pseudo-words, off-language fragment that does not fit) by reconstructing the speaker's intent in the target language using surrounding context.
9. Fix one-letter typos that do not rise to rule 8.

**Preserve (the model MUST NOT change these):**
- Familiar register (`t'es`, `dispo`, `19h`, contractions, abbreviations).
- Oral negation form (`je sais pas` stays; do NOT add `ne`).
- Code-switched tech anglicisms (`today`, `ship`, `commit`, `push`, `merge`, `PR`, `feature`, `bug`, `release`, `deploy`, …).
- Word choice (no synonym substitution: `bosser` ≠ `travailler`).
- Tone and register.

**Forbidden:**
- Adding words or content that were not in the input (no inventing endings like "Merci.", no completing cut-off sentences).
- Reordering words.
- Translating.
- Adding `<<NL>>` markers where none existed.

The post-pass (`PolishPostpass`) still applies after the engine call: marker decode → `\n`, and French NBSP insertion before double-punctuation marks. The pre-pass (`VerbalPunctuationPrepass`) is unchanged.

The length-ratio guardrail from ADR 0002 is unchanged at `[0.5, 2.0]` for Natural; values may be revisited after round 5 measurement.

## Why

**Light was the wrong calibration for the dominant use case.** The Light contract was authored on the assumption that the dominant failure mode would be "polish drifting into Smart Mode reformulation". The 30 May 2026 comparison session (Dictus vs Wispr Flow, same audio replayed into both apps) made the opposite clear: the dominant failure mode is "polish produces text too faithful to the oral original to be sent as a written message". Light prevents fillers/repetitions from being cleaned, which is exactly what users want cleaned when transcribing for a message. Wispr Flow, the reference competitor in the comparison, does exactly this kind of cleanup by default.

**Apple FM was already violating Light implicitly.** The same 30 May session showed Apple FM removes fillers, drops sentence-end `tu vois`, collapses `comme comme` repetitions, and reconstructs hallucinated ASR fragments — all in violation of Light's `Do NOT` list, but spontaneously and well. The contract was fighting the model. Making the contract match the model's natural behaviour stabilises the output and lets us reason about it.

**ASR hallucination repair is the highest-value emergent capability.** Parakeet has a known failure pattern where, on French audio with mid-sentence hesitation, it emits a pseudo-English fragment in the middle of an otherwise-French transcription. The 30 May test 3 confirmed Apple FM repairs this transparently with surrounding context. Listing this as an explicit allowed operation in the prompt protects the capability against future Apple FM regressions (the model can decide our prompt no longer requires it and stop doing it; an explicit rule prevents that drift).

**Preserving anglicisms and informal register is what makes the polish feel like the speaker's own voice.** The 30 May test 1 surfaced this directly: Dictus (Light) returned `tu es disponible vers 19 heures`, Wispr returned `t'es dispo vers 19h`, and Pierre's stated cible is closer to Wispr. Formalising contractions changes the tone of the message in a way the speaker did not intend.

**Hallucinated completion is the one thing Light got right and Natural keeps.** Wispr's test-1 output ended with a fabricated `Merci.`. The Light contract had no explicit rule against this because the focus was on word substitution, not addition. Natural explicitly bans content invention — addition is the highest-risk hallucination class because there is no way for the user to know what was added without re-reading carefully.

**One prompt per language plus EN fallback is the right scale.** FR + EN have been tested against real dictation. ES + DE are authored on-paper from the FR template with language-specific rules adapted. Per-language prompts let us state language-specific operations (NBSP for FR, inverted `¿?` for ES, noun-capitalization mentions for DE) without polluting a single mega-prompt. The dispatch falls back to English Natural when a language has no dedicated prompt — for now this only affects `(.repair, .spanish/.german)` since all four Natural prompts ship in this round.

## Alternatives considered

**Keep Light, add a separate "polish for messages" mode.** Rejected because the two modes would overlap on the dominant use case (90 %+ of polish runs) and force a UI toggle the user is unlikely to manage. The simpler answer is "the default is what fits the dominant use case".

**Match Apple FM's spontaneous behaviour but document nothing.** Rejected. The 30 May data showed Apple FM occasionally violates rules in ways we don't want (substituting `je check` → `je vérifie`, adding `ne` to negations). An explicit contract lets us push back on those specific behaviours through prompt rules without losing the parts we want to keep.

**Author ES + DE prompts later, once tested by a native speaker.** Considered. Rejected on the grounds that shipping with English fallback for ES/DE means those users get a prompt designed for English contractions and English fillers — clearly worse than a best-effort language-specific prompt even if not native-validated. The risk is the prompts encode mistakes that ship to users; mitigation is that the prompts are flagged as "needs native-speaker validation" both in the file doc-comment and in the language-onboarding checklist, and the next iteration can re-author from a test set once we have one.

**Widen the length-ratio guardrail for Natural.** Considered. Natural can shorten input more than Light (filler removal can drop 10-20 % of characters; ASR repair can drop a pseudo-fragment without replacing it). The current `[0.5, 2.0]` band still covers this in practice (Wispr's outputs were within 0.7 of the raw on all four tests). We will revisit if the round-5 measurement shows guardrail rejections rising.

## Migration

- `PolishMode.light` → `PolishMode.natural` rename (rawValue + Codable). Old debug-ring JSON exports show `"mode": "light"`, new ones show `"mode": "natural"`. The format is for debugging only — no migration of stored events needed.
- `PolishLightPromptFR.swift` / `PolishLightPromptEN.swift` renamed to `PolishNaturalPrompt<XX>.swift`. The original Light content was kept verbatim in commit 1 (refactor) and rewritten in commit 2 (this ADR).
- New files: `PolishNaturalPromptES.swift`, `PolishNaturalPromptDE.swift`.
- Dispatch in `AppleFoundationModelsPolishEngine.instructions(for:language:)` now routes all four `(.natural, language)` cases to dedicated prompts. The English-Natural fallback survives in the dispatch as the documented behaviour for any future language added without a dedicated prompt.
- `docs/agents/language-onboarding.md` gains a §"Polish prompt" section listing where to create the prompt, what skeleton to copy, what language-specific rules to adapt, and where to wire it into the dispatch.

## Risks and follow-ups

- ES + DE prompts are unvalidated. Track in `docs/agents/language-onboarding.md` checklist. Re-author after a native speaker can sit a test session per language.
- The "preserve tech anglicisms" list is curated and could miss terms used in production. Logs surface this — terms found unexpectedly translated can be added in PR.
- The "ASR repair" capability is implicit in Apple FM's behaviour but the prompt rule now codifies it. A future Apple FM update could stop honouring rule 8 even with an explicit instruction; round 5 testing should re-verify rule 8 holds. If it stops working we have no code-level fallback for ASR repair — it's a polish-layer-only capability for now.
