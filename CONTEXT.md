# Dictus — Domain Context

Living glossary of the terms that domain conversations rely on. When a term in conversation conflicts with what's defined here, raise it: the glossary or the conversation needs to change.

## Languages and onboarding

### Language onboarding
The process of adding a new transcription language to Dictus. **Distinct from user onboarding** (the first-run tutorial pages in `DictusApp/Onboarding/`). Language onboarding is a maintainer-facing workflow defined by `tools/onboard_language.py` + `docs/agents/language-onboarding.md`.

### Supported language
A language registered in `DictusCore/SupportedLanguage.swift` as an enum case. Registration unlocks: settings picker entry, keyboard toolbar cycle slot, autocorrect/predict pipeline, transcription language hint to Whisper. **Adding a `SupportedLanguage` case is the act of "registering" the language** — the script and checklist exist to make every other touch point a mechanical follow-on.

### Language profile (`LanguageProfile`)
The per-language data struct in `DictusCore/Languages/LanguageProfile.swift`. Pure data — no logic. One file per language (`French.swift`, `English.swift`, `Spanish.swift`, `German.swift`). Holds: code, displayName, shortCode, defaultLayout, spaceName, returnName, longPressAccents, overrides, accentMap, contractionPrefixes. Algorithms in `AOSPTrieEngine` and elsewhere read the profile; they don't switch on language code.

### Override map (`LanguageProfile.overrides`)
Per-language **must-correct** map: input → forced correction, applied before edit-distance lookup. Used for cases the trie can't infer (e.g., French `ca → ça`: "ca" is itself never a valid French word). **Distinct from accent map** (which is generative — try adding accents and check the dict) and from **edit-distance correction** (which is statistical). Policy: empty for new languages on first ship; populated from real user feedback. See ADR 0001.

### Accent map (`LanguageProfile.accentMap`)
Per-language map from base letter to accented variants used by `accentExpansion()` to attempt accent insertions when a typed word isn't in the dictionary. Generative, not curated — you list which accents *could* apply to which letters, then the algorithm tries them and picks the highest-frequency hit.

### Adaptive accent key
A French-specific feature of the AZERTY layout: the apostrophe/accent key on row 3 changes its label based on context (shows `é` after `e`, apostrophe after `qu`, etc.). **Not generalized to other languages.** Lives in `DictusCore/Languages/French.swift`. Other languages reach accents via standard long-press popups.

### Seed bigrams
Hand-curated word pairs injected into the n-gram corpus by `tools/ngram_builder.py` to compensate for underrepresentation in encyclopedic sources (Wikipedia, Google Books). Required for splitting compound input like `pasmal → pas mal`. Per-language list in `SEED_BIGRAMS_BY_LANG`. Policy: empty for new languages onboarded by non-native maintainers; populated post-launch from native-speaker contributions. See ADR 0001.

### Onboarding script (`tools/onboard_language.py`)
Phased command-line tool that handles the deterministic parts of language onboarding: `scaffold` (create `Languages/<Lang>.swift`, register stubs), `build-dicts` (run dictionary pipeline), `wire-xcode` (edit `project.pbxproj`), `verify` (run regression + per-language tests). Curated decisions (display name, layout, accent map, override population) stay manual and live in `docs/agents/language-onboarding.md`.

## Speech-to-text

### Transcription language
The language hint passed to the active STT engine. Read from App Group via `SharedKeys.language`. Whisper uses it as a forced-decode hint; Parakeet auto-detects and ignores it. Set by user via the settings picker or the keyboard toolbar cycle.

### STT engine
A speech-to-text backend conforming to `SpeechModelProtocol`. Two exist today: `WhisperKitEngine` (local Whisper variants) and `ParakeetEngine` (FluidAudio Parakeet v3, auto-detects language). New engines plug in via the protocol; language registration is engine-agnostic.

## Post-transcription polish

