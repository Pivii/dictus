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

*(written after the run)*
