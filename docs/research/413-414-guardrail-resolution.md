# Closing the two guardrail holes #393 found

**Issues:** [#413](https://github.com/getdictus/dictus-ios/issues/413) (the language check is
blind to bilingual output), [#414](https://github.com/getdictus/dictus-ios/issues/414) (a prompt's
worked example was copied into the user's output)
**Where they came from:** [#393](https://github.com/getdictus/dictus-ios/issues/393) / PR #412 —
30 Notes calls against Apple FM, raw outputs committed under `docs/research/79-smart-modes/raw/`
**Date:** 2026-08-27

> **§0–§4 below were written and committed BEFORE the corpus was scored and before the first
> Apple FM call of this run.** That is PR #388's and PR #412's discipline, and it is the only
> reason a threshold reported here is worth anything: the bars cannot move to meet the result.
> Everything from §5 on was written after.

---

## 0. Why the two ship together

They edit the same file and they ask it the same question: **look inside the output at a finer
resolution than the whole blob.** #413 segments it for language; #414 compares it to the input for
content. Doing one without the other means opening `PolishGuardrail.swift` twice with the same
question.

## 1. What is broken, in one line each

**#413.** `PolishGuardrail.detectedLanguageMatches` runs `NLLanguageRecognizer` over the whole
output. That answers *"what is the dominant language of this text"*, and a list that drifts item by
item keeps its aggregate reading. Measured in round 1: an output of 5 English bullets + 1 French
read as **French at 0.789** and was **accepted**; a wholly-English one on the same fixture read as
**English at 0.607** and was correctly rejected. The more broken output is the one that got
through.

**#414.** `SmartModeNotesPrompt` carries a worked example whose output contains
`- Appeler Sophie avant : elle a les données de décembre`. That exact line appeared in an
**accepted** output on a dictation that names neither Sophie nor December. Neither guardrail can
see it: a fabricated bullet is the same length as a real one, and it is in the target language.

## 2. Who consumes `PolishGuardrail`, and what a wrong answer costs them

`PolishGuardrail` has exactly one caller: `PolishPipeline.transform`, at two sites (the length
band, then `languageGuardrailPasses`). `transform` in turn is reached by:

| Consumer | Path | Cost of a WRONG REJECTION | Cost of a WRONG ACCEPTANCE |
|---|---|---|---|
| Free polish, in DictusApp (`PolishService.polishTargeted` / `polishAutoDetected` ← `PolishCoordinator`) | every dictation with polish on | **Low.** `resolvedOutput` returns the deterministic floor — the user's own words with verbal punctuation applied, merely unpolished | Low. ADR 0003 output is close to the input by construction |
| Free polish, in the keyboard extension (since #361) | every dictation | same as above | same as above |
| A Smart Mode | every armed dictation | **High.** `resolvedOutput` returns `nil` and **nothing is inserted**. The user speaks, waits, and gets a red message | **High.** Invented content, or the wrong language, lands in a document they are about to send |
| `polish-harness` | measurement only | none | none |

**The asymmetry is the whole design constraint, and it runs the opposite way to intuition.** A new
check is *cheapest* to get wrong on free polish — which is where it runs on every user — and
*most expensive* on the Smart Mode that needs it. So a check that cannot be made false-positive-free
on the mode corpus must not ship on the mode, whatever it buys.

## 3. What each new check does when it is uncertain

#79's fail-closed guarantee cuts both ways: a wrong rejection loses the user's words, a wrong
acceptance puts invented content in their document. Every uncertainty branch is therefore written
down here, before the code exists.

**#413, the per-segment language check.**
- Segment too short to read → **pass**. Same philosophy as today's 12-character floor: acting on
  an unreliable detection is worse than not acting.
- Segment read with low confidence → **pass**. 0.789 was a *confident wrong* answer, so a floor
  alone never was the fix (#413 says so); the floor exists only to stop the check firing on noise.
- Recogniser returns nothing → **pass**.
- Only a **confident disagreement** rejects. Uncertainty is always resolved toward accepting.

**#414, the grounding check.**
- The output's language is not the input's (translation, repair) → **the check does not run at
  all.** A translation localises names, months and weekdays by design, so surface identity is not
  expected and the check would be measuring the wrong thing.
- No anchor found in the output → **pass** (vacuously). This is a real limit and §6 states it: a
  refusal carrying no name and no figure is invisible to this check, which is why #349 needs the
  *second* query over the same primitive rather than this one.
- An anchor found but the input cannot be normalised for comparison → **pass**.
- Only an anchor that is **present in the output and absent from the input** rejects.

## 4. The bars, pre-registered

Fixed before scoring. The mechanism and its parameters are what the measurement chooses; **these
are not negotiable by the result.** If a mechanism cannot clear them, it is reported as failing,
not relaxed.

### The corpus

Every output committed by the #393 campaign, extracted from
`docs/research/79-smart-modes/raw/` and committed here as `413-414-guardrail/corpus.json`:
**110 outputs** — 30 from round 1 (Notes), 30 from round 2 (Translate → EN), 29 from round 7
(Notes v2), 10 from round 3 and 11 from round 4 (the free-polish/mode A/B passes). Accepted and
rejected engine outputs alike, since a check has to keep the rejections rejected.

Round 4 contributes 11 of its 12 recoverable outputs: the free-polish side of `T3` is excluded
because Italian on the French per-language path is skipped by the gibberish gate, so **the
guardrail never ran on it** and scoring it would score a code path that does not exist.

Each output is hand-labelled `sameLanguage` / `bilingual` / `wrongLanguage` and `grounded` /
`fabricated`, by reading, with the label written into the committed file so anyone can disagree
with it in the open. (The count in the first draft of this paragraph was 111 with a per-round
breakdown that was written before the corpus existed and never corrected; found in review.)

Plus an adversarial set written by hand for the cases the campaign does not contain — a French
list quoting English product names, a German list (where every noun is capitalised), a one-bullet
output, an output of pure proper nouns.

### #413

| | Bar | Threshold |
|---|---|---|
| **G1** | The N3 run-3 output (5 English bullets + 1 French) is **rejected** | absolute |
| **G2** | Every output already rejected by the shipping check stays rejected | absolute |
| **G3** | Every output hand-labelled `sameLanguage` is **accepted** | **0 false rejections**, absolute |
| **G4** | The adversarial French-list-quoting-English set is accepted | **0 false rejections**, absolute |
| **G5** | Free polish, single-passage output: behaviour byte-identical to today | pinned by a unit test |

### #414

| | Bar | Threshold |
|---|---|---|
| **F1** | The N2 run-5 output (`Sophie` / `décembre`) is **rejected** | absolute |
| **F2** | Every output hand-labelled `grounded` is **accepted** | **0 false rejections**, absolute |
| **F3** | The check does not run where it is unsound, and the code says why | by reading |
| **F4** | Recall is **reported, not gated**: how many hand-built fabrications it misses | reported |

F4 is deliberately not a gate. A precision-first check that catches the measured case and never
rejects a good output is worth shipping even at poor recall; a recall-first one that costs a user
their dictation is not. Stating this before the numbers exist is the point.

### Both

| | Bar | Threshold |
|---|---|---|
| **H1** | The rejection rate on `polish-harness`'s shipping fixtures does not rise, except on the outputs the checks are built to catch | absolute |
| **H2** | `cd DictusCore && swift test` green, `swiftlint lint --strict` clean | absolute |

## 5. The mechanisms, and the ordered changes

Written before the measurement; §6 reports whether they held.

1. **`PolishGuardrail` gains a segment-aware language check.** Split the output on line breaks
   (after `decodeNewlines`, one bullet is one line), run the recogniser per segment, reject on a
   confident disagreement. The whole-blob check stays, because it is what catches a wholly-wrong
   single passage. Two parameters — minimum segment length, and the confidence floor at which a
   disagreement counts — are chosen by scoring the corpus, not guessed.
2. **`PolishGuardrail` gains a grounding check**, built on `NLTagger`'s `.nameType` scheme rather
   than on a capitalised-token heuristic. The heuristic is not merely worse, it is unusable: German
   capitalises every noun, so it would flag `Rechnung`, `Büro` and `Freitag` in an ordinary German
   sentence. `NLTagger` reads the same sentence and returns only `Herr Müller`.
3. **`PolishAcceptanceContract` gains a field** saying whether its outputs are subject to the
   grounding check — a field rather than a derivation, for the reason `SmartModeOverflowBehaviour`
   is one: a custom mode (#269) must answer the question rather than inherit an answer from a
   property chosen for something else. It decodes with a **default of off**, because the record
   crosses the App Group inside the per-dictation snapshot and an app update can land between the
   write and the read; off means one dictation across one upgrade behaves as it does today, where
   on could cost that dictation its text.
4. **`PolishPipeline` dispatches the new check** off that field, next to the language dispatch it
   already does.
5. **Tests.** `PolishGuardrail` is pure logic; every case above gets one, with the measured
   strings from the campaign rather than invented ones.
6. **A harness command** that scores the committed corpus offline, so the measurement is
   re-runnable by anyone — it drives no model and needs no Apple Intelligence.

### Risks

- **The grounding check's false-positive rate is the shipping risk.** It is the only new way for a
  user to lose a dictation. F2 is absolute for that reason.
- **`NLTagger` recall is context-sensitive.** The probe already shows `Thomas` recognised on its
  own line and missed inside the same six-line block. Running the tagger per segment as well as
  whole is the mitigation; what it still misses goes in §6.
- **Digits as an anchor are likely unusable and will be measured anyway.** ADR 0003 rule 3
  authorises free polish to turn spoken numbers into digits, and round 3 shows it doing exactly
  that (`eighteen` → `18`, `8000` → `8 000`). A digit anchor would reject those. Measured, then
  reported, then almost certainly dropped.
- **German is unmeasured by the campaign.** No German fixture exists. `NLTagger` is the choice
  that makes German *safe by construction* rather than by measurement, and that gap is stated
  rather than papered over.
- **A prompt example that carries no name and no figure stays invisible.** This closes the
  measured hole, not the class.

## 6. Results

**160 Apple Foundation Models calls** on this Mac (macOS 26.5.1), plus **128 hand-labelled
outputs replayed offline** through the two checks. Every raw output is committed under
`413-414-guardrail/raw/`. The offline replay is the load-bearing measurement and it drives no
model, so anyone can re-run it:

```sh
cd DictusCore
swift run polish-harness guardrail ../docs/research/413-414-guardrail/corpus.json \
                                   ../docs/research/413-414-guardrail/adversarial.json --sweep
```

### 6.1 #413 — every bar cleared

| Bar | Threshold | Measured | |
|---|---|---|---|
| **G1** the 5-English-plus-1-French output is rejected | absolute | rejected | ✓ |
| **G2** outputs already rejected stay rejected | absolute | 10/10 | ✓ |
| **G3** every `sameLanguage` output accepted | 0 false rejections | **0 / 117** | ✓ |
| **G4** the French-list-quoting-English set accepted | 0 false rejections | **0 / 9** | ✓ |
| **G5** free polish single passage unchanged | pinned by a test | pinned | ✓ |

**The two thresholds sit in an empty band 0.42 wide.** Over 273 segments:

| | worst case |
|---|---|
| A **legitimate** segment read as the wrong language | `Checker le build sur GitHub Actions` — **en 0.504** |
| A genuinely **drifted** segment, weakest reading | `Total 3 major changes` — **en 0.927** |

Only 3 of 219 legitimate segments disagreed with their expected language at all, and the other two
were at 0.220 and 0.164. The sweep gives `11 caught / 0 false rejections` for **every** pair from
(12 chars, 0.60) to (40 chars, 0.95), so the choice of (12, 0.85) is not balanced on a knife edge.
The floor sits near the top of the band rather than its middle, deliberately: too high leaves
today's behaviour, too low costs a Smart Mode user everything they said.

**What #413 predicted and the measurement confirmed.** Raising the confidence floor alone was
never the fix. The accepted bilingual output reads as French at **0.789** as one blob — a
*confident wrong* answer — so no floor low enough to be useful rejects it. Read line by line the
same text is `fr 1.000`, then `en 0.992 / 0.988 / 0.908 / 0.961 / 0.999`.

**Sentence-level segmentation was measured and is not what ships.** It buys nothing on this corpus
and spends the confidence floor on segments too short to read.

### 6.2 #414 — the check ships, and its first acceptance criterion is NOT met

| Bar | Threshold | Measured | |
|---|---|---|---|
| **F1** the `Sophie` / `décembre` output is rejected | absolute | rejected | ✓ |
| **F2** every `grounded` output accepted | 0 false rejections | **0 / 83** | ✓ |
| **F3** the check is off where it is unsound, and the code says why | by reading | Translate and Repair, with the reason on each | ✓ |
| **F4** recall, reported not gated | reported | **7 / 9** | — |

Two of the nine were added in review and are described in §6.5. The two **misses** are the whole
story of this issue, and one of them was not predicted.

**Miss 1, declared in advance.** #349's refusal — *"Je suis désolé, mais je ne peux pas fournir une
sortie polie…"* — carries no person, place or organisation, so a check built on grounded anchors
has nothing to look at. Named in §4 before the run as expected to be missed.

**Miss 2, found LIVE during this verification, and it changes the verdict.** The 30-call Notes run
made to check this change **reproduced the Sophie fabrication**, with one clause reworded, and the
shipped check **accepted it**:

```
committed (round 1)   - Appeler Sophie avant : elle a les données de décembre        → NLTagger tags Sophie
live      (this run)  - Appeler Sophie avant parce qu'elle a les données de décembre → NLTagger tags NOTHING
```

Same name, same position in the bullet, same language. A different continuation. No framing
recovers it: the tagger was run over the whole output, over each line with its list marker, and
over each line without, and none of the three finds it.

So: **#414's acceptance criterion 1 — "No prompt example can appear in output without appearing in
the input" — is not met, and this run has a live counterexample rather than a theoretical one.**
The case is committed as `Z1-sophie-reoccurrence` and pinned by a test that asserts the miss on
purpose, so the next attempt is scored against it from the first line of code.

**Why `NLTagger` and not capitalised words.** German capitalises every noun. On
`Die Rechnung für das Büro muss bis Freitag bezahlt werden` a capitalised-token heuristic proposes
`Rechnung`, `Büro` and `Freitag` and refuses an ordinary German note; the tagger returns
`Herr Müller` and nothing else. The #393 campaign measured no German at all, so the primitive had
to be safe there by construction rather than by measurement.

**Figures were measured as a second anchor kind and dropped.** ADR 0003 rule 3 authorises the
polish to turn spoken numbers into digits, and round 3 shows it doing exactly that —
`the build image is on eighteen` came back as `on 18`, and `8000` as `8 000`. A figure anchor
rejects a correct transformation. Same for a translation: `alle undici` becomes `at 11`. This is
the half of the maintainer's hypothesis that does not survive contact with the corpus.

**A capitalised-token rule WAS measured as an addition, and does not ship.** It closes the live
miss — one more catch — at the cost of **2 false rejections in 82**, both flagging
`February` / `March` on French dictations. Two things are true about them and neither rescues the
rule: those two outputs are rejected by the language check anyway, so no user would see the
refusal; and the same rule flagged `Finir` in a perfectly good French bullet under the other
colon-handling variant, which is a mechanism, not an accident. **F2 was pre-registered as
absolute, and §4 says a mechanism that cannot clear a bar is reported as failing rather than
relaxed.** The numbers are here so the maintainer can overrule that, which is their call and not
this PR's.

### 6.5 Two holes in the matching, found in review

CodeRabbit's review of PR #442 found the anchor matching too loose in two ways, and both were real:

- **`Alice Smith` was grounded by an input naming an unrelated `Alice` and an unrelated `Smith`**
  in different clauses. The first version asked only that every word of an anchor appear
  *somewhere*, so the model could compose a person nobody named out of two who were.
- **`Paul` was grounded by an input containing only `Pauline`**, because the match allowed a prefix
  in either direction. A fabricated name that happens to be a prefix of a real one is precisely the
  shape this check exists to catch.

Matching is now an **ordered, contiguous** sequence over the input's words, with one bounded
allowance: a non-final word of a multi-word anchor may carry one extra trailing letter, which is
there for German declension (`Herr Müller` against `Herrn Müller`) and cannot reach a single-word
anchor. Three cases were added to the corpus — the two failures and the counter-test that the same
full name, adjacent and in order, is still accepted — so they are scored rather than argued.

**`NLTagger`'s recall gap turned up again while writing those tests**, and is worth recording: the
French tagger does not fire on `Paul`, `Paul Durand` or `Marion` in an ordinary bullet, while it
fires on `Alice Smith`. A test of the matching routed through extraction would have passed while
asserting nothing, so the matching rule is tested through an explicit seam and the extraction
recall is pinned separately.

### 6.3 Both — the live suites

| suite | calls | outcome | #393 baseline |
|---|---|---|---|
| Notes, `notes-fr.json --runs 5` | 30 | 20 success, 10 `rejectedGuardrail` | 24 success, 6 rejected |
| Translate → EN, `translate-en.json --runs 5` | 30 | **30/30 success** | 30/30 success |
| Free polish, `seed.json --runs 5` | 70 | 65 success, 5 rejected | — |
| Free polish auto path, `auto.json --runs 3` | 30 | **30/30 success** | — |

**H1 holds, and the honest reading of the Notes row is that the rise is not this change.** All 10
rejections were scored against the whole-output check on its own: **10 of 10 were already caught
by it**, and the per-segment pass added **zero** rejections across the 160 live calls. The move
from 6/30 to 10/30 is a different draw of a non-deterministic model — N3 drifted 5/5 this time
against 2/5 in round 1. The evidence for #413 is the corpus replay, where the one measured
*accepted* bilingual output lives; the live run simply never produced that shape again.

**The 5 free-polish rejections are the documented DE-Repair Polish leak**, not this change. ADR
0002's 2026-06-08 update describes it exactly: cross-lingual reconstruction into German from a
Romance input reproducibly leaks Polish, the language guardrail catches it, the user gets the raw
fallback. The fixture is `7-repair-de`, the mode is `repair`, and grounding is deliberately **off**
for repair. **Zero of the 100 free-polish calls were rejected by anything this PR added.**

### 6.4 What the checks cost

Measured on this Mac over a 395-character, 7-bullet output against a 656-character input:

| | per call |
|---|---|
| language check, whole output only (before) | 1.17 ms |
| language check, whole + per segment (after) | 6.13 ms |
| grounding check | 2.52 ms |

**About 7.5 ms added**, against an engine call measured here at 1.1–3.1 s: a fifth to two thirds of
one percent. Like every other figure in the #393 campaign, this is a Mac reading and not a device
one — but the checks are pure `NaturalLanguage` calls with no model load, and they run in the
keyboard extension since #361, so the order of magnitude is what matters and it is small.

## 7. Verdict, and what is still open

**#413 is closed.** The measured hole is shut, every bar cleared with margin, and the thresholds
sit in an empty band rather than on a boundary.

**#414 ships a real improvement and does not close.** It rejects the fabrication that was measured
and six of six hand-built ones, with zero false rejections in 83 outputs and 160 live calls. It
misses the same fabrication when the model rewords one clause. That is `NLTagger`'s recall, not a
tuning parameter, and no framing of the input recovers it.

Two things follow, and both are the maintainer's to decide:

1. **The capitalised-token rule is the cheapest next step** and its cost is measured above: 6/7
   one more catch, 2 false rejections in 82, both on outputs the language check already refuses.
2. **#414's own second proposal — neutralising the prompt's worked examples — is deliberately not
   done here.** `SmartModeNotesPrompt` carries the example that was copied, and replacing its
   named person and concrete facts would attack the measured failure at its source. It is not done
   because **a cut decision on Notes is pending on PR #412's measurement, and changing the prompt
   underneath that decision invalidates the evidence it rests on.** #388 also found that examples
   measurably improve output shape, so the change would need its own 30-call run before anyone
   could say it was free. It is a follow-up with a reason, not an omission.

**What #349 inherits.** `PolishGrounding` is the type it asked for, with the tokeniser and the
normalisation it needs. Its question is the *second* query over the same tokens — how much of the
output's vocabulary appears in the input at all — and it is deliberately not written here: it has
no consumer yet, and its threshold has to be sized against a fixture set of refusals that does not
exist. The exclusion of `repair` from the grounding check is written down with #349 named, so the
next person does not read it as an oversight.
