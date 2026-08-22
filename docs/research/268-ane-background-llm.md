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

**#268's question is answered, and the answer is no — but not for any of the
reasons the spike expected.**

1. **A backgrounded DictusApp *can* reach the Neural Engine.** On the phone,
   backgrounded, Core ML's compute plan is byte-for-byte the Mac's: **1,166 ANE
   operations against 13 CPU** in the transformer chunk, **0 GPU** everywhere
   **[measured]**. It does not silently re-plan onto the CPU when the app leaves
   the foreground. That mechanism was the predecessor's largest open question.

2. **The ANE holds the prompt.** 1,680 tokens of prefill inside a 2048-context
   ANEMLL build, EOS stop, coherent French **[measured]**.

3. **And it costs 14 seconds.** Backgrounded on an `iPhone16,2` at `nominal`
   thermal, three consecutive iterations: prefill **4.5–4.9 s**, decode
   **9.3–9.5 s**, **total 13.8–14.4 s** per polish call **[measured]**. The
   pre-registered budget is p50 ≤ 5 s; the Apple FM field baseline on this exact
   device is p50 **1,654 ms** **[field]**. That is **2.8× the ceiling and 8.4×
   the incumbent**.

4. **Memory is not the constraint, and the whole memory argument was measuring
   the wrong thing.** With all 1.8 GB of weights loaded: **3,090 MB** of jetsam
   headroom left and a `phys_footprint` of **284 MB** **[measured]**, against
   D1's 3,369 MB baseline on the same device **[field]**. Core ML maps ANE
   weights instead of allocating them, so **1.8 GB of model costs about 280 MB of
   the budget jetsam enforces**. The pre-registered 1.2 GB ceiling, D1's
   correction of it, and the addendum's "does 1.9 GB fit alongside Parakeet"
   table all priced a quantity that does not bind.

5. **The binding term is decode, and no prompt redesign touches it.** Decode is
   9.4 s of the 14 s. The one lever the predecessor identified — shorten the
   1,150-token instruction block — moves prefill only, so even a prompt of length
   zero leaves 9.4 s **[derived]**. A future candidate would need roughly **3×**
   ANEMLL 0.3.5's decode rate on this checkpoint to land inside the budget.

6. **Sustained ANE inference throttles the phone.** A first run that began at
   `thermal=fair` crossed to `serious` within ninety seconds; decode fell from
   13.5 to 7.0 tok/s and the call reached **33.9 s** **[measured]**. DictusApp
   stays warm between dictations by design, which is the pattern that produces
   this curve.

