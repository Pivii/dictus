# ANE harness — #268 D2

**Throwaway.** Nothing here is a step toward shipping a second LLM backend. It
exists to answer one question and is meant to be deleted with the branch:

> Can a backgrounded DictusApp reach the Neural Engine to run an LLM, and hold a
> ~1,700-token prefill there?

Nothing in `Dictus.xcodeproj`, `DictusCore`, or CI references this directory.
The findings are in [`docs/research/268-ane-background-llm.md`](../../docs/research/268-ane-background-llm.md).

## What it measures, and on what

- **Model:** `anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5` — ANEMLL's own
  pre-converted Core ML build of Qwen3 1.7B. 2048-token context, batch 64, LUT6
  on the FFN and LM head. 1.8 GB of `.mlmodelc` on disk.
- **Prompt:** the shipping one, built at runtime from DictusCore — the resolved
  `PolishNaturalPromptFR` instructions as the system message and the `3-long`
  fixture through `VerbalPunctuationPrepass` in the Input/"Polished output:"
  framing. ~1,680 tokens by the model's own tokenizer.
- **Compute units:** `.cpuAndNeuralEngine`, the value FluidAudio sets for
  Parakeet — the one path this product already knows runs backgrounded.

## Setup

```bash
cd tools/ane-harness
./setup.sh          # clones ANEMLL at a pinned sha, downloads 1.8 GB of weights
```

Both land in `.deps/`, which is gitignored. `setup.sh` also copies
`seed.json` next to the kit's sources, so the harness reads the same fixture the
polish harness does rather than a transcription of it.

## Mac gate

Does it load, is Core ML really placing it on the ANE, is the French sane:

```bash
cd tools/ane-harness/AneBenchKit
swift run -c release ane-bench --iterations 2
swift run -c release ane-bench --iterations 1 --max-tokens 60 --compute-units cpu   # the control
```

A Mac has no jetsam and no application lifecycle, so this cannot answer #268.
It is a floor and a sanity check, exactly as the predecessor spike's Mac figures
were.

## Phone

```bash
cd tools/ane-harness
xcodegen
xcodebuild build -project AneHarness.xcodeproj -scheme AneHarness -configuration Debug \
  -destination 'id=<device-id>' -derivedDataPath build/DerivedData -allowProvisioningUpdates
xcrun devicectl device install app --device <device-id> \
  build/DerivedData/Build/Products/Debug-iphoneos/AneHarness.app
```

The app is ~1.8 GB, so the install takes a couple of minutes over Wi-Fi.

Then, with the phone **unlocked**:

```bash
xcrun devicectl device process launch --device <device-id> --terminate-existing com.pivi.dictus.anebench
```

It loads the model in the foreground, then shows "Loaded. Press Home now." and
waits. Press Home — or launch any other app from the Mac, which backgrounds it
the same way — and it runs on its own. Nothing needs tapping while it runs.

Follow it and collect it without touching the phone:

```bash
xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer \
  --domain-identifier com.pivi.dictus.anebench --source Documents --destination ./out
```

`Documents/phase.txt` is one word — `loading`, `waiting-for-background`,
`running`, `done`, `failed`. The results are `ane-bench-<epoch>.txt` and
`.json`. They are also on screen when the app is reopened, with a share sheet.

**Every reading carries the lifecycle state it was taken in**, and the report
prints `allIterationsBackgrounded`. A run that says `state=active` is not an
answer to #268 and the file says so rather than looking like one.

## Layout

| Path | What |
| --- | --- |
| `setup.sh` | fetches ANEMLL + the model, copies the fixtures |
| `AneBenchKit/` | the SwiftPM package: prompt, runner, compute-plan probe, `ane-bench` CLI |
| `App/` | the iOS app: audio keep-alive, self-running protocol, result writing |
| `project.yml` | xcodegen input; regenerate with `xcodegen` |
| `.deps/` | gitignored — the ANEMLL checkout and the weights |

## Two things that are not obvious

**Thinking is off, deliberately.** Qwen 3 reasons before answering unless the
chat template emits an empty `<think></think>` block, and the predecessor spike
threw away a whole measurement pass after finding it had run with thinking
silently on. `AneBenchRunner.tokens(for:tokenizer:)` appends that block.

**No App Group.** #268 asked for the results to come out through the persistent
log, and this bundle id cannot be signed with `group.solutions.pivi.dictus` on
this machine — see the comment in `project.yml`. The write is attempted and its
outcome reported; what actually carries the numbers is the app's own Documents
directory.
