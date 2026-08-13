# Can the keyboard extension call Apple Foundation Models? — research plan

**Issue:** [#357](https://github.com/getdictus/dictus-ios/issues/357)
**Scope:** measurement only. No feature work, no move of the polish call, no change to what a normal dictation does.
**Date:** 2026-08-13.

**This document is the plan, committed before any measurement was taken**, so the findings can be checked against the criteria rather than against criteria written to fit them. Follows the convention set by [`287-user-dictionary-learning.md`](287-user-dictionary-learning.md). The findings are appended below in a later commit on this branch.

---

## Why this spike exists

[#315](https://github.com/getdictus/dictus-ios/issues/315) established, first from Apple's documentation and then from a controlled device experiment on 2026-08-13, that `LanguageModelSession.GenerationError.rateLimited` is a **per-call decision applied to backgrounded processes**. The same process, seconds apart, is refused when backgrounded and served in ~800 ms when active. A foreground visit does not refund the budget; only a fresh process resets it.

DictusApp is backgrounded for every polish call by design — the keyboard extension holds the screen while the app records, transcribes and polishes behind it. So polish runs in the one state Apple deprioritises, on every single dictation.

**The keyboard extension is in the foreground at exactly the moment polish would run.** If the extension's process is treated as foreground by this limiter, the problem stops existing rather than needing to be handled.

Nobody has checked. That is this spike.

---

## Evidence labels

Every claim in the findings carries one, and the label is part of the claim.

| Label | Meaning |
| --- | --- |
| **[sdk]** | Read in the iOS SDK on this machine, cited by absolute path and line. |
| **[code]** | Read in this repository, cited by file and line. |
| **[doc]** | Apple developer documentation, cited by URL, quoted exactly. |
| **[build]** | Output of a build or test command run on this machine, command recorded. |
| **[device]** | Measured on the maintainer's iPhone. **Nothing in this spike can carry this label until he runs the probe.** |
| **[derived]** | Inference on top of a labelled fact. The input is sourced; the output is not. |

---

## The constraint that shapes this plan

`docs/agents/simulator.md` §7 establishes **by experiment, not by assumption**, that the Dictus keyboard cannot be enabled in any iOS simulator. Four methods were tried and all four failed; the extension registers with the plug-in system but never appears in `UITextInputMode.activeInputModes`.

Therefore:

- **Q2 and Q3 are not measurable by an agent on this machine.** They require the extension's process to actually run.
- **An app-target measurement cannot stand in for either.** The entire question is whether the *extension's process* is treated differently from the app's. Running the same code in DictusApp answers nothing, and reporting it as an extension result would be worse than reporting nothing.
- Q4 likewise requires a live extension.

So this spike splits into **what is answerable now by build and by SDK** (Q1's static half), and **a probe plus a written procedure** for everything else. The probe is the deliverable for Q2/Q3/Q4; the answers arrive when the maintainer runs it.

---

## Falsifiable criteria, written before measuring

A spike that concludes "it seems feasible" has failed. Each question below has a stated yes and a stated no.

### Q1 — Is `FoundationModels` usable from an app extension at all?

This question has a static half and a runtime half, and **they are not the same question**. Splitting them is deliberate: a compile proves the toolchain permits the call, not that the system serves it across the extension sandbox boundary.

#### Q1a — static / toolchain

| | Criterion |
| --- | --- |
| **YES** | (i) `FoundationModels.swiftinterface` in the iOS SDK carries no `iOSApplicationExtension, unavailable` annotation, **and** that grep is calibrated against a framework in the same SDK where the annotation does appear, so a null result is a real absence and not a broken method; **and** (ii) the `DictusKeyboard` target compiles and links a real `LanguageModelSession` call. |
| **NO** | A compile error naming the API as unavailable in application extensions, a link failure, or a documented prohibition. |

**Why (ii) is strong evidence and not merely suggestive:** `DictusKeyboard` builds with `APPLICATION_EXTENSION_API_ONLY = YES` (`Dictus.xcodeproj/project.pbxproj:1231`, `:1259`). That setting makes the compiler *enforce* extension-safety — an API marked unavailable to extensions is a hard error, not a warning. A clean build of that target is the toolchain stating that the call is permitted.

**A documented prohibition outranks a clean build.** If Apple documents FoundationModels as unsupported in extensions, that is the answer regardless of what compiles today.

#### Q1b — runtime

| | Criterion |
| --- | --- |
| **YES** | Inside the extension process on device: `SystemLanguageModel.default.availability` reports `.available`, **and** a `respond()` returns generated text. |
| **NO** | Availability reports unavailable inside the extension while the same device reports available to the app; or `respond()` throws `assetsUnavailable`; or the call never returns. |

**Q1a passing does not establish Q1b.** Compile-time permission is not runtime service access. This is measured by the probe.

### Q2 — Does a keyboard extension count as foreground for this limiter?

The question the whole issue turns on.

| | Criterion |
| --- | --- |
| **YES** | While DictusApp is **demonstrably** in the refusing state, a probe generation issued from the extension **succeeds**. Decisive. |
| **NO** | The probe generation throws `rateLimited` in the same window. Also decisive, and it is the answer that re-ranks [#351](https://github.com/getdictus/dictus-ios/issues/351) onto the Dictus Pro critical path. |
| **INCONCLUSIVE** | The app is not actually refusing at the moment the probe runs. |

The inconclusive row is the trap, and the procedure is built around avoiding it: **the app's refusal must be pinned in the same log window as the probe's result**, not assumed from "I did a lot of dictations". A probe success against an app that was quietly serving requests again proves nothing.

### Q3 — What does a `LanguageModelSession` cost inside the extension's budget?

| | Criterion |
| --- | --- |
| **ROOM** | Peak `phys_footprint` during session creation + `respond()` stays clearly below the extension's ceiling, with the keyboard's normal footprint already loaded, and no memory warning or process death follows. |
| **NO ROOM** | The extension is jetsam-killed (the keyboard visibly resets, and the probe's completion line never reaches the log), or the peak lands close enough to the ceiling that a real dictation on top of it would not fit. |

Both the **delta** and the **absolute peak** must be recorded. The ceiling is absolute, so a small delta on top of an already-high baseline is still a no. The hypothesis under test is #357's own: that inference is hosted by a system daemon and the extension holds only a session object and two strings, making the cost small. That is plausible and unmeasured.

### Q4 — What happens if the extension is torn down mid-generation?

| | Answer shape |
| --- | --- |
| The probe logs a start line and a completion line carrying the same run token. If the keyboard is dismissed while a generation is in flight: a completion line naming a cancellation means it fails cleanly; **no completion line at all** means the process was killed with the call in flight. |

Honest limit, stated in advance: the probe can establish what happens to an in-flight `respond()` in the extension. It **cannot** establish "whether the raw transcription still reaches the document", because that is a property of an architecture that does not exist yet — today the app owns the call and the insertion. That half of Q4 is a design question for the follow-up issue, not a measurement available here.

---

## The probe

### What it is

A new file, `DictusKeyboard/AppleFMExtensionProbe.swift`. Throwaway diagnostic code, marked as such, following the precedent of `DictusKeyboard/KeyboardLifecycleProbe.swift` (the #281 probe): observation only, no control flow depends on it.

It runs the **real** engine — `AppleFoundationModelsPolishEngine` from DictusCore, the shipping prompts, the real session lifecycle — on a **fixed synthetic French string**. Using the production engine is what makes the measurement transferable: it prices exactly what a future implementation would pay. Using a fixed string rather than the user's text keeps user speech out of a log that gets exported and mailed.

### Why it is safe to leave on this branch

The branch may sit for a while, so the bar is that a normal dictation must be bit-identical whether this file exists or not.

- **Inert by default.** It is armed by an App Group boolean that defaults to false. Disarmed, the probe's entire cost is one `UserDefaults` bool read, once per keyboard appearance — not per keystroke, not on the dictation path.
- **One-shot.** Arming is consumed on the first run, so a forgotten flag cannot turn into a probe that fires on every keyboard appearance.
- **No allocation on the normal path.** The session, the strings and the engine are constructed only inside the armed branch. This matters because the keyboard runs under a hard memory ceiling and a `didReceiveMemoryWarning` storm is a known hazard in this codebase.
- **One line at one existing call site.** `KeyboardRootView.onAppear`. Deliberately **not** `KeyboardViewController.swift`, `KeyboardLayouts.swift` or `Vendored/Views/KeyboardView.swift` — PR #354 is open against all three.
- **No new `LogEvent` case.** It reports through the existing `.diagnosticProbe(component:instanceID:action:details:)` event, so `DictusCore` is untouched and nothing has to be kept decoding later.

### Arming surface

A toggle on `PolishDebugView` — the hidden screen already reached by long-pressing the Version row in Settings for 3 seconds, and already the screen the maintainer uses to export polish data. No new navigation, and nothing reachable by an ordinary user.

### What it records

One line when armed and starting, one line on completion or failure, carrying:

- `availability` — `SystemLanguageModel.default.availability` as seen **from inside the extension** (Q1b)
- `outcome` — success, or the `PolishFailureReason` slug via the engine's existing `failureReason(for:)` mapping (Q2: `rateLimited` or not)
- `engineMs` — the arming signature from #315 is that the first refusal is slow (52–436 ms) and everything after returns in 4–9 ms
- `memBefore` / `memAfter` / `memPeak` in MB via the existing `MemoryFootprint` (Q3)
- a run token shared by the start and completion lines (Q4)

No generated text and no input text is logged — only its length.

---

## The device procedure

Written out in full in the findings section and in the PR body. Its shape:

1. Arm nothing yet. Drive DictusApp into the refusing state using the recipe measured twice on 2026-08-13: polish on, one ordinary dictation every one to two minutes for roughly twenty-five minutes.
2. Confirm the refusal is real and current, from the app's own polish debug screen.
3. Arm the probe, then bring the keyboard up. The probe fires on appearance.
4. Export the persistent log and send it.

Step 2 is the one that must not be skipped: it is what separates a decisive Q2 answer from an inconclusive one.

---

## What this spike will not do

- It will not move the polish call. #357 says so explicitly, and the move is a significant architectural change — the polish pipeline, its guardrails, the metrics ring and the debug export all live app-side today. It needs its own issue and its own plan.
- It will not report an app-target measurement as an extension result.
- It will not label anything **[device]** that was not measured on the device.
