# Language onboarding

How to add a new transcription language to Dictus end-to-end. Written after onboarding German (issue #109) — the workflow below is what actually shipped, not what was planned.

The split between automated and curated work is deliberate: the maintainer authors a few small data files, and `tools/onboard_language.py` handles the mechanical Swift / Xcode / pipeline plumbing.

## TL;DR

```bash
# 1. Scaffold Swift skeletons + register the case
python3 tools/onboard_language.py scaffold it \
    --display-name "Italiano" --short-code IT --layout qwerty

# 2. Manually fill the gaps the scaffold reported (see "Curated decisions")

# 3. Author scripts/curate_<code>_dictionary.py, then build the binaries
python3 tools/onboard_language.py build-dicts it

# 4. Wire the resources into Xcode and verify the project still builds
python3 tools/onboard_language.py wire-xcode it
python3 tools/onboard_language.py verify it

# 5. Smoke-test on simulator, ship to TestFlight, tag the requesting user
```

## Pieces involved

- **`SupportedLanguage`** (`DictusCore/Sources/DictusCore/SupportedLanguage.swift`) — the type-safe enum. Adding a case unlocks settings picker, keyboard cycle, and the autocorrect pipeline.
- **`LanguageProfile`** (`DictusCore/Sources/DictusCore/Languages/LanguageProfile.swift`) — pure-data struct. One file per language under `Languages/<Lang>.swift`. Holds: `code`, `displayName`, `shortCode`, `defaultLayout`, `spaceName`, `returnName`, `overrides`, `accentMap`, `contractionPrefixes`. Algorithms read the profile; they don't switch on language code.
- **Per-language tests** under `DictusCore/Tests/DictusCoreTests/Languages/<Lang>LanguageTests.swift`. One file per language.
- **Frequency JSON** at `DictusKeyboard/Resources/<code>_frequency.json` — top ~40K word→count entries. Authored by `scripts/curate_<code>_dictionary.py`.
- **Spellcheck binary** at `DictusKeyboard/Resources/<code>_spellcheck.dict` — built by `tools/dict_builder.py` from the frequency JSON.
- **N-gram binary** at `DictusKeyboard/Resources/<code>_ngrams.dict` — built by `tools/ngram_builder.py` from OpenSubtitles + Google Books + Wikipedia CirrusSearch dumps.
- **Xcode wiring** in `Dictus.xcodeproj/project.pbxproj` — three resources added to the `DictusKeyboard` target's `PBXResourcesBuildPhase`. Mechanical; the script handles it.

## The four phases

### 1. `scaffold`

Generates `Languages/<Lang>.swift` and `Tests/Languages/<Lang>LanguageTests.swift` from templates, then patches `SupportedLanguage.swift` and `LanguageProfile.swift` to register the case and map it to the new profile.

The script scaffolds **only the data structures**. It explicitly does NOT generate `accentMap`, `overrides`, `contractionPrefixes`, `spaceName`, or `returnName` — those are language-specific and need a curated answer (see below). The scaffold leaves `TODO` markers in the new files; running `xcodebuild` will fail until they're populated.

The script also does NOT auto-update the per-arm switches in `SupportedLanguage.swift` (`displayName`, `defaultLayout`, `spaceName`, `returnName`). It prints a reminder to add them by hand. We chose this over auto-edits because the switches are already exhaustive — the compiler will yell if you miss one, which is the right behavior.

### 2. `build-dicts`

Runs three Python scripts in order:

1. `scripts/curate_<code>_dictionary.py` — language-specific. **You must author this** before running the phase. Output: `DictusKeyboard/Resources/<code>_frequency.json` (top ~40K word→count entries).
2. `tools/dict_builder.py` — corpus-agnostic. Reads the frequency JSON, builds a compressed patricia trie at `<code>_spellcheck.dict` (typically 0.4–0.5 MiB).
3. `tools/ngram_builder.py --lang <code>` — pulls OpenSubtitles top sentences, Google Books German n-grams, and 50 000 articles across `<code>wikinews/wikiquote/wikibooks/wikivoyage` CirrusSearch dumps. Outputs `<code>_ngrams.dict` (~6–7 MiB after the 50K bigram + 30K trigram cap). Wikipedia parsing dominates run time (~3–5 minutes for German).

**The trie does not store raw counts.** `dict_builder.py` writes `65535 * ln(1 + freq) / ln(1 + max_freq)` into each node, and that log-normalized value is what `AOSPTrieEngine.frequency(of:)` returns. The compression is severe: German `fuer` (712) against `für` (735 252) is 1033x in the corpus and 2.06x once stored. Two consequences, both learned the hard way in issue #326:

- `AccentExpander`'s 5x-dominance rule is **unreachable for every entry a curated list actually contains.** The stored value is capped at 65535, so clearing 5x needs the input to normalize below 13107 — which means a raw count under `(1 + max_freq)^0.2`. For German that threshold is **21.6**, and the top-40K list bottoms out at 88. Only corpus entries far below any sane cutoff could ever be dominated. So a misspelling that is in the trie will not be corrected by accent expansion, whatever its corpus frequency: curate it out of the frequency JSON instead. Recompute the threshold when onboarding a language, rather than assuming German's.
- A test that drives `expandAccents` through `MockFrequencyProvider` (raw counts) will pass where the device fails. Use `LogNormalizedFrequencyProvider` when the *threshold* is what's under test.

For `ngram_builder.py` to recognize the new language you must also extend two constants in that file:

- `LANG_MAP[<code>] = "<orgtre name>"` — maps the BCP-47 code to the directory name used by the orgtre repos (`german`, `french`, etc.).
- `--lang` argparse `choices` — add the code so the CLI accepts it.

`SEED_BIGRAMS_BY_LANG` is **deliberately left empty for non-native launches** (see ADR 0001). Do not invent seed bigrams from a phrasebook; they require native intuition for spoken-form usage.

### 3. `wire-xcode`

Edits `Dictus.xcodeproj/project.pbxproj` directly to add three resources to the `DictusKeyboard` target's resource build phase:

- `<code>_frequency.json`
- `<code>_spellcheck.dict`
- `<code>_ngrams.dict`

Four sections of the pbxproj need updates: `PBXBuildFile`, `PBXFileReference`, `PBXGroup` children (Resources group), and `PBXResourcesBuildPhase`. The script generates stable IDs from the language code so re-runs are idempotent.

### 4. `verify`

Runs:

```
cd DictusCore && swift test
xcodebuild build -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -configuration Debug
```

The DictusCore suite runs on the host Mac, not on a simulator. The package builds for macOS on purpose — that is what the `#if canImport(UIKit)` guards scattered through the library are for — and no test in the suite is gated to iOS, so a simulator destination costs minutes and buys no coverage. The app build below it is the part that needs a simulator.

## Curated decisions (no automation can guess these)

- **`displayName`** — the language's name in its own language. `Français`, `English`, `Español`, `Deutsch`. No anglicized "French / German".
- **`shortCode`** — the two-letter uppercase code shown on the keyboard toolbar switcher. Always equal to `code.uppercased()`.
- **`defaultLayout`** — `.azerty` (French only) or `.qwerty` (everything else, including German on launch). Per-language layout selection (e.g. QWERTZ for German) is tracked in issue #52 / #151.
- **`spaceName` / `returnName`** — local convention. `espace / retour` (fr), `space / return` (en), `espacio / intro` (es), `Leertaste / Eingabe` (de). Look up the local convention; do not translate "space" word-for-word.
- **`accentMap`** — generative, doesn't require fluency. List each base letter and the accent variants the algorithm should try. German example: `"a": ["ä"], "o": ["ö"], "u": ["ü"]`. `accentMap` models single-character substitution only; anything that changes the word's length (German `ss → ß`, `ue → ü`) goes in **`collapseRules`** instead, which `AccentExpander` applies in the same pass. Long-press on `s` still reaches `ß` directly.
- **`overrides`** — **empty on first ship for non-native launches** (ADR 0001). The override map forces a correction unconditionally, so populating it from a phrasebook produces silent regressions when a "must-correct" turns out to be a valid alternative. Populate post-launch from real user feedback.
- **`contractionPrefixes`** — language-specific. French has nine (`l'`, `d'`, `c'`, ..., `qu'`); English handles contractions via the override map; Spanish and German leave this empty.

## Choosing a frequency corpus

`scripts/curate_<code>_dictionary.py` is the smallest piece of new code per language and the most language-dependent. Look at the three existing curate scripts for the patterns we have:

- `curate_en_dictionary.py` — Norvig's `count_1w.txt` (Google Trillion Word Corpus, lemmatized). Best when a high-quality unigram frequency table is published.
- `curate_fr_dictionary.py` — Lexique 3.83 (academic French linguistic database, weighted 70% films + 30% books). Adds curated SMS abbreviations and proper nouns. Best when the upstream is research-grade.
- `curate_de_dictionary.py` — HermitDave's FrequencyWords 2018 (OpenSubtitles top 50K). Best when you want the same conversational register the n-gram pipeline already pulls (`orgtre/top-open-subtitles-sentences`).

Pick one of those three patterns. **Don't** layer in SMS abbreviations or proper-noun curation on a non-native launch (ADR 0001 — same reasoning as `overrides`).

## What we deliberately don't automate

- Deciding the corpus source.
- Filling `accentMap`. Generative but language-knowledge-dependent.
- Adding `case` arms to the per-language switches in `SupportedLanguage.swift`. The compiler enforces exhaustiveness; the loud failure on missing-arm is intended.
- Localizing UI strings (`Localizable.xcstrings`). Tracked separately in issue #52.
- Translating the user-facing onboarding flow (`GlobeKeyTutorialPage` etc.). Tracked separately.

## Polish prompt (Apple Foundation Models)

The polish layer (issue #141, ADR 0003) runs a per-language system prompt against Apple FM. **Adding a new language without a dedicated prompt is supported** — the dispatch falls back to English Natural — but ships a polish that uses English contractions and English fillers, which is clearly worse than language-specific rules even before native-speaker validation. Author a dedicated prompt as part of the launch unless the language genuinely has no business adding one (e.g., a language Apple FM does not support).

### Where to add the prompt

`DictusCore/Sources/DictusCore/Polish/Prompts/PolishNaturalPrompt<XX>.swift` where `<XX>` is the uppercase two-letter ISO 639-1 code (`FR`, `EN`, `ES`, `DE`, …). One file per language, one `enum` per file, single static `instructions(glossary:)` method returning the prompt string.

### What to copy from

`PolishNaturalPromptFR.swift` is the reference. It was authored against real dictation tests and carries the structure all per-language prompts share:

1. TEXT TRANSFORMATION FUNCTION framing (anti-chat-reply guard).
2. OUTPUT LANGUAGE lock.
3. RESPONSE-IS-POLISHED-TEXT block.
4. GOAL statement.
5. RULES section (1-9) — the operations the model MUST perform.
6. PRESERVE section — what stays untouched.
7. FORBIDDEN section — what must never happen.
8. Domain glossary slot (`\(glossary)`).
9. INPUT/OUTPUT examples covering each rule.
10. ASR-repair example (rule 8).
11. `<<NL>>` marker examples (rule 5).

### What to adapt per language

| Aspect | French | English | Spanish | German |
|---|---|---|---|---|
| Typographic spacing | NBSP before `? ! ; :` | none | none | none |
| Question/exclamation | `?`, `!` | `?`, `!` | inverted: `¿…?`, `¡…!` | `?`, `!` |
| Apostrophe | typographic `’` | typographic `’` | not standard | not standard |
| Diacritics rule | French accents | n/a | Spanish accents (`tú`/`tu`, `sí`/`si`) | umlauts + `ß` |
| Capitalization | sentence + proper nouns | sentence + proper nouns + standalone "I" | sentence + proper nouns | sentence + ALL nouns |
| Familiar register list | `t'es`, `dispo`, `19h`, `appart`, … | `gonna`, `wanna`, `dunno`, `cuz`, … | `pa'`, `na'`, `to'`, … | `'ne`, `'nen`, `gehste`, … |
| Negation form | oral negation (no `ne`) | contractions (`don't` not `do not`) | n/a | n/a |
| Filler list | `euh`, `hum`, `tu vois`, `en fait` | `uh`, `um`, `like`, `you know` | `eh`, `pues`, `o sea`, `tipo` | `äh`, `ähm`, `halt`, `naja` |
| Transition keep-list | `voilà`, `bon`, `bref`, `donc` | `so`, `well`, `anyway` | `bueno`, `pues`, `entonces` | `also`, `naja`, `tja`, `nun` |
| Tech anglicism list | identical across languages | identical | identical | identical |

The tech anglicism list (`today`, `ship`, `commit`, `push`, `merge`, `PR`, `deploy`, `feature`, `bug`, `release`, …) is **the same in every prompt** — devs working in any of these languages still use the English terms.

### How to wire it

Add a `case` arm in `AppleFoundationModelsPolishEngine.instructions(for:language:)`:

```swift
case (.natural, .<yourLanguage>):
    return PolishNaturalPrompt<XX>.instructions(glossary: glossary)
```

The compiler enforces exhaustiveness — adding a new `SupportedLanguage` case without an arm here is a build error, which is what we want.

No Xcode project edits are needed: the prompts live in the `DictusCore` SwiftPM target (`path: "Sources/DictusCore"`), which auto-discovers every `.swift` file under it. Just create the file in the `Prompts/` directory and it compiles.

### Repair prompts

Each language also needs a `PolishRepairPrompt<XX>.swift` (Repair mode, ADR 0002). Repair fires on Parakeet when the language detected on the raw STT output differs from the target — Parakeet ignores the language picker, so a speaker who code-switches can get a transcript in the wrong language, and Repair reconstructs the intent in the target language.

Without a dedicated Repair prompt, the dispatch falls back to `PolishRepairPromptEN`, which forces **English** output — the language guardrail (`PolishGuardrail.detectedLanguageMatches`) then rejects it and writes raw instead, so the user gets no polish at all. Copy `PolishRepairPromptFR.swift` (template) and wire the arm:

```swift
case (.repair, .<yourLanguage>):
    return PolishRepairPrompt<XX>.instructions(glossary: glossary)
```

Caveat (Apple FM, 26.x): cross-lingual reconstruction is not uniformly reliable. ES Repair works; **DE Repair reproducibly leaks Polish** when reconstructing from a Romance-language input, and the prior is not promptable away. The guardrail catches it (raw fallback), but until a third-party local LLM lands, Repair quality is language-dependent and must be checked per language with `polish-harness show`.

### Validation

A new prompt **needs native-speaker validation before being trusted in production**. The ES/DE prompts shipped in the round-1 Natural rollout are flagged in their file doc-comment as "authored on-paper without a native-speaker test set". Validation = read a written test script in the target language, dictate it through Dictus, export the polish ring JSON, compare to what a native speaker would have typed. File quality gaps against the language's GitHub issue or the post-launch playbook (#152).

### When to skip the prompt

Skip the dedicated prompt **only** when:
- Apple FM does not support the language at all (`SystemLanguageModel.default.supportedLanguages` doesn't include it). The English fallback is then a no-op since the user won't see meaningful output anyway.
- The language ships as a keyboard-only launch with the polish toggle hidden in Settings for that locale. (This is not currently a supported launch shape — file an issue first.)

In every other case, write the prompt.

## Smoke testing on the simulator

After `verify` passes, install the build on the iPhone 17 Pro simulator. The runbook for German (PR2) was:

1. Open Settings, change language to Deutsch.
2. Confirm spacebar reads `Leertaste`, return key reads `Eingabe`, layout stays QWERTY.
3. Type `uber`, `schon`, `madchen` → expect `über`, `schön`, `mädchen` (single-substitution accent expansion).
4. Type `strasse`, `fuer`, `koennen` → expect `straße`, `für`, `können` (collapse rules).
5. Switch to French, English, Spanish in turn — verify the six pre-existing autocorrect cases from PR1 still pass.

If a smoke test surfaces a quality gap (missing override, missing seed bigram), file it on the language's GitHub issue. **Don't** add it to the launch PR — the post-launch playbook (issue #152) handles iterative improvements driven by real usage.

## Reference

- ADR 0001 — empty overrides and seed bigrams for non-native language launches: `docs/adr/0001-empty-overrides-and-seeds-for-non-native-language-launches.md`
- ADR 0003 — Natural polish contract (per-language polish prompts): `docs/adr/0003-natural-polish-contract.md`
- Domain glossary: `CONTEXT.md` (sections "Language onboarding", "Language profile", "Override map", "Accent map", "Seed bigrams")
- The German launch (issue #109): the worked example. PR2 commits show every file touched.
- Follow-ups: #151 (QWERTZ layout for German), #152 (post-launch quality playbook).
