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

# Print the exact bytes the engine sends for a fixture: the resolved system
# instructions and the Input/"Polished output:" user turn over pre-passed text.
# Runs no model, so it needs no Apple Intelligence. --out writes them as files.
swift run polish-harness prompt Sources/polish-harness/fixtures/seed.json --id 3-long
```

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

## Caveats

- **Not deterministic.** Apple FM samples — re-run (`--runs`) to gauge variance;
  a single `eval` pass is a signal, not a gate.
- **Mac ≈ iPhone, not identical.** Same foundation-model family, but revision /
  state can differ. Use the harness to iterate fast; **confirm on device before
  shipping** a prompt change.
- **Not in CI.** Needs Apple Intelligence (absent from CI runners) and is slow.
  The deterministic passes are covered by `swift test` (`PolishPostpassTests`,
  `VerbalPunctuationPrepassTests`, `PolishPipelineTests`).
