# User-dictionary learning — research findings

**Issue:** [#287](https://github.com/getdictus/dictus-ios/issues/287)
**Scope:** research only. No production code, no change to `UserDictionary`, no change to `repetitionThreshold`, no implementation of [#114](https://github.com/getdictus/dictus-ios/issues/114).
**Date:** 2026-08-03.

The research plan was written and committed *before* any research began, so the findings can be checked against it — see the first commit on this branch, `docs(research): record the research plan before researching (refs #287)`.

This document answers the five questions in the agent brief. It does not propose an implementation. Where a question has no good answer, it says so.

---

## Evidence labels

Every claim carries one, and the label is part of the claim.

| Label | Meaning |
| --- | --- |
| **[code]** | Read in this repository, cited by file and line. |
| **[source]** | Read in a named third-party source file or official API reference, cited by URL or path. |
| **[paper]** | A published paper, cited by title and identifier. |
| **[derived]** | Arithmetic or inference on top of a **[source]** fact. The input is sourced; the output is not quoted. |
| **[secondary]** | Blog post, forum answer, press coverage. Context only. |

**Nothing labelled [secondary] appears as the basis for a design conclusion in this document.** Where a fact could not be established, the text says "not publicly documented" and stops.

---

## Summary

Five things, in the order they matter.

1. **A learned word in Dictus does exactly one thing: it makes autocorrect leave it alone, forever.** It never reaches the suggestion bar by any path. The maintainer's device observation is fully explained by the code, and the `learnWord` call that looks like it feeds the engine is a documented no-op in both engines. **[code]**
2. **So the feature is not inert — it is the opposite.** Of the three things a learned word could do, Dictus grants only the one that is invisible to the user and cannot be dismissed. The cost side of the issue's framing is right; the "all of the cost and none of the benefit" phrasing understates the cost, because permanent autocorrect immunity is a stronger commitment than appearing in a suggestion bar.
3. **AOSP LatinIME does the opposite of Dictus on the single most important axis.** Its learned words are *never* treated as valid words — `UserHistoryDictionary.isValidWord()` hard-returns `false` — so AOSP will happily autocorrect away from a word it has learned. It grants learned words the *weak* trust level (they can be suggested) and withholds the strong one. Dictus grants the strong one and withholds the weak one. **[source]**
4. **The maintainer's "Apple probably also learns in one shot" premise is not supported by Apple's own documentation, and the documentation points somewhere more interesting.** Apple documents the trigger as *rejecting a suggestion*, and says "if you reject the same suggestion **a few times**, iPhone stops suggesting it". The documented mechanism is repeated rejection — which maps onto Dictus's undo path, not its repetition path. Everything *after* learning (threshold, capacity, decay, eviction) is undocumented, confirmed by a full-text search of the 14,000-line Apple Platform Security guide. **[source]**
5. **Nobody in the open-source field implements the categorical rule "suggestable but not allowed to autocorrect".** HeliBoard's two-tier promotion is the closest prior art, it is opt-in and off by default, and it is GPL-3.0 so only the design is reusable. This is a genuine gap in the field, not a gap in the search. **[source]**

---

## Question 1 — What does a learned word actually do in Dictus today?

Answered entirely from this repository. This is the strongest section of the document.

### 1.1 There is exactly one read site

`UserDictionary.isLearned` is called from **one** place in the whole codebase:

- `DictusKeyboard/TextPrediction/TextPredictionEngine.swift:165`, inside `spellCheck(_:isAtSentenceStart:)`. **[code]**

```swift
if UserDictionary.shared.isLearned(wordToCheck) {
    return nil  // User-learned word: no correction needed
}
```

`return nil` means "this word is correct, do not offer a correction". That is the entire runtime effect of learning a word.

Both `spellCheck` overloads funnel through it: the context-aware one (`TextPredictionEngine.swift:343`) calls the base overload at line 363 after its language-override early return. **[code]**

The other two `UserDictionary` reads are not runtime consumers: `UserDictionary.shared.reload()` at `KeyboardViewController.swift:476` (cross-process cache refresh) and `.count` / `.resetAll()` at `DictusApp/Views/SettingsView.swift:197-206` (the reset button). **[code]**

### 1.2 The call that looks like it feeds the engine is a no-op

Both learning sites do the same thing on promotion:

```swift
if UserDictionary.shared.recordUsage(word) {
    state.learnWord(word)          // DictusKeyboardBridge.swift:495-497
}
```
```swift
if UserDictionary.shared.recordUsage(undo.originalWord) {
    suggestionState.learnWord(undo.originalWord)   // KeyboardRootView.swift:479-480
}
```

`SuggestionState.learnWord` (`SuggestionState.swift:337`) forwards to `engine.injectUserWord(_:)`. Both engine implementations are empty, and both say so:

- `TextPredictionEngine.swift:527-530` — *"No-op: user words are handled by the two-pass lookup in `spellCheck()`. The mmap'd trie is read-only."*
- `AOSPTrieEngine.swift:150-153` — *"No-op for trie engine. User words are checked separately via `UserDictionary`."* **[code]**

This is honest code — the comments are accurate and the intent is documented. But it means the promotion branch has no effect beyond the `UserDictionary` write that already happened on the line above.

### 1.3 None of the three suggestion-bar modes consults the learned set

The bar has three content modes (`SuggestionState.swift:14-20`): `.completions`, `.corrections`, `.predictions`. **[code]**

| Mode | Data source | Reads learned set? |
| --- | --- | --- |
| `.completions` | `engine.suggestions(for:)` (`SuggestionState.swift:151`, `:180`) → `UITextChecker.completions(...)` (`TextPredictionEngine.swift:81`), reranked by `FrequencyDictionary` | **No** |
| `.corrections` | `engine.spellCheck(...)` (`SuggestionState.swift:162-168`) | Yes — and a learned word makes it return `nil`, so the bar shows **nothing** |
| `.predictions` | `engine.predictNextWords(after:)` (`TextPredictionEngine.swift:327`) → AOSP trie n-grams, falling back to `frequencyDict.topWords` | **No** |

The `.completions` path is the one that would surface a learned word, and it is backed by `UITextChecker`, Apple's system spell checker. **Dictus never calls `UITextChecker.learnWord`** — a grep for `UITextChecker` across the tree returns only the instantiation, `availableLanguages` checks, `completions(...)`, and comments. **[code]** So the system checker has no idea the word exists, and the learned set is not consulted separately.

The `.corrections` interaction is worth stating plainly, because it is counter-intuitive: learning a word does not put it in the bar, it **removes** the bar. A learned word produces `mode = .idle` where an unlearned one would have produced a correction row.

**Conclusion for question 1: the maintainer's device observation is exactly what the code does.** A word learned on first use will never appear in the suggestion bar, in any mode, under any condition. There is no bug to find; the consumer was never written.

### 1.4 What the issue body gets right, and one place it needs refining

The issue says "a typo typed once is learned and kept". The code says something narrower and more useful.

Learning from typing is gated by `wordWasEvaluated` (`DictusKeyboardBridge.swift:442`), and the correction path `return`s before reaching `recordUsage` when a correction actually fires. **[code]** So the set of words that get learned by repetition is:

> every word the autocorrect pipeline **evaluated and declined to correct**.

That excludes typos the corrector caught (those are corrected, and only learned if the user undoes them — which is the strong-signal path, working as designed). It includes:

- **(a) every correctly-spelled word the user types.** "bonjour" typed once is learned. This is by far the largest category.
- **(b) unknown words preserved by the proper-noun guard** (`TextPredictionEngine.swift:225`) — names, acronyms. This is the category the feature exists for.
- **(c) unknown words the corrector had no candidate for** — typos far enough from any dictionary word that nothing fired. This is the real false-learning surface.

Category (a) has a consequence the issue does not mention. The 1000-word cap evicts by **ascending usage count** (`UserDictionary.swift:149-152`): least-used first. **[code]** Common words accumulate counts in the hundreds; a colleague's name typed twice sits at 2. **When the cap is reached, eviction removes exactly the personal vocabulary the feature exists to protect and keeps the dictionary words that never needed protecting.** The eviction policy is backwards relative to the feature's purpose.

A second observation, not a recommendation: `saveToDefaults()` re-serialises the entire dictionary on every word boundary (`UserDictionary.swift:145-166`), because `recordUsage` calls it on both the learned-bump and the promotion branch. **[code]** At the 1000-entry cap that is a full plist write per space keystroke.

### 1.5 The trust inversion

Three things a keyboard can grant a learned word, in increasing order of commitment:

1. **Offered** — it appears in the suggestion bar. The user must tap it. Visible, reversible, zero risk.
2. **Immune** — autocorrect will not rewrite it. Invisible to the user; affects only that word.
3. **Authoritative** — the keyboard rewrites *other* words into it. Strongest; can damage text the user did not ask about.

Dictus today grants **level 2 on a single use**, and never grants level 1. That is the finding that reframes the issue: this is not a feature with cost and no benefit, it is a feature that hands out the harder-to-notice permission on the weakest possible evidence, while withholding the safe one entirely.

---

## Question 2 — How do open-source keyboards do it?

### 2.1 AOSP LatinIME — Apache-2.0, the only licence-clean adaptive model in the field

Read at `android.googlesource.com/platform/packages/inputmethods/LatinIME`, tree `127336e9f29d69607eab55982324b210279ae8c5`. Apache-2.0 headers on every file. **[source]**

Two navigational corrections for anyone following up: `DynamicLanguageModelProbabilityUtils` exists only as **C++** (`native/jni/src/dictionary/structure/v4/content/`), not Java; `DecayingExpandableBinaryDictionaryBase.java` no longer exists at HEAD. The native tree moved from `native/jni/src/suggest/policyimpl/dictionary/` to `native/jni/src/dictionary/`. **[source]**

**What triggers learning.** One entry point: `performAdditionToUserHistoryDictionary` from `commitChosenWord` (`InputLogic.java:2191`). Four blockers, all in `InputLogic.java:1424-1444`: autocorrect setting off, slow `InputConnection`, empty word, and length > 48. **[source]**

There is **no distinction between a word the user typed and a word the IME autocorrected to**. `commitType` is not even passed to the learning call, and the code carries a TODO admitting it cannot tell them apart at that point (`InputLogic.java:2201-2204`). **[source]** This is worth knowing before assuming AOSP is more careful than Dictus about signal quality — on this specific axis it is less careful.

The slow-`InputConnection` blocker is the piece of reasoning most worth borrowing, and its comment states the principle directly:

> *"Since we don't unlearn when the user backspaces on a slow InputConnection, turn off learning to guard against adding typos that the user later deletes."* **[source]**

**If you cannot observe the undo, do not learn in the first place.**

**Validation against the base lexicon.** Every committed word is learned, but whether it is in the main dictionary decides its validity flag (`DictionaryFacilitatorImpl.java:550-590`):

```java
final int maxFreq = getFrequency(word);
...
// We demote unrecognized words (frequency < 0, below) by specifying them as "invalid".
final boolean isValid = maxFreq > 0;
```

`getFrequency` only ever returns a real value from the main dictionary — `ExpandableBinaryDictionary` (superclass of user history, contacts and user dictionaries) never overrides it, so it inherits `Dictionary.getFrequency` returning `NOT_A_PROBABILITY = -1`. **`isValid` therefore means exactly "this word is in the base lexicon".** **[source]**

**Two-occurrence probation, and it is elegant.** When an out-of-vocabulary word is committed for the first time, `ver4_patricia_trie_policy.cpp` creates a placeholder entry with `count = 0` and returns early — no count increment, no n-grams. And `language_model_dict_content.cpp:58-62`:

```cpp
if (mHasHistoricalInfo && unigramProbabilityEntry.getHistoricalInfo()->getCount() == 0) {
    // The word should be treated as a invalid word.
    return WordAttributes();
}
```

A `count == 0` entry is reported invalid and is invisible to suggestions. On the **second** commit the lookup succeeds, the count goes 0 → 1, and n-grams begin. **An OOV word needs two commits before it can ever be suggested; a word already in the base lexicon skips probation entirely.** **[source]**

The cost of this probation is one placeholder entry — the placeholder doubles as the memo that the word has been seen. No separate pending store, no timestamps.

**The confidence model.** `P = clamp(255 + log2(count / max(contextCount, minCount)) × 8.589) + backoff`, from `probability_utils.cpp` and `dynamic_language_model_probability_utils.cpp`. The constants: **[source]**

```cpp
const int ASSUMED_MIN_COUNTS[]        = {8192, 2, 2, 1};   // uni, bi, tri, quad
const int ENCODED_BACKOFF_WEIGHTS[]   = {-32, -4, 2, 8};
const int DURATION_TO_DISCARD_ENTRY_IN_SECONDS = 300 * 24 * 60 * 60;   // 300 days
```

The unigram denominator floor of **8192** plus the **−32** backoff is the load-bearing safety mechanism. A learned unigram with count 1 scores ≈ 111 of 255; with count 8, ≈ 137; with count 100, ≈ 168. **[derived]** A learned word's probability starts deliberately low and climbs only logarithmically, so it can never stampede the base lexicon. Learned *n-grams*, normalised against a small context count, are allowed to be strong — a single bigram observation after a word seen five times scores ≈ 231. **[derived]**

That asymmetry — weak unigrams, strong n-grams — is what makes AOSP's learning safe. Not a decay curve.

**Decay: there isn't one.** `getDecayedProbability` is an identity function with a TODO:

```cpp
// TODO: Improve this logic.
// We don't modify probability depending on the elapsed time.
return probability;
```

An entry that is never reused keeps its probability for **exactly 300 days** and is then discarded by GC. Eviction under capacity pressure is strict LRU by timestamp with count as tiebreak (`EntryInfoToTurncate::Comparator`). Capacity: 10 000 unigrams, 30 000 each of bi/tri/quadgrams, hard limit ×1.2. Count halving at 65 472 is overflow protection, not forgetting. **[source]**

The famous forgetting curve (`ForgettingCurveUtils`, `MAX_LEVEL = 15`, `MIN_VISIBLE_LEVEL = 2`, one level lost per 15 days of non-use) is **largely dead code** at HEAD — `WORD_LEVEL_FIELD_SIZE = 0` in `ver4_dict_constants.cpp` means level is not even persisted, and the v4 writers never call it. **[source]** It is a better decay design than what ships; it just isn't what runs. Anyone citing AOSP's forgetting curve as shipped behaviour is citing dead code.

**Competition with the base lexicon: a single scored list, no override.** Every dictionary is queried independently and results go into one bounded `TreeSet` ranked by pure score (`SuggestionResults.java:74-82`). There are **no per-dictionary-type weights** — `mConfidence` is declared and never read again, and `mWeightForTypingInLocale` never leaves `1.0f` since multi-locale support was removed. **[source]**

**The asymmetry that matters most for Dictus** (`UserHistoryDictionary.java:131-135`):

```java
@Override
public boolean isValidWord(final String word) {
    // Strings out of this dictionary should not be considered existing words.
    return false;
}
```

A learned word contributes suggestions but is **never** a valid word. It cannot suppress autocorrect. **AOSP will autocorrect away from a word it has learned.** **[source]** This is the exact inverse of Dictus, where the only thing a learned word does is suppress autocorrect.

**Unlearning.** `unlearnFromUserHistory` hard-**deletes** the unigram (not a demotion) on `EVENT_REVERT` — a reverted autocorrect removes the autocorrected word from history. `EVENT_BACKSPACE` is explicitly excluded by an unresolved TODO, so backspacing over a word does not currently unlearn it. **[source]**

**N-grams.** Up to quadgrams (`MAX_PREV_WORD_COUNT_FOR_N_GRAM 3`). The loop building them stops at the first previous word that is not in any dictionary (`if (prevWordIds[i] == NOT_A_WORD_ID) break;`), so a bigram is only learned if the preceding word already has an entry. And because a word on its first sighting returns early, **no n-grams at all are recorded for a word's first occurrence.** **[source]**

### 2.2 HeliBoard — the only two-tier design in the field. GPL-3.0. Design only.

Repo has moved to `github.com/HeliBorg/HeliBoard`. Root `LICENSE` is GPL-3.0; modified AOSP files carry `SPDX-License-Identifier: Apache-2.0 AND GPL-3.0-only` — note `AND`, not `OR`. **The code cannot be lifted into an MIT repo. The design can be reimplemented freely.** **[source]**

`DictionaryFacilitatorImpl.kt`, `addToPersonalDictionaryIfInvalidButInHistory()`:

```kotlin
// User history always reports words as invalid, so we check the frequency instead.
// Testing shows that after 2 times adding, the frequency is 111, and then rises slowly with usage.
// 120 is after 3 uses of the word, so we simply require more than that.
if (userHistoryDict.getFrequency(word) > 120) {
    UserDictionary.Words.addWord(userDict.mContext, word, 250, null, dictionaryGroup.locale)
}
```

Note that the author's empirical `111` is the same number the AOSP formula yields for a count-1 learned unigram — independent corroboration of the arithmetic in §2.1.

**Tier 1** is the AOSP user-history dictionary: decaying, deletable, `isValidWord() == false`. **Tier 2** is the Android platform personal dictionary at frequency **250 of 255** — near-maximal, permanent, validity-conferring. Promotion needs **more than 3 uses** plus every one of: an opt-in setting (**default off**), the input field not disagreeing with the user's autocorrect preference, personalized suggestions enabled, `!wasAutoCapitalized`, single word only, length > 1, an unambiguous active language, and the word not already in the platform dictionary. **[source]**

**Lexicon validation, inverted.** `if (isValidWord(word, ALL_DICTIONARY_TYPES, dictionaryGroup)) return` — HeliBoard only promotes words **absent** from the lexicon. The lexicon check establishes *novelty*, not *legitimacy*. Legitimacy is proven purely by repetition, so a typo made four times gets permanently enshrined at frequency 250, and nothing demotes a tier-2 entry. **[source]**

Learning is blocked in incognito, which is broader than a user toggle: `mIncognitoModeEnabled = alwaysIncognito || mInputAttributes.mNoLearning`, where `mNoLearning` honours the OS `IME_FLAG_NO_PERSONALIZED_LEARNING`. **[source]**

**HeliBoard does not implement the categorical rule either.** Its autocorrect gate (`Suggest.kt:157-265`) is purely score-based and **no clause tests the source dictionary of the autocorrect target**. A tier-1 word that accumulates enough score simply becomes an autocorrect target. Probation there is probabilistic, never categorical. **[source]**

### 2.3 The rest of the field

| Keyboard | Licence | Learns? | Useful? |
| --- | --- | --- | --- |
| **FlorisBoard** | Apache-2.0 | **No** — README: word suggestions "are not included in the current releases"; `LatinLanguageProvider.suggest` returns `emptyList()`, `spell` returns hardcoded test data | Licence is fine, but there is nothing to reuse. One idea worth stealing: `isPrivateSession` is a **mandatory parameter** on every suggest/spell call rather than a global check, which makes the privacy gate impossible to forget. **[source]** |
| **FUTO Keyboard** | **FUTO Source First License 1.1-kb** — non-commercial only, no sublicensing. Not OSI-approved, **MIT-incompatible on three independent clauses** | Unchanged from AOSP (`UserHistoryDictionary.java` differs by two test-hook lines) | One free idea: `mNoLearning = noLearning \|\| mIsPasswordField \|\| mIsCodeField` — FUTO widened the no-learning gate beyond AOSP. Its neural LM never sees the user-history dictionary, only the explicit OS personal dictionary. Its LoRA on-device finetuning is dead code (`trainingEnabled = false`). **[source]** |
| **OpenBoard** | GPL-3.0 | Stock AOSP, zero divergence | Last commit 2022-12-17. Dead. **[source]** |
| **Simple Keyboard** | Apache-2.0 | No — the entire suggestion subsystem was deleted from its AOSP fork | Nothing. **[source]** |
| **Thumb-Key** | AGPL-3.0 | No, as a design principle | Nothing. **[source]** |
| **Presage / libpresage** | **GPL-2.0, no LGPL carve-out** | Yes, and badly | A useful **negative** example — see below. **[source]** |

**Presage is the failure mode Dictus is trying to design against.** Its `SmoothedNgramPredictor` is fixed-weight linear interpolation with hand-configured deltas (`<DELTAS>0.01 0.1 0.89</DELTAS>`), not Witten-Bell. `learn()` only ever increments or inserts; `removeNgram` exists but its only callers are unit tests. **No decay, no demotion, no eviction, no lexicon validation on the learn path at all.** Learned scores are simply *summed* on top of corpus scores by `MeritocracyCombiner`, whose own doc comment admits this "might introduce some imbalance". It learns any typo you type twice, forever, and adds its score to the corpus score. **[source]**

The one Presage idea worth keeping is structural: a read-only corpus DB (`<LEARN>false</LEARN>`) and a writable user DB (`<LEARN>true</LEARN>`) are never mixed at the storage layer and meet only in the combiner. Dictus already has this shape — a read-only mmap'd trie and a separate `UserDictionary` — so this is corroboration of the existing architecture rather than a new idea.

### 2.4 Android's platform personal dictionary, for reference

`android.provider.UserDictionary` (Apache-2.0, quoted from the AOSP source the docs are generated from; the rendered developer.android.com page could not be fetched). **[source]**

```java
private static final int FREQUENCY_MIN = 0;
private static final int FREQUENCY_MAX = 255;
/** Sort by descending order of frequency. */
public static final String DEFAULT_SORT_ORDER = FREQUENCY + " DESC";
```

**A single unbounded-lifetime integer, no timestamp, no usage count, no confidence, no decay.** The platform offers no mechanism whatsoever for probation or demotion. Any two-tier scheme has to live entirely in the keyboard, with the platform store as the terminal, irreversible tier — which is exactly the shape HeliBoard ended up with, and exactly why its promotion is one-way.

### 2.5 iOS and Swift — nothing permissive with learning exists

| Option | Licence | Learns? | Reusable by an MIT repo? |
| --- | --- | --- | --- |
| `UITextChecker` | Platform API | Binary learned/not-learned set only, no frequency, no ranking, no decay | Yes (it is the OS) |
| `UILexicon` | Platform API | No, read-only | Yes, supplementary only — see §4.2 |
| `gdetari/SymSpellSwift` | MIT | **No persistence at all** — no `Codable`, no save path | Yes, but every learning mechanism would be yours to build |
| **KeyboardKit** | **Closed Source** — `LICENSE` reads "Closed Source License … is closed-source"; autocomplete is Pro-gated | — | **No** |
| Hunspell | MPL 1.1 / GPL 2.0 / LGPL 2.1 tri-license | Runtime `add()`/`remove()`, in-memory only | Yes via the MPL arm |
| Nuspell | LGPL-3.0 | No | Practically no on iOS (static-link relinking clause) |
| **AOSP LatinIME** | **Apache-2.0** | **Yes — the only well-designed adaptive model found** | Licence yes; it is a port job, not a dependency |

**[source]** for every licence in this table. `Ryu0118/SwiftSpellChecker` does not exist (404); `github.com/Presage/presage` is a 404 and the real upstream is SourceForge.

The confidence on "nothing else exists" is **medium-high**, not high — this is an exhaustiveness claim over a search, and exhaustiveness claims are the weakest kind. The licence facts in the table are high confidence; the absence claim is not.

---

## Question 3 — How is false learning contained?

Consolidating the mechanisms actually observed in source, and what each would cost Dictus.

| Technique | Who does it | What Dictus would need to record |
| --- | --- | --- |
| **Validate against the base lexicon before committing** | AOSP (`isValid = maxFreq > 0`); HeliBoard (inverted, to detect novelty) | **Nothing new.** `AOSPTrieEngine.wordExists(_:)` already answers this and `recordUsage` does not currently ask. This is the one containment mechanism available at zero storage cost today. **[code]** |
| **Probation: N occurrences before an entry is visible** | AOSP (2 commits, via a `count = 0` placeholder) | Nothing new. Dictus already has a `pendingWords` store; at `repetitionThreshold = 1` it is structurally unreachable, which is why the below-threshold test is skipped. The machinery exists and is switched off. **[code]** |
| **Frequency weighting so a learned word starts weak** | AOSP (`ASSUMED_MIN_COUNTS[0] = 8192`, backoff `−32`) | Only meaningful if learned words are scored against the lexicon on a common scale. Dictus has no unified scoring — that is #114's item 3. Not available without it. |
| **Two-tier promotion (history → permanent)** | HeliBoard only (`getFrequency > 120`, ~4 uses, opt-in, default off) | A tier flag per entry: 1 bit. |
| **Decay over time / demotion on non-reuse** | **Nobody, in shipped code.** AOSP's decay function is an identity function with a TODO; its forgetting curve is dead code | A last-used timestamp per entry: 1 `Int`. |
| **Hard eviction after long non-use** | AOSP (300 days, plus LRU under capacity pressure) | Same timestamp. Note Dictus's current eviction is by *count ascending*, which is backwards (§1.4). |
| **Unlearn on reverted autocorrect** | AOSP (`EVENT_REVERT` → hard delete); HeliBoard (same) | Nothing new — but note Dictus does the **opposite**: an undo *teaches* the word (`KeyboardRootView.swift:479`). Both are defensible; they are different products. AOSP deletes the word it *corrected to*; Dictus learns the word the user *restored*. These are not in conflict, and it is worth being precise about that before anyone "fixes" it. **[code]** |
| **Unlearn on backspace** | **Nobody** — AOSP and HeliBoard both explicitly exclude `EVENT_BACKSPACE` behind an unresolved TODO | A record of what was just deleted. |
| **Block learning when the undo cannot be observed** | AOSP + HeliBoard (slow `InputConnection`) | Dictus has the analogous guard already: `wordWasEvaluated` blocks learning in fields where autocorrect never ran, and on aborted replacements (#191, #200). **[code]** |
| **Block learning in password / code / no-learning fields** | FUTO (`mIsPasswordField \|\| mIsCodeField`); HeliBoard (OS `IME_FLAG_NO_PERSONALIZED_LEARNING`) | Whether `HostInputTraits` already covers this needs checking against `HostFieldPolicy`; it is a field-traits question, not a storage question. |
| **Block learning on auto-capitalized words** | HeliBoard (`!wasAutoCapitalized` — "we can't be 100% sure what the user intended to type") | Nothing new; the information is at the call site. |

### 3.1 The honest answer on cost

**Storage is not the constraint, and it would be dishonest to present it as one.**

Dictus stores `[String: Int]` for at most 1000 entries, about 30 KB. **[code]** Adding a last-used timestamp and a source/tier flag to every entry is on the order of 8–12 bytes per entry, so **under 12 KB at the cap** — roughly 0.02 % of the keyboard extension's ~50 MB ceiling. Every per-entry containment mechanism in the table above is free at this scale.

The real costs are elsewhere, and they are worth naming:

1. **Write amplification.** `saveToDefaults()` re-serialises the whole dictionary on every word boundary (`UserDictionary.swift:145-166`). **[code]** Richer per-entry data makes each of those writes larger. This is an I/O and latency question on the typing hot path, not a memory-ceiling question.
2. **Migration.** Existing dictionaries hold `[String: Int]` with no timestamps. Any timestamp-based policy has to decide what "last used" means for an entry that predates the field. The issue already flags this; it is a real design decision, not a detail.
3. **Schema shape.** `UserDefaults` dictionaries of heterogeneous values are awkward in Swift. A richer entry probably wants `Codable` structs and a different storage key, which is a bigger change than it first appears — and it interacts with #103 (iCloud KVS mirroring), which assumes `[String: Int]` throughout its merge strategy.

### 3.2 What nobody does

**No keyboard examined validates a candidate learned word against a lexicon to decide whether it is plausibly a real word rather than a typo.** AOSP uses the lexicon check to set a validity flag; HeliBoard uses it to detect novelty. Neither asks "is this string plausible in this language". The frequency-weighted valid-word guard recorded for #114 would be, as far as this survey found, **ahead of the open-source field rather than an alignment with it**. That is worth knowing before #114 is described as "aligning with AOSP" on this specific point.

**And no keyboard implements time-based decay in shipped code.** The technique is much discussed and, in the sources read here, universally deferred behind a TODO.

---

## Question 4 — What is known about Apple's behaviour?

The deliverable here is the line between documented and undocumented. Everything below Part A2 is quoted from Apple pages. **[source]**

### 4.1 What Apple documents

**The trigger is rejection, not typing.** From Apple's own support page on resetting settings:

> **Reset Keyboard Dictionary:** You add words to the keyboard dictionary by **rejecting words iPhone suggests as you type**. Resetting the keyboard dictionary erases only the words you've added.

And from the predictive-text page:

> To reject a correction, tap the "x." **If you reject the same suggestion a few times, iPhone stops suggesting it.**

**This is the finding that contradicts the issue.** The maintainer's framing is "Apple probably also learns in one shot, so a threshold of 1 may not be wrong". Apple's own documentation describes the mechanism as *repeated rejection* — "a few times", not once — and describes the trigger as rejection rather than mere typing. That maps onto Dictus's **undo** path, not its **repetition** path.

Two caveats, so this is not over-read. Apple never quantifies "a few times". And a support page describes user-visible behaviour, not implementation — it is entirely possible that some other, faster path also writes to the dictionary. But on the evidence available, the premise "Apple learns in one shot" is **not supported by anything Apple has published**, and the observation that prompted it (teaching iOS a word appears to register almost immediately) was a small number of device taps.

**Other documented facts:**

- A **blank-shortcut Text Replacement** is Apple's sanctioned explicit way to add a protected word: *"Have a word or phrase you use and don't want it corrected? … leave the Shortcut field blank."*
- The store is a named, first-class iCloud data category: **"QuickType Keyboard learned vocabulary"**, listed as end-to-end encrypted under both Standard and Advanced Data Protection.
- One reset clears custom words *and* shortcuts: *"All custom words and shortcuts are deleted."*
- `UITextChecker.learnWord(_:)` is a **type method**, and its discussion says the learned word *"is added to the dictionary. **It is global across languages**."* `unlearnWord` and `hasLearnedWord` are likewise type-level. By deliberate contrast, `ignoreWord(_:)` is documented as applying *"during the current spell-checking session only"*.
- Apple learns **new words for everyone** via local differential privacy — the Sequence Fragment Puzzle algorithm, QuickType at ε = 8, two donations per day, ≤ 3-month retention, gated on the Device Analytics setting. Examples given: *wyd*, *bruh*, *Despacito*, *Moana*. **[source]** + **[paper]** ("Learning with Privacy at Scale", Apple Machine Learning Research)

### 4.2 The load-bearing negative: `UILexicon` does not expose learned words

This closes off an idea Dictus might otherwise reach for. `UILexicon`'s documentation names exactly three sources:

> - Unpaired first names and last names from the user's Address Book database
> - Text shortcuts defined in the Settings > General > Keyboard > Shortcuts list
> - A common words dictionary
>
> Apple intends for you to consider the words in a lexicon object as supplementary to an autocorrection/suggestion lexicon of your own design.

**Words the system keyboard has learned are not among them.** The QuickType learned-vocabulary store is not mentioned on any of the `UILexicon`, `UILexiconEntry`, or `requestSupplementaryLexicon` pages. The list is hedged with "including", so it is not sworn to be exhaustive, but nothing anywhere expands it.

What `UILexicon` *is*: an Apple-blessed source of high-confidence user vocabulary — contact names and the user's own text replacements — available to a keyboard extension **regardless of open access** (per the archived App Extension Programming Guide: *"Every custom keyboard (independent of the value of its `RequestsOpenAccess` key) has access to a basic autocorrection lexicon through the `UILexicon` class"*). Whether Dictus already consumes it is outside this issue's scope, but it is the cheapest source of trustworthy proper nouns on the platform and it is not the same thing as the learned dictionary.

### 4.3 What Apple does not document

Established by a full-text search of the complete Apple Platform Security guide PDF (March 2026 edition, 14,238 lines of extracted text) for `keyboard|quicktype|predictive|personaliz|lexicon|autocorrect|dictionary|vocabulary|typing data|learned word|text replacement`. **[source]**

**The guide contains nothing about learned words, the keyboard dictionary, or QuickType personalization.** "QuickType" appears twice, both about the Password AutoFill bar. "Vocabulary" appears twice, both about SiriKit's `INVocabulary`. There is no Data Protection class assignment for the keyboard dictionary. The only relevant section is "How custom keyboards are used", which is about sandboxing, not learning.

Specifically undocumented, with no source found anywhere:

1. Whether `UITextChecker` learned words are device-global or app/extension-local.
2. Whether they persist across launches, where they are stored, or under what protection class.
3. Whether `UITextChecker`'s dictionary is the same store as the QuickType keyboard dictionary that "Reset Keyboard Dictionary" clears.
4. Whether learned words influence `completions(...)` or `guesses(...)` at all. The class overview says learning "adds those words to the lexicon" and that the checker spell-checks "using a lexicon" — suggestive, but not a documented guarantee.
5. **Any post-learning policy whatsoever**: threshold count, capacity, decay, eviction, aging.
6. Any way for a third-party keyboard to read the system's learned vocabulary.

**Item 5 is the maintainer's actual question, and the answer is that it is not publicly documented.** Not thinly documented — absent, including from a security guide that documents keyboard sandboxing in detail on the adjacent page.

Two consequences worth stating. First, the six items above can only be answered by measurement, and any answer obtained that way is unsupported by contract and can change between iOS releases. Second, item 1 combined with the documented "global across languages" behaviour of `learnWord` is a genuine architectural conflict with the four-axis language decoupling in #272 — not a nitpick, if `UITextChecker.learnWord` is ever considered as a storage mechanism.

**No WWDC claim appears in this document.** developer.apple.com no longer serves session transcripts in page HTML, WWDC17 session 242 could not be fetched, and its contents are not characterised from memory.

### 4.4 Do not conflate Apple's differential privacy with personal learning

Apple's DP work discovers new words **at the population level** and ships them in the on-device lexicon for everyone. *"Differential privacy transforms the information shared with Apple before it ever leaves the user's device such that Apple can never reproduce the true data."* It says nothing about what happens to a word *your* keyboard learns. **[source]**

The same trap exists on the Google side. Four of the five Gboard papers read are about federated aggregation into one global model — client updates are *"ephemeral … never stored on the server … immediately discarded"* (Hard et al., §4.1). **[paper]** The exception is Ouyang et al. 2017 (arXiv:1704.03987), §5.1, the only primary source describing a device-local user-specific model in Gboard:

> "Dynamic models can be used to **accumulate n-grams the user has previously typed**, or information such as their contact list … These models are **constantly updated** … incorporated in the decoding process using an **on-the-fly lattice rescoring** technique. The vocabulary of the dynamic LM can contain **words which are not covered by the main LM** … We integrate these OOV words in the decoder graph by splicing a character to word transducer to the LM FST."

The paper's own abstract calls this a *sketch*. The words "evict", "retention", "persist", "expire", "decay" and "forget" appear nowhere in it. **[paper]** Its term is "dynamic models", not "personal language model" — cite it as *Ouyang et al. 2017, §5.1*.

**None of the five Gboard papers documents Gboard's local personal-dictionary policy.** This is structural, not a search gap: they are ML-systems papers about training a shared model without collecting raw text.

One correction worth recording, since #114 may lean on this literature: Chen et al. (arXiv:1903.10635, OOV word discovery) applies **no differential privacy**. The words "noise", "Gaussian" and "epsilon" do not appear; DP is named only as deferred future work. **[paper]**

### 4.5 SwiftKey

Microsoft documents SwiftKey's learning thoroughly at the **behaviour** level and nowhere at the **mechanism** level. Documented: a "personalized language model"; vocabulary split into *static* (words SwiftKey already knows) and *dynamic* (words you teach it); users can view and export learned words; long-press in the prediction bar removes a word, which *"won't be predicted again unless you retype the word"*; deleting the cloud account *"will not affect your dynamic language model stored on your device"*. **[source]**

The one exception is a Microsoft-authored paper, *Privacy-Preserving Transformers: SwiftKey's Differential Privacy Implementation* (arXiv:2505.05648), which describes the **static** model (n-grams → GRUs → a scaled-down GPT-2, ~6 MB quantized, ONNX on device) and names the personal model twice only to exclude it:

> "it is compensated by the user dynamic vocabulary but **this is out of scope of this paper**."
> "the **dynamic user model starts to kick in after certain period and override the improvements from the static language model**."

**[paper]** That second sentence is the useful part — Microsoft states in a citable venue that the personal model eventually dominates the shipped model — but supplies no data structure, capacity, threshold, or eviction rule. Everything mechanistic is absent.

---

## Question 5 — What would it take to let learned words feed suggestions *and* autocorrection safely?

No implementation proposal here, per the brief. What follows is the trust model the evidence supports and the signals each level would need.

### 5.1 Three levels, not two

The brief asks for two levels of trust. The code (§1.5) shows there are three, and Dictus currently sits on the middle one:

| Level | What it means | Failure mode when wrong | Dictus today |
| --- | --- | --- | --- |
| **L1 — Offered** | The word appears in the suggestion bar. The user must tap it. | A junk row in the bar. Visible, ignorable, costless. | **Never granted** |
| **L2 — Immune** | Autocorrect will not rewrite this word. | A real typo silently survives forever, everywhere. Invisible to the user; no affordance to undo it. | **Granted on one use** |
| **L3 — Authoritative** | The keyboard rewrites *other* words into this one. | The keyboard corrupts text the user did not ask about. | Never granted |

Dictus grants L2 on the weakest evidence available and never grants L1. AOSP does the reverse: L1 from the second commit, L2 never (`isValidWord() → false`), L3 only through the shared scoring function where the 8192 floor keeps a learned unigram weak. HeliBoard grants a permanent L2+L3 through its tier-2 promotion at ~4 uses, behind an opt-in that is off by default.

**That HeliBoard's author shipped the only aggressive design in the field as opt-in and default-off is itself a data point about confidence.**

### 5.2 Signals, and which ones Dictus already has

| Signal | Discriminates | Available today? |
| --- | --- | --- |
| **In the base lexicon or not** | Ordinary vocabulary (category (a) in §1.4, the bulk of the store) from genuinely novel words | **Yes, free.** `AOSPTrieEngine.wordExists(_:)`. `recordUsage` does not ask. **[code]** |
| **Source: rejection vs. repetition** | An explicit act of correction from passive typing | Yes at the call site; **not recorded**. `recordUsage` cannot tell its two callers apart. 1 bit. **[code]** |
| **Occurrence count** | Repetition from accident | Yes — stored, but at `repetitionThreshold = 1` the pending store is structurally unreachable as a gate. **[code]** |
| **Distinct sessions / recency** | A word used across days from a burst of test typing in one field | **No.** Needs a timestamp. This is the signal that would have caught the #222 episode (test typos in a no-autocorrect field). |
| **Survived without being deleted** | A word the user kept from one they backspaced away | **No.** Needs a post-commit observation window. Note nobody in the field does this — AOSP and HeliBoard both explicitly punt on `EVENT_BACKSPACE`. |
| **Context (bigram) plausibility** | A word that fits the sentence from noise | **No.** This is #114's personal LM. |

The first two are the interesting ones: **both are already knowable at the moment of learning and neither is used.**

### 5.3 What each level would plausibly need

Framed as questions for the maintainer to decide, not as a design.

- **L1 (offered)** is cheap and low-risk, and the field agrees: AOSP grants it from the second occurrence. Its precondition is not a confidence signal at all — it is a **missing consumer**. No amount of tuning `repetitionThreshold` produces a suggestion; the `.completions` path has to learn to consult the user set alongside `UITextChecker`, and the `.predictions` path has to decide whether a learned word with no n-gram context can ever be predicted. That is real work and it is independent of the threshold question.
- **L2 (immunity)** is what Dictus grants today and is the level that most needs a gate, because it is the invisible one. On the evidence, the two cheapest gates that need no new stored data are: *is this word absent from the base lexicon* (otherwise immunity is meaningless — the `wordExists` guard already covers it), and *did this come from an explicit rejection or from passive typing*. A gate that needs new data — recency across sessions — is where the #222 class of accident actually gets caught.
- **L3 (authoritative)** is the only level where the field is unanimous in *not* trusting learned words on their own: AOSP reaches it only through a shared scoring function whose constants are chosen to keep learned unigrams weak. Getting there in Dictus means the unified candidate scoring of #114 item 3, not a threshold change. Until every candidate is scored on one scale, "let learned words autocorrect" has no safe implementation, because there is nothing to weigh them against.

### 5.4 The finding that most constrains the answer

**Nobody implements the categorical rule "suggestable but never allowed to autocorrect".** Both AOSP-lineage autocorrect gates were read directly and neither tests the source dictionary of the autocorrect target. Everywhere in the field, probation is probabilistic — a learned word that accumulates enough score becomes an autocorrect target — and it is enforced by *scoring*, not by *categorisation*.

If Dictus wants the categorical rule, it would be building something the field does not have. That may still be right for a keyboard with no unified scoring function, where a category is the only thing available to reason about. But it should be chosen with the knowledge that there is no implementation to copy and no shipped product to point at.

---

## What could not be established

Stated plainly, because these are answers, not gaps.

1. **Apple's post-learning policy.** Not publicly documented anywhere, including in the full Apple Platform Security guide. Threshold, capacity, decay and eviction are all absent. Only measurement could answer it, and measurement would be unsupported by contract.
2. **Whether `UITextChecker`'s learned dictionary is the same store as the QuickType keyboard dictionary**, and whether it is device-global or extension-local. Never stated, in either direction.
3. **Gboard's local personal-dictionary policy.** The architecture is sketched in one paper; no policy is published in any of the five.
4. **SwiftKey's mechanism.** Behaviour is well documented; the data structure, thresholds and eviction rules are documented nowhere, and Microsoft's own paper names the personal model only to declare it out of scope.
5. **WWDC content.** developer.apple.com no longer serves session transcripts in page HTML. Nothing in this document is sourced to a WWDC session.
6. **Whether any permissively licensed Swift/iOS learning engine exists.** The search found none, but this is an exhaustiveness claim and is held at medium-high confidence, not high.

---

## Which findings are load-bearing

The maintainer will pick a direction from this document, so this is the most important section.

**Safe to build on (read directly in source, cited by line):**

- Everything in §1. The single `isLearned` read site, the two no-op `injectUserWord` implementations, the three suggestion-bar modes and their data sources, the `wordWasEvaluated` gate, and the ascending-count eviction. All read in this repository.
- AOSP's two-occurrence probation, the `isValid = maxFreq > 0` lexicon check, `UserHistoryDictionary.isValidWord() → false`, the `ASSUMED_MIN_COUNTS` / `ENCODED_BACKOFF_WEIGHTS` constants, the 300-day discard, the LRU eviction, and the fact that `getDecayedProbability` is an identity function. All read in AOSP source at a named commit, Apache-2.0.
- HeliBoard's `> 120` promotion threshold and its full guard list. Read in source. GPL-3.0 — **design only, do not copy code**.
- The licence facts in every table. All fetched from licence files.
- `UILexicon`'s three documented sources, and the absence of learned words from that list. Quoted from Apple's documentation.
- Apple's documented trigger for the keyboard dictionary being *rejection*, "a few times". Quoted from Apple support pages.

**Not safe to build on:**

- **Any mechanism for Apple's post-learning policy.** There is none in this document, by design. If a future discussion needs one, it does not exist yet.
- **The claim that Apple learns in one shot.** The issue's premise. Contradicted by Apple's own documentation, and the observation behind it was a small number of device taps.
- **The derived AOSP probability values** (~111 for a count-1 unigram). The formula and constants are sourced; the arithmetic is mine. HeliBoard's author independently measured 111, which corroborates it, but treat the table as illustrative rather than as a specification.
- **"Nothing permissive exists in Swift."** An exhaustiveness claim. Medium-high confidence.
- **The characterisation of AOSP's forgetting curve as shipped behaviour.** It is dead code at HEAD (`WORD_LEVEL_FIELD_SIZE = 0`, no v4 callers). It is a good design and it does not run. Any document or article describing it as AOSP's live decay model is describing dead code.

---

## What contradicts the issue

Three things, all worth resolving before an implementation brief is written.

1. **"Apple probably also learns in one shot" is not supported by Apple's documentation.** Apple documents repeated rejection. See §4.1. This weakens the argument that a threshold of 1 is defensible by analogy, and points at the undo path rather than the repetition path as the closer analogue.
2. **"The mechanism currently has all of the cost and none of the benefit … it accumulates entries without improving suggestions."** True on the suggestion side, but incomplete: learning grants permanent autocorrect immunity, which is a real and invisible effect, not an absence of one. The feature is not inert. See §1.5.
3. **"A typo typed once is learned and kept" is narrower than stated.** A typo the corrector catches is corrected, not learned — unless the user undoes it, which is the intended strong signal. The false-learning surface is typos the corrector had no candidate for, plus everything the proper-noun guard preserves. See §1.4. The larger and unmentioned effect is that **every correctly-spelled word is also learned**, which fills the 1000-word cap with ordinary vocabulary and makes the ascending-count eviction drop personal names first.

---

## Sources

**Read as source code or licence files:**

- AOSP LatinIME — `android.googlesource.com/platform/packages/inputmethods/LatinIME`, tree `127336e9f29d69607eab55982324b210279ae8c5`. **Apache-2.0.**
- `android.provider.UserDictionary` — AOSP `platform_frameworks_base`. **Apache-2.0.**
- HeliBoard — `github.com/HeliBorg/HeliBoard` (moved from `Helium314/HeliBoard`). **GPL-3.0**, modified AOSP files `Apache-2.0 AND GPL-3.0-only`.
- FlorisBoard — `github.com/florisboard/florisboard`. **Apache-2.0.**
- FUTO Keyboard — `gitlab.futo.org/keyboard/latinime`. **FUTO Source First License 1.1-kb**, non-commercial, no sublicensing, MIT-incompatible.
- OpenBoard — `github.com/openboard-team/openboard`. **GPL-3.0.** Last commit 2022-12-17.
- Simple Keyboard (**Apache-2.0**), Thumb-Key (**AGPL-3.0**), Presage (**GPL-2.0**, no LGPL carve-out).
- `gdetari/SymSpellSwift` (**MIT**), KeyboardKit (**Closed Source**), Hunspell (**MPL 1.1 / GPL 2.0 / LGPL 2.1**), Nuspell (**LGPL-3.0**).

**Read as official documentation:**

- `UITextChecker`, `UILexicon`, `UILexiconEntry`, `requestSupplementaryLexicon(completion:)` — developer.apple.com.
- Archived App Extension Programming Guide, "Custom Keyboard" chapter — developer.apple.com/library/archive.
- support.apple.com: reset settings (`iphea1c2fe48`), text replacements (`iph6d01d862`), predictive text (`iphd4ea90231`), iCloud data security overview (`102651`).
- Apple Platform Security guide, March 2026 edition (full PDF, searched).
- Apple Differential Privacy Technical Overview.

**Read as papers:**

- Apple ML Research, "Learning with Privacy at Scale".
- Hard et al., "Federated Learning for Mobile Keyboard Prediction", arXiv:1811.03604.
- Chen et al., "Federated Learning of Out-of-Vocabulary Words", arXiv:1903.10635.
- Ouyang et al., "Mobile Keyboard Input Decoding with Finite-State Transducers", arXiv:1704.03987.
- Yang et al., "Applied Federated Learning", arXiv:1812.02903.
- "Federated Learning of Gboard Language Models with Differential Privacy", arXiv:2305.18465.
- "Privacy-Preserving Transformers: SwiftKey's Differential Privacy Implementation", arXiv:2505.05648.

**Not used as evidence:** no blog post, forum answer, press article or reverse-engineering write-up is cited anywhere in this document.
