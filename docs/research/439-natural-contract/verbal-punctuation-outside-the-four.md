# Verbal punctuation is not removed outside the four supported languages

**Measured 2026-08-29**, on the branch for #441, after CodeRabbit raised the contradiction
between rule 4 and the new deletion ban.

## What was claimed, and what is true

The triage commit claimed the contradiction was *inert* on `fr`/`en`/`es`/`de` — because
`VerbalPunctuationPrepass` runs in code before the model — and **live** on the auto path
with an unsupported language, where `PolishPipeline.autoPreprocess` returns the raw
unchanged and rule 4 is the only mechanism.

The first half holds. **The second half was an assumption and it is wrong**, in the sense
that mattered: fixing the wording does not fix the behaviour.

## The measurement

`harness/probe-unsupported-verbal.json` — one Italian and one Portuguese dictation, each
containing spoken punctuation commands. Both languages are outside `SupportedLanguage`,
so no pre-pass runs and `PolishAutoPrompt` is alone.

A/B over 5 passes, the two prompts differing by **one line** and nothing else:

- **A** — the ban as #441 first wrote it: *"Every noun … in the input appears in the
  output. Rules 5 and 6 … are the only licence to remove a word."*
- **B** — the ban corrected: scoped to what the speaker DICTATED, naming rule 4 alongside
  5 and 6.

| | command removed (the wanted result) |
|---|---|
| A, Italian | **0/5** |
| A, Portuguese | **0/5** |
| B, Italian | **0/5** |
| B, Portuguese | **0/5** |

`punto esclamativo`, `virgola`, `ponto final` and `vírgula` survive into the output as
words, under both wordings. One Portuguese run out of ten removed them and invented a
clause while doing it.

## What this means

- **The correction stands, on coherence grounds only.** A prompt that says "delete
  `virgule`" and "every noun survives" in the same breath is wrong whatever the model
  does with it, and the auto path is where nothing else covers for it. But it buys no
  measured behaviour, and the commit must not claim otherwise.
- **The real defect is upstream and is not #441's.** Spoken punctuation works because a
  regex pass in code does it, and that pass only knows four languages. Every other
  language gets whatever Apple FM decides, which is measured here as "nothing". A user
  dictating Italian into Dictus says "virgola" and reads `virgola`.
- **Same shape as bar 1.** #439 already measured that Apple FM will not repair a homophone
  under any instruction tried. This is a second instruction the model does not honour, and
  the answer is the same: put it in code or do not promise it.

## Not fixed here

Widening the pre-pass to more languages is a change to `VerbalPunctuationPrepass`, not to
a prompt, and it needs its own vocabulary per language. Out of #441's scope.
