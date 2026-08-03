# User-dictionary learning — research findings

**Issue:** [#287](https://github.com/getdictus/dictus-ios/issues/287)
**Scope:** research only. No production code, no change to `UserDictionary`, no change to `repetitionThreshold`, no implementation of [#114](https://github.com/getdictus/dictus-ios/issues/114).
**Status:** plan recorded, research in progress.

---

## 0. Plan (written before the research, per the brief)

### Question 1 — what a learned word does in Dictus today

Answered from the code in this repo, not from the issue body. Code paths to read, in order:

| Path | What it should tell us |
| --- | --- |
| `DictusCore/Sources/DictusCore/UserDictionary.swift` | The store itself: what is written, when, and what the read API exposes. |
| `DictusKeyboard/DictusKeyboardBridge.swift` (~line 495) | The repetition-learning write site, and what happens on the `true` return. |
| `DictusKeyboard/KeyboardRootView.swift` (~line 479) | The rejection-learning write site (undo path). |
| `DictusKeyboard/TextPrediction/SuggestionState.swift` (`learnWord`, ~line 337) | Whether `learnWord` reaches the prediction engine, and whether the effect survives a keyboard restart. |
| `DictusKeyboard/TextPrediction/TextPredictionEngine.swift` (~lines 97-230, 527) | The only `isLearned` read site. Where it sits in the pipeline, what it gates. |
| `DictusKeyboard/TextPrediction/AOSPTrieEngine.swift` | Whether the trie has any notion of a user word, or whether the user set is bolted on outside it. |
| `DictusKeyboard/KeyboardViewController.swift` (~line 476) | When the in-memory cache is reloaded across processes. |
| `DictusApp/Views/SettingsView.swift` (~lines 197-206) | The app-side consumer (reset UI), for completeness. |

The specific thing to settle: the suggestion bar is a **different** consumer from the spell-checker. `isLearned` appears once, inside `spellCheck`. If the suggestion bar is fed by a prediction path that never consults the learned set, that alone explains the maintainer's device observation. Confirm or refute by reading the suggestion-bar data source end to end, not by inference from the grep.

### Questions 2-4 — external sources

Primary sources only. Named up front so the document can be checked against them:

- **AOSP LatinIME** — `android.googlesource.com/platform/packages/inputmethods/LatinIME`. Specifically `UserHistoryDictionary`, `DecayingExpandableBinaryDictionaryBase`, `DynamicLanguageModelProbabilityUtils`, `ExpandableBinaryDictionary`, `DictionaryFacilitator`, and the native `dicttoolkit` / `ver4` header that owns the decay constants. Licence: Apache-2.0.
- **HeliBoard** — `github.com/Helium314/HeliBoard`, the actively maintained AOSP fork. Licence: GPL-3.0 (relevant: **not** reusable in an MIT repo).
- **FUTO Keyboard** — `gitlab.futo.org/keyboard/latinime`. Licence to be checked; FUTO uses a source-available licence that is probably not OSI-permissive.
- **FlorisBoard** — `github.com/florisboard/florisboard`, its `nlp` module. Apache-2.0.
- **Apple** — developer.apple.com only: `UITextChecker` (`learnWord(_:)`, `hasLearnedWord(_:)`, `unlearnWord(_:)`), `UILexicon` / `requestSupplementaryLexicon(completion:)`, `UITextInputTraits.autocorrectionType`, and anything in the Apple Platform Security guide or the Differential Privacy Overview about keyboard learning. Apple's *policy* is expected to be undocumented; that will be reported as such.
- **Google / Gboard** — published papers, not blog posts: the federated-learning line of work (Hard et al., "Federated Learning for Mobile Keyboard Prediction"; Chen et al., "Federated Learning of Out-of-Vocabulary Words"; Ouyang et al., "Mobile Keyboard Input Decoding with Finite-State Transducers"). These describe Google's *server-side/federated* learning, which is a different problem from an on-device personal dictionary — that distinction has to be stated, not blurred.
- **SwiftKey** — expected to have no primary source. Will be reported as unknown rather than filled in from press coverage.

### How this document stays honest about evidence

Every claim carries one of four labels, and the label is part of the claim:

- **[code]** — read in this repo at a cited file and line. The strongest evidence here.
- **[source]** — read in a named third-party source file or official API reference, cited by URL.
- **[paper]** — a published, peer-reviewed or arXiv paper, cited by title and identifier.
- **[secondary]** — blog post, forum answer, press article, or reasoning by analogy. Context only. **Nothing labelled [secondary] may be used as the basis for an implementation decision.**

Where a question has no answer, the document says "not publicly documented" and stops. Where a technique needs data Dictus does not store, the document names the data and estimates its cost against the extension's ~50 MB ceiling.

### If the brief turns out to be wrong

The brief assumes the maintainer's device observation ("learned but never suggested") needs explaining. If the code shows the learned set *does* reach the suggestion bar, that is a finding that changes the issue, and it gets reported as such rather than argued away.
