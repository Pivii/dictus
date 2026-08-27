# Natural contract, three violations — measured (#439)

**Bars and plan:** `bars.md`, committed before the first model call on this fixture set.
**Fixtures:** `DictusCore/Sources/polish-harness/fixtures/longform-fr.json` — the six
device dictations from #437, `raw` verbatim.
**Where:** Mac, macOS 26.5.1, Apple Intelligence on, `polish-harness`, 2026-08-27.
**Raw captures:** `raw/`. **Scorer:** `harness/score.py`. **Probe inputs:** `harness/*.json`.

Everything below is 5 samples per fixture per arm, per path, on Apple FM on a Mac.
Nothing here was confirmed on a physical iPhone.

---

## The headline

**Bar 1 does not clear, and the prompt is not the lever it fails on.** After the edit,
Apple FM repairs **1 of the 6** listed ASR errors on the per-language path and **0-1 of 6**
on the auto path — the same as before. Five of the six are never repaired, on any run, on
either path, under any prompt tested.

That is not a calibration miss. It was probed directly: **each broken segment was handed
to the model alone, in one short sentence, with the surrounding context that makes the
intended reading obvious** (`harness/probe-isolated.json`). Result, 5 runs each:

| Probe | Segment, in one sentence with its context | Repaired |
|---|---|---|
| P1 | `une visio depuis la salle à tante mais ce sera moyen` | **0/5** |
| P2 | `le découpe en petits morceaux. Le modèle prend ses morceaux` | **0/5** |
| P3 | `je répète le comptable … c'est l'assurance qu'il faut que je rappelle` | **0/5** |
| P4 | `l'intégration StoreKit … caler la partie Apple Store` | **0/5** |
| P5 | `une semaine et demie qu'il attend … si je les zappais` | **0/5** |

And with a **minimal prompt whose stated primary job is finding misheard words**, with a
three-step method in front of everything else and no long-form task competing for
attention (`prompts/C-minimal-repair-probe.txt`, 1.5 KB against the shipping prompt's
7.1 KB): still 0/5 on all five (`raw/probe-isolated-ab.txt`). That candidate also
introduced a fresh Preserve violation of its own, substituting `a fini` with `a terminé`.

**The capability #439 assumes is not present in this model.** ADR 0003 rule 8 works on
the shape it was written from — a whole-clause language switch, which fires 5/5 — and does
not generalise to a homophone that reads as fluent French. The issue's own sentence
*"So the capability is present"* is the inference this measurement falsifies: what is
present is off-language-fragment detection, which is a different and much easier signal.

## Bar 3 has a mechanism, and it is not a missing prohibition

`en calcul` is still deleted 4/5 on both paths after an explicit, named ban on deleting
meaningful words. So it was probed too (`harness/probe-length-ladder.json`, 5 runs each):

| Input | Chars | `en calcul` survives |
|---|---|---|
| The closing passage alone, as dictated (run-on, no boundaries) | 311 | 2/5 |
| …with the preceding section | 599 | 1/5 |
| …with two preceding sections | 727 | 1/5 |
| The whole fixture | 838 | 2/5 |
| **The same 311 characters with the sentence boundaries supplied** | 316 | **5/5** |

Length explains nothing — 6/20 across a 2.7x range. **Punctuation explains everything.**
The words that get dropped are the tail of a clause the model has to cut in two, and it
drops them while deciding where the cut goes. Feed it the same words already segmented
and it deletes nothing, 5 times out of 5.

This is the same defect #437 named from the other side: *"a pass that has to place a
break, and places it by comma rather than by discourse, produces a sentence that never
existed."* The two issues split fidelity from structure, and on this one defect the split
does not hold: **the deletion is a symptom of segmentation**, and no clause in a fidelity
prompt reaches it.

## Every bar, scored

5 runs per fixture, 30 outputs per arm per path. Occurrences, not rates.

