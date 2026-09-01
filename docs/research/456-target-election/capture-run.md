# The captured #456 transcript, run through the path the fix selects

Acceptance criterion 1 has two halves. The first — *does it elect `fr`* — is settled
offline and pinned by tests. The second — *is its French translated* — needs the model,
so it was measured rather than argued.

```sh
cd DictusCore
swift run polish-harness show ../docs/research/456-target-election/capture-fixture.json --runs 5
```

Apple Foundation Models on macOS 26.5.1, 2026-09-01. **Not** CI-runnable: Apple FM is
non-deterministic and absent from CI runners.

## Route

Every run: `detected=fr→natural`.

Before the fix the same input routed `detected=en→repair` — the whole-blob reading gave
`en`, which against a French target selects Repair, the mode licensed to substitute
words to reconstruct intent in the target language. Both halves of that were wrong: the
target was English on device, and the mode was the permissive one.

## Result: the French survives 5/5

Every run keeps `curseur`, `héros`, `la cloche`, `l'utilisateur`, and returns French
prose. The shipped failure — 100 % English output from a 78 % French input — does not
reproduce on any run.

Length ratios all sit inside the Natural band `[0.5, 2.0]`; the four declared
expectations (`contains curseur`, `contains héros`, ratio bounds) hold on all five.

## Two things a reader should see, neither of them a pass

**1. The English head is reconstructed in French, not preserved.** All five runs turn
`Okay, it's coming to approach to what I've got on the pencil to other children` into
French. Under ADR 0003 rule 8 that is authorised — an off-language fragment that does
not fit is a repair target — and those 105 characters were never the user's words in
the first place: they are Parakeet mistranscribing French speech as English. So the fix
does not make the pipeline stop translating altogether; it moves what gets translated
from *the 78 % the user said* to *the 22 % the ASR invented*. That is the intended
direction, and it is a judgement worth stating rather than burying.

**2. Four of five runs carry an Apple FM chat-reply preamble** —
`Bien sûr, voici une version polie de votre texte :`. This is **not** introduced by this
change: it appeared on all five runs of the pre-fix Repair route too. The language
guardrail cannot see it (the preamble is in the target language) and the length
guardrail cannot either (ratio ≈ 1.06, well inside the band). It does not reproduce on
any of the 14 shipped `seed.json` fixtures, which all come back clean — it is specific
to this transcript, which is bilingual and semantically incoherent. Left alone here
because it is a different defect with a different guardrail, and fixing it inside a
target-election PR would hide it.

## Regression check

`swift run polish-harness eval Sources/polish-harness/fixtures/seed.json` → **14/14**
fixtures pass all declared checks. `7-repair-de` rejects on the guardrail, which is
ADR 0002's documented DE-Repair leak and pre-dates this branch.
