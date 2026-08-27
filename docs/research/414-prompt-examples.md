# Can the worked example stop being copied without costing the mode its shape?

**Issue:** [#414](https://github.com/getdictus/dictus-ios/issues/414), second proposal —
*"Neutralise the examples. Replace named people and concrete facts in prompt examples with
placeholders that read as obviously non-content."*
**Why now:** the guardrail half of #414 shipped in PR #442 and **does not close the issue**. The
same fabrication reproduced live with one clause reworded and the check accepted it, because
`NLTagger` tags `Sophie` in `avant : elle a…` and tags nothing in `avant parce qu'elle a…`. That
is the tagger's recall, not a threshold. **If the prompt never contains Sophie, the model cannot
copy her**, which makes this the only lever left that attacks the failure at its source.
**Unblocked by:** #79, 2026-08-27 — *"The bullet mode ships. This question is closed."* There is no
pending cut decision for a prompt change to invalidate.
**Date:** 2026-08-27

> **§1–§3 were written and committed BEFORE the first model call of this run.** Same discipline as
> PR #388, PR #412 and the guardrail half of this PR. Everything from §4 on was written after.

---

## 1. What is being decided, and what is at risk

**The change is not free, and PR #388 is why.** It found that a prompt's worked examples
measurably improve output shape. So deleting or abstracting one can buy a lower fabrication rate
and pay for it in a mode that stops producing bullets — and **shape regresses silently**, where a
fabrication at least leaves a name in the text.

Two questions, and the second is the one that can go wrong without anyone noticing:

- **Q1 — does the copying stop?**
- **Q2 — does the output shape hold?**

## 2. The candidates

Written before any run. `A` is the shipping prompt; `B` and `C` are the two honest readings of
#414's proposal, and they are measured against each other rather than one being assumed correct.

| | What it changes |
|---|---|
| **A — shipping** | Nothing. The baseline. Its French worked example contains `Sophie` and `décembre`, and its INPUT side contains `j'appelle Sophie avant parce qu'elle a les données de décembre` — which is **closer to the live fabrication than the example's own OUTPUT side is**. |
| **B — neutralised** | The same examples, with the person and the concrete month replaced by a role and a relative time. Minimal targeted edit: keeps the natural language and the demonstrated transformation, removes the fabricable person. |
| **C — no worked examples** | Rules and counter-examples only. The null hypothesis for #388's finding, tested on this mode rather than inherited from Email. |

## 3. The bars, pre-registered

**n = 6 fixtures × 5 runs = 30 calls per candidate**, on `notes-fr.json`, the same set the #393
campaign used, through the real pipeline and the real engine. Every raw output committed.

| | Bar | Threshold |
|---|---|---|
| **P1** | A **person name** from the prompt's examples appears in an output whose input does not contain it | **0 / 30**, absolute, for any candidate that ships |
| **P2** | Any other content word from the examples appears in an output whose input does not contain it | **≤ A**, and every hit read by hand |
| **P3** | **Shape.** Every non-empty line of an accepted output begins with a list marker — #393's bar B ("visibly different from free polish": bullets against prose) made mechanical | **≥ A**, and never below 28/30 of accepted outputs |
| **P4** | **No padding, no collapse.** `N4-une-idee` is one idea and must yield exactly one bullet | **≥ A** |
| **P5** | No title line, no bracketed placeholder | **0**, matching round 1's measured 0/30 |

**Reported, not gated: the guardrail success rate.** It is dominated by the language drift #393
measured at 7/30, which is a different defect with its own home (#437). Gating a prompt-example
change on it would be gating on noise from another bug.

**The decision rule, stated before the numbers exist:** ship the candidate that clears P1
absolutely and does not lose to A on P3, P4 or P5. **If none does, ship none and report that** —
the guardrail already shipped, so the floor here is "no change", not "something must land".

### How P1/P2 are detected

Deterministically, then by hand. The screen is: content words present in the prompt's example
block, absent from that fixture's input, and present in the output. It is a **screen, not a
verdict** — every hit is read before it is counted, because a word can appear in an example and in
an output for no other reason than that both are French.

## 4. Results

**239 Apple Foundation Models calls**, four candidates, two fixture sets each: the six shipping
`notes-fr.json` fixtures at n=5, and a stress set of `N2-reunion-vrac` alone at n=30 — the fixture
the copy was measured on twice, whose meeting-prep shape is the example's own shape. n=30 spread
over six fixtures cannot resolve a ~5 % event on one of them; n=30 on that one can.

Reproduce the table with `python3 docs/research/414-prompt-examples/score.py --summary`.

| candidate | set | outputs carrying copied example content | **of those, accepted** | shape |
|---|---|---|---|---|
| **A** shipping | six fixtures | 2/30 | 1 | 22/22 |
| | N2 stress | 2/30 | 1 | 29/29 |
| **B** worked example neutralised | six fixtures | 1/30 | 0 | 24/24 |
| | N2 stress | 4/30 | 4 | 30/30 |
| **C** worked examples deleted | six fixtures | 4/30 | 3 | 23/23 |
| | N2 stress | **9/30** | **9** | 30/30 |
| **D** worked example **and** counter-example neutralised | six fixtures | 5/30 | **0** | 18/18 |
| | N2 stress | **1/29** | **1** | 29/29 |

Accepted copies over both sets: **A 2, B 4, C 12, D 1.**

### 4.1 The proposal's premise is wrong, and that is the main finding

#414 proposes neutralising the examples to stop the copying. **Neutralising an example does not
stop the copying. It changes what gets copied.**

- **A** copied `Sophie` and `décembre` — a fabricated person.
- **B**, with that example neutralised, copied its replacement instead: `comptable`, `budget
  marketing`, `données manquantes`, on 4 accepted outputs of 30.
- **D**, with both examples neutralised, copied the one example left concrete: `racheter du café
  demain matin`, the short-input illustration.

Whichever concrete content remains is what the model reaches for. The rate is a property of
showing examples at all, not of what they say.

### 4.2 Deleting the examples is decisively worse — PR #388's finding, reproduced on this mode

**C copied the COUNTER-example into 9 of 30 accepted outputs on the stress fixture**, against 1 for
D and 1 for A. The line was `- Rappeler le client cette semaine`, verbatim from the block whose own
heading says *"the WRONG outputs below invent content"*, arriving as the **first bullet** of a
meeting-prep note that mentions no client.

The model does not know which block a line came from. It copies what it was shown. Removing the
worked examples leaves the counter-examples as the only concrete material in the prompt and
concentrates the copying there — six times the shipping rate.

**This also caught a real mistake in this run's own instrument.** The first version of the screen
scored only the *worked*-example block, so on candidate C it matched nothing and reported a clean
sheet. The finding was visible by reading the outputs, not by the number. The screen now covers
every example block, and every figure above is from the corrected version.

### 4.3 What the shipping prompt does that nobody had measured

`- Rappeler le client cette semaine` also reached an accepted output under **the shipping prompt**,
in its own stress round. So the counter-example was already a copy source before this run, and
neutralising the worked example alone (candidate B) leaves it in place. That is why D exists.

### 4.4 The guardrail from PR #442 was observed working, live

Stress round A, run 23: the model emitted `- Appeler Sophie avant : elle a les données de décembre`
and the grounding check **rejected it** — `rejectedGuardrail`, nothing inserted. That is the exact
#414 failure, caught end to end by the check shipped in the first half of this PR, on a run made
for a different purpose.

It does not close the recall gap. The one that got through in PR #442's verification used the
`parce qu'elle a` phrasing that `NLTagger` does not tag, and that limit is unchanged.

### 4.5 The bars

| | A | B | C | **D** |
|---|---|---|---|---|
| **P1** person name copied | **1** | 0 | 0 | **0** |
| **P2** other example content copied, accepted | 2 | 4 | 12 | **1** ✓ ≤ A |
| **P3** shape: accepted outputs entirely bullets | 51/51 | 54/54 | 53/53 | **47/47** ✓ |
| **P4** N4 answered with exactly one bullet | 5/5 | 5/5 | 5/5 | **5/5** ✓ |
| **P5** title line / bracketed placeholder | 0 / 0 | 0 / 0 | 0 / 0 | **0 / 0** ✓ |
| guardrail success *(reported, not gated)* | 51/60 | 54/60 | 53/60 | 47/59 |

**D is the only candidate that clears every pre-registered bar.** B and C both fail P2 — they are
copied from more often than the prompt they replace.

## 5. Verdict

### Candidate D ships.

Fewest accepted copies of any candidate including the baseline, no person nameable from the prompt,
and shape, padding and placeholder behaviour identical to shipping. The Swift prompt was then
verified **byte-identical** to the measured candidate file, so what ships is what was measured:

```sh
swift run polish-harness prompt Sources/polish-harness/fixtures/notes-fr.json \
                                --mode notes --id N4-une-idee --out /tmp/verify
diff /tmp/verify/N4-une-idee/system.txt docs/research/414-prompt-examples/prompts/D-neutralised-both.txt
```

### What I am not comfortable with

- **D's guardrail success rate is 18/30 on the six-fixture set against A's 22/30.** It is the one
  number that moved against D. It measures the language drift #393 put at 7/30, which is a
  different defect with its own home (#437), and success was pre-registered as reported rather
  than gated — but 18 against 22 at n=30 is about 1.6σ and **it is not established as noise, only
  consistent with it.** If a future run reproduces it, D is the first thing to re-examine.
- **The events are rare and the samples are small.** 1 against 2 accepted copies is not a
  significant difference. What the run establishes solidly is the *ordering* of C against
  everything else (9 against 1, on the same fixture and n), and that neutralisation moves severity
  rather than rate. The choice of D over B rests as much on P1-by-construction as on its count.
- **French only, Mac only**, as with every measurement on this mode.
- **The screen has false hits**, all reported rather than filtered: `appeler` for an input's
  `j'appelle` (rule 1 turns spoken verbs into infinitives, which is the prompt working), and
  `before` on English-drifted outputs. Every hit above was read before it was counted.

### What this does not do

It does not close #414. The guardrail's recall gap is unchanged, and a prompt with any concrete
example can still have that example copied. What it removes is the **worst form** of the copy — a
fabricated person, in a document the user is about to send — and it lowers the rate of the rest to
the best measured of four candidates.

The next edit, if the rate ever needs to come down further, is the short-input example: it is the
one concrete example D leaves standing and it is where D's single residual copy came from. It stays
because it is what teaches "one idea in, one bullet out", which measures 5/5 on every candidate.
