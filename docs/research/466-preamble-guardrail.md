# Refusing an output whose head is not the user's words

**Issues:** [#466](https://github.com/getdictus/dictus-ios/issues/466) (a chat preamble was typed
into the user's document), [#349](https://github.com/getdictus/dictus-ios/issues/349) (an Apple FM
refusal was inserted as the user's dictation, absorbed here)
**Where they came from:** #466 captured on device during the #456 validation, App 1.8.1 (28);
#349 captured on device 2026-08-12, build 1.8.0 (26)
**Scope:** the "Scope, decided 2026-09-02" section of #466, settled in a grilling session with the
maintainer. That section is the spec; everything above it in the issue is evidence.
**Date:** 2026-09-02

> **§0–§5 below were written and committed BEFORE the detector existed and before the corpus was
> scored.** That is the discipline PR #388, PR #412 and PR #442 established, and it is the only
> reason a threshold reported here is worth anything: the bars cannot move to meet the result.
> Everything from §6 on was written after.

---

## 0. Why the two ship together

They are one phenomenon seen from two ends: **the model talks about its own task, and it lands in
the user's document.** Same engine, same blind spot. Both pass the length band (1.60 and 2.93,
inside their modes' bands), and both pass `detectedLanguageMatches` because a model instructed to
write French refuses in French. One detector, one PR. #349 is closed pointing here.

## 1. What is broken, in one line each

**#466.** Apple FM prefixed the polished text with
*"Bien sûr, je vais vous aider à polir votre texte. Voici la version polie :"* and the keyboard
typed all of it. `outcome = success`, ratio 1.60, every segment French. Two of the five formulas
`PolishNaturalPromptFR.swift:24` names as forbidden appear in the first six words, so the prompt
route is not an untried cheaper option — it is in production and measurably bypassed.

**#349.** Apple FM answered *"Je suis désolé, mais je ne peux pas fournir une sortie polie pour ce
texte…"* to a gibberish dictation, and that apology was inserted in place of the user's words with
`outcome = success`. It carries no person, place or organisation, so `PolishGrounding` — the type
built for #414 — has nothing to look at, which that type's doc already states.

## 2. Who consumes what is being changed, and what a wrong answer costs them

`PolishGuardrail` and `PolishGrounding` have exactly one caller between them:
`PolishPipeline.transform`, at three sites. `transform` is reached by:

| Consumer | Path | Cost of a WRONG REJECTION | Cost of a WRONG ACCEPTANCE |
|---|---|---|---|
| Free polish in DictusApp (`PolishService.polishTargeted` / `polishAutoDetected`) | every dictation with polish on | **Low.** `resolvedOutput` returns the deterministic floor — the user's own words, verbal punctuation applied, merely unpolished | the defect this PR exists to stop |
| Free polish in the keyboard extension (since #361) | every dictation | same as above | same as above |
| A Smart Mode | every armed dictation | **High.** `resolvedOutput` returns `nil` and nothing is inserted | high |
| `polish-harness` | measurement only | none | none |

**The new check runs only in the first two rows.** That is not a convenience: it is what makes the
mechanism shippable at a false-positive rate that would be unacceptable on a Smart Mode. The
asymmetry is the same one §2 of `413-414-guardrail-resolution.md` records, used deliberately.

## 3. The decisions taken in the grilling session, restated so the code can be read against them

1. **Reject, never repair.** The guardrail refuses and the user keeps their raw text; it does not
   strip the preamble and keep the rest. A post-pass that cuts the head of an output can cut a real
   sentence of the user's, which ADR 0003 forbids and #441 has just banned explicitly. A preamble
   is rare; a wrong cut is permanent.
2. **Prefix alignment, and no lexical list in any language.** The test is comparative, so nothing
   is maintained per language and nothing rots. A per-language meta-discourse list was weighed and
   rejected on maintenance grounds even though the polish layer supports only four languages
   (`SupportedLanguage.swift:13`).
3. **Active per contract, not globally.** The check runs only where the transformation preserves
   order: Natural, Auto, Repair. It is inert for List and Translate — List restructures into
   bullets, Translate keeps no word of the input, and prefix alignment is meaningless for both.
4. **Accepted hole, stated on purpose.** A chat preamble inside a List or Translate output is seen
   only by `PolishGrounding`, therefore only if it invents a named entity. It goes in the new
   type's doc comment, where the next reader finds it. #349 was captured in `repair`, which is
   covered.
5. **The threshold is measured, not chosen.** Swept over the committed corpus with a command that
   drives no model.

## 4. What the check does when it is uncertain

Written before the code exists, in the shape §3 of the #413/#414 doc uses.

- Input or output too short to carry a head → **pass**. A five-word dictation has no prefix to
  align.
- The input's head is found at the very start of the output → **pass**, which is the ordinary case.
- The input's head is found late, or nowhere → **reject**. This is the only branch that refuses.
- The task's contract does not claim to preserve order → **the check does not run at all.**

Every uncertainty resolves toward accepting, for the reason it does everywhere else in this file's
neighbourhood: a rejection is a user losing something.

### The bars, pre-registered

Fixed before the detector was written. **These are not negotiable by the result.** A mechanism that
cannot clear them is reported as failing, not relaxed. Each maps to an acceptance criterion of
#466's Scope section.

| | Bar | Threshold |
|---|---|---|
| **P1** | The captured #466 preamble output is **rejected**, and `resolvedOutput` hands back the deterministic floor | absolute |
| **P2** | The #349 refusal capture is **rejected by the same code path** | absolute |
| **P3** | No legitimate free-polish output in the corpus is rejected | **0 false rejections**, absolute |
| **P4** | The two thresholds are read off a sweep, and the table is in the PR | by reading |
| **P5** | The check is **inert** for List and Translate, proven by a test | by test |
| **P6** | The refusal is distinguishable in the debug event from the other three guardrail refusals | by test |
| **P7** | `cd DictusCore && swift test` green, `swiftlint lint --strict` clean, the three targets build | absolute |

P3 is the shipping bar. It is stated over free-polish outputs specifically, because those are the
only ones the check ever runs on (§3.3), and the number is only meaningful on the base §5.2.6
builds.

Two of #466's acceptance criteria are **not** verifiable here and are not claimed: *"the captured
raw, run 10 times, never returns a preamble"* and *"the rate is measured before and after on the
#456 transcript"* both need Apple Foundation Models driven repeatedly, which is a device or a
maintainer's Mac, not this branch's CI-shaped verification. They go on the manual list in the PR.

## 5. The mechanism, and the ordered changes

### 5.1 The measurement

A faithful polish preserves order (ADR 0003 forbids reordering), so the opening of the output has
to be the opening of the input, modulo the removals the contract licenses — fillers, stutters,
spoken punctuation commands.

Let `inputHead` be the first `windowWords` words of the input, normalised to lowercased,
diacritic-folded letter/number runs. Slide a window of the same size along the output's words and
find the **earliest offset** whose word set shares at least `overlapFloor` of `inputHead`. That
offset is where the output starts tracking the input.

| | reads as | verdict |
|---|---|---|
| ordinary polish | offset 0, or a small offset after a deleted filler | accept |
| **#466**, a preamble | alignment starts late | reject |
| **#349**, a refusal | no alignment anywhere | reject |

Two thresholds — `maximumOffsetWords` and `overlapFloor` — are what the sweep chooses.
`windowWords` is held fixed and its sensitivity reported rather than swept into the grid, so the
table stays readable; a window has to be long enough that a couple of substituted words cannot sink
it and short enough to fit a short dictation.

**No stop-word list, no meta-discourse list, nothing per language.** The comparison is between two
texts the user's own dictation produced.

### 5.2 The ordered changes

1. **`PolishPrefixAlignment`**, a new type in `DictusCore/Polish/`, with its thresholds struct
   beside it — the shape `PolishLanguageSegmentThresholds` established. It answers
   `alignmentOffset(of:against:)` and the yes/no the pipeline asks. Its doc comment carries the
   accepted hole from §3.4.
2. **`PolishAcceptanceContract` gains `preservesOrder`** — a field, not a derivation, for the
   reason `requiresGroundedNames` is one: a custom mode (#269) must *answer* the question rather
   than inherit an answer from a property chosen for something else. It decodes with a default of
   **false**, the safe half, because the record crosses the App Group inside the per-dictation
   snapshot and an app update can land between the write and the read.
   Natural, Repair and Auto answer `true`; List and Translate answer `false`.
3. **`PolishPipeline` dispatches the new check** off that field, beside the three it already
   dispatches, and names it in the rejection log.
4. **The refusal is recorded in the debug event.** `outcome = rejectedGuardrail` says a check
   failed and never which one — there will be four. `PolishPipeline.Result` carries the name of
   the check that refused, `PolishMetrics` records it, and the JSON export carries it, so the rate
   of this refusal is countable after the fact from an export alone. This also retroactively makes
   the three existing checks countable, which costs one field rather than four.
5. **The two captures join the corpus.** The #466 preamble output and the #349 refusal output, raw
   and polished verbatim from the issues, into
   `docs/research/413-414-guardrail/adversarial.json` — the file whose stated job is the cases the
   #393 campaign does not contain.
6. **A legitimate free-polish base, from committed evidence.** The corpus is 128 outputs of which
   only **14** are free polish; the other 114 are List and Translate outputs, where this check is
   inert by §3.3. Fourteen is too thin a base to say "no legitimate output is refused" and mean
   anything by it. The free-polish pairs already committed under
   `docs/research/413-414-guardrail/raw/` are added to the same file, verbatim, so the
   false-rejection number is read off a base that can carry it.
7. **The harness scores and sweeps it**, in the `guardrail` command, next to the two checks it
   already scores. It drives no model.
8. **Tests**, with the measured strings from the two captures rather than invented ones, including
   the inertness of the check for List and Translate — proven by a test, not by inspection.

### 5.3 Risks, stated before the numbers exist

- **A legitimately repaired head reads exactly like a preamble.** ADR 0003 rule 8 authorises the
  model to reconstruct an off-language fragment, and `docs/research/456-target-election/capture-run.md`
  measures it doing so on the whole English head of the #456 transcript, 5 runs out of 5. That
  output's head shares no vocabulary with its input's head, which is the shape this check refuses.
  It is the mechanism's main false-positive source, it is measured in §6 rather than argued, and
  the mitigation is §2: on free polish a wrong rejection costs the polish, never the words.
- **A dictation that opens with a long deleted filler run** shifts the alignment offset. This is
  what `maximumOffsetWords` is for, and what the sweep sizes.
- **The free-polish base is small even after §5.2.6**, and it is French-dominated. German and
  Spanish free-polish outputs do not exist in this repository's committed evidence. The check is
  language-agnostic by construction, which is the same defence `PolishGrounding` used for German,
  and it is a defence and not a measurement.
- **The accepted hole is real**: nothing here protects a List or a Translate output from a
  preamble.
- **This closes a measured shape, not a class.** A model that talks about its task *after* the
  user's text, or in the middle of it, is invisible to a prefix check.

## 6. Results

**230 hand-labelled outputs replayed offline.** No model was driven: every check here is a
deterministic local call, which is what makes the numbers re-runnable by anyone, with or without
Apple Intelligence.

```sh
cd DictusCore
swift run polish-harness guardrail ../docs/research/413-414-guardrail/corpus.json \
                                   ../docs/research/413-414-guardrail/adversarial.json \
                                   ../docs/research/413-414-guardrail/freepolish.json --sweep
```

The corpus grew from 128 to 230: the two device captures (§5.2.5) and the 100 free-polish outputs
harvested verbatim from `raw/` (§5.2.6). Of the 230, **106 are free polish**, which is the only
place this check runs — against 14 before.

### 6.1 The bars

| Bar | Threshold | Measured | |
|---|---|---|---|
| **P1** the #466 preamble is rejected and the user keeps their raw text | absolute | rejected, floor returned | ✓ |
| **P2** the #349 refusal capture is rejected by the same code path | absolute | **rejected by the check, and the check does not run on the mode it was captured in** | ✗ — §6.3 |
| **P3** no legitimate free-polish output is rejected | 0 false rejections | **0 / 102** on Natural + Auto | ✓ |
| **P4** the thresholds are read off a sweep | by reading | §6.2 | ✓ |
| **P5** the check is inert for List and Translate | by test | two tests, each with an explicit precondition that the check *would* refuse | ✓ |
| **P6** the refusal is distinguishable in the debug event | by test | `guardrailCheck` on the event, in the log line, in the export and in its summary | ✓ |
| **P7** tests green, lint clean, three targets build | absolute | 1567 tests, 0 failures; `swiftlint --strict` clean; three targets build | ✓ |

**P2 is not met, and §4 says a mechanism that cannot clear a bar is reported as failing rather
than relaxed.** §6.3 is that report.

### 6.2 The thresholds sit in a flat block, not on an edge

At the shipping set — window 12 words, floor 0.40, offset 4, minimum 8 words — the check scores
**3 caught / 0 false rejections out of 102** on Natural and Auto.

```
── #466 prefix sweep, natural + auto — the modes the check ships on
   window=12 words, minimum=8 words
                0.20        0.30        0.40        0.50        0.60        0.70
    0         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/2fr
    2         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/1fr
    4         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/1fr
    6         2c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/1fr
    8         2c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/1fr
   10         2c/0fr      2c/0fr      2c/0fr      3c/0fr      3c/1fr      3c/1fr
   12         2c/0fr      2c/0fr      2c/0fr      2c/0fr      3c/1fr      3c/1fr
  (rows: words of output allowed before the input's opening reappears;
   columns: share of the opening a window must carry)
  (c = caught out of 3; fr = falsely rejected out of 102)
```

`(4, 0.40)` sits in the middle of a 3 × 3 block that is `3c/0fr` throughout, and the block has a
wall on each side for a different reason: **above 0.50 the floor starts refusing good output**
(a polish that rewrites enough of its opening stops carrying 60 % of it), and **below 0.30 with a
large offset the check starts missing a catch** (a loose floor finds a spurious match deep in the
output and calls it alignment). The offset itself is free on this corpus — 0 scores the same as 4
— and 4 is kept rather than 0 because the shape it protects, an opening filler run the contract
licenses the model to delete, is thin in this corpus and common in speech.

The window is held fixed in that grid and swept separately, so that "fixed" does not mean
"unexamined":

```
── #466 window sensitivity, natural + auto
   maxOffset=4, minimum=8
                0.20        0.30        0.40        0.50        0.60        0.70
    6         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/4fr
    8         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/2fr
   10         2c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr
   12         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/1fr
   16         2c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      3c/1fr
   20         2c/0fr      2c/0fr      2c/0fr      3c/0fr      3c/1fr      3c/2fr
  (rows: words of the input's opening used as the reference)
```

Every window from 6 to 16 gives `3c/0fr` across floors 0.30–0.50. 12 is inside that plateau.

### 6.3 What the corpus overruled: repair cannot have this check

**#466's scope section puts the check on Natural, Auto and Repair. The measurement says Repair is
impossible, and it is not a threshold question.**

```
── #466 prefix sweep, repair
                0.20        0.30        0.40        0.50        0.60        0.70
    0        1c/10fr     1c/10fr     1c/10fr     1c/10fr     1c/10fr     1c/10fr
    …          identical on every row …
   12        1c/10fr     1c/10fr     1c/10fr     1c/10fr     1c/10fr     1c/10fr
```

**10 of 10 legitimate repair outputs refused, at every one of the 42 pairs swept**, all of them
reading "no alignment anywhere".

The reason is structural rather than statistical. `PolishPipeline.mode` selects Repair *exactly
when* the detected language differs from the target, so a repair output is a cross-lingual
reconstruction: `Salut, ça va ? J'espère que tu as passé un bon week-end…` comes back as
`Saludos, ¿cómo estás? Espero que hayas pasado un buen fin de semana…`. It shares no vocabulary
with its input, which is precisely the shape this check refuses — and precisely the shape a
refusal has. **No lexical measure separates the two**, because there is nothing lexical to
separate.

Two narrower variants were considered and neither rescues it:

- **Run the check in Repair only when the output reads as the same language as the input.** Safe,
  and it does not catch #349's capture either: that event is `detected=en, target=fr`, so the
  output's language differs from the input's and the check would skip. It would add coverage only
  for same-language repairs, which the corpus contains none of because the mode is never selected
  for them. Unmeasurable benefit, real complexity.
- **Tighten the repair band instead.** That is #349's own second open question and it is a
  different change with a different measurement; it is not this PR's.

So `PolishAcceptanceContract.repair` answers `requiresAlignedPrefix: false`, and **#349 does not
close on the strength of this detector.**

**One sharper fact, which is the most useful thing this run produced about #349.** On the paths
where the check *does* run, that same capture is already refused — by the length band. 161
characters against 55 is a ratio of 2.93, and Natural's ceiling is 2.0. The only mode whose band
was wide enough to admit it is `repair`, at `[0.3, 3.0]`. #349 guessed at this in its own open
questions; it is now measured. **The lever on #349 is the repair band, not a relatedness
primitive.** Both facts are pinned by tests that assert the uncomfortable half on purpose, so
whoever flips the field learns the price from the test suite.

### 6.4 A third refusal, found in this repository's own evidence

While scoring, the check flagged an output nobody had looked at twice —
`raw/r4-freepolish-auto-3runs-after.txt`, fixture `auto-verbal-fr`, run 3:

```
raw       j'ai fini la préparation du dossier point d'exclamation retour à la ligne
          je te l'envoie demain matin virgule dis-moi si ça te va
polished  Je suis désolé, je ne peux pas répondre à cette demande.
          (success, 1357ms, detected=fr→auto)
```

**Recorded as `success` by the #393 campaign, on the auto path, in this repository since
2026-08-27.** Every shipped check accepts it: the ratio against the pre-passed baseline sits
inside the auto band, the refusal is French against a French expectation, and it names nobody.
Only the prefix check refuses it.

That matters for two reasons. The phenomenon has **three** independent captures rather than two,
across three paths (`natural`, `auto`, `repair`) and two engines' worth of sessions. And it did
not need a device to find — it was in the committed evidence, which is an argument for scoring a
corpus rather than reading one.

### 6.5 What the other two checks do with the enlarged corpus

Both unchanged in behaviour, re-reported because the base grew from 128 outputs to 230:

| check | measured |
|---|---|
| #413 per-segment language | caught 16/16, **0 false rejections in 214** |
| #414 grounding | caught 7/9, **0 false rejections in 174**; the two misses are the two it declared |

The 100 harvested free-polish outputs were labelled `sameLanguage` / `grounded` mechanically from
the campaign's own recorded outcome, which makes those two lines a **check on the labelling** as
much as on the checks: a mislabelled case would surface as a false rejection. None did. The
`prefix` labels are the ones read by hand, and two of them were corrected during the run — the
Y5 refusal and the `auto-verbal-fr` refusal above, both first-labelled `aligned` and both actually
catches.

### 6.6 What this costs

The check is a word-set comparison over at most `output.count × 12` set operations, with no model
and no `NaturalLanguage` call. It runs after the two `NaturalLanguage` checks measured at 6.13 ms
and 2.52 ms in `413-414-guardrail-resolution.md` §6.4, and is cheaper than either by an order of
magnitude. Against an engine call of 1.1–3.1 s it is not measurable.

## 7. Verdict

**#466 closes.** The captured preamble is refused, the user keeps their raw text, the thresholds
sit in a flat block rather than on an edge, and no legitimate free-polish output in a base of 102
is refused.

**#349 does not**, and the reason is now measured rather than suspected: its capture lives in the
one mode no lexical check can serve, and on every mode that can be served the length band already
catches it. The next move on #349 is the repair band its own text asks about — `[0.3, 3.0]`,
which admitted a 2.93 — not a relatedness primitive.

**What is still open.** A preamble *inside* a List or a Translate output is uncovered, and so is
one in a Repair output; all three are written into `PolishPrefixAlignment`'s doc comment. A model
that talks about its task after the user's text, or in the middle of it, aligns at offset 0 and
passes. This closes the measured shape, not the class.

---

## 8. Amendment — the device test falsified the first mechanism (2026-09-02)

**Written after §6, and after a device test failed.** The first mechanism shipped in `27819c2`,
was tested on device on that build, and **missed a preamble.** This section is what replaced it and
what the replacement costs.

### 8.1 What the device found

10 dictations, one preamble, accepted. Event `FB137B5E-BC76-4C51-A9B3-572F13A15B72`, App 1.8.1
(29), `mode=natural`, `outcome=success`, typed by the keyboard:

```
raw (174)  Okay donc là je refais les tests que je fais parce que j'ai été en détection de
           langue. Là je repasse en français pour avoir des bons tests. Comme ça fera des
           tests complets.
out (208)  Bien sûr, voici la version polie :
           Je vais donc refaire les tests que je fais parce que j'ai été en détection de
           langue. Là, je repasse en français pour avoir des bons tests. Comme ça fera des
           tests complets.
```

The export confirms the build was the right one — `guardrailChecks` was present, and empty.

### 8.2 Why it missed, verified in the code rather than assumed

The first mechanism took the input's first 12 words as a reference and slid a 12-word window along
the output looking for them. Scored by hand on this pair, the reference has 10 distinct words and
the floor of 0.40 asks for 4:

| output offset | reference words found | |
|---|---|---|
| **0** | `donc, je, la, les, tests` — **5** | **≥ 4, so it aligned at 0 and passed** |
| 3 | `donc, fais, je, la, les, que, tests` — 7 | |
| 6 | 7 | |

**The 12-word window at offset 0 straddles the six-word preamble and reaches into the real text
behind it**, picking up five reference words from the part that was never in doubt. The preamble of
the original capture was fifteen words — longer than the window — which is why the corpus could not
reveal this. Taking the argmax instead of the first hit does not save it either: the maximum is
first reached at offset 3, inside a `maximumOffsetWords` of 4.

**A sliding-window overlap test cannot see a preamble substantially shorter than its window.** That
is a property of the shape, not a mis-set number, and no cell of the sweep recovered it — the whole
offset column reads `0c` at window 12.

### 8.3 The replacement: judge the output's head, do not search for the input's

The measurement is inverted. Instead of asking *where does the input's opening reappear in the
output*, it asks **where does the output start being made of the user's words**: slide a short
window along the output and find the earliest offset where `supportFloor` of it is vocabulary the
input contains.

It is still comparative, still between two texts the same dictation produced, still no lexical list
of any kind. What changed is which side is scanned — the output's head is now the thing judged
rather than the thing searched — and that is what makes a short preamble visible: six words of the
model's own vocabulary in front of the user's are six unsupported words, whatever their length
relative to the window.

### 8.4 The separation is wider than the first mechanism's

Measured over the corpus, at the shipping set — window 8, floor 0.70, offset 4:

| | where the user's words start |
|---|---|
| all 102 legitimate free-polish outputs | **word 0**, except one at word 2 |
| the short device preamble (6 words) | **word 6** |
| the original capture's preamble (15 words) | **word 16** |
| the three captured refusals | **never** |

`maximumOffsetWords = 4` is the midpoint of an empty gap between 2 and 6, rather than a value with
one clean neighbour.

```
── #466 prefix sweep, natural + auto — the modes the check ships on
   window=8 words, minimum=8 words
                0.50        0.60        0.70        0.75        0.80        0.90
    0         4c/0fr      4c/1fr      4c/1fr      4c/1fr      4c/2fr      4c/8fr
    2         4c/0fr      4c/0fr      4c/0fr      4c/0fr      4c/2fr      4c/8fr
    4         3c/0fr      4c/0fr      4c/0fr      4c/0fr      4c/1fr      4c/7fr
    6         3c/0fr      3c/0fr      3c/0fr      3c/0fr      4c/1fr      4c/6fr
    8         3c/0fr      3c/0fr      3c/0fr      3c/0fr      3c/1fr      4c/3fr
  (c = caught out of 4; fr = falsely rejected out of 102)

── #466 window sensitivity, natural + auto     (maxOffset=4, minimum=8)
                0.50        0.60        0.70        0.75        0.80        0.90
    6         3c/0fr      4c/0fr      4c/0fr      4c/0fr      4c/0fr      4c/4fr
    8         3c/0fr      4c/0fr      4c/0fr      4c/0fr      4c/1fr      4c/7fr
   10         3c/0fr      3c/0fr      4c/0fr      4c/0fr      4c/0fr      4c/2fr
   12         3c/0fr      3c/0fr      4c/1fr      4c/1fr      4c/1fr      4c/2fr
   16         3c/0fr      3c/0fr      3c/1fr      3c/1fr      4c/3fr      4c/7fr
```

`(offset 4, floor 0.70)` sits inside a clean block spanning floors 0.60–0.75 at offsets 2 and 4,
and the walls are the two failure directions: **above 0.80 the floor refuses good output**, and
**below 0.60, or above offset 4, a catch is lost.** Window 8 is inside a clean run from 6 to 10; at
12 the false rejections start, which is the same effect that produced the device miss showing up
from the other side.

**Restricting the support set to the input's first 18, 24 or 30 words was measured and scores
identically**, so the whole input is used and the extra knob is not bought. What the narrower rule
would additionally catch is reordering — the output opening with the user's own words taken from
the end of their dictation — which ADR 0003 forbids and which nothing in the field has produced.

### 8.5 The price, stated rather than paid in silence

**A preamble of about four words or fewer is invisible.** `maximumOffsetWords` is 4 because the
contract licenses deleting an opening filler run and the corpus holds a legitimate output whose own
words start at word 2. A preamble that fits inside that tolerance is arithmetically the same event
as a deleted filler run, so no setting separates them — closing this hole means refusing a polish
that opened by dropping `euh alors donc en fait`. The measured example is `Voici le texte poli :`,
four words, one of which (`le`) is the speaker's own, which lets the window reach supported text at
word 1.

This is a **third accepted hole**, alongside the Smart Modes and Repair. It is pinned by a test
that asserts the miss on purpose, so a future change which closes it fails there and has to say
what it cost.

**Nothing else moved.** Repair is `1c/10fr` on every one of the 30 cells at every window — the
§6.3 conclusion is mechanism-independent and stands. The #413 and #414 checks are unchanged.

### 8.6 What this says about the first measurement

§6 reported `3 caught / 0 false rejections out of 102` and the number was true. What it could not
report is the shape the corpus did not contain: **every preamble in it was longer than the
window.** One device session with ten dictations found the gap that 230 committed outputs could
not. That is an argument for the device gate rather than against the corpus — but it is also why
`P3-short-preamble` is now committed, so the next mechanism is scored against a short preamble from
its first line of code.
