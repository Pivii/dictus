# Can a backgrounded DictusApp reach the ANE for LLM inference? — D2

**Issue:** [#268](https://github.com/getdictus/dictus-ios/issues/268)
**Scope:** measurement only. No `PolishEngineProtocol` implementation, no model
delivery, no engine selection, no change to `PolishCoordinator` or to any app
target.
**Date:** 2026-08-22.
**Predecessor:** [`268-second-llm-backend.md`](268-second-llm-backend.md) — the
2026-08-13 spike and its 2026-08-21 addendum (D1). Read that first; this
document extends it and assumes its findings.

D2 is the experiment the addendum called decisive:

> The question is whether a ~1.7B model can be made ANE-resident and hold a
> 1,704-token prefill on modern silicon while backgrounded. A negative result
> closes #268 completely; a positive one makes `qwen3:1.7b` a real alternative to
> Apple FM on 8 GB devices.

---

## Evidence labels

Same scheme as the predecessor, because the two documents are read together.

| Label | Meaning |
| --- | --- |
| **[code]** | Read in this repository, cited by file and line. |
| **[source]** | Official API reference, official model card, or a named third-party source file, cited by URL or path. |
| **[measured]** | Produced by running something during this spike. The command is recorded. |
| **[field]** | Recorded on the maintainer's own device and quoted in the tracker. |
| **[derived]** | Arithmetic on top of a sourced fact. The input is sourced; the output is not quoted. |

---

## Summary

1. **The ANE holds the prompt. That question is answered, and it turns out not
   to be the one that decides.** A 1,680-token prefill runs to completion in a
   2048-context ANEMLL build of Qwen3 1.7B, stopping on EOS with no window shift
   and no truncation **[measured]**. The predecessor's "does it fit" worry is
   closed for modern silicon.

2. **Core ML really does place it on the Neural Engine, and this is read from
   Core ML rather than inferred from a timing.** `MLComputePlan` reports **1,166
   ANE operations against 13 CPU** in the transformer chunk under
   `.cpuAndNeuralEngine`, and **0 ANE against 1,179 CPU** for the same file under
   `.cpuOnly` **[measured]**.

3. **The decisive cost is decode, not prefill, and no prompt redesign touches
   it.** On an M4 Pro, ANE-resident, thinking off: prefill of the real French
   polish prompt is **2.69–3.31 s**, decode of the 162-token answer is
   **5.80–5.91 s**, total **8.49–9.15 s** per polish call **[measured]**. The
   pre-registered budget is p50 ≤ 5 s. **Decode alone misses it**, so the one
   lever the predecessor identified — shorten the 1,150-token instruction block —
   cannot rescue this: it is arithmetic on the wrong term **[derived]**.

4. **The ANE is much better than the CPU at prefill and barely better at
   decode.** Same model, same prompt, same process: prefill **6.5× faster**
   (3.05 s median vs 19.78 s) but decode only **1.35× faster** (27.7 vs
   20.8 tok/s) **[measured]**. Against the predecessor's Metal figures for the same
   checkpoint, the GPU decodes roughly **4×** faster than the ANE does
   **[derived]**. The Neural Engine is not a small GPU; it is a prefill engine.

5. **No conversion was needed, and none was attempted.** ANEMLL publishes
   `anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5` — the exact candidate, converted by the
   toolchain's own authors at the version #268 names, with the conversion
   parameters recorded in its `meta.yaml` **[source]**. This is a deliberate
   deviation from the issue's step 1, and it is the reason the time-box the issue
   set aside for toolchain trouble was not spent. See
   [Deviations](#deviations-from-the-issue).

6. **Placing the model on the ANE costs 96–104 s of load, every process
   launch.** Against 21.2 s for the same bundle under `.cpuOnly` **[measured]**. Not
   fatal — DictusApp is long-lived and pre-loads at launch — but it is a real
   number that a shipping integration would have to hide, and it is not one the
   predecessor's Ollama load times (1.7–2.5 s) predict.

7. **The device measurement is not in this document yet.** Everything above is a
   Mac. A Mac has no jetsam and no application lifecycle, so it cannot answer the
   question in #268's title. The apparatus is built, installed on the iPhone, and
   rehearsed end to end in a simulator with `allIterationsBackgrounded=true`; it
   is blocked on one thing, which is that `devicectl` will not launch an app on a
   locked phone. See [What is still missing](#what-is-still-missing).

**Reading so far: the ANE is reachable and the prompt fits, and the candidate
still misses the latency budget on hardware faster than any iPhone.** The device
run can move that from "indicated" to "measured"; on the evidence here it is
unlikely to reverse it.

---

## What was built

`tools/ane-harness/` — throwaway, its own Xcode project, referenced by nothing.
`README.md` there is the operating manual. Two entry points share one
measurement core:

- `ane-bench`, a macOS CLI — the gate #268's work-split puts before the phone.
- `AneHarness.app`, an iOS app — the measurement itself.

Three decisions inside it are worth stating, because each one is a way the
measurement could have been quietly wrong.

**The prompt is built from DictusCore at runtime, not transcribed.** The
resolved instructions come through `AppleFoundationModelsPolishEngine.instructions(for:language:)`
— the same entry point both shipping engines use **[code]** — and the user turn
is the same `Input:` / `Polished output:` framing, over text that has been
through `VerbalPunctuationPrepass`, because that is what the engine receives.
`setup.sh` copies `seed.json` in rather than letting a second copy of the fixture
exist. A new `polish-harness prompt` command prints the same two strings, so the
bytes can be checked by hand.

**Thinking is off, and that was checked rather than assumed.** Qwen 3 reasons
before answering unless the chat template emits an empty `<think></think>`
block; the predecessor threw away an entire measurement pass on finding it had
run with thinking silently on. The harness appends that block and the recorded
outputs contain no reasoning.

**Compute placement is read, not inferred.** `MLComputeUnits` is documented as
"allow", not "require", and the predecessor's own "what I am not comfortable
asserting" records that the fallback mechanism was never investigated. So the
harness reads `MLComputePlan.deviceUsage(for:)` per operation, and
`--compute-units cpu` gives the contrast.

---

## Finding 1 — the model, and why it was not converted here

| | |
| --- | --- |
| Bundle | `anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5` **[source]** |
| Base checkpoint | `Qwen/Qwen3-1.7B` (Apache-2.0), snapshot `0060bc56` per `meta.yaml` **[source]** |
| Context / batch | 2048 / 64 |
| Quantization | LUT6 per-channel 4 on the FFN and LM head; embeddings FP16 |
| On disk | 1.80 GB across four `.mlmodelc` bundles |
| Conversion | ANEMLL 0.3.5, parameters recorded verbatim in `meta.yaml` **[source]** |

`meta.yaml` carries the full converter invocation — context length, batch size,
chunk count, LUT settings, `argmax_in_model: false`, `prefill_dynamic_slice:
true`, `anemll_version: 0.3.5`. That is more provenance than a conversion run
here would have produced, and it is the same toolchain at the same version the
issue names.

The 2048 context matters. #268's coverage half was closed partly on ANEMLL's
documented "M1/A14 limitation: constrained to 512-context monolithic models"
**[source]**, against a 1,704-token prompt. This bundle is neither monolithic nor
512-context, and the A14 constraint is untouched by anything here — the coverage
tier stays closed.

## Finding 2 — the ANE holds the prompt

The real prompt tokenises to **1,680 tokens** by the model's own tokenizer
**[measured]** — the predecessor's 1,704 was the same prompt through Ollama's
Qwen tokenizer with a different chat-template wrapper, so the two agree to within
the template overhead.

Every run terminated on `eos_token` after 162 generated tokens, with no window
shift: 1,680 + 162 = 1,842 of the 2,048-token window **[measured]**.

The output is coherent French, in the speaker's register, with no fabrication and
no English:

> Ce que j'aimerais bien tester aussi, c'est un texte un petit peu plus long, que
> je décris à l'oral, comme je suis en train de le faire en fait. […] j'ai envie
> de voir exactement comment ça se comporte avec dictus mais aussi avec
> whisperflow.

This is a sanity gate, not a quality score — see
[What I am not comfortable asserting](#what-i-am-not-comfortable-asserting) on
what LUT6 does and does not inherit from the 66/72 the predecessor measured on a
Q4_K_M build of the same checkpoint.

## Finding 3 — Core ML places it on the ANE

`MLComputePlan`, per compiled model, `const` operations excluded **[measured]**:

| Model | `.cpuAndNeuralEngine` | `.cpuOnly` |
| --- | --- | --- |
| `qwen_FFN_PF_lut6_chunk_01of02` (the transformer body) | ANE **1,166** / CPU 13 / GPU 0 / undetermined 1,448 | ANE **0** / CPU 1,179 |
| `qwen_lm_head_lut6` | ANE **50** / CPU 0 | ANE 0 / CPU 50 |
| `qwen_embeddings` | ANE 0 / **CPU 4** | ANE 0 / CPU 4 |

Two things to read here. The transformer body and the LM head are planned
essentially entirely for the Neural Engine: 1,179 = 1,166 + 13, so the 13
operations that stay on the CPU under `.cpuAndNeuralEngine` are ones the planner
never offers to the ANE **[derived]**. And the embedding table is a CPU gather in
both columns, which is expected — it is 622 MB of FP16 weights the ANE never
touches.

**The GPU column is zero in every row.** Nothing in this path asks for Metal,
which is the constraint the predecessor's Finding 1 established.

The 1,448 operations Core ML declines to plan a device for are reported as
undetermined rather than folded into any column. An absent count is not a zero.

## Finding 4 — latency, and the term that decides

Measured on **Apple M4 Pro, 14 cores, 24 GB, macOS 26.5.1**, `temperature: 0`,
thinking off, the real French polish prompt, ANEMLL Swift runtime **[measured]**:

| Run | Prefill | Decode (162 tok) | Total | Prefill rate | Decode rate |
| --- | --- | --- | --- | --- | --- |
| ANE, iteration 1 | **3,305 ms** | 5,845 ms | **9,150 ms** | 508 tok/s | 27.7 tok/s |
| ANE, iteration 2 | **2,688 ms** | 5,800 ms | **8,488 ms** | 625 tok/s | 27.9 tok/s |
| ANE, iteration 3 | **2,790 ms** | 5,910 ms | **8,700 ms** | 602 tok/s | 27.4 tok/s |
| CPU-only control | **19,784 ms** | 2,890 ms (60 tok) | — | 85 tok/s | 20.8 tok/s |

An earlier two-iteration pass in a separate process reproduces this within noise
(3,152 / 2,590 ms prefill, 5,732 / 5,709 ms decode) **[measured]**, so the spread
above is run-to-run variance and not drift.

Against the two numbers the decision rule names:

- Pre-registered budget: **p50 ≤ 5 s**.
- Apple FM field baseline, backgrounded, on the maintainer's own device:
  **p50 1,654 ms**, p90 4,842 ms **[field]**.

**8.5 s on an M4 Pro is 5× the Apple FM baseline and 1.7× the budget ceiling.**
The predecessor establishes that a Mac figure is a *floor* for any iPhone.

### Why the prompt-shortening lever does not apply

The predecessor named one way out of its arithmetic: the instruction block is
1,150 tokens because Apple FM needed it to be, and a different backend could be
given a shorter one. That lever moves **prefill**. Prefill here is 2.7–3.3 s of
an 8.5 s call; decode is 5.8–5.9 s and depends on how much text the user
dictated, not on how long the instructions are. Even a prompt of length zero
leaves **5.8 s**, which is still over the budget **[derived]**.

### The ANE is a prefill engine

The control makes the shape of the hardware visible. Moving from CPU to ANE buys
**6.5×** on prefill and **1.35×** on decode. Set against the predecessor's Metal
figures for the same checkpoint — 1.25 s of decode inside a 3.82 s cold run — the
GPU decodes roughly **4×** faster than the ANE does **[derived]**. That factor
rests on an assumption the predecessor does not state: that its Metal run
generated about as many tokens as this one's 162. Same prompt, same
`temperature: 0`, different quantization and a different server, so treat the
factor as an order of magnitude and not a measurement.

That is a coherent picture rather than an anomaly: decode is one token at a time
against the whole weight matrix, so it is bound by memory bandwidth, which is
what the ANE has least of. It also explains why published ANE LLM demos are
impressive on time-to-first-token and quiet about tokens per second.

### One more number the Ollama measurements do not predict

Model load, same bundle, same machine **[measured]**:

| | Load |
| --- | --- |
| `.cpuAndNeuralEngine` | **95,827 ms** and **103,636 ms**, two separate processes |
| `.cpuOnly` | 21,227 ms |

Some 75–82 seconds of that is ANE placement. It is paid per process launch, and
it did not shrink on a later launch from the same path — ANEMLL's README says
"subsequent loads will be instantaneous" **[source]**, and that was not observed
here. DictusApp is long-lived and
already pre-loads its STT model at launch, so this is an engineering problem
rather than a blocker — but a first dictation after an app cold start would find
the model still loading, and no Ollama figure in the predecessor (1.7–2.5 s
load) hints at it.

## Finding 5 — the CPU is not a fallback for this artifact

The `.cpuOnly` control produced this, on the same prompt that gives clean French
on the ANE **[measured]**:

```text
olieottonologagal俑Publish.eTRACT most . 【ITU怪杞
```

An ANEMLL bundle is not a model that runs anywhere and runs faster on the ANE. It
is an ANE artifact. Whatever this says about the toolchain, it removes an option
that might otherwise look available: there is no graceful degradation to the CPU
if the ANE is unavailable or busy.

---

## What is still missing

**The device run.** This is D2's actual question and it is the one thing a Mac
cannot stand in for: there is no jetsam on a Mac, and no `applicationState` to be
in the background of.

The apparatus is complete and installed:

- `AneHarness.app`, bundle id `com.pivi.dictus.anebench`, built from this branch,
  installed on `iPhone16,2` on 2026-08-22 **[measured]**. It is not a target of
  `Dictus.xcodeproj`, so the "Generate build info" phase never runs for it and
  its output reads `rev unknown` — there is no revision line to check on this
  one, unlike every other build the maintainer validates.
- It stays alive backgrounded the same way DictusApp does — `UIBackgroundModes:
  audio` plus a running `AVAudioEngine` — because reproducing that state is the
  measurement, not a workaround.
- It loads in the foreground, waits to be backgrounded rather than counting down
  at the person holding the phone, then runs three iterations on its own.
- Every reading carries `os_proc_available_memory()`, `phys_footprint`, thermal
  state **and the lifecycle state it was taken in**. The report prints
  `allIterationsBackgrounded`, so a run that was not backgrounded reports itself
  as invalid rather than as a number.

**The apparatus itself has been run end to end**, on an iPhone 17 Pro Max
simulator, backgrounded by launching Safari over it **[measured]**. Everything
except the ANE worked: the app launched, the audio keep-alive kept it alive
through eight minutes in the background, the model loaded from the bundle, the
prompt built from DictusCore to the same 1,680 tokens, three iterations ran, the
results were written and read back, and the file ends

```text
allIterationsBackgrounded=true
```

with every sample reading `state=background`. **None of its numbers mean
anything** — a simulator has no Neural Engine, so it ran the same CPU path that
produces gibberish on the Mac, at 1.6–4.0 tok/s. It is a rehearsal of the
protocol, not a measurement, and it is recorded here only because it removes
"does the harness work" from the list of things the maintainer's unlock window
could be spent discovering.

It has not run on the phone, for one reason: `devicectl` cannot launch an app on
a locked phone.

```text
Unable to launch com.pivi.dictus.anebench because the device was not, or could
not be, unlocked. (FBSOpenApplicationErrorDomain error 7)
```

Everything after "unlock the phone" is automatable from the Mac — the run needs
no taps, and `devicectl device copy from --domain-type appDataContainer` fetches
the results over Wi-Fi. The steps are in the PR and in
`tools/ane-harness/README.md`.

**What the device run adds, beyond confirming or refusing the Mac figures:**

- the iPhone multiplier on 8.3 s, which is the number the decision rule wants;
- `os_proc_available_memory()` with the model resident, against D1's 3.33 GB
  backgrounded headroom — how much of it a 1.8 GB tenant plus its KV cache
  actually costs, and what is left for Parakeet's ~800 MB. **This one cannot be
  guessed from the Mac readings, and the reason is worth stating**: with the
  whole 1.8 GB model loaded, `phys_footprint` read **324 MB** on the Mac and
  **100 MB** in the simulator **[measured]**. Core ML's weights are mapped, not
  allocated, so the footprint number does not see most of them. Whether jetsam
  does is exactly what `os_proc_available_memory()` answers, and it returns 0
  anywhere but a device **[code]** `DictusCore/DeviceCapabilities.swift:103`;
- whether the ANE is reachable at all from a backgrounded process for an LLM, or
  whether Core ML silently re-plans onto the CPU there. The harness reads the
  compute plan on device, so this is answerable rather than arguable.

**What was not attempted, and is not on the way to an answer:** running Parakeet
and the LLM in the same process. D1 gives Parakeet's cost and this gives the
LLM's; composing them is arithmetic, and the composition is only worth measuring
if the latency question comes back positive.

---

## Deviations from the issue

**The model was not converted here.** #268 step 1 says "install ANEMLL and
convert a ~1.7B checkpoint for the ANE", and warns that this is the uncertain
part, time-boxes it, and asks for a conversion failure to be reported as a
finding rather than worked around. Neither happened: ANEMLL publishes the
converted artifact for exactly this checkpoint, at the release the issue names,
with the conversion parameters recorded. Using it is the same toolchain output
with better provenance than a local run, and it spent none of the time-box.

This does mean one thing is untested: whether *this machine* can run the ANEMLL
conversion pipeline. Nothing in #268's question depends on that, and if a future
integration needs a different context length or quantization it will find out
then.

**The results do not come out through the App Group.** #268 asks the harness to
write into the App Group and reuse the `PersistentLog` export path, "so the
results come out the way D1's did". Signing refuses it:

```text
error: Provisioning profile "iOS Team Provisioning Profile: *" doesn't support
the group.solutions.pivi.dictus App Group.
error: No Accounts: Add a new account in Accounts settings.
```

The three profiles on this machine carrying that group are bound to
`com.pivi.dictus`, `.keyboard` and `.widgets`; a new bundle id needs the
capability enabled in the developer portal, which needs an authenticated Xcode.
The substance of the requirement — self-running, self-recording, nothing to tap
while backgrounded — is unaffected. The results land in the app's own Documents
directory, which `devicectl` reads over Wi-Fi with no interaction at all, which
is less work for the maintainer than an export would have been. The App Group
write is still attempted and its outcome recorded.

---

## What I am not comfortable asserting

- **Any iPhone number.** Nothing in this document was measured on a phone. The
  M4 Pro figures are floors with an unknown multiplier, exactly as the
  predecessor's were, and the summary says "indicated", not "measured", for that
  reason.

- **That LUT6 inherits the 66/72 the predecessor measured.** That score is a
  Q4_K_M build of `Qwen3-1.7B` served by Ollama; this is a 6-bit look-up-table
  quantization with per-channel scales, produced by a different toolchain, and
  ANEMLL's own README warns "Quantization should be improved. LUT4 quality is
  fairly low due to lack of Block Quantization on Apple Neural Engine"
  **[source]**. One fixture producing clean French is a sanity gate. Scoring this
  build would mean putting an OpenAI-compatible façade in front of the ANE
  runtime and re-running `polish-harness eval` — cheap enough, and worth nothing
  until the latency question comes back positive.

- **That 162 generated tokens is representative.** The `3-long` fixture is the
  largest shipping one, and its polished output happens to be close to a copy of
  its input. A mode that condenses or translates would decode a different amount,
  and decode is the term that decides.

- **That the undetermined operations in the compute plan are ANE operations.**
  1,448 of them in the FFN chunk is more than the 1,166 that are named. They are
  reported as undetermined because that is what Core ML returned.

- **That 95.8 s of load is inherent.** It is what this bundle costs on this
  machine at this ANEMLL version. Whether a monolithic build, a smaller context
  or a different chunking loads faster was not investigated.

- **That 28 tok/s is the Neural Engine's ceiling rather than ANEMLL's.** What was
  measured is one open-source runtime, at 0.3.5, on one LUT6 chunked build. Apple
  runs its own model on the same silicon and does not publish how. The claim this
  document makes is about the option available to this product today — an
  MIT-licensed toolchain and a public checkpoint — not about what the hardware
  could do in principle. A future ANEMLL release could move this number; a
  reopening of #268 on that basis would need it measured, not argued.

---

## Reproducing

Everything below is `tools/ane-harness/`, after `./setup.sh`. The full manual is
in that directory's `README.md`.

```sh
# The exact prompt, from the shipping source of truth
cd DictusCore
swift run polish-harness prompt Sources/polish-harness/fixtures/seed.json --id 3-long

# Mac: the ANE run, and the CPU control
cd tools/ane-harness/AneBenchKit
swift run -c release ane-bench --iterations 3
swift run -c release ane-bench --iterations 1 --max-tokens 60 --compute-units cpu

# Phone: build, install, launch (needs the phone unlocked), collect
cd tools/ane-harness
xcodebuild build -project AneHarness.xcodeproj -scheme AneHarness -configuration Debug \
  -destination 'id=<device-id>' -derivedDataPath build/DerivedData -allowProvisioningUpdates
xcrun devicectl device install app --device <device-id> \
  build/DerivedData/Build/Products/Debug-iphoneos/AneHarness.app
xcrun devicectl device process launch --device <device-id> --terminate-existing \
  com.pivi.dictus.anebench
# press Home, or launch any other app from the Mac, then:
xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer \
  --domain-identifier com.pivi.dictus.anebench --source Documents --destination ./out
```
