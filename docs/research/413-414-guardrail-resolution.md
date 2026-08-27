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
111 outputs — 28 Notes (round 1) + 25 Notes v2 (round 7) + 36 Translate → EN (round 2) + 12 free
polish and 10 rejected engine outputs (rounds 3, 4 and the `engineOut` lines). Each is
hand-labelled `sameLanguage` / `bilingual` / `wrongLanguage` and `grounded` / `fabricated`, by
reading, with the label written into the committed file so anyone can disagree with it in the open.

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

*(written after the run)*
