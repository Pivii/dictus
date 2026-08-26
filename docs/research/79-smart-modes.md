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

**126 harness invocations, 125 Apple Foundation Models calls** (one free-polish side was skipped
by the gibberish gate, which is itself a result — see T3). Seven rounds, every raw output
committed under `raw/`, including the failed ones. Rounds 1–6 use the shipping prompts; round 7
is a candidate Notes prompt written after round 1 and measured against the same fixtures.

### 4.1 Notes — bar A

| Bar | Threshold | Measured | |
|---|---|---|---|
| **A1** output not in the input's language | ≤ 1/30 | **6/30 refused + 1/30 accepted** | ✗ **FAIL** |
| **A2** invents a fact, name or date | 0/30 | **≥ 3 accepted inventions** | ✗ **FAIL** |
| **A3** title, heading or bracketed placeholder | 0/30 | 0/30 | ✓ pass |
| **A4** the length band rejects good output | 0/30 | 0/30 | ✓ pass |

**A1.** The field failure is not an outlier, it is the mode's behaviour on that input:
`N1-field-commits` drifted to English **5 times out of 5**. The refusals concentrate — N1×5,
N3×1, nothing on the other four French fixtures — so the drift is triggered by a property of the
input, not spread evenly across French. N1's properties are the three the #393 comment named:
it opens by addressing the assistant, it carries STT garble, and it is an unstructured ramble.

The 7th case is worse than the six refusals, because it was **accepted**:

```
raw (fr): … côté design c'est bon les maquettes ont été validées vendredi par contre le dev a
          pris deux semaines de retard …
N3 run 3 (success — this text would have been inserted):
- Design: maquettes validées vendredi
- Development: two-week delay due to API issues
- Delivery: potential delay to March 15
- Budget: 8000 euros remaining, 3000 euros from February licenses
- Thomas: three-week vacation starting March 20
- Payment: need to be completed before March 20
```

Five English bullets and one French one, on a French dictation, past the contract. Measured, not
inferred: `NLLanguageRecognizer` reads that text as **French at 0.789** confidence — the French
bullet, the proper nouns and "euros" carry it. Run 2 on the same fixture is nearly the same list
with one bullet fewer and reads as **English at 0.607**, so it was refused. The two land on
opposite sides of the check on a one-bullet difference.

**This is a hole in the fail-closed guarantee, and it is code rather than prompt.**
`PolishGuardrail.detectedLanguageMatches` is a *dominant*-language check; a bilingual output is
exactly the shape it cannot see, and Notes — telegraphic bullets, technical nouns, numbers — is
the mode that produces that shape. #79 does not cover it. It deserves its own issue.

**A2.** Three inventions reached accepted outputs in 24 accepted runs, and the first is the one
that matters most:

```
raw: … faut que je récupère les chiffres de janvier auprès de Marion … appeler le prestataire …
     réserver la salle du deuxième étage …
N2 run 5 (success):
- Récupérer les chiffres de janvier auprès de Marion
- …
- Appeler Sophie avant : elle a les données de décembre      ← verbatim from the prompt's example
```

`- Appeler Sophie avant : elle a les données de décembre` is the **first worked example inside
`SmartModeNotesPrompt`, copied out word for word** into a user's notes: a person who does not
exist in the dictation and a fact nobody said. The other two: `Marion, mardi` where the speaker
self-corrected to *mercredi* (rule 4 says keep what they corrected TO), and `starting March 20`
where the raw says only *"à partir du 20"* with no month named.

This is the failure class PR #388 cut Email for — invented content in a message the user is about
to send — and here the length band saw nothing, exactly as #388 predicted a length band would.

### 4.2 Notes — bar B (visibly different from free polish)

Round 3, both sides on their shipping prompts. On **4 of 4 fixtures where the mode produced
anything, the difference is unmissable** — free polish returns punctuated prose, Notes returns
bullets. On the other 2 the mode produced nothing at all.

```
raw: bon alors euh je récapitule ce qu'il faut que je fasse avant la réunion donc déjà faut que
     je récupère les chiffres de janvier auprès de Marion …
A [polish]:      Bon alors, euh je récapitule ce qu'il faut que je fasse avant la réunion. Donc
                 déjà, faut que je récupère les chiffres de janvier auprès de Marion. Elle m'a
                 dit qu'elle les aurait mardi, enfin, non, mercredi, euh, du coup, …
B [smart.notes]: - Récupérer les chiffres de janvier auprès de Marion, mardi ou mercredi
                 - Faire le tableau comparatif avec ceux de l'année dernière
                 - Appeler le prestataire, devis passé de 12000 à 15000 euros, non validé
                 - Réserver la salle du deuxième étage, l'autre est prise toute la semaine
```

**Bar B is not Notes' problem.** Its axis is real and free polish will never move text along it.
And on N1, the fixture the mode refuses 5 times out of 5, free polish produced a clean result —
it even repaired `commith` → `commits`.

### 4.3 Notes — round 7, a candidate prompt

One candidate (`prompts/B-notes-v2.txt`), written against the round-1 failures with three
changes: identify the language from the input as a whole rather than its first word or its
technical terms; a counter-example built on the exact N1 failure; a final self-check step naming
the language. Same fixtures, same n.

| | shipping | v2 candidate |
|---|---|---|
| non-success | 6/30 | 5/30 |
| N1 drift | 5/5 | 3/5 |
| N5 (English input) drift | 0/5 | **1/5 — came back in French** |
| Apple FM `guardrailViolation` | 0/30 | 1/30 |

**The candidate moved the failure, it did not remove it.** Pushing harder toward "the input's
language" bought two of N1's five back and cost an English dictation, which came back as
`- Certificat expiré sur le serveur de staging, déploiement bloqué`. And twice the model produced
a *mixed* list under v2 — `- Committed 5 instead of 6 / - Achat de yaourts` — which is the shape
§4.1 shows the guardrail cannot reliably see.