| | FR before | FR after | Auto before | Auto after |
|---|---|---|---|---|
| **Bar 1** repairs per run (of 6) | 1,0,1,0,1 | 1,1,1,1,1 | 1,1,1,0,1 | 0,1,1,0,0 |
| runs clearing ≥4/6 | 0/5 | **0/5** | 0/5 | **0/5** |
| **Bar 2** `cela` for `ça` | 4 | **4** | 2 | **4** |
| `machin` → `machine` | 4 | **2** | 3 | **0** |
| hour format expanded (`11h` → `11 h`) | 2 | 1 | 0 | 2 |
| digits spelled back out | 0 | 0 | 2 | 0 |
| added `ne` | 0 | 0 | 0 | 0 |
| **Bar 3** `en calcul` deleted | 4 | **4** | 5 | **4** |
| other content deleted | 0 | **1** | 0 | 0 |
| **Bar 4** content invented | 0 | **0** | 0 | **0** |
| **Bar 5** outside `[0.92, 1.15]` | 0 | 0 | 0 | 0 |
| guardrail rejections | 0/30 | **0/30** | 0/30 | **0/30** |
| **Bar 6** line breaks · `<<NL>>` leaks | 0 · 0 | **0 · 0** | 0 · 0 | **0 · 0** |

Read straight:

- **Bar 1 — fails.** Unchanged. R4 (`honnêtement`) is the only repair that ever fires and
  it fired before the edit too. Its rate did move on the per-language path, 3/5 to 5/5.
- **Bar 2 — fails, and one item went backwards.** `machin` → `machine`, the one item
  taught by name in the Preserve list, dropped from 7 occurrences in 10 runs to 2 — the
  taught fix works. `cela` went from 6 to 8: the register clause, stated twice and
  demonstrated with a counter-example, did not take. The hour-format expansions
  (`11h` → `11 h`) are new on the auto path and are the same failure in a different
  costume.
- **Bar 3 — fails**, for the reason above. And one **new** deletion appeared that the
  baseline did not have: fixture 5's trailing `ça m'échappe mais ça me reviendra` was
  dropped once in 5 on the per-language path. That is #385's exact signature, at 1/30
  where the baseline had 0/30 — one occurrence, not a trend, and worth watching.
- **Bar 4 — holds.** No invention, 60/60 outputs.
- **Bar 5 — holds.** No guardrail rejection anywhere, all ratios inside the tripwire.
- **Bar 6 — holds.** Zero line breaks in 60 outputs, both arms, both paths. The scope
  fence with #437 is intact and #437's baseline is unchanged by this branch.

## Regressions on the fixture sets this round did not target

- `seed.json` (per-language polish): 3/3 passes clean before; **5/6 passes clean after**,
  the one miss being `2-bilingue` losing `push` in a single run. 1 fixture-failure in 84
  checks against 0 in 42 — sampling noise at this resolution, not a signal.
- `auto.json` (the anti-translation set, the one at risk from a new repair rule):
  **10/10, 9/10, 9/10 before, then 10/10 three times after.** The rule 8 added to
  `PolishAutoPrompt` did not cost the anti-translation contract, which was the main
  identified risk in `bars.md`.

## What the prompt edit cost

The prompts grew: FR Natural 5 483 to 7 096 characters, `PolishAutoPrompt` similarly.
Instructions and input share one 4 096-token window (#270), so that is paid in maximum
dictation length: the French Natural ceiling moves from ~4 160 characters of input to
**~3 580**. `PolishContextBudgetTests` caught the first draft at 3 008, under the 3 500
floor #270 measured; the prompt was rewritten compact rather than the floor moved.

**~580 characters of maximum dictation length, for one Preserve item.** That is the trade
as measured, and it is the maintainer's call whether it is worth keeping.

## What this means for #439

The issue's three defects do not share the lever it proposes.

1. **A (rule 8 never fires) is not a prompt problem.** Apple FM cannot detect a homophone
   that reads as fluent French, in isolation or in context, under any instruction tested.
   Closing this needs a different mechanism — a lexicon or frequency check that flags
   improbable n-grams before the model sees them, a second pass, or a larger model — and
   that is an issue of its own, not a calibration round. The prompt rule is still worth
   keeping: it costs little, it protects the capability that *does* work, and it is what a
   future engine would need to find already written.
2. **C (deletion) is a segmentation problem** and belongs with #437, not here. A fidelity
   clause cannot reach it; supplying the boundary does, completely.
3. **B (register) is the only one of the three that is genuinely a prompt matter**, and
   even there the results split: the lexical item taught by name improved, the
   grammatical form stated as a rule did not.

The honest recommendation is that **#439 as written cannot be closed by this PR**, and
that its bar 1 should be re-cut against what the engine can actually do — with the six
probes above as the evidence, since they are cheap to re-run against any future engine.
