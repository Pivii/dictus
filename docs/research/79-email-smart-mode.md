# Email Smart Mode — harness validation

**Issue:** [#79](https://github.com/getdictus/dictus-ios/issues/79)
**Question:** does Dictus Pro v1 ship **two** Smart Modes or **three**?
**Scope:** measurement only. No change to any shipping Swift source. The deliverable is a
candidate prompt, French fixtures, and a verdict.
**Date:** 2026-08-23.

> **The plan below (§1–§3) was written and committed BEFORE any model was run**, so the
> findings can be checked against what was promised rather than against what turned out to be
> convenient. See the commit `docs(research): record the Email harness plan before measuring
> (refs #79)`. Everything from §4 on was written after.

---

## 0. What is being decided

#79 ships Notes and Translate → X as certain, and makes Email conditional:

> Two independent implementations (Superwhisper, Dictus Desktop) fail the same way: they invent
> greetings and sign-offs the user never dictated, with names the model cannot know. […] The
> Dictus Email prompt must change register and structure and **invent neither salutation nor
> signature**. If it cannot hold that line on real French dictations in `polish-harness`, Email
> ships as a custom mode (#269) instead of a built-in, and v1 ships two modes.

and, catalogue-wide:

> **Any mode whose output is not visibly different from free polish is cut.**

So there are two independent bars, and Email must clear **both**.

---

## 1. The bars, stated before any output was seen

### Bar A — invents neither salutation nor signature

A **failure** is any of:

- **A1** — an opener addressed to a recipient that has no counterpart in the raw dictation.
  Machine-checked per fixture by `regexAbsent` over
  `(?i)\b(bonjour|bonsoir|salut|coucou|cher|chère|chers|madame|monsieur|hello|hey)\b`, with the
  alternatives the speaker actually said removed from that fixture's regex.
- **A2** — a closing formula with no counterpart in the raw. Machine-checked by `regexAbsent`
  over `(?i)(cordialement|bien à vous|sincèrement|salutations|amicalement|bonne journée|bonne
  réception|à bientôt|dans l'attente|au plaisir|merci d'avance|en vous remerciant|
  respectueusement)`, same per-fixture subtraction.
- **A3** — any invented proper noun: a recipient name, a surname, a company, a sender signature.
  Read by hand on every output, because no regex can enumerate names.

**Pre-registered pass threshold: zero failures over the whole fixture set × 3 runs.** Not "few".
The issue's own framing is *hallucinated content in a message the user is about to send*; a
1-in-30 invention rate still means the user occasionally sends a mail signed by a name they never
uttered. So the bar is 0/N, and a candidate that produces one invention over three runs fails and
gets iterated on.

Two measurement rules, fixed now:

- **Bar A is scored on the ENGINE output, not on the final string.** When the length guardrail
  rejects an output the pipeline returns the deterministic floor, which by construction contains
  no invention — scoring `final` would launder a hallucinating prompt into a pass. `show` prints
  `engineOut` on every non-success, so both are visible.
- **A guardrail rejection is itself a failure**, recorded separately. #79 requires that a mode
  never silently insert untransformed text; a rejected Email output is exactly that.

### Bar B — visibly different from free polish

Compared against the **shipping** French Natural prompt
(`PolishNaturalPromptFR`, dumped verbatim to `prompts/A-baseline-natural-fr.txt`), on the same
fixtures, in the same session.

- **B0 — the floor (hard gate, 10/10 fixtures).** The Email output must differ from the free
  polish output by more than punctuation and casing. If they are the same string modulo
  punctuation, the mode moves the text along no axis and #79 cuts it by its own rule.
- **B1 — register (the substantive gate, ≥ 8/10 fixtures).** The Email output must show at least
  one register lift that ADR 0003 explicitly **forbids** free polish from making: `tu` → `vous`,
  oral negation restored (`je sais pas` → `je ne sais pas`), a familiar abbreviation expanded
  (`dispo` → `disponible`), a familiar contraction expanded (`t'es` → `vous êtes`), or a
  colloquialism replaced (`c'est mort` → a neutral equivalent). 8/10 rather than 10/10 because
  E10 is deliberately already formal and E3 is a single clause with almost no surface to lift.
- **B2 — structure.** Reported as an observation, not gated: a two-sentence dictation has no
  structure to reorganise, so a threshold over the whole set would measure the fixtures rather
  than the prompt.

---

## 2. Fixtures

`DictusCore/Sources/polish-harness/fixtures/email-fr.json` — 10 French dictations, written for
this measurement, in the register and shape Parakeet emits (no punctuation, fillers, run-ons).
They are not user data; Dictus keeps none.

The set is designed around the failure mode, not around Email in general:

| Fixture | Shape | What it puts pressure on |
| --- | --- | --- |
| E1 `relance-devis` | bare | the archetypal "this is an email" input |
| E2 `dispo` | bare, familiar | invention **and** register lift |
| E3 `court` | bare, one clause | padding a short input into a letter |
| E4 `reclamation` | bare, irritated | inventing a polite frame the speaker refused |
| E5 `long-projet` | bare, long, multi-topic | the structure half of the axis |
| E6 `demande-fichier` | bare, a request | "Bonjour X" + "Merci d'avance" bait |
| E7 `salutation-seule` | **control** | speaker said a greeting, no sign-off → completing the pair |
| E8 `signature-seule` | **control** | speaker said a closing thanks, no greeting → mirror of E7 |
| E9 `prenom` | **control** | a first name is given → inventing a surname or a sender signature |
| E10 `deja-formel` | **control** | already formal → the fixture most likely to fail bar B |

Six bare fixtures carry bar A. Four controls exist to catch the two ways a prompt can cheat:
suppressing every formula including the ones the speaker *did* say (E7, E8), and treating a known
first name as a licence to invent the rest of an identity (E9).

---

## 3. Method

- Baseline column: `swift run polish-harness show fixtures/email-fr.json --runs 3` — shipping
  prompt, no override. Also confirms free polish does not itself invent on these inputs.
- Candidate column: `swift run polish-harness show fixtures/email-fr.json --instructions
  prompts/<candidate>.txt --runs 3`.
- Machine cross-check: `swift run polish-harness eval fixtures/email-fr.json --instructions
  prompts/<candidate>.txt` (with the `engineOut` caveat above).
- Side-by-side for the maintainer's own eyes: `swift run polish-harness ab fixtures/email-fr.json
  --a prompts/A-baseline-natural-fr.txt --b prompts/<candidate>.txt`.
- Every round is recorded, including the ones that fail. Raw outputs are kept under
  `docs/research/79-email/raw/`.

### The framing confound, declared up front

`--instructions` overrides the **system** prompt only. The user turn is hardcoded in the shipping
engine (`AppleFoundationModelsPolishEngine.polish`) as:

```
Polish this text. Output only the polished version, nothing else.
```

#79 already says this framing has to become per-mode — *"asking the model to produce notes under
an instruction that says 'polish' is self-defeating"*. So the stock harness measures the Email
prompt under an instruction that says "polish".

Order of operations, fixed now: measure under the stock framing first, because that is the
zero-source-change measurement and the conservative one. Only if the stock framing is what blocks
bar B does a framing-capable engine get added, confined to `Sources/polish-harness/`, and both
numbers get reported.

---

## 4. Rounds

*(written after measuring)*

---

## 5. Verdict

*(written after measuring)*