One round is not four, and a better prompt may exist. What this round does establish is that the
defect is not a missing rule: the shipping prompt already carries the strongest language
instruction in the codebase, copied from the device-validated auto prompt (#239), and stating it
twice more does not hold it. That is PR #388's transferable finding reproducing — an
instruction-level ban does not beat the model's prior — on a different mode.

### 4.4 Translate → EN

| Bar | Threshold | Measured | |
|---|---|---|---|
| **A1** an accepted output that is not English | 0/30 | 0/30 | ✓ pass |
| **A2** refuses a translation it should have made | ≤ 1/30 | 0/30 | ✓ pass |
| **A3** invents a greeting, sign-off or name | 0/30 | 0/30 | ✓ pass |
| **A4** proper nouns preserved | 0/30 | 0/30 | ✓ pass |
| **A5** `<<NL>>` leak or lost line break | 0/30 | 0/30 | ✓ pass |
| **B** visibly different from free polish | 5/5 | 5/5 | ✓ pass |

**30/30 success. Not one refusal, not one guardrail rejection, not one invention.**

The clearest single piece of evidence is T3 — Italian spoken on a French keyboard, the shape a
travelling user actually produces:

```
raw: allora senti volevo dirti che domani non riesco a venire in ufficio perché ho una cosa dal
     dentista alle undici …
A [polish] (0 ms):        allora senti volevo dirti che domani non riesco a venire in ufficio …
B [smart.translate.en]:   Okay, I wanted to tell you that tomorrow I can't come to the office
                          because I have something with the dentist at 11, but in the afternoon,
                          if you want, we can meet at 3.
```

`0 ms` on the A side is the gibberish gate skipping the engine entirely: Italian is outside the
four languages the per-language path has prompts for, so free polish hands back the raw
unchanged. The mode ran because `PolishGatePolicy` refuses to skip for an armed mode — the gate
work #79 asked for, doing exactly what it was for. Nothing else in this run demonstrates a
paid mode earning its place as plainly.

T6, the already-English control declared in §3 as expected not to differ, did not differ.

**Measured, not pre-registered, and reported anyway — translation accuracy.** My bars covered
invention, register and language, and not whether the translation is *correct*. Three defects
turned up:

- **T2, 5/5**: `avancer la deadline d'une semaine` (move it *earlier*) came back as "push the
  deadline back by a week" or "extend the deadline by a week" in every run. The direction is
  inverted in all five.
- **T4, 3/5**: Italian `senti` (*listen*) rendered as "I feel like I wanted to tell you". The
  same input on the per-language route (T3) did this 0/5 — same target, same prompt, different
  route. n=5 per side; this could be the draw.
- **T1, 2/5**: `un truc qui traîne` became "something that's been dragging me down".

None of these is a bar failure and none is a hallucination — they are ordinary machine-translation
errors, at a rate a user of a translation feature would expect. They belong in the record because
a "30/30 success" line reads like an absence of defects and it is not one.

### 4.5 Latency, and what it is not

On this Mac: free polish 1.4–4.2 s, Notes 1.1–3.0 s, Translate 1.1–1.9 s. The modes were not
slower than free polish here, which is the opposite of the Email finding.

**None of these numbers is a device reading.** A Mac's Apple Foundation Model is the same model
family, so output *quality* transfers and that is what this report is about; the silicon is not
an A17 Pro, so latency does not transfer. Smart Mode latency on device is **unmeasured**.

## 5. Verdict

### Translate → EN is CONFIRMED. It clears both bars with no failure in 30 calls.

It moves text along an axis free polish cannot touch, it holds every rule it was given, and on an
input free polish declines to process at all it produces a clean English message. Ship it.

The other three targets (→ FR, → ES, → DE) share one parameterised prompt with → EN and were
**not measured**. #79 asked for → EN; the prompt is one builder with the target substituted, so
the finding plausibly carries, and "plausibly carries" is not "measured".

### Notes fails its own contract, and the decision is the maintainer's.

It is the maintainer's call, on the same bar Email was held to, and this report does not make it.
What the evidence says:

- **It is not Email's failure.** Email was cut for clearing bar A and failing bar B — it did not
  look different enough from free polish to be worth paying for. Notes is the mirror image: bar B
  is unmissable, and it fails **bar A, its own contract**, on 7 of 30 calls.
- **One French dictation in four gets nothing.** 6/30 refusals means the user speaks, waits for
  the model, and receives a red message and no text. On the one fixture drawn from the field it
  is 5 out of 5.
- **One accepted output carried a name from inside the prompt.** That is the failure class Email
  was cut over, and no guardrail in the pipeline can see it.
- **The prompt did not yield to one round of hardening**, and the fix for the accepted-drift case
  is code (`detectedLanguageMatches` cannot see a bilingual list), not prompt.

My recommendation, stated as a recommendation: **do not ship Notes in v1 on this prompt.** Either
cut it to #269 as Email was, and ship v1 with Translate → X alone, or hold it until a candidate
measures ≤ 1/30 on this fixture set. Shipping it as it stands makes the flagship Pro capability
fail one French dictation in four, on the language the first paying users speak.

### Two follow-ups this run found that #79 does not cover

1. **`detectedLanguageMatches` is a dominant-language check and a bilingual output evades it.**
   Measured: an English-dominant bullet list on a French dictation reads as French at 0.789. The
   fail-closed guarantee has a hole exactly where Notes lives. Needs its own issue.
2. **A prompt's worked examples can be copied verbatim into a user's document.** Measured once in
   30 calls, on the shipping Notes prompt. Every mode carries examples; nothing detects this.
