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

Written after the measurement. See below.
