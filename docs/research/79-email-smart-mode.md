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

Eight rounds, 240 model calls, all on this Mac with Apple Intelligence enabled (macOS 26.5.1,
`SystemLanguageModel.default.availability == .available`). Every raw output is in
`docs/research/79-email/raw/`, one file per round, unedited.

**Every call in every round returned `outcome = success`.** The length guardrail never rejected
anything, so `final` and the engine output are the same string throughout and nothing in the
tables below was laundered by the deterministic floor.

| # | Prompt | User-turn framing | Runs | Verdict |
| --- | --- | --- | --- | --- |
| 0 | shipping `PolishNaturalPromptFR` | shipping | 3 × 10 | baseline column |
| 1 | `B-email-v1` | shipping | 3 × 10 | fail — chat-reply contamination |
| 2 | `B-email-v2` | shipping | 3 × 10 | fail — register collapsed, one meaning inversion |
| 3 | `B-email-v2` | **email** | 3 × 10 | **fail — the #79 failure reproduces** |
| 4 | `B-email-v3` | shipping | 3 × 10 | fail — bar B1 at 7/10 |
| 5 | `B-email-v4` | shipping | 3 × 10 | fail — bar B1 at 7/10 |
| 6 | `B-email-v4` | shipping | 5 × 10 | bar A clean, bar B1 at 8/10 |
| 7 | `B-email-v4` | **email** | 1 × 10 | invention reproduces on the hardened prompt |
| 8 | `A` vs `B-email-v4` side by side | shipping | 1 × 10 | the artefact in §5 |

### Round 0 — the baseline

Free polish on these fixtures does what ADR 0003 promises: 0 inventions in 30 outputs. So any
invention seen later is attributable to the Email prompt, not to the fixtures.

Two incidental observations, out of scope but recorded because they were measured: free polish
expanded `dispo` → `disponible` (3/3) and `prod` → `production` (1/3), both of which ADR 0003's
PRESERVE list explicitly forbids; and it produced ungrammatical French on E6 (`Je ne l'arrive pas
à retrouver`, run 1; `Je suis arrivé pas à le retrouver`, round 8). Neither belongs to #79.

### Round 1 — `B-email-v1`, shipping framing

Bar A clean, 0/30, including on E3 (`je confirme pour la réunion de lundi à 14h` — the shortest
input, the one most tempting to pad) which produced `Je vous confirme ma présence à la réunion de
lundi à 14 h.` three times out of three, with no greeting and no signature. Bar B1 at 8/10.

Failed on something the bars did not name. E2 run 3:

```
Bien sûr, voici la version polie du texte:
"Oui, alors je suis disponible mardi après-midi ou jeudi matin, mais le mercredi, je suis occupé
toute la journée. Dis-moi ce qui t'arrive."
```

The model addressed the user and quoted its own answer — and the phrase it used, *"la version
polie"*, is a direct echo of the hardcoded user turn. That is the framing confound announced in §3
showing up in the output. `ce qui t'arrange` also became `ce qui t'arrive`, which means something
else.

### Round 2 — `B-email-v2`, shipping framing