7. **No conversion was needed and none was attempted.** ANEMLL publishes
   `anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5` — the exact candidate, at the release
   #268 names, conversion parameters recorded in its `meta.yaml` **[source]**. A
   deliberate deviation from the issue's step 1; see
   [Deviations](#deviations-from-the-issue). There is no toolchain failure to
   report: the model converted, loaded, and ran.

8. **The converted build barely polishes, and quality is unreachable on it for a
   structural reason.** With reasoning off — the only mode that fits — its output
   differs from its input by **one character**, on the Mac and on the phone
   identically **[measured]**. Allowed to reason, it reasons coherently and
   on-task, so the weights are not the problem; but the prompt occupies 1,676 of
   a 2,048-token window and its reasoning needs 500–700 more, so **the mode that
   works does not fit** **[measured, derived]**. Quality would need a larger
   context, and a larger context means more prefill on a call already 2.8× over
   budget.

9. **Loading is a once-per-install cost, not a per-launch one.** 118.5 s the
   first time on the device, **2.1 s** every time after **[measured]**.

**Against the pre-registered rule this is the negative branch: close #268.** The
detail, and what a future reopening would have to show, is in
[The decision](#the-decision-against-the-rule-that-was-registered-before-the-measurement).

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

**And the protocol was rehearsed before it was used.** The whole flow ran on an
iPhone 17 Pro Max simulator first, backgrounded by launching Safari over it,
ending on `allIterationsBackgrounded=true` **[measured]**. None of its numbers
mean anything — a simulator has no Neural Engine, so it ran the CPU path that
produces gibberish — but it meant the maintainer's phone was not the place where
a crash-on-launch would be discovered.

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

## Finding 4 — latency on the Mac, and the term that decides

This is the gate, not the answer; Finding 6 has the phone. It is kept because the
Mac is where the shape of the problem became visible, and because the
iPhone-to-Mac multiplier it establishes (1.65×) is useful to anyone reading the
predecessor's Mac-only tables.

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
The predecessor establishes that a Mac figure is a *floor* for any iPhone, and
Finding 6 measures the multiplier: **1.65×**, for 14.0 s on the phone.

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

Some 75–82 seconds of that is ANE placement, and on the Mac it did not shrink on
a later launch from the same path — ANEMLL's README says "subsequent loads will
be instantaneous" **[source]** and that was not observed here.

**On the phone it is.** Finding 6 measures 118.5 s the first time and 2.1 s every
time after, so the Mac behaviour above is a macOS quirk and not a property of the
model. It is recorded rather than dropped because it is what the Mac gate saw,
and because it would otherwise look like an unexplained discrepancy with the
device figures.

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

## Finding 6 — the device, backgrounded: the measurement #268 asked for

`iPhone16,2`, iOS 26.6, 8 GB, `AneHarness.app` backgrounded, three iterations,
same prompt, same `temperature: 0`, thinking off. Collected 2026-08-22
**[measured]**. Two runs, and the difference between them is itself a finding.

### Which build produced these numbers

Line 2 of every export in this repository carries `rev <sha>@<branch>`, and this
one says **`rev unknown`**. That is not a fault in the run: the harness is not a
target of `Dictus.xcodeproj`, so the "Generate build info" phase that writes
`DictusBuildInfo.plist` never runs for it, and `PersistentLog.codeRevision`
correctly reports that it has no revision to report rather than guessing
**[code]**.

**The binary on the phone was built from the working tree that became
`eba99cf`**, and nothing under `tools/ane-harness/App/` changed between that
commit and the run. So there is no revision line to check on this one, and the
sha is recorded here instead.

### Run B — the clean one, thermal `nominal` throughout

```text
ane-bench — #268 D2
rev unknown | iPhone16,2 | Version 26.6 (Build 23G71) | ramGB=8
model ctx=2048 batch=64 computeUnits=cpuAndNeuralEngine
prompt 3-long systemChars=5483 userChars=729
modelLoadMs=2079
computePlan qwen_FFN_PF_lut6_chunk_01of02.mlmodelc: ANE 1166 / CPU 13 / GPU 0
iteration 1 prefillMs=4947 (340 tok/s) decodeMs=9480 generated=162 (17.1 tok/s) totalMs=14427 stop=eos_token
  iteration1.start available=3091MB footprint=284MB thermal=nominal state=background
  iteration1.done  available=3090MB footprint=285MB thermal=nominal state=background
iteration 2 prefillMs=4463 (376 tok/s) decodeMs=9337 generated=162 (17.4 tok/s) totalMs=13800 stop=eos_token
iteration 3 prefillMs=4476 (375 tok/s) decodeMs=9358 generated=162 (17.3 tok/s) totalMs=13834 stop=eos_token
allIterationsBackgrounded=true
```

Every sample in every iteration reads `state=background` and `thermal=nominal`.
This is the number.

### What it answers

**The ANE is reachable from a backgrounded app, and the compute plan proves it
rather than implying it.** The on-device plan is byte-for-byte the Mac's — 1,166
ANE operations against 13 CPU in the transformer chunk, 0 GPU in every row
**[measured]**. Core ML does not silently re-plan onto the CPU when the app
leaves the foreground. That was an open mechanism in the predecessor, named in
its own "what I am not comfortable asserting", and it is now closed.

**The prompt fits.** 1,680 tokens of prefill, EOS stop after 162 generated
tokens, coherent French identical in substance to the Mac's.

**Memory is not the constraint, and it is not close.** This is the result that
most contradicts the predecessor:

| | |
| --- | --- |
| Jetsam headroom with the whole model loaded | **3,090 MB** |
| `phys_footprint` | **284–285 MB** |
| D1's baseline, DictusApp at launch, same device | 3,369 MB **[field]** |

**1.8 GB of weights cost about 280 MB of jetsam headroom.** Core ML maps ANE
weights rather than allocating them into the process, so almost none of the model
lands in the budget jetsam enforces. The 280 MB is a comparison across two
different processes — this harness against DictusApp in D1 — so read it as an
order of magnitude; the load-bearing figure is the absolute one, **3,090 MB still
available with the model fully loaded and running**, which needs no comparison at
all. Every memory argument in the predecessor —
the pre-registered 1.2 GB ceiling, the correction to 3.33 GB, the "does 1.9 GB
fit alongside Parakeet's ~800 MB" arithmetic in the addendum — was measuring the
wrong quantity. Neither the ceiling nor its falsification decides anything.

The readings are also flat across three iterations (3,091 → 3,090 → 3,091 MB), so
the KV cache does not grow between calls.

### What it refuses

| | Backgrounded, `nominal` | Budget | Apple FM field baseline |
| --- | --- | --- | --- |
| Prefill, 1,680 tokens | 4,463 – 4,947 ms | | |
| Decode, 162 tokens | 9,337 – 9,480 ms | | |
| **Total per polish call** | **13,800 – 14,427 ms** | **≤ 5,000 ms** | **1,654 ms** **[field]** |

**2.8× the budget ceiling and 8.4× what Apple FM actually delivers on this
device.** Not a near miss.

And the term that decides is decode, as the Mac indicated: 9.4 s of a 14 s call.
Prefill is 4.5 s. Even a prompt of length zero leaves 9.4 s, so the one lever the
predecessor identified — shorten the 1,150-token instruction block — still
cannot reach the budget **[derived]**.

### The iPhone-to-Mac multiplier, given separately because it was asked for

Like for like — same runtime, same bundle, same prompt, same compute units,
medians of three iterations **[measured]**:

| | Mac (M4 Pro, ANE) | iPhone16,2 (ANE) | Multiplier |
| --- | --- | --- | --- |
| Prefill, 1,680 tokens | 2,790 ms (602 tok/s) | 4,476 ms (375 tok/s) | **×1.60** |
| Decode, 162 tokens | 5,845 ms (27.7 tok/s) | 9,358 ms (17.3 tok/s) | **×1.60** |
| Total | 8,635 ms | 13,834 ms | **×1.60** |

The two terms scale by the same factor, which is the useful thing to know: on
this runtime the phone is uniformly 1.6× the Mac, so a Mac figure can be scaled
without asking which half of the call it came from.

**A larger multiplier can be produced by comparing the wrong pairs.** Setting the
predecessor's Mac figures against these device figures gives roughly ×2.7 on
prefill and ×4.5 on decode — but those Mac figures are Ollama serving a Q4_K_M
build on the CPU, and these are ANEMLL serving a LUT6 build on the ANE. Runtime,
quantization and compute unit all differ, so the ratio measures the change of
stack, not the change of machine. The table above changes one variable.

### Run A — what thermal pressure does, and why it is not a footnote

The first run started at `thermal=fair` and crossed to `serious` during it
**[measured]**:

| Iteration | Prefill | Decode | Total | Thermal |
| --- | --- | --- | --- | --- |
| 1 | 8,966 ms | 12,042 ms | **21,008 ms** | `fair` |
| 2 | 9,743 ms | 17,370 ms | **27,113 ms** | `fair` → `serious` |
| 3 | 10,725 ms | 23,158 ms | **33,883 ms** | `serious` |

Decode falls from 13.5 to 7.0 tok/s across roughly ninety seconds of ANE work.
**Sustained LLM inference on the ANE heats an iPhone until the SoC throttles**,
and the throttled figure is 34 s — 6.8× the budget.

This matters more for Dictus than a benchmark footnote suggests, because
DictusApp runs under `UIBackgroundModes: audio` and stays warm between
dictations. A user dictating repeatedly would be holding the ANE busy in exactly
the pattern that produced this curve, and thermal state also throttles the
transcription that has to happen first.

Iterations 2 and 3 of run A carry `state=active` — the app came to the foreground
mid-run — so run A does not qualify as a background measurement and its file says
`allIterationsBackgrounded=false`. Its iteration 1 is clean and is quoted above
on its own terms. Run B replaces it as the measurement; run A is kept because the
thermal curve is real evidence and run B, being short and starting cold, does not
show it.

### The load cost, corrected

| | |
| --- | --- |
| First load on the device, ever | **118,501 ms** |
| Every load after that | **2,079 ms** |

ANEMLL's README says "the first time the model loads, macOS will take some time
to place it on the device. Subsequent loads will be instantaneous" **[source]**.
On the phone that is exactly right. On the Mac it was not — two separate
processes loading the same bundle from the same path both paid 96–104 s
**[measured]**. Whatever caches the ANE placement works on iOS and did not here.

So the two-minute load is a once-per-install cost, not a once-per-launch one, and
it is not an argument against anything.

---

## Finding 7 — the converted model barely polishes, and the reason is not the one it looks like

Noticed by the maintainer on reading the export, and worth recording even though
latency already decides the issue: on `3-long` the ANE build returns the input
almost unchanged.

Measured rather than eyeballed — the model's output against the exact text the
prompt carried **[measured]**:

| Build | Similarity to input | Edits |
| --- | --- | --- |
| ANEMLL LUT6, Mac ANE | **0.9992** | one: a final `.` |
| ANEMLL LUT6, iPhone ANE | **0.9992** | one: a final `.` |
| `qwen3:1.7b` Q4_K_M via Ollama, same prompt | 0.113 | a real rewrite |

The Mac and the phone produce **byte-identical** 638-character output, so this is
a property of the build, not of the device. And the Ollama rewrite is a genuine
polish — punctuation added, `pardon` and `tout simplement` dropped:

> T'aimerais bien tester un texte un peu plus long que je décris à l'oral, comme
> je le fais en fait. Et justement, quand je ne sais pas trop quoi dire […]
> L'idée, c'est de voir comment se comporte le modèle et l'application en
> général.

(It also mangles the opening clause — `Ce que j'aimerais` → `T'aimerais`. Neither
output is being held up as good here; the point is that one transformed the text
and the other did not.)

### LUT6 is the obvious suspect and it is probably not the culprit

The two runs differ in more than quantization: **the Ollama run reasoned first
and the ANE run did not.** Ollama generated 1,800–2,500 characters of reasoning
before answering **[measured]**, while the harness suppresses reasoning by
injecting the empty `<think></think>` block. A model that thinks before rewriting
is not the same model.

Re-running the ANE build with reasoning left on settles it **[measured]**:

```text
computeUnits=cpuAndNeuralEngine +thinking
iteration 1 promptTokens=1676 prefillMs=2711 decodeMs=12744 generated=360 stop=max_tokens
output: <think>
Okay, let's tackle this input. The user wants the French text polished according
to the given rules. […] Here, "pardon" is a word that should be replaced with the
punctuation mark. […]
```

**The weights are fine.** Allowed to think, the LUT6 build reasons coherently and
on-task about the French text — it identifies the filler, quotes the rules, works
through the clauses. This is not a model destroyed by quantization.

### What actually blocks it is the context window

The reasoning above never reaches an answer. It runs to the token cap still
inside `<think>`, and it cannot do otherwise: the prompt is **1,676 tokens of a
2,048-token window**, leaving **372 tokens**, and this model's own reasoning on
this prompt needs 500–700 **[derived, from the Ollama runs]**.

So the two modes available on this bundle are:

- **reasoning off** — fits, and returns the input plus a full stop;
- **reasoning on** — polishes, and does not fit.

A build with a larger context would be needed to get the quality, and a larger
context means more prefill on top of a call that is already 2.8× over budget.
That is why this finding, which looks like a footnote, points the same way as
the latency: **it makes the gap wider, not narrower.**

### A correction the predecessor should carry

The predecessor established that `chat_template_kwargs: {enable_thinking: false}`
was accepted and ignored by Ollama while `reasoning_effort: "none"` worked, and
verified that against `qwen3.5:0.8b`.

On Ollama 0.32.6 today, with `qwen3:1.7b`, **neither key suppresses reasoning**.
Both were sent and the response still carried 1,812–2,481 characters of it
**[measured]** — moved into a separate `message.thinking` field rather than
inlined in `content`, which is why it does not show up by reading the answer.

Two consequences, neither of which changes this document's conclusion:

- `LocalHTTPPolishEngine` reads `message.content` and strips inline reasoning, so
  the predecessor's **quality** scores are unaffected — the content it scored was
  clean **[code]**.
- Its **latency** figures for `qwen3:1.7b` include generating reasoning tokens
  that were believed to be suppressed, so they are, if anything, overstated
  against a product that would not pay for them.

---

## The decision, against the rule that was registered before the measurement

#268 pre-registered this:

> **Negative** — the ANE cannot hold the prompt, or backgrounded latency lands
> above the p50 ≤ 5 s budget: **close this issue permanently**. Both rationales
> are then answered and a second local backend is not a thing Dictus does.

The first clause fails and the second holds. The ANE *does* hold the prompt, and
memory turned out not to be a constraint at all — but backgrounded latency is
**13.8–14.4 s at nominal thermal and up to 33.9 s under thermal pressure**,
against a 5 s ceiling and a 1,654 ms incumbent.

**That is the negative branch. #268 should be closed.**

Two things are worth saying about *how* it is closed, because they are not the
same as the reasons anyone expected.

**It is not closed on memory.** The predecessor's whole arithmetic — a 1.2 GB
ceiling, D1's correction to 3.33 GB, the table of which candidates fit — measured
a quantity that does not bind. An ANE-resident Core ML model costs the app
roughly 280 MB of jetsam headroom regardless of how many gigabytes of weights it
has. If this question is ever reopened, that page of reasoning should not be
reopened with it.

**It is not closed on "the ANE is unreachable in the background" either.** It is
reachable, it is planned, it works. A future reopening would need a decode rate
roughly **three times** what ANEMLL 0.3.5 delivers on this checkpoint —
17.3 tok/s measured, and about 55 tok/s needed to land 162 tokens plus prefill
inside 5 s **[derived]**. That is the number to hold any future candidate to, and
it is a measurement, not an argument.

---

## What was not measured, and does not need to be

**Parakeet and the LLM resident in one process.** The composition is no longer
interesting: the LLM costs ~280 MB of headroom, D1 showed Parakeet's whole
transcription cycle moving the same reading by ~35 MB, and there is 3 GB of room
**[derived]**. Memory was never going to be the deciding term and now demonstrably
is not.

**Whether a shorter prompt or a smaller model gets under the budget.** Out of
scope: #268 is about `qwen3:1.7b`, and its decode rate misses by 3×. A different
model is a different issue, opened for a named model with a named footprint, as
the coverage half already requires.

**Quality of this LUT6 build through the full 72-check suite.** Finding 7 settles
the question the suite would have been asked — the build returns its input
unchanged in the only mode that fits its context window — without needing 72
fixture-runs to say it. Scoring it properly would mean putting an
OpenAI-compatible façade in front of the ANE runtime, and it would have mattered
only if latency had come back positive.

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
directory, which `devicectl device copy from --domain-type appDataContainer`
reads over Wi-Fi. In practice this cost the maintainer *less* than the App Group
route would have: the entire measurement — launch, background, three iterations,
collection — was driven from the Mac, and the only human act in it was unlocking
the phone. The App Group write is still attempted and its outcome recorded.

---

## What I am not comfortable asserting

- **That one device generalises.** Everything phone-shaped here is one
  `iPhone16,2` on iOS 26.6. The conclusion survives a wide margin — 14 s against
  a 5 s ceiling — so a faster phone does not flip it without a 3× improvement,
  but the *numbers* are one device's.

- **That the three iterations of run B are a p50.** They are three consecutive
  calls on one fixture, minutes apart, in one thermal state. The spread is
  narrow (13.8–14.4 s) and that is all it establishes. The budget is written as a
  p50 and this is not one.

- **That LUT6 is why the output is near-identical.** Finding 7 rules out the
  obvious reading rather than confirming it: allowed to reason, the same build
  reasons coherently on the same prompt. What is established is that *this
  build, in the only mode its context window allows*, does not transform the
  text. Whether a LUT6 build with a 4K context would polish acceptably is
  untested, and so is whether LUT6 costs anything against the 66/72 the
  predecessor measured on a Q4_K_M build. ANEMLL's own README does warn that
  "Quantization should be improved. LUT4 quality is fairly low due to lack of
  Block Quantization on Apple Neural Engine" **[source]** — a reason to suspect
  it, not evidence that it bit here.

- **That one fixture characterises the quality gap.** Finding 7 is `3-long`, the
  largest shipping fixture. A shorter input leaves more of the window free and
  might behave differently in the reasoning-on mode. The 72-check suite was not
  run against this build.

- **That 162 generated tokens is representative.** The `3-long` fixture is the
  largest shipping one, and its polished output happens to be close to a copy of
  its input. A mode that condenses or translates would decode a different amount,
  and decode is the term that decides.

- **That the undetermined operations in the compute plan are ANE operations.**
  1,448 of them in the FFN chunk is more than the 1,166 that are named. They are
  reported as undetermined because that is what Core ML returned.

- **That the load numbers say anything about a shipping integration.** 118.5 s
  once and 2.1 s after is what this bundle costs on this device at this ANEMLL
  version, installed as an app resource. A real integration would download the
  weights rather than bundle them, and whether the ANE placement cache survives
  that, an OS update, or a device reboot was not tested.

- **That 17.3 tok/s is the Neural Engine's ceiling rather than ANEMLL's.** What
  was measured is one open-source runtime, at 0.3.5, on one LUT6 chunked build.
  Apple runs its own model on the same silicon and does not publish how. The
  claim this document makes is about the option available to this product today —
  an MIT-licensed toolchain and a public checkpoint — not about what the hardware
  could do in principle. A future ANEMLL release could move this number; a
  reopening of #268 on that basis would need it measured, not argued, against the
  ~55 tok/s the budget implies.

- **That the thermal curve in run A is characterised.** It is one run, and the
  phone's starting state was not controlled — it read `fair` before any
  measurement began. What it shows is that ANE inference at this duty cycle
  reaches `serious` and that decode degrades roughly 2× when it does. How quickly
  it recovers, and what a realistic dictation cadence would do, were not
  measured.

---

## Reproducing

Everything below is `tools/ane-harness/`, after `./setup.sh`. The full manual is
in that directory's `README.md`.

```sh
# The exact prompt, from the shipping source of truth
cd DictusCore
swift run polish-harness prompt Sources/polish-harness/fixtures/seed.json --id 3-long

# Mac: the ANE run, the CPU control, and the reasoning-on control (Finding 7)
cd tools/ane-harness/AneBenchKit
swift run -c release ane-bench --iterations 3
swift run -c release ane-bench --iterations 1 --max-tokens 60 --compute-units cpu
swift run -c release ane-bench --iterations 1 --max-tokens 360 --thinking

# Phone: build, install, launch (needs the phone unlocked), collect
cd tools/ane-harness
xcodebuild build -project AneHarness.xcodeproj -scheme AneHarness -configuration Debug \
  -destination 'id=<device-id>' -derivedDataPath build/DerivedData -allowProvisioningUpdates
xcrun devicectl device install app --device <device-id> \
  build/DerivedData/Build/Products/Debug-iphoneos/AneHarness.app
xcrun devicectl device process launch --device <device-id> --terminate-existing \
  com.pivi.dictus.anebench

# Poll Documents/phase.txt until it reads waiting-for-background (~2 min the first
# time, ~5 s after), then background the harness without touching the phone:
xcrun devicectl device process launch --device <device-id> com.apple.Preferences

# Poll again until phase.txt reads done (~45 s), then:
xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer \
  --domain-identifier com.pivi.dictus.anebench --source Documents --destination ./out
```
