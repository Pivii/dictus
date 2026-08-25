# Notes and Translate → EN — harness validation

**Issues:** [#79](https://github.com/getdictus/dictus-ios/issues/79) (the spec),
[#393](https://github.com/getdictus/dictus-ios/issues/393) (the harness could not run a mode)
**Question:** #79 requires that *"every shipped mode is harness-validated as visibly different
from free polish."* Notes and Translate → X shipped in block A (PR #389) **unmeasured**, because
no invocation of `polish-harness` could build a `.smart(…)` task. This is that measurement.
**Date:** 2026-08-25.

> **§1–§3 below were written and committed BEFORE any model was run**, so the findings can be
> checked against what was promised rather than against what turned out to be convenient. This is
> PR #388's discipline, and it is the reason its verdict on Email is worth anything. Everything
> from §4 on was written after.

---

## 0. What is being decided

Two independent bars, and each mode must clear **both**.

- **Bar A — the mode does what its own contract says.** Not the free-polish contract: the
  `0.5…2.0` band rejects Notes for condensing and the same-language check rejects every
  translation, which is exactly why a mode carries its own (`PolishAcceptanceContract`).
- **Bar B — the mode is visibly different from free polish.** #79, catalogue-wide: *"Any mode
  whose output is not visibly different from free polish is cut."* SMS was cut on this bar before
  a line of it existed; Email was cut on it after 240 calls.

There is already one piece of field evidence and it is not favourable. On 2026-08-24, 16 Smart
Mode dictations on device produced **one `rejectedGuardrail` on Notes: French in, English bullets
out** (#393). Every layer behaved as designed — the `sameAsInput` check caught it, the mode
failed closed, nothing was inserted. The defect is the prompt. One call in six is a discovery,
not a rate; producing the rate is what this run is for.

## 1. Method

Every call runs the **real** `PolishPipeline` with the **real** `AppleFoundationModelsPolishEngine`
on this Mac (macOS 26.5.1, Apple silicon), through the same `PolishJob` the app builds, with the
same gates (`PolishGatePolicy`), the same deterministic pre/post-passes, and the mode's own
contract judging the output. The only thing absent is audio: the polish input is text.

```sh
cd DictusCore
swift run polish-harness show Sources/polish-harness/fixtures/notes-fr.json     --mode notes        --runs 5
swift run polish-harness show Sources/polish-harness/fixtures/translate-en.json --mode translate.en --runs 5
swift run polish-harness ab   Sources/polish-harness/fixtures/notes-fr.json     --mode-b notes
swift run polish-harness ab   Sources/polish-harness/fixtures/translate-en.json --mode-b translate.en
swift run polish-harness eval Sources/polish-harness/fixtures/notes-fr.json     --mode notes
swift run polish-harness eval Sources/polish-harness/fixtures/translate-en.json --mode translate.en
```

**n = 6 fixtures × 5 runs = 30 calls per mode** for bar A, plus one A/B pass per mode for bar B.
Every raw output is committed under `docs/research/79-smart-modes/raw/`, including the runs that
fail.

**Latency is reported but is not evidence about the device.** A Mac's Apple Foundation Model is
the same model family, so *quality* transfers; the silicon is not an A17 Pro, so *latency* does
not. No millisecond figure here is a device reading.

## 2. Bar A — the mode's own contract

### Notes

| | Failure | How it is checked | Pre-registered threshold |
|---|---|---|---|
| **A1** | Output is not in the input's language | The mode's own contract (`sameAsInput`), i.e. a `rejectedGuardrail` on the language check | **≤ 1/30** |
| **A2** | Invents a fact, name, date or conclusion absent from the raw | Read by hand, every output. No regex enumerates invention | **0/30** |
| **A3** | Emits a title, heading, or bracketed placeholder | `regexAbsent` per fixture, and by hand | **0/30** |
| **A4** | Rejects its own good output on the length band | Any `rejectedGuardrail` whose engine output is a sound list | **0/30** — the `0.1` floor is a judgement call, and #79 says it is the first thing to revisit |

A1's threshold is **not** zero, and the reason is worth stating before the number is known: the
mode fails closed, so a drift costs a refused dictation and an explicit message, never a wrong
insertion. That is a materially different cost from Email's invented signature. But 1/30 is
already three times better than what the field saw, and anything worse is a prompt that does not
hold its central rule.

### Translate → EN

| | Failure | How it is checked | Pre-registered threshold |
|---|---|---|---|
| **A1** | An accepted output that is not English | The mode's own contract (`fixed(.english)`) — the check #79 says flips from obstacle to asset here | **0/30**, absolutely |
| **A2** | Refuses a translation it should have made | `rejectedGuardrail` on an engine output that *is* good English | **≤ 1/30** |
| **A3** | Invents a greeting, sign-off or name | The PR #388 regexes, plus reading | **0/30** |
| **A4** | Shifts the register up, or leaves a proper noun translated | Read by hand | **0/30** on proper nouns; register lift reported as a count, not gated |
| **A5** | Leaks a `<<NL>>` marker, or loses a dictated line break | `regexAbsent` + `contains` on T5 | **0/30** |

A1 is absolute because an accepted non-English output *is* the insertion #79 names as the worst
outcome available: French sent to an American client.

## 3. Bar B — visibly different from free polish

Scored on the `ab` pass, one run per side per fixture, both sides on their shipping prompts. A
fixture counts as **visibly different** when a reader would call the two columns different
transformations, not two samplings of the same one — for Notes, prose against bullets; for
Translate, one language against another.

- **Notes: ≥ 5/6 fixtures.** Bullets against prose is unmissable, so a low bar here would be a bar
  that measures nothing. N4 (one idea) is the one that may legitimately land close.
- **Translate → EN: 5/5 non-English fixtures.** T6 is already in English, is **declared here,
  before the run, as expected not to differ**, and is excluded from the denominator. #388's own
  stated regret was making this bar a hard gate while naming a fixture designed to fail it; the
  fix is to say so in advance, not to carve it out afterwards.

## 4. Results

*(written after the run — see §5 for the verdict)*

## 5. Verdict

*(written after the run)*
