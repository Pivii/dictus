# polish-harness

Off-device eval harness for the polish layer (#141). Runs the **real** pipeline
— `PolishPipeline` + `AppleFoundationModelsPolishEngine` + the deterministic
pre/post-passes — on text fixtures, on a Mac, sharing one source of truth with
the app. It is the fast iteration loop for prompt/quality work and the safety
net for the upcoming third-party-LLM migration (any `PolishEngineProtocol`
engine plugs in unchanged).

## Requirements

- macOS 26+ on Apple Silicon with **Apple Intelligence enabled** (System
  Settings → Apple Intelligence & Siri). Without it the model is unavailable and
  the harness exits with an error.
- Run from the `DictusCore/` package directory.

The polish input is **text** (the `raw` field of a device JSON export) — no
audio is needed.

## Usage

```sh
cd DictusCore

# Show raw → polished for each fixture
swift run polish-harness show Sources/polish-harness/fixtures/seed.json

# Run each fixture N times to gauge sampling variance
swift run polish-harness show Sources/polish-harness/fixtures/seed.json --runs 3

# Property-check the contract (pass/fail report)
swift run polish-harness eval Sources/polish-harness/fixtures/seed.json

# Test a candidate prompt without recompiling (overrides the system prompt)
swift run polish-harness show fixtures/seed.json --instructions /tmp/candidate.txt

# A/B two prompt files side by side
swift run polish-harness ab fixtures/seed.json --a /tmp/baseline.txt --b /tmp/candidate.txt

# Reroute a whole fixture file (#439). Which prompt a dictation reaches is a
# device SETTING, not a property of the text: an `autoDetect` device sends French
# to PolishAutoPrompt, a French-pinned one to PolishNaturalPromptFR. Both have to
# hold, so one fixture file measures both.
#
# An expectation that only holds on ONE of the two routes carries
# `"onlyOnRoute": "perLanguage"` or `"auto"`, and `eval` filters on it. There is
# one today: `notContains: "I think"` on `3-message-draft`. The off-language
# fragment is a rule-8 repair target for PolishNaturalPromptFR and is PRESERVED
# by name under PolishAutoPrompt, so asserting it on both routes would score the
# auto prompt's own contract as a failure. `notContains: "salle à tante"` is NOT
# marked and must not be: auto simply carries no rule 8, and that gap is the
# measurement rather than a false failure.
swift run polish-harness show Sources/polish-harness/fixtures/longform-fr.json --lang auto

# Print the exact bytes the engine sends for a fixture: the resolved system
# instructions and the Input/"Polished output:" user turn over pre-passed text.
# Runs no model, so it needs no Apple Intelligence. --out writes them as files.
swift run polish-harness prompt Sources/polish-harness/fixtures/seed.json --id 3-long
```

`prompt` covers the per-language path only — a fixture that routes through auto
mode has no per-language prompt to resolve, and it says so and exits.

## Smart Modes (#79, #393)

`--mode <identifier>` arms a Smart Mode instead of the free polish. What runs is
the mode's system prompt, **its own user-turn framing**, and — the part that
cannot be inherited — **its own acceptance contract**: the free-polish bands
reject Notes for condensing and Translate for changing language, which is the
whole reason a mode carries a contract of its own. Identifiers are catalogue
identifiers (`notes`, `translate.en`, …); an unknown one lists what the build
ships.

```sh
# Run a mode over a fixture set, five samples per fixture. Ends with an outcome
# tally — the drift RATE, which a device session cannot produce.
swift run polish-harness show Sources/polish-harness/fixtures/notes-fr.json --mode notes --runs 5

# The comparison #79 requires: the mode against free polish, both on their
# shipping prompts. The sides differ by TASK, so neither --a nor --b is needed.
swift run polish-harness ab Sources/polish-harness/fixtures/notes-fr.json --mode-b notes

# A prompt candidate against the shipping one, on the same mode.
swift run polish-harness ab fixtures/notes-fr.json --mode notes --b /tmp/notes-v2.txt

# The exact bytes a mode sends. Runs no model, so it needs no Apple Intelligence.
swift run polish-harness prompt fixtures/notes-fr.json --mode notes --id N1-field-commits
```

Two gates behave differently under a mode, and the harness mirrors the app
(`PolishGatePolicy`): the gibberish gate does not skip, so an input in a
language outside the four reaches the engine, and a non-success inserts
**nothing** rather than the untransformed floor. A refusal prints as
`<refused — a Smart Mode inserts nothing>`, with the engine's actual output on
the `engineOut` line beneath it.

Mode fixtures: `fixtures/notes-fr.json` and `fixtures/translate-en.json`. They
are written to put pressure on their mode — a field dictation that failed on
device, rambles with no structure, input already partly in the target language,
and input in a language outside the four.

## Guardrail corpora (#413, #414, #466)

`guardrail` scores the three output-inspection checks — the per-segment language
check, the grounding check and the prefix-alignment check — against corpora of
**hand-labelled outputs**, not fixtures of raw inputs. It drives **no model**:
two of the three are deterministic local `NaturalLanguage` calls and the third
is a word-set comparison. That is the point: unlike every other command here,
this measurement is re-runnable by anyone, with or without Apple Intelligence,
so the numbers behind the shipped thresholds are reproducible rather than a
claim.

```sh
# The confusion matrix at the shipping thresholds.
swift run polish-harness guardrail ../docs/research/413-414-guardrail/corpus.json \
                                   ../docs/research/413-414-guardrail/adversarial.json \
                                   ../docs/research/413-414-guardrail/freepolish.json

# --sweep    the threshold grids the #413 and #466 numbers were read off
# --segments every segment with its language reading and confidence
# --anchors  every name found per output, flagged when absent from the input
```

Corpora live in `docs/research/413-414-guardrail/`: `corpus.json` is every
output the #393 campaign committed, `adversarial.json` the cases it does not
contain — a French list quoting English product names, a German list (where
every noun is capitalised), bullets too short to read, bare proper nouns,
hand-built fabrications, and since #466 the two device captures of Apple FM
writing about its own task. `freepolish.json` (#466) is the campaign's
free-polish rounds harvested verbatim from `raw/`, because the prefix check runs
**only** on the free polish and the other two files hold 14 such outputs between
them. Labels are in the JSON rather than in code because they are judgements,
and a judgement that decides a threshold has to be disagreeable with in the
open.

The prefix check is scored with `natural + auto` and `repair` split apart rather
than totalled. Repair is selected exactly when the detected language differs
from the target, so its output shares no vocabulary with its input and the check
refuses all of it — 10 of 10, at every pair swept. That is why the mode's
contract turns the check off, and the split is what keeps the fact visible
instead of averaged away.

## Fixtures

A JSON array of cases (`fixtures/seed.json` seeds the 5 Wispr-Flow comparison
cases). Each case:

```json
{
  "id": "2-bilingue",
  "lang": "fr",                // fr | en | es | de  → target language
  "sttEngine": "PK",           // PK (Parakeet, default) | WK (WhisperKit)
  "raw": "…the raw STT text…", // paste from a device export's `raw` field
  "expect": [                  // optional, used by `eval`
    { "contains": "commit" },
    { "notContains": "validation" },
    { "regexAbsent": "\\n\\n\\n" },
    { "lengthRatioMin": 0.85 },
    { "lengthRatioMax": 1.3 }
  ]
}
```

Expectations are **tolerant property checks** (the contract), not exact-string
matches — LLM output is non-deterministic, so we assert "preserves `commit`",
"no stray `\n\n\n`", "length within ±X%", never a fixed string.

`lang` decides the path, and `--lang <code>` overrides it for the whole file.

Long-form set: `fixtures/longform-fr.json` — the six French dictations measured
on device on 2026-08-27 (#437), `raw` verbatim from the debug-ring export. They
are the fixture set for both #437 (structure) and #439 (fidelity); the
expectations currently in the file are #439's bars, declared in
`docs/research/439-natural-contract/bars.md` before the first model call.

## Caveats

- **Not deterministic.** Apple FM samples — re-run (`--runs`) to gauge variance;
  a single `eval` pass is a signal, not a gate.
- **Mac ≈ iPhone, not identical.** Same foundation-model family, but revision /
  state can differ. Use the harness to iterate fast; **confirm on device before
  shipping** a prompt change.
- **Not in CI.** Needs Apple Intelligence (absent from CI runners) and is slow.
  The deterministic passes are covered by `swift test` (`PolishPostpassTests`,
  `VerbalPunctuationPrepassTests`, `PolishPipelineTests`).
