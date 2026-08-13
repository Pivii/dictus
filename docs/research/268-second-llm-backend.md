# A second local LLM backend — spike findings

**Issue:** [#268](https://github.com/getdictus/dictus-ios/issues/268)
**Scope:** measurement only. No production integration, no shipped `PolishEngineProtocol` implementation, no change to `PolishCoordinator` or to any app target.
**Date:** 2026-08-13.

The plan for this spike — the decision rule, the candidate list, the thresholds —
was written and committed **before** any measurement was taken, so the findings
below can be checked against what was promised rather than against what turned
out to be convenient. See the first commit on this branch,
`docs(research): record the spike plan before measuring (refs #268)` (`203ab97`).

---

## Evidence labels

Every claim carries one, and the label is part of the claim.

| Label | Meaning |
| --- | --- |
| **[code]** | Read in this repository, cited by file and line. |
| **[sdk]** | Read in the iOS SDK headers shipped with Xcode on this machine, cited by path. |
| **[source]** | Official API reference, official model card, or a named third-party source file, cited by URL or path. |
| **[measured]** | Produced by running something during this spike. The command is recorded. |
| **[field]** | Recorded on the maintainer's own device and quoted in the tracker. |
| **[derived]** | Arithmetic or inference on top of a sourced fact. The input is sourced; the output is not quoted. |
| **[secondary]** | Blog post, forum answer, press coverage. Context only. |

**Nothing labelled [secondary] carries a decision in this document.** The search
results for "best small LLM 2026" are uniformly SEO content and were excluded on
that basis; every model fact below comes from an official model card or from a
run on this machine.

---

## Summary

Seven things, in the order they matter.

1. **The GPU is not available to this app, and that invalidates every published iPhone LLM benchmark.** Apple's own Core ML documentation says to restrict a model to the CPU "**if your app might run in the background**" **[source]**, UIKit's background guidance says "**Don't commit any new Metal work to be processed**" **[source]**, and iOS 26 added a *separate, entitlement-gated* capability for background GPU work that is scoped to `BGContinuedProcessingTask` and "**not supported on all devices**" **[sdk]**. DictusApp is backgrounded for every polish call. So the candidate must run on **CPU or the Neural Engine**, and essentially every tok/s figure published for on-device LLMs is a Metal figure that does not apply here.

2. **On this M4 Pro, CPU-only inference on the real shipping prompt already misses the latency budget — for a 1B model.** Cold, CPU-only, French Natural prompt (1,704 tokens by the model's own tokenizer) plus the largest shipping fixture: **gemma3:1b takes 4.79 s**, **llama3.2:3b takes 13.03 s** **[measured]**. An iPhone SoC is a smaller configuration of the same core designs, so these are best read as floors; the multiplier above them is exactly what a device measurement would supply. The pre-registered budget was p50 ≤ 5 s.

3. **The only candidate that fits the memory budget is the one that makes the text worse than doing nothing.** `gemma3:1b` is the sole model measured at or under the 1.2 GB ceiling (1.2 GB resident, CPU-only, 4096 context **[measured]**), and it scored **60/72 property checks against a no-LLM control of 63/72** **[measured]**. It translates the developer jargon the French prompt exists to protect: "je te laisse **examiner** la pull request" where Apple FM and the 4B model both keep "review".

4. **The smallest Qwen fabricated content the user never said.** `qwen3.5:0.8b` turned *"J'espère que tu es passé un bon week-end"* into *"Je te souhaite une semaine très réussie"* and invented *"je me sentais calme tout au long de la période"* **[measured]**. For a dictation product that is a categorical disqualification, not a lower score.

5. **Quality is not the blocker at 4B — everything else is.** `gemma3:4b` scored **72/72**, above Apple FM's 69/72 on the same fixtures in the same session, and reproduced Apple FM's jargon handling exactly **[measured]**. It needs **3.4 GB resident** and **4.29 s CPU-only warm** on an M4 Pro **[measured]**. It is a good answer to a question about a desktop.

6. **The Neural Engine route is the only one not yet excluded, and it is excluded on the coverage tier by its own documentation.** ANEMLL (MIT, active) is the credible ANE path; its README records an "**M1/A14 limitation**: constrained to 512-context monolithic models" and recommends 512–1024 tokens for ANE performance **[source]**. A14 is the iPhone 12. The shipping French prompt alone is 1,704 tokens **[measured]** — it does not fit in the window those devices can offer.

7. **Apple FM is not a fair memory comparison and it is worth saying why.** Its ~3B weights are quantized to **2 bits per weight** with QAT, its KV cache to 8 bits **[source]**, and the model ships and updates **with the OS** **[source]** — so it costs the app no download and no app-owned weights. A second backend pays for all three in DictusApp's own jetsam budget, at 4–8 bits per weight instead of 2.

**Recommendation: no for the coverage rationale, on measured evidence. Not answered for the reliability rationale, and #351 answers it better.** Detail in the last section.

---

## What the spike was asked, and the two questions hiding inside it

#268 was opened as a **coverage** question: Apple Foundation Models requires
"iPhone 15 Pro models, and iPhone 16 models or later" **[source]**
(support.apple.com/en-us/121115), Dictus ships `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
**[code]** `Dictus.xcodeproj/project.pbxproj:1118`, and everything between those
bounds can buy Pro and cannot run the flagship Pro feature.

On 2026-08-13 a **reliability** rationale was added from #315: Apple documents
that `GenerationError.rateLimited` "will only happen if your app is running in
the background and exceeds the system defined rate limit" **[source]**
(independently re-fetched from Apple's documentation during this spike, not
taken on trust from the issue), and DictusApp is backgrounded for every polish
call by design. Field captures show latched runs of **11 min 50 s with zero
successes** **[field]**.

These two rationales do not want the same model, and the plan said so before the
measurements. Coverage wants something that runs on an iPhone 12. Reliability
wants something good enough to *replace* Apple FM on an iPhone 17 Pro. The
findings below answer them separately because the answers differ.

---

## Finding 1 — V1: the app cannot use the GPU, and that is the whole shape of the problem

Three independent primary sources, none of which needed a device.

**Apple's Core ML reference, on `MLComputeUnits`:**

> Use `cpuOnly` to restrict the model to the CPU, if your app might run in the background or runs other GPU intensive tasks.

— `developer.apple.com/documentation/coreml/mlcomputeunits` **[source]**

**Apple's UIKit background guidance**, under "Quiet your app upon deactivation":

> Don't commit any new Metal work to be processed.
> Don't commit any new OpenGL commands.

and under "Release resources upon entering the background":

> Ensure that all Metal command buffers have been scheduled.

— `developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background` **[source]**

**The iOS 26 SDK headers**, which added a dedicated capability for the case where
you really do need background GPU:

```objc
/// Indicate to the scheduler that the workload will require background GPU utilization.
/// Task submissions will be rejected if the submitting app does not have the correct entitlement.
/// Background GPU execution is not supported on all devices.
/// - Important: Applications must have the
///   `com.apple.developer.background-tasks.continued-processing.gpu` entitlement …
BGContinuedProcessingTaskRequestResourcesGPU NS_SWIFT_NAME(gpu) = (1 << 0),
```

— `iPhoneOS26.4.sdk/…/BackgroundTasks.framework/Headers/BGTaskRequest.h:122-129` **[sdk]**

That capability is `iOS 26.0+`, is attached to `BGContinuedProcessingTask`, and is
not reachable from `UIBackgroundModes: audio`, which is how DictusApp stays alive
**[code]** `DictusApp/Info.plist:60`. An entitlement would not exist if the
default were permission.

### The product already demonstrates the permitted half

FluidAudio, the Parakeet path that is the shipping default, configures Core ML as:

```swift
config.allowLowPrecisionAccumulationOnGPU = true
// Prefer Neural Engine across platforms for ASR inference to avoid GPU dispatch.
config.computeUnits = .cpuAndNeuralEngine
```

— `FluidAudio/Sources/FluidAudio/ASR/AsrModels.swift:262` **[source]**

Every dictation in this product transcribes with that configuration from a
backgrounded process — `appState=2` on every `engineDarwinStartReceived` in the
#315 captures **[field]**. **CPU and ANE inference in the background is not a
hypothesis here; it is the shipping product.**

### What this rules in and out

| Runtime | Compute path | V1 |
| --- | --- | --- |
| **llama.cpp / ggml, CPU build** | NEON, Accelerate, Arm KleidiAI. `-DGGML_METAL=OFF` is a documented supported configuration **[source]** `llama.cpp/docs/build.md:136` | **Pass** |
| **ExecuTorch, XNNPACK backend** | CPU, "All" platforms **[source]** `executorch/docs/source/backends-overview.md` | **Pass** |
| **Core ML with `.cpuAndNeuralEngine`** | ANE + CPU | **Pass** — same path the product already uses |
| **llama.cpp / ggml, Metal build** | Metal. On macOS "Metal is enabled by default" **[source]**; on iOS it is the usual build | **Fail** |
| **MLX / MLX Swift** | Metal on Apple silicon. A CPU device exists ("Operations can run on any of the supported devices (currently the CPU and the GPU)" **[source]**), but every published iOS example uses the Metal backend and the framework exists for it | **Fail as normally used.** Not categorically impossible; running it CPU-only on iOS forfeits its reason for existing and is off every documented path |
| **ExecuTorch, MPS backend** | GPU **[source]** | **Fail** |

**The consequence is larger than the table.** The on-device LLM figures that
circulate — the ones that make a 3B model on an iPhone look comfortable — are
Metal figures. This spike measured the cost of that directly: on the same
machine, the same model, the same prompt, **Metal is 2.2–2.9× faster than CPU on
decode and 2.5–7× faster on prefill** **[measured]**, and none of that speed is
available to a backgrounded Dictus.

---

## Finding 2 — V4: CPU-only latency, measured

Measured on this machine: **Apple M4 Pro, 14 cores, 24 GB, macOS 26.5.1**, Ollama
0.32.6, `num_ctx: 4096`, `temperature: 0`, thinking disabled. The prompt is the
real one: `PolishNaturalPromptFR` as the system message plus the largest shipping
fixture (`3-long`, 637 characters) in the same Input/"Polished output:" framing
the Apple FM engine uses — **1,704 tokens of prefill**, counted by the model's own
tokenizer, not estimated **[measured]**.

| Model | Quant | CPU-only **cold** | CPU-only **warm** | Metal warm |
| --- | --- | --- | --- | --- |
| `gemma3:1b` | Q4_K_M | **4.79 s** (load 1.65 + prefill 1.79 + decode 1.34) | 1.69 s | 1.10 s |
| `qwen3.5:0.8b` | Q8_0 | **5.09 s** (load 2.08 + prefill 1.71 + decode 1.30) | 1.48 s | 1.14 s |
| `qwen3:1.7b` | Q4_K_M | — | 2.97 s | 1.30 s |
| `llama3.2:3b` | Q4_K_M | **13.03 s** (load 2.47 + prefill 7.23 + decode 3.32) | 3.52 s | 1.71 s |
| `gemma3:4b` | Q4_K_M | — | 4.29 s | 2.47 s |

"Warm" means the constant ~1,150-token system prompt was already in the prefix
cache. That is a real and legitimate optimisation — the instructions never change
between dictations, and `PolishCoordinator` already calls `prewarm()` at recording
start **[code]** — but it is not free: it requires holding that KV cache resident
between calls, which adds to the footprint in Finding 3, and the first call after
a load pays the cold price.

### Reading these as iPhone numbers, honestly

**They are not iPhone numbers and this document will not present them as such.**
What can be said without a device:

An iPhone SoC is a smaller configuration of the same core designs — fewer
performance cores, a narrower memory interface. Decode is bound by both. Treating
the M4 Pro CPU figure as a **floor** for any iPhone is the conservative reading,
and the multiplier above that floor is exactly what a device measurement would
supply and this spike cannot.

Against the pre-registered budget of **p50 ≤ 5 s, p90 ≤ 12 s**, the floor for a
1B is already 4.79 s cold and the floor for a 3B is 13.03 s cold. The budget was
not tight — it was derived from the Apple FM field baseline, whose observed
maximum is 12.5 s **[field]** — and the smallest useful candidate is at its edge
on hardware the target devices cannot approach.

### The Apple FM baseline it is being compared against

From the metrics ring, `dictus-polish-debug-20260805-174258.json`, iPhone16,2,
iOS 26.5.2, build 1.8.0 (25), **backgrounded**, quoted in #315 **[field]**:

```text
success: n=196, min=688 ms, p50=1654 ms, p90=4842 ms, max=12528 ms
```

For reference, Apple FM measured through this same harness on this Mac, in the
**foreground** and therefore free of the rate limit the whole exercise is about:
p50 1,412 ms, p90 2,224 ms **[measured]**.

---

## Finding 3 — V2/V3: memory

### The computable half, measured rather than derived

Resident set reported by the runtime with a 4,096-token context, which is the
window `PolishContextBudget.appleFoundationModels` is built around **[code]**:

| Model | Quant | On disk | Resident, Metal | Resident, **CPU-only** | V2 (≤ 1.2 GB) |
| --- | --- | --- | --- | --- | --- |
| `gemma3:1b` | Q4_K_M | 815 MB | 883 MB | **1.2 GB** | at the line |
| `qwen3.5:0.8b` | Q8_0 | 1.0 GB | 1.1 GB | **1.4 GB** | over |
| `qwen3:1.7b` | Q4_K_M | 1.4 GB | 1.9 GB | **1.9 GB** | over |
| `llama3.2:3b` | Q4_K_M | 2.0 GB | 2.5 GB | **2.9 GB** | well over |
| `gemma3:4b` | Q4_K_M | 3.3 GB | 3.7 GB | **3.4 GB** | well over |

**[measured]** — `ollama ps` after a warm call, per model, per compute path.
Note that the CPU-only figure is the *larger* one for the small models: the path
V1 forces is also the more expensive one.

For scale, the app's current heaviest single asset is Parakeet at **~800 MB**
**[code]** `DictusCore/Sources/DictusCore/ModelInfo.swift:154`, and it is resident
and pre-loaded at launch. A 1B LLM alongside it roughly triples the app's
model-owned memory; a 3B roughly quadruples it.

### Why Apple FM is not a fair comparison, and what that costs a challenger

Apple published the compression it applies to the on-device model **[source]**
(machinelearning.apple.com, "Apple foundation models 2025 updates"):

> We compressed the on-device model to 2 bits per weight (bpw) using
> Quantization-Aware-Training (QAT) … we quantized the embedding table to 4 bits
> per weight … The KV cache was quantized to 8 bits per weight.

and, on the architecture:

> we divided the full model into two blocks with a 5:3 depth ratio. All of the
> key-value (KV) caches of block 2 are directly shared with those generated by the
> final layer of block 1, reducing the KV cache memory usage by 37.5%

That is a **~3B model at 2 bpw**. A candidate at Q4_K_M is carrying roughly twice
the bits per parameter with no QAT recovery training and no adapter stack. And
`SystemLanguageModel` is "periodically updated in routine OS updates" **[source]**
— the weights arrive with the OS, so they cost the app nothing to download.
Everything a second backend weighs, DictusApp owns.

### The half that could not be measured

**V3 — peak `phys_footprint` during a backgrounded dictation with the LLM
resident, the STT model resident and the audio engine warm — was not measured and
cannot be from this machine.** A simulator has no jetsam limit
(`os_proc_available_memory()` returns 0 there **[code]**
`DictusCore/Sources/DictusCore/DeviceCapabilities.swift:103`), runs Core ML on the
host, and cannot reproduce background memory pressure. A simulator figure here
would be worse than no figure, because it would look like an answer.

Apple's guidance is explicit about the direction of the risk:

> The foreground has priority over memory and other system resources, and the
> system terminates background apps as needed to make those resources available.

**[source]** — and a jetsam kill mid-dictation is exactly the regression #268's
own body names as worse than not having the feature.

Exact steps for the device measurement are in the last section.

---

## Finding 4 — V5: quality, measured through the real pipeline

This is the criterion the plan said could be settled properly, and it was.

Each candidate ran through `polish-harness eval` — the **real** `PolishPipeline`,
the real verbal-punctuation pre-pass, the real post-pass, the real guardrails, the
shipping fixtures — three times over `seed.json` (14 fixtures) and three times
over `auto.json` (10), 72 fixture-runs per engine. The candidate engine differs
from the Apple FM engine only in where the tokens come from: it reads the same
resolved instructions through `AppleFoundationModelsPolishEngine.instructions(for:language:)`
and wraps them in the byte-identical user turn.

| Engine | Passed | % | Engine outcomes |
| --- | --- | --- | --- |
| **apple-fm** (baseline, foreground) | **69/72** | 95.8 | 68 success, 4 guardrail rejections |
| `gemma3:4b` | **72/72** | 100.0 | 66 success, 6 guardrail rejections |
| `qwen3:1.7b` | 66/72 | 91.7 | 69 success, 3 rejections |
| `llama3.2:3b` | 66/72 | 91.7 | 69 success, 3 rejections |
| **control: no LLM at all** | **63/72** | **87.5** | 72 engineFailed → deterministic floor |
| `qwen3.5:0.8b` | 63/72 | 87.5 | 63 success, 9 rejections |
| `gemma3:1b` | 60/72 | 83.3 | 54 success, 18 rejections |

**[measured]**

### The control is the most important row in that table

The no-LLM control was produced by accident — a shell quoting bug sent an empty
model name, every call failed, and `PolishPipeline.resolvedOutput` returned the
deterministic floor for all 72 runs. It was kept deliberately, because it
calibrates the whole metric: **doing no LLM polish at all scores 63/72.**

The harness README says why, and says it up front: the expectations are "tolerant
property checks (the contract), not exact-string matches" **[code]**
`Sources/polish-harness/README.md:62`. They are built to catch a model **damaging**
the text, not to rank models that are all behaving. So:

- A score at or below 63/72 means the model is a **net negative**. `gemma3:1b` is
  below it. `qwen3.5:0.8b` merely ties it.
- The gap between 66/72 and 72/72 is real but the suite is not sensitive enough to
  turn it into a ranking. It should not be read as one.

### What the failures actually look like

Fixture `2-bilingue` exists to check one thing: French output that **keeps** the
developer jargon and translates only the stray English word. `expect` requires
`push`, `commit` and `merge` to survive.

Raw input:

> Alors écoute, faut que je push le commit sur GitHub avant la deadline de today
> et ensuite je te laisse review la pull request.

| Engine | Output |
| --- | --- |
| **apple-fm** | "faut que je **push** le **commit** sur GitHub avant la deadline de **aujourd'hui** et ensuite je te laisse **review** la pull request" ✓ |
| `gemma3:4b` | "faut que je **push** le **commit** … je te laisse **review** la pull request" ✓ |
| `llama3.2:3b` | "faut que **j'envoie** le commit … tu me laisses faire **la revue de** la pull request" ✗ |
| `gemma3:1b` | "il faut que je **pousse** le commit … je te laisse **examiner** la pull request" ✗ |
| `qwen3.5:0.8b` | "il faut **qu'on passe** le commit … que **tu me laissez faire** la pull request" ✗ — and ungrammatical |

**[measured]**

And on `1-normal`, `qwen3.5:0.8b` did the thing a dictation product cannot ship.
Input: *"J'espère que tu es passé un bon week-end. Moi de mon côté c'était
tranquille"*. Output:

> **Je te souhaite une semaine très réussie.** De ma part, **je me sentais calme
> tout au long de la période**; j'ai travaillé sur le projet…

Neither clause is a rewrite of anything the speaker said. That is fabrication in
the user's own voice, and it is not a score, it is a disqualification.

`llama3.2:3b` also produced *"Je m'espère que"* — not French.

### Two caveats on this measurement, both mine

- **Ollama, not the runtime that would ship.** Quality is a property of the
  weights, the quantization and the prompt, so it transfers; latency and memory
  from the same harness would not, and are not used that way here.
- **`reasoning_effort: "none"` is what actually disabled thinking.** Measured
  against Ollama 0.32.6 with `qwen3.5:0.8b`: `chat_template_kwargs:
  {enable_thinking: false}` was accepted and **ignored** — 4,594 characters of
  reasoning still generated — while `reasoning_effort: "none"` suppressed it
  **[measured]**. An earlier pass of this spike ran the Qwen models with thinking
  silently on and was discarded. Any future harness work against a reasoning model
  should check this rather than assume the flag took.

---

## Finding 5 — V6: download size and licence

| Model | Licence | What shipping it in a paid App Store binary costs |
| --- | --- | --- |
| **Qwen3 / Qwen3.5** | **Apache-2.0** **[source]** (HF model cards for `Qwen/Qwen3-1.7B`, `Qwen/Qwen3.5-2B`, `Qwen/Qwen3.5-0.8B`) | Attribution and a NOTICE. No use restrictions, no branding obligation. The cleanest of the three. |
| **Gemma 3** | **Gemma Terms of Use** **[source]** | Redistribution is permitted, but "You must include the use restrictions referenced in Section 3.2 as an **enforceable provision in any agreement**", provide every recipient a copy of the agreement, and ship a NOTICE file. Dictus's own terms would have to carry Google's Prohibited Use Policy as an enforceable term — real legal work for an individual seller. |
| **Llama 3.2** | **Llama 3.2 Community Licence** **[source]** | Must "provide a copy of this Agreement" and "prominently display **'Built with Llama'** on a related website, user interface, blogpost, about page, or product documentation". 700 M MAU ceiling — irrelevant here. A visible branding obligation inside a product sold on its own name. |

Download size is the resident figures in Finding 3 minus the KV cache: **815 MB
to 3.3 GB**. For scale, the largest thing Dictus asks a user to download today is
Whisper Turbo at ~954 MB and Parakeet at ~800 MB **[code]**. The delivery
machinery exists — `ModelManager` already downloads, verifies and compiles models
at runtime — so this is a size question, not a plumbing question.

`LiquidAI/LFM2-1.2B` was on the plan's candidate list and **was not evaluated**:
it has no Ollama manifest (`Error: pull model manifest: file does not exist`) and
building a separate serving path for one candidate was not worth the spike's time
**[measured]**. Its licence is "other" on the HF card **[source]**, which would
have needed reading anyway.

`Qwen/Qwen3.5-2B` was evaluated only at **Q8_0**, because Ollama publishes no q4
tag for it. At Q8 it is 2.7 GB, far outside V2, so the omission does not change
any conclusion.

---

## Finding 6 — the Neural Engine, the one path this spike could not close

CPU is measured and fails. Metal is forbidden. That leaves the ANE, which is
where Apple runs its own model and where FluidAudio already runs Parakeet from a
backgrounded process.

The credible open route is **ANEMLL** (MIT **[source]**, active — 0.3.5 in
2026-03, with an iOS reference app and pre-converted Gemma 3 / Qwen 3 / Llama 3.2
Core ML bundles). Its own README sets the boundaries **[source]**:

- Gemma 3 (270M, 1B, **4B QAT**): "Context lengths: Up to 4096 tokens
  (**512-2048 recommended for ANE**)"
- Qwen 3 (0.6B, 1.7B, 8B): "Up to 4K (512-2048 recommended for ANE)"
- "**M1/A14 limitation**: Constrained to **512-context** monolithic models due to
  ANE non-uniform state shape restrictions"

Set that against this product's actual prompt: **1,704 tokens for the French
Natural instructions plus the largest shipping fixture** **[measured]**. The
instructions alone are the majority of it.

- **On A14 (iPhone 12) the shipping prompt does not fit in the window at all.**
  Not "is slow" — does not fit. That is the coverage tier, and it is closed.
- On newer silicon the 4K ceiling is reachable but is above the recommended
  operating range, and no latency figure for it exists that this spike could
  produce.

There is a lever worth naming: **the prompt is 1,150 tokens because Apple FM
needed it to be.** A different backend could be given a shorter, differently
shaped instruction set. That is a redesign with its own quality risk — ADR 0003
records how much of the Natural contract lives in those prompts — and it is not a
measurement, so this spike does not claim it as a way out. It records it as the
one lever that would change the arithmetic.

---

## What could not be measured, and exactly what it would take

For a spike this replaces a test list. Two of these need a physical iPhone; one
needs a decision.

### D1 — Peak footprint and jetsam headroom during a backgrounded dictation *(needs the maintainer's iPhone)*

This is V3, and it is the criterion #268's body calls "the hard part". Nothing
about it is measurable off-device.

The instrumentation already exists and already runs — `ModelManager` logs a
jetsam-headroom delta across prewarm, and `TranscriptionService.logPerformance`
records `peakMemoryMB` from `os_proc_available_memory()` after every
transcription **[code]**. **No LLM work is needed to get the first half of the
answer.**

Steps, in order:

1. On the iPhone, with the current `develop` build, do **five ordinary dictations
   from the keyboard** with the default Parakeet model — normal length, French,
   polish on.
2. Settings → export the **persistent log** (not the polish debug JSON — the
   persistent log, which carries `transcriptionPerformance` and
   `modelPrewarmPeakMemory`).
3. Send that file. It gives the baseline: how much jetsam headroom DictusApp
   actually has left, backgrounded, with Parakeet resident and the audio engine
   warm, on his hardware.

That number decides whether there is room for a 1.2 GB tenant before anyone
writes a line of integration code. If the headroom is under about 1.5 GB, the
question is settled and no further work is warranted.

### D2 — Whether an ANE-resident model can hold this prompt on modern silicon *(needs a physical iPhone, and a day of work)*

Only relevant if the reliability rationale is being pursued rather than coverage.
It means converting Gemma 3 4B QAT with ANEMLL, loading it in a throwaway iOS
target, and timing a 1,704-token prefill plus ~160-token decode **while
backgrounded**. A simulator cannot answer it: there is no ANE on a Mac in the way
there is on a phone, and there is no jetsam.

### D3 — A decision, not a measurement: which rationale is being served

Coverage and reliability point at different models and this spike cannot choose
between them. See the recommendation.

---

## Recommendation

### On the coverage rationale — **no**

Shipping a second local LLM backend to pre-Apple-Intelligence iPhones is not
viable, and the evidence is measured rather than argued:

- The GPU is unavailable to a backgrounded app, so the candidate runs on CPU or
  ANE **[source, sdk]**.
- CPU-only, the smallest useful candidate costs **4.79 s cold on an M4 Pro**, and
  no iPhone is faster **[measured]**.
- ANE, on A14, cannot hold the prompt at all **[source, measured]**.
- The only model inside the memory budget scores **below a no-LLM control** on the
  shipping fixtures and translates away the jargon the French prompt exists to
  protect **[measured]**.

The 4 GB and 6 GB tier is closed. I would close this half of #268 rather than
leave it open as something to retry, and reopen only if a specific new model with
a specific new footprint appears — not on a general "models get better" argument.

### On the reliability rationale — **not answered here, and probably not the right tool**

A second backend would sidestep the background rate limit. But the model that
matched Apple FM's quality in this measurement is `gemma3:4b` at **3.4 GB
resident and 4.29 s warm on an M4 Pro CPU** **[measured]**. On the devices where
reliability is the problem — iPhone 15 Pro and later, which *have* Apple
Intelligence — that is a large tenant and an unmeasured latency, to replace
something that works 90% of the time.

The one path not excluded is Gemma 3 4B QAT on the ANE (D2), and it costs a day
of conversion work plus a device measurement plus the Gemma licence obligation in
Finding 5.

**#351 gets the same reliability outcome for far less.** It targets the identical
seam (`PolishEngineProtocol`), it is already specced, its "model" is a 32B on
hardware the user already owns, and it adds **zero** bytes to the app's resident
footprint — which is the constraint that kills every option above. It does not
help the user with no server, but neither does anything measured here.

### What I would do next, in order

1. **Get D1.** Five dictations and one log export. It is the cheapest decisive
   measurement available and it needs no new code.
2. **Do #315's option 3 regardless.** Detecting the latch and telling the user
   honestly is independent of everything in this document and is the only change
   that is unambiguously an improvement whatever else is decided.
3. **Sequence #351 ahead of any further work here.** Same seam, no footprint,
   already designed.
4. **Leave D2 on the shelf** unless D1 comes back with more headroom than expected
   *and* the maintainer wants the coverage story badly enough to accept the Gemma
   licence terms.

---

## What I am not comfortable asserting

- **Any iPhone latency number.** The Mac figures are floors with an unknown
  multiplier. I have not converted them into phone figures and the report should
  not be read as if I had.
- **That `gemma3:1b` is weak at French *because* it is 1B.** The Gemma 3 model
  card documents "multilingual support in over 140 languages" without
  differentiating by size, and the context-window difference it does document
  (32K for 1B, 128K for the rest) says nothing about language coverage
  **[source]**. What is measured is that this checkpoint, at this quantization,
  with this prompt, performed below a no-LLM control on these fixtures. The cause
  is not established.
- **That the property-check suite ranks models.** It calibrates against a floor;
  63/72 for doing nothing is the proof. Treat 66 vs 72 as "both behaving", not as
  a margin.
- **That Core ML would hard-fail rather than degrade if it were asked for the GPU
  in the background.** Apple's wording for `MLComputeUnits` is "allow", not
  "require", and the shipping WhisperKit path requests `.cpuAndGPU` for the mel
  spectrogram by default **[source]** `WhisperKit/Sources/WhisperKit/Core/Models.swift:101`
  while working backgrounded. The mechanism was not investigated. It does not
  affect the conclusion — a runtime that *requires* Metal, like a Metal-built
  llama.cpp, has no such fallback — but the distinction is real and I did not
  close it.
- **The exact RAM of each iPhone model.** Apple does not publish it. This document
  deliberately gives no RAM table: the app reads the real value at runtime
  (`DeviceCapabilities.physicalMemoryGB`) and already gates a model on it
  (`ModelInfo.isSupported(on:)` gates Whisper Turbo at `>= 6` GB **[code]**), so a
  threshold is what a decision needs, not a table.

---

## Reproducing the measurements

Throwaway code added on this branch, confined to the `polish-harness` target
(macOS-only, out of every app target, not built by CI):

- `DictusCore/Sources/polish-harness/LocalHTTPPolishEngine.swift` — a
  `PolishEngineProtocol` engine speaking `POST /v1/chat/completions`.
- `--engine local --model <name> [--base-url <url>]` on `show` and `eval`.

```sh
# Baseline (needs Apple Intelligence on the Mac)
cd DictusCore
swift run polish-harness eval Sources/polish-harness/fixtures/seed.json

# Candidate, against a local OpenAI-compatible server
ollama pull gemma3:4b
swift run polish-harness eval Sources/polish-harness/fixtures/seed.json \
  --engine local --model gemma3:4b

# Side-by-side text
swift run polish-harness show Sources/polish-harness/fixtures/seed.json \
  --engine local --model gemma3:1b
```

Latency and resident-set figures came from Ollama's native `/api/chat` with
`options.num_gpu` set to `0` (CPU-only) or `99` (Metal), `num_ctx: 4096`, the
`PolishNaturalPromptFR` system message and the `3-long` fixture, with `ollama ps`
read after a warm call.
