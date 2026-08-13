# A second local LLM backend — spike plan

**Issue:** [#268](https://github.com/getdictus/dictus-ios/issues/268)
**Scope:** measurement only. No production integration, no `PolishEngineProtocol` implementation shipped, no change to `PolishCoordinator` or any app target.
**Date the plan was written:** 2026-08-13.

This document is the **plan**, committed before any measurement was taken, so the
findings can be checked against what was promised rather than against what turned
out to be convenient. The findings replace the body of this file in a later commit
on the same branch; this plan survives in the branch's first commit.

---

## Evidence labels

Same scheme as `docs/research/287-user-dictionary-learning.md`. Every claim in the
findings will carry one, and the label is part of the claim.

| Label | Meaning |
| --- | --- |
| **[code]** | Read in this repository, cited by file and line. |
| **[sdk]** | Read in the iOS SDK headers shipped with Xcode on this machine, cited by path. |
| **[source]** | Official API reference, official model card, or a named third-party source file, cited by URL or path. |
| **[measured]** | Produced by running something during this spike, with the command recorded. |
| **[field]** | Recorded on the maintainer's own device and quoted in the tracker. |
| **[derived]** | Arithmetic or inference on top of a sourced fact. The input is sourced; the output is not quoted. |
| **[secondary]** | Blog post, forum answer, press coverage. Context only. |

**Nothing labelled [secondary] may carry a decision in the findings.** Where a fact
cannot be established, the findings say so and stop.

---

## What the spike is for

Two separate reasons now point at the same measurement, and they do not want the
same answer. The plan names both up front because the recommendation has to
address both or say which one it is abandoning.

**Reason 1 — coverage (the original framing, 2026-07-30).** Apple Foundation
Models requires Apple Intelligence: iPhone 15 Pro or later, on iOS 26. Dictus
ships `IPHONEOS_DEPLOYMENT_TARGET = 17.0` **[code]** `Dictus.xcodeproj/project.pbxproj:1118`.
Every device between those two bounds can buy Pro and cannot run the flagship Pro
feature. A second backend lifts that cap.

**Reason 2 — reliability (added 2026-08-13, from #315).** Apple documents that
`LanguageModelSession.GenerationError.rateLimited` occurs *only* when the app is in
the background, and DictusApp is in the background for every polish call by design.
Field captures show latched runs of up to 11 min 50 s with zero successes. A
backend running in-process under our own scheduling is not subject to foreground
priority.

These pull in different directions. Reason 1 wants something that runs on a 4 GB
iPhone. Reason 2 wants something good enough to *replace* Apple FM on an iPhone 17
Pro. A candidate can satisfy one and fail the other, so the findings will answer
per device tier and not as a single yes/no.

---

## Decision rule, pre-registered

A candidate is **viable** only if all six hold. Anything short of all six is
"viable under stated conditions" at best, and the conditions get named.

| # | Criterion | Threshold | How it will be decided |
| --- | --- | --- | --- |
| **V1** | **Runs backgrounded at all.** | The runtime must complete inference without submitting GPU (Metal) work, because the process is backgrounded under `UIBackgroundModes: audio`. | Documentary gate, from the SDK headers and Apple's background-execution rules. A Metal-only runtime is disqualified here and its other numbers are not collected. |
| **V2** | **Memory, computable half.** | Weights + KV cache at the working context + runtime overhead ≤ **1.2 GB** on the smallest targeted device. | Arithmetic from published quantized file sizes and the model's KV geometry. **[derived]** |
| **V3** | **Memory, device half.** | Peak `phys_footprint` of DictusApp during a backgrounded dictation, with the LLM resident *and* the STT model resident *and* the audio engine warm, must leave ≥ 300 MB of `os_proc_available_memory()` headroom. | **Cannot be measured without a physical iPhone.** Will be reported as unmeasured with the exact steps needed. |
| **V4** | **Latency.** | On the target device: **p50 ≤ 5 s, p90 ≤ 12 s** on the shipping fixtures. | Justified from the field baseline below, not invented. Measurable on a Mac only; the device figure will be derived and labelled as such. |
| **V5** | **Quality.** | Through `polish-harness eval` on the shipping fixtures, the candidate must pass **at least as many property checks as Apple FM on the same fixture set**, and produce **zero** language-guardrail rejections on the French fixtures. | **[measured]** — this is the one criterion that can be settled properly during the spike. |
| **V6** | **Distribution.** | Download ≤ **1.5 GB**, and a licence that permits redistribution of the weights inside a paid App Store binary. | **[source]** — official model cards and licence texts only. |

### Where V4's numbers come from

The Apple FM baseline is not a guess; it is the metrics ring, quoted in #315 from
`dictus-polish-debug-20260805-174258.json`, iPhone16,2 (15 Pro Max), iOS 26.5.2,
build 1.8.0 (25), **backgrounded** like every polish call in this product **[field]**:

```text
success: n=196, min=688 ms, p50=1654 ms, p90=4842 ms, max=12528 ms
```

`max = 12528 ms` is a latency the product already ships and users already tolerate,
so it is the honest ceiling to hold a replacement to — hence p90 ≤ 12 s. p50 ≤ 5 s is
three times the Apple FM median: a pre-Apple-Intelligence device is slower silicon,
and a backend that is reliable but three times slower than an unreliable one is
still the better trade for a feature that currently stops working for twelve
minutes at a stretch.

---

## What will be measured, on what

### Measurable during this spike, on this Mac

- **V1** — from `$(xcrun --sdk iphoneos --show-sdk-path)` headers and Apple's
  published background-execution rules. Documentary, but decisive, and it
  disqualifies candidates before any benchmarking effort is spent on them.
- **V5, quality** — the real thing. `polish-harness` already runs the *real*
  `PolishPipeline` on text fixtures off-device, and its README states the intent
  outright: it is "the safety net for the upcoming third-party-LLM migration
  (any `PolishEngineProtocol` engine plugs in unchanged)" **[code]**
  `DictusCore/Sources/polish-harness/README.md:6`. Candidate models will run
  through that same pipeline — same pre-pass, same guardrails, same post-pass,
  same fixtures — against the Apple FM baseline produced on the same machine in
  the same session.
- **V2 and V6** — arithmetic and licence reading.
- **Mac-side latency** — real numbers, on an M4 Pro. Useful for *relative*
  comparison between candidates and against Apple FM on identical inputs. **It is
  not an iPhone number** and will never be presented as one.

### Not measurable during this spike

- **V3, and the device half of V4.** A simulator runs on the host CPU and GPU, has
  no jetsam limit (`os_proc_available_memory()` returns 0 there **[code]**
  `DictusCore/Sources/DictusCore/DeviceCapabilities.swift:103`), and cannot
  reproduce background memory pressure. Simulator numbers would be worse than no
  numbers because they would look like answers. These go on the maintainer's
  manual list with exact steps.

---

## The code this spike will add, and its status

One throwaway `PolishEngineProtocol` implementation that speaks
`POST /v1/chat/completions` to a local server, plus the minimum harness change
needed to select it. Both live in the **`polish-harness` target only**, which is
macOS-only, excluded from the app targets and not built by CI **[code]**
`DictusCore/Package.swift`. Marked throwaway in their own headers.

Why a local HTTP server rather than linking a runtime into the harness: the
question this spike must answer about a runtime is *whether iOS will let it run
backgrounded*, and that is decided by reading the platform rules, not by linking it
on a Mac. What the harness is needed for is **output quality for a given model at a
given quantization**, and that is a property of the weights and the prompt, not of
the host. Running the weights behind an HTTP call gets the quality answer with a
fraction of the build complexity, and does not pretend to answer the latency
question it cannot answer.

Nothing is added to `DictusCore`, `DictusApp` or `DictusKeyboard`.

---

## Candidate runtimes, and why these

Selected against V1 first, because V1 kills candidates cheaply.

| Runtime | Compute path | Expected V1 verdict | Why it is on the list |
| --- | --- | --- | --- |
| **llama.cpp / ggml** | Metal **or** CPU (NEON + Accelerate) | Needs checking — CPU backend plausibly survives V1 | The default answer for on-device LLM, MIT, ships on iOS today |
| **ExecuTorch** | XNNPACK (CPU), Core ML, MPS | Needs checking — XNNPACK path plausibly survives | PyTorch's own on-device runtime, BSD, first-class iOS support |
| **Core ML on the ANE** | ANE + CPU | Expected to pass — this is the path the product already uses in the background | `FluidAudio` sets `config.computeUnits = .cpuAndNeuralEngine` with the comment "Prefer Neural Engine across platforms for ASR inference **to avoid GPU dispatch**" **[source]** `FluidAudio/Sources/FluidAudio/ASR/AsrModels.swift:262` |
| **MLX / MLX Swift** | Metal only | Expected to fail V1 | Must be checked and named, because it is the obvious Apple-shaped answer and will be re-proposed otherwise |
| **MediaPipe LLM Inference** | GPU-preferred on iOS | Expected to fail V1 | Same reason |

## Candidate models, and why these

Filtered on: real French, small enough for V2, and a licence that survives V6.
The issue names "Gemma 3 at 1B / 4B, and any comparable compact instruct model";
the list below is the justification for what "comparable" means here.

| Model | Why | Licence to verify |
| --- | --- | --- |
| **Gemma 3 1B / 4B** | Named in the issue. Must be evaluated on its merits, not accepted on its mention. | Gemma Terms of Use — **not** OSI, redistribution terms need reading against App Store distribution |
| **Qwen3 1.7B / 4B** | The strongest multilingual claim in this size class | Apache-2.0 |
| **Llama 3.2 1B / 3B** | The reference small instruct pair | Llama 3.2 Community Licence |
| **LFM2 1.2B** | Designed for on-device from the start rather than shrunk into it | LFM Open Licence |

Model facts — parameter counts, quantized sizes, language coverage — will be taken
from **official model cards only**. The search results for "best small LLM 2026" are
uniformly SEO content and are excluded under the [secondary] rule above.

Not on the list, and why: 7B-and-up anything (fails V2 on a 4 GB device by
inspection); English-only small models (fail V5 on French fixtures by
construction); base (non-instruct) checkpoints (the task is instruction-shaped).

---

## Questions the findings must answer

1. Which backends are viable on the pre-Apple-Intelligence installed base, **and on
   which devices exactly** — named by model identifier and RAM tier, not "older
   iPhones".
2. Their latency against the Apple FM baseline above, on the same inputs, with the
   app backgrounded — or an explicit statement of which half of that could not be
   measured and why.
3. Memory footprint under background pressure, and download size.
4. Output quality against the `polish-harness` baseline.
5. A recommendation: yes, no, or yes-under-these-conditions.

## What would make this spike report a failure

Answering "it seems feasible". Reporting a Mac latency as a device latency.
Reporting a simulator memory figure as a device figure. Any of those is worse than
the gap it papers over.