Hardened against the preamble; it worked, 0/30 chat replies. But the added caution ("if you are
not sure of an equivalent, keep the speaker's word") made the model collapse toward free polish:
E2 came back with `c'est mort`, `un truc` and `t'arrange` intact, i.e. indistinguishable from the
baseline, where v1 had lifted all three.

And E4 run 2 turned `franchement j'en ai marre` into **`franchement, je suis vraiment désolé`** —
the complaint became an apology. A user chasing a provider for the third time would have sent an
apology. That is worse than an invented `Cordialement`, and no bar in §1 catches it.

### Round 3 — `B-email-v2`, EMAIL framing — the decisive round

Same prompt as round 2. The only change is the user turn: `Rewrite this dictation as the body of
an email. […] Email body:` instead of `Polish this text. […] Polished output:`.

Bar A goes from 0/30 to **5/30**:

```
E1 #1  Bonjour,
       Je voulais revenir sur le devis […] cela me serait utile.
       Merci d'avance.

E1 #3  Bonjour, je voulais revenir sur le devis […]

E9 #1  Julien,
       J'ai regardé ce que tu m'as envoyé […]
       À bientôt,
       [Your Name]

E9 #3  (same, including [Your Name])

E9 #2  Je suis Julien, je vous écris pour vous faire part de ma récente analyse […]
```

`[Your Name]` — an English signature placeholder in a French email. And E9 #2 is worse than a
hallucinated formula: the model decided the speaker **is** Julien, when Julien is the person being
addressed. It invented the sender's identity.

The email framing broke three other things at the same time:

- **E4 runs 1 and 2 returned the raw dictation byte-for-byte** — no punctuation, no capitals,
  nothing — and the pipeline recorded `success` both times.
- **E8 lost a fact in 2/3 runs**: `je pense qu'on peut valider comme ça` disappeared entirely.
- **E2 came back identical to free polish, 3/3.**

### Rounds 4 and 5 — `B-email-v3` and `B-email-v4`, shipping framing

v3 added the placeholder ban, the "a name in the dictation is the addressee, never the sender"
rule, and a "never return the dictation unchanged" rule. v4 restated the negation and
colloquialism rules generatively, after round 4 showed the model was pattern-matching the
enumerated examples rather than applying the rule (`j'arrive pas` → `je n'arrive pas` fired 3/3
because it is in the list; `je comprends pas` did not, because it was not).

Bar A: 0/30 on each. Bar B1: **7/10 on both** — below the pre-registered 8/10.

The interesting part is what did *not* move. `c'est mort` and `j'en ai marre` are written out in
the prompt, verbatim, with their replacements. Across rounds 4, 5 and 6 — 11 observations each —
`c'est mort` survived 9 times and `j'en ai marre` survived 11 times out of 11. This is not a
prompt-wording problem. Apple FM's on-device model declines to execute those substitutions on
French even when they are spelled out for it.

### Round 6 — `B-email-v4`, shipping framing, 5 runs

The confirmation round, 50 observations.

- **Bar A: 0/50.** No invented salutation, no invented sign-off, no name, no placeholder.
- **Bar B0: 9/10.** E10 is byte-identical to free polish, 5/5.
- **Bar B1: 8/10.** E4 and E10 fail; every other fixture shows at least one lift free polish did
  not make on the same input.

So v4 meets both pre-registered thresholds — at n = 5. The same prompt missed B1 at n = 3, twice,
because E7's negation restoration fires between 1/3 and 3/5 depending on the draw. That is a real
finding about the measurement and it is stated here rather than buried: **the B1 threshold is
being decided by sampling noise as much as by the prompt.**

Two defects the bars do not name, both from this round:

- **The form of address switches.** On E5 the speaker says `de ton côté`; v4 answered `de votre
  côté` in 4 of 5 runs, despite a dedicated absolute rule and an explicit self-check instruction.
  Switching `tu` to `vous` invents a relationship the model cannot know — the same class of harm
  as inventing a greeting, and #79's wording does not happen to cover it.
- **Email removes fewer fillers than free polish.** `euh` survived 5/5 on E1 under the Email
  prompt; free polish drops it more often.

### Round 7 — `B-email-v4`, EMAIL framing

The hardened prompt, under the email framing, `eval`, one run per fixture. E5:

```
Bonjour,
Je fais le point sur le projet. […] car cela commence à presser.
Merci d'avance.
[Votre Nom]
```

v4 explicitly forbids `[Your Name]`, `[Nom]`, `[Signature]`, `[Entreprise]` and `XXX`. The model
emitted `[Votre Nom]` — the one French variant not on the blocklist. Enumerating the placeholders
does not close the behaviour; it just moves it.

### Structure — the half of the axis that never arrived

#79's catalogue gives Email one axis: *"register — formal, paragraph structure"*.

Counting outputs containing a line break, across every round:

| Framing | Observations | Outputs with paragraph structure |
| --- | --- | --- |
| shipping (`Polish this text…`) | 190 | **0** |
| email (`…as the body of an email`) | 40 | 8 — **every one of them a hallucinated greeting, sign-off or `[Votre Nom]` line** |

The prompt invites paragraph breaks explicitly (rule 3, with the `<<NL>>` marker the pipeline
decodes). It never produced one. Under the framing that holds the invention line, the structure
half of the axis is delivered zero times out of 190. Under the framing that produces structure,
**the structure *is* the hallucination.**

---

## 5. Verdict

### Email is CUT as a built-in. Dictus Pro v1 ships two Smart Modes: Notes and Translate → X.

Email moves to #269, as #79's own conditional provides for.

This is not a failure to hold the salutation line. Under the shipping framing that line held
perfectly — **0 inventions in 190 observations**, which by the rule of three bounds the invention
rate below about 1.6 %. The candidate prompt is real and it is committed at
`docs/research/79-email/prompts/B-email-v4.txt`. Four things, in order of weight, say it should
not ship as a built-in anyway.

**1. Half the declared axis was never delivered.** 0 paragraph-structured outputs in 190 calls
under the working framing. Email's catalogue entry promises "register — **formal, paragraph
structure**". It delivers register, thinly, and no structure at all.

**2. The pass is conditional on never telling the model it is writing an email — and #79 is
committed to doing exactly that.** The issue lists per-mode user-turn framing as a required engine
change. The measurement says the invention rate is 0/190 when the framing says "polish" and 6/40
(15 %) when it says "email", on the same prompts. Shipping Email would mean shipping a mode whose
correctness rests on an implementation detail that reads like an oversight, that the parallel
pipeline branch has no reason to know about, and that the natural implementation ("rewrite as an
email") violates.

**3. What is left, once the structure is gone, is thin — and the complaint case never worked.**
Judged on the round-8 side-by-side below, a French reader would call the Email output visibly
different from free polish on 2 fixtures out of 10, modestly different on 2, and not different on
6. Bar B1's 8/10 counts a single word swap as a lift; that is what the bar said, and it is not
what "visibly different" means to a person looking at the two columns. Meanwhile E4 — the
complaint, the case where an Email mode most obviously earns its money — never lifted once in six
rounds and twenty observations, with the exact substitution written into the prompt.

**4. It costs roughly double the latency for that delta.** Round 8, same machine, same call:
free polish 1.4–3.0 s, Email 3.6–5.3 s.

Against that, one honest point on the other side: the register lift on E5, E6 and E3 is genuine and
free polish will never make it, because ADR 0003 forbids it. There *is* a real mode in here. It is
just not one that clears "visibly different" on the majority of real dictations today.

### Side by side — free polish (A) vs Email v4 (B)

Full run: `docs/research/79-email/raw/round8-ab-freepolish-vs-email-v4.txt`. Four fixtures, chosen
as the two best and the two worst cases for Email.

**E3 — the clearest win.**

```
raw: je confirme pour la réunion de lundi à 14h
A:   Je confirme pour la réunion de lundi à 14h.
B:   Je vous confirme ma présence à la réunion de lundi à 14 heures.
```

**E5 — a genuine lift, with a relationship invented on top of it.**

```
raw: […] par contre le dev il a pris du retard […] je sais pas si c'est jouable de ton côté […]
A:   […] Par contre, le dev a pris du retard […] Je sais pas si c'est jouable de ton côté. […]
B:   […] Par contre, le développement a pris du retard […] Je ne sais pas si c'est envisageable
     de votre côté, […]
```

`dev` → `développement`, `je sais pas` → `je ne sais pas`, `jouable` → `envisageable`: three lifts
ADR 0003 forbids free polish from making. And `de ton côté` → `de votre côté`, which the speaker
did not say.

**E4 — the complaint. Six rounds, twenty observations, never lifted.**

```
raw: […] ça fait deux semaines que ça dure là franchement j'en ai marre je veux qu'on me rappelle
A:   […] Ça fait deux semaines que ça dure, franchement, j'en ai marre. Je veux qu'on me rappelle.
B:   […] Ça fait maintenant deux semaines que ça dure, et franchement, j'en ai marre. Je veux
     qu'on me rappelle.
```

The only difference is the word `maintenant`, which the speaker did not say.

**E10 — byte-identical.**

```
raw: je vous prie de bien vouloir trouver ci-joint les documents demandés […]
A:   Je vous prie de bien vouloir trouver ci-joint les documents demandés. Je reste à votre
     disposition pour toute information complémentaire.
B:   Je vous prie de bien vouloir trouver ci-joint les documents demandés. Je reste à votre
     disposition pour toute information complémentaire.
```

Correct behaviour — there is nothing to lift — but it is what a paid mode looks like on an input
that is already written well.

### What #269 inherits from this

The custom-mode editor is the right home, and this measurement hands it four things:

1. **`B-email-v4.txt` is a working starting point** for a user who wants an Email mode, and it is
   already written in the one-English-prompt-per-mode form #239 established.
2. **Never put the word "email" in a custom mode's framing** — or in any framing that reaches a
   mode which must not invent people. This is the single most transferable finding here, and it
   applies to any future mode with a strong genre prior (letter, CV, press release).
3. **Placeholder bans do not generalise.** Banning `[Your Name]` produced `[Votre Nom]`. A custom
   mode's guardrail should look for the *shape* `[…]` rather than a word list.
4. **#269 already says a custom mode has no meaningful acceptance contract.** This measurement
   adds a specific one worth having: reject any output containing a bracketed placeholder, and
   reject any output that adds an opener or closer absent from the input. Both are cheap regexes
   and both would have caught every failure in rounds 3 and 7.

### Two things worth flagging beyond #79's scope

- **The length guardrail caught nothing.** Every one of the 240 calls, including
  `Bonjour, / … / Merci d'avance. / [Votre Nom]`, landed inside the 0.5–2.0 band and was recorded
  as `success`. #79 assigns Email the Natural band on the assumption it is a meaningful check for
  this mode. It is not: an invented greeting and signature cost about 25 % of the length. Whatever
  contract a future Email-like mode carries, the length band is not it.
- **Free polish violates ADR 0003's PRESERVE list on `dispo` and `prod`** (round 0, measured), and
  produced ungrammatical French twice on E6. Separate from #79; worth its own issue if it
  reproduces on device.

### Reproducing this

```sh
cd DictusCore
swift run polish-harness show Sources/polish-harness/fixtures/email-fr.json --runs 5            # A
swift run polish-harness show Sources/polish-harness/fixtures/email-fr.json --runs 5 \
    --instructions ../docs/research/79-email/prompts/B-email-v4.txt                             # B
swift run polish-harness eval Sources/polish-harness/fixtures/email-fr.json \
    --instructions ../docs/research/79-email/prompts/B-email-v4.txt \
    --framing ../docs/research/79-email/prompts/framing-email.txt                               # the failure
```

### The one harness source change, and why

`--instructions` overrides the system prompt only, so the stock harness cannot vary the user turn
— and the user turn turned out to be the variable that decides this question. Two files, confined
to `DictusCore/Sources/polish-harness/`, no shipping source touched:

- `FramedAppleFMPolishEngine.swift` — Apple FM with a caller-supplied user turn. Same model, same
  `LanguageModelSession(instructions:)` wrapper, same one-call stateless lifecycle, same
  `PolishPipeline` and guardrails around it.
- `main.swift` — a `--framing <file>` flag on `show` and `eval`, which requires `--instructions`
  and refuses `--engine local`.

`swiftlint lint --strict`: 0 violations in 198 files. `cd DictusCore && swift test`: 1075 tests,
0 failures.

### Caveats

- **Mac, not iPhone.** Same foundation-model family; revision and state can differ. The harness's
  own README says to confirm on device before shipping a prompt. Nothing here was device-checked,
  and the verdict is "do not ship", so nothing here needs to be.
- **n = 190 bounds the invention rate below ~1.6 %, not below 0.1 %.** A rate low enough to look
  clean in 190 draws is not a proof of impossibility.
- **The fixtures are mine, not field data.** They were written to be adversarial for the failure
  mode, in the register Parakeet emits, and committed before any model ran — but a real corpus of
  Pierre's own dictations would be better evidence, and does not exist.
- **One language.** French only, as #79 asked. An English or German Email prompt could behave
  differently, and the genre-prior finding in particular is a property of the model's training
  data, not of French.
- **Bar B1 is a noisy statistic** at these sample sizes; §4 round 6 says where and by how much.