### Polish
The post-STT enhancement layer (issue #141). Runs synchronously in DictusApp after the STT engine emits final text and before the text is written to the App Group for keyboard injection. Off by default, toggled by the user in DictusApp Settings. **Distinct from Smart Mode (#79)**, which is user-triggered and reformulates clean text for tone/structure. Polish is automatic and corrective only.

### Faithful contract
The defining boundary between polish and Smart Mode (#79). Polish must preserve the user's **intent**, not necessarily their exact STT-output words. In Light mode the words are preserved; in Repair mode words may be substituted to recover intent when STT failed. Polish is forbidden from reformulating, reordering, changing tone, removing fillers/hesitations, or adding clarifying content. The contract enumerates ~20 operations as allowed or forbidden; see ADR 0002.

### Light mode
The polish prompt variant applied when the language detected on raw STT output matches the target language. Conservative: adds punctuation, capitalization (including German common-noun rule), accents, digit conversion for spoken numbers and dates, verbal-punctuation commands, and obvious typo fixes. Content words preserved. Active for Whisper always; active for Parakeet when `NLLanguageRecognizer` confirms the target language. Also called **Mode A**.

### Repair mode
The polish prompt variant applied when raw STT output is in a different language than the target (typically Parakeet hallucinating in the wrong language) or when language detection is uncertain. Allowed to substitute words to reconstruct the user's intent in the target language, while preserving loanwords and proper nouns. Triggered only on Parakeet, never on Whisper. Skipped entirely (raw passes through) when raw output is gibberish — measured by `NLLanguageRecognizer` returning all candidate languages with low confidence. Also called **Mode B**.

### PolishGlossary
Static, maintainer-curated list of ~20-30 domain terms (`Dictus`, `WhisperKit`, `Parakeet v3`, `GitHub`, `TestFlight`, `iOS`, …) injected into every polish prompt as context. Biases the LLM toward correct spellings of terms STT commonly massacres. Language-agnostic. Lives in `DictusCore/Polish/PolishGlossary.swift`. **Distinct from `LanguageProfile.overrides`** (keyboard autocorrect, offline trie) and from custom vocabulary (#80, premium, user-managed). Evolves by PR as failures appear in test logs.

### Polish guardrail
Runtime sanity check applied to every polish output. Rejects the polished string and writes the raw text instead when the polished/raw character-length ratio falls outside `[0.5, 2.0]` in Light mode or `[0.3, 3.0]` in Repair mode. Logged as `outcome = rejected_guardrail`. Minimal by design — catches catastrophic divergence (empty output, runaway generation) but does not attempt content-word fidelity validation. Lives in `DictusCore/Polish/PolishGuardrail.swift`.

### Polish engine
A polish backend conforming to `PolishEngineProtocol` (in DictusCore). One implementation at round 1: `AppleFoundationModelsPolishEngine` (in DictusApp, requires iOS 26+ with Apple Intelligence enabled and A17 Pro / M-series hardware). Round 2 will evaluate an OSS fallback backend (llama.cpp via LocalLLMClient, MLX, or Core ML) for devices without Apple Foundation Models; the decision is data-driven based on round 1 measurements.

## Keyboard

### Layout type
The physical key arrangement: `LayoutType.azerty` (French), `LayoutType.qwerty` (English, Spanish) or `LayoutType.qwertz` (German, #151). Each `SupportedLanguage` declares its `defaultLayout`, which seeds the layout when that language is *selected* and never rewrites a layout already stored. Layout is global today (one active at a time), not per-language; per-language layout selection is tracked in issue #52, and decoupling layout from dictionary language in #272.

QWERTZ carries dedicated ä/ö/ü keys, which makes its first two rows 11 units wide against 10 for every other row in every layout. The renderer normalizes each row against its own unit total, so those rows draw narrower keys. Row data lives in `DictusCore/KeyboardLayoutData.swift`; `DictusKeyboard/KeyboardLayouts.swift` builds the keys from it.

### Substitution-cost tables (`KeyboardProximity`, `AccentRelation`)
The two tables the C++ trie scorer consults when it substitutes one character for another while walking correction candidates: **keyboard proximity** (how far apart two keys are on the active layout) and the **accent relation** (which accented letters are variants of which base letter, and at what cost). Both are declared in `DictusCore/Sources/DictusCore/TextCorrection/`, computed once per dictionary load, and installed into the scorer across the ObjC bridge; the scorer holds the lookup and the traversal, no rules of its own. **Distinct from `LanguageProfile.accentMap`**, which drives the Swift-side generative accent expansion — the accent relation is a *cost*, consulted during edit-distance scoring, not a list of variants to try. Declared in DictusCore because the keyboard target has no test bundle (#321, same reasoning as the QWERTZ rows in #151).

`ß` is deliberately outside the accent relation: its relation to `ss` changes length, which one-to-one substitution cannot express. That relation lives in `LanguageProfile.collapseRules` instead.

### Long-press accents (`AccentedCharacters.mappings`)
Pop-up accent variants shown when a key is long-pressed. Currently merged across languages (French + Spanish ñ + acute variants), keyed by base letter. To be migrated into `LanguageProfile.longPressAccents` so each language declares its own popups.
