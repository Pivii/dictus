# Can the keyboard extension call Apple Foundation Models? — spike findings

**Issue:** [#357](https://github.com/getdictus/dictus-ios/issues/357)
**Scope:** measurement only. No feature work, no move of the polish call, no change to what a normal dictation does.
**Date:** 2026-08-13.

**The plan below was committed before any measurement was taken** (commit `de3b2fb`), so the findings can be checked against criteria that were not written to fit them. Follows the convention set by [`287-user-dictionary-learning.md`](287-user-dictionary-learning.md).

## The answer, in four lines

| | Question | Answer |
| --- | --- | --- |
| **Q1a** | Is `FoundationModels` usable from an app extension, statically? | **Yes, and it is settled.** The extension target compiles and links it, under a compiler setting proven to reject extension-unsafe API. Apple documents no prohibition. |
| **Q1b** | Does it work at runtime inside the extension? | **Not measured.** Needs the device. |
| **Q2** | Does a keyboard extension count as foreground for the limiter? | **Not measured.** Needs the device. This is the one that decides the roadmap. |
| **Q3 / Q4** | Memory cost, and teardown mid-generation | **Not measured.** Need the device. |

**The objection that killed this idea in #315 is dead.** "The extension cannot call Apple FM" is now disproved rather than assumed. What replaces it is a single unanswered question and a probe that answers it in about half an hour of the maintainer's time.

Jump to [Findings](#findings), the [device procedure](#the-device-procedure-what-the-maintainer-runs), or [what I will not assert](#what-i-am-not-comfortable-asserting).

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
| **YES** | While DictusApp is **demonstrably** in the refusing state, a **burst of ten** generations issued from the extension succeeds with no `rateLimited`. |
| **NO** | The burst starts returning `rateLimited` partway through, in the same window. |
| **INCONCLUSIVE** | The app is not actually refusing at the moment the probe runs. |

Two traps, and the design is built around both.

**The first is the confound that makes a single call worthless.** #315 established the budget is **per process** and only a fresh process resets it. The keyboard extension is a *different process* from DictusApp, so one successful call from it has two explanations that a single result cannot separate:

1. the extension counts as foreground and is never limited — the hypothesis; or
2. the extension is simply a fresh process whose background budget has never been spent, and it would have succeeded either way.

Under (2) the problem is **not solved, only relocated**: the extension would deplete its own budget with use and start refusing exactly as the app does, and a design built on a single green result would ship straight into it. A burst inside one process lifetime separates them, because (2) predicts refusals appearing partway through and (1) predicts none.

The asymmetry is worth stating in advance: a burst that survives is strong evidence for (1), because a backgrounded app gets refused under far lighter load than ten back-to-back calls. A burst that fails is weaker evidence for (2) — it could be specific to the density — and would need the slower once-a-minute protocol before concluding.

**The second is the inconclusive row.** The app's refusal must be pinned in the same log window as the probe's result, not assumed from "I did a lot of dictations". A probe success against an app that had quietly started serving requests again proves nothing.

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

A `started` line, one `call` line per generation in the burst, and a `finished` line, all sharing one run token so a whole run greps out together. Between them they carry:

- `availability` — `SystemLanguageModel.default.availability` as seen **from inside the extension** (Q1b)
- `outcome` per call — success, or the `PolishFailureReason` slug via the engine's existing `failureReason(for:)` mapping (Q2: `rateLimited` or not)
- `engineMs` per call — the arming signature from #315 is that the first refusal is slow (52–436 ms) and everything after returns in 4–9 ms, so the *shape* of a refusal run is as diagnostic as the slug
- `memMB` per call plus `memPeakMB` from a 25 ms sampler, and `memBefore` / `memAfter`, all via the existing `MemoryFootprint` (Q3)
- the run token, shared by every line (Q4)

Every line is flushed as it is written. Under Q3's bad outcome the process is jetsam-killed partway through the burst, and the last line to reach disk is the only evidence of how far it got.

No generated text and no input text is logged — only its length.

---

## What this spike will not do

- It will not move the polish call. #357 says so explicitly, and the move is a significant architectural change — the polish pipeline, its guardrails, the metrics ring and the debug export all live app-side today. It needs its own issue and its own plan.
- It will not report an app-target measurement as an extension result.
- It will not label anything **[device]** that was not measured on the device.

---

# Findings

## Q1a — Is `FoundationModels` usable from an app extension, statically? **Yes.**

Five pieces of evidence, in increasing order of weight.

### 1. The SDK carries no extension-unavailability annotation **[sdk]**

`FoundationModels.swiftinterface` for the iOS 26.4 device SDK — 1503 lines, the complete public surface:

```
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/
  iPhoneOS26.4.sdk/System/Library/Frameworks/FoundationModels.framework/
  Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface
```

```console
$ grep -c "ApplicationExtension" …/FoundationModels.swiftinterface
0
```

Zero. **And the file does use the annotation mechanism** — `@available(tvOS, unavailable)` and `@available(watchOS, unavailable)` appear throughout (lines 14, 15, 18, 19, …). Apple annotates unavailability on this API where it applies; extensions are not among the places it applies.

### 2. The null result is calibrated, so it is a real absence **[sdk]**

A grep that finds nothing proves nothing until you show it can find something. The same pattern **does** occur elsewhere in the same SDK:

```console
$ grep -rl "iOSApplicationExtension, unavailable" \
    …/iPhoneOS26.4.sdk/System/Library/Frameworks/ --include='*.swiftinterface'
…/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface
```

The method detects the annotation when it is present. Its absence from FoundationModels is a fact about FoundationModels, not about the grep.

### 3. The extension target builds, under a setting proven to bite **[build]**

`DictusKeyboard` builds with `APPLICATION_EXTENSION_API_ONLY = YES` — confirmed *in effect*, not merely read out of the pbxproj:

```console
$ xcodebuild -project Dictus.xcodeproj -target DictusKeyboard -configuration Debug -showBuildSettings
    APPLICATION_EXTENSION_API_ONLY = YES
    PRODUCT_BUNDLE_IDENTIFIER = com.pivi.dictus.keyboard
```

That setting makes extension-unsafe API a hard compile error. With `AppleFMExtensionProbe.swift` — which constructs `AppleFoundationModelsPolishEngine`, reads `SystemLanguageModel.default.availability`, and awaits `session.respond(to:)` through the engine — in that target:

```console
$ ./scripts/patch-fluidaudio-swift5.sh build/DerivedDataDevice
$ xcodebuild build -project Dictus.xcodeproj -scheme DictusKeyboard -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/DerivedDataDevice \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY=""
** BUILD SUCCEEDED **
```

**The negative control matters more than the build itself.** A green build under a setting that was silently inert would be worthless, so the setting was tested directly. Temporarily adding `UIApplication.shared.applicationState` to the very same file, in the same target:

```
DictusKeyboard/AppleFMExtensionProbe.swift:92:27: error: 'shared' is unavailable in
application extensions for iOS: Use view controller based solutions where appropriate
instead.
** BUILD FAILED **
```

(Reverted immediately; it appears in no commit.) The enforcement is real, so FoundationModels producing no such error is a meaningful result rather than a vacuous one.

### 4. The shipped extension binary actually links it **[build]**

Compiling is not linking. The built `.appex`, device SDK:

```console
$ otool -L build/DerivedDataDevice/Build/Products/Debug-iphoneos/DictusApp.app/
    PlugIns/DictusKeyboard.appex/DictusKeyboard.debug.dylib | grep -i foundationmodels
	/System/Library/Frameworks/FoundationModels.framework/FoundationModels
	    (compatibility version 1.0.0, current version 1.4.34, weak)
```

35 FoundationModels symbols are referenced from the extension binary, including exactly the ones this question is about:

```
FoundationModels.SystemLanguageModel.availability.getter
static FoundationModels.SystemLanguageModel.default.getter
enum case for FoundationModels.LanguageModelSession.GenerationError.rateLimited(…)
```

A note for whoever repeats this: in a Debug configuration the `.appex`'s main binary is a stub and the code lives in `DictusKeyboard.debug.dylib` beside it. `otool -L` on the stub lists no frameworks and looks like a negative result. Check the dylib.

### 5. Apple documents no prohibition — and documents nothing at all **[doc]**

Fetched through Apple's documentation JSON API; the HTML pages are a JS-rendered shell that returns only a title to a plain fetch.

`rateLimited`, quoted exactly — the sentence the whole issue rests on:

> An error that indicates your session has been rate limited.
>
> This error will only happen if your app is running in the background and exceeds the system defined rate limit.

— <https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/ratelimited(_:)>

`prewarm(promptPrefix:)`:

> Calling this method doesn't guarantee that the system loads your assets immediately, particularly if your app is running in the background or the system is under load.

— <https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)>

The framework landing page, `SystemLanguageModel`, `LanguageModelSession` and *Generating content and performing tasks with Foundation Models* were each scanned in full for `extension`, `entitlement`, `background`, `daemon`, `process` and `memory`. **None of them mentions app extensions, and none mentions an entitlement.** No entitlement key exists anywhere in the framework's SDK directory, which holds only a `.tbd` stub and the Swift module.

A forum thread that surfaced in search as possibly relevant ("Foundation Models unavailable for…", <https://developer.apple.com/forums/thread/805378>) turns out to concern device *language* restrictions and Siri language settings, not extensions. No documented prohibition was found anywhere.

**So Apple's wording is silent on the question, and that silence is exactly Q2.** "Your app is running in the background" does not say which process it means, and a keyboard extension has no `UIApplication` to have a state at all.

---

## Q1b, Q2, Q3, Q4 — not measured

Not measurable on this machine, for the reason recorded in the plan before any of this began: `docs/agents/simulator.md` §7 establishes by experiment that the Dictus keyboard cannot be enabled in any simulator. No app-target substitute was run, because an app-target result answers a different question than the one asked.

The instrument for all four is `DictusKeyboard/AppleFMExtensionProbe.swift`; the procedure is below.

### The design flaw caught before the probe shipped

Worth recording, because it would have produced a confident wrong answer.

The obvious probe is one call from the extension: if it succeeds while the app is refused, the extension counts as foreground. **That reasoning is broken.** #315 established the budget is per process and only a fresh process resets it — and the extension *is* a different process. So a single success has a second explanation: the extension is merely a fresh process whose background budget has never been spent. Under that explanation the extension would deplete its own budget with use and start refusing exactly as the app does. The problem would be relocated, not solved, and an architecture built on that single green result would ship straight into it.

The probe therefore fires **ten back-to-back generations inside one extension process**. The relocation story predicts refusals appearing partway through; the foreground story predicts none.

The asymmetry is deliberate, and is stated so the result is not over-read: **a surviving burst is strong evidence** (a backgrounded app is refused under far lighter load than ten consecutive calls), while **a failing burst is weaker** — it could be an artefact of the density — and would need the slower once-a-minute protocol before concluding "no".

---

## The device procedure — what the maintainer runs

About thirty minutes, most of it ordinary use. Each step names the question it answers.

**Prerequisites:** a build of this branch on the iPhone; polish enabled; French; Parakeet; the keyboard enabled with Full Access.

1. **Use Dictus normally for about twenty-five minutes**, polish on, one ordinary dictation every one to two minutes. This is the recipe measured twice on 2026-08-13. *Nothing to observe yet — this drives DictusApp into the refusing state.*

2. **Confirm the app is actually refusing. Do not skip this.** Settings → long-press the Version row for 3 seconds → Polish debug. Recent events must show a run of `engineFailed` / `rateLimited`, the latest ones returning in single-digit milliseconds. If they do not, keep dictating and check again. *This is what makes step 4 mean anything: a probe that runs while the app is quietly succeeding proves nothing.*

3. **Arm the probe on that same screen.** Section "#357 spike" → turn on "Arm keyboard Apple FM probe". *From here on, do not force-quit the app and do not restart the phone — a fresh process resets the very state being measured.*

4. **Open any app with a text field, bring up the Dictus keyboard, and leave it on screen for about ninety seconds.** Do not dictate. The probe fires on keyboard appearance and runs ten generations back to back. *Answers Q1b (does Apple FM work at all inside the extension), Q2 (is the extension refused like the app, or served), and Q3 (memory cost).*
   - If the keyboard visibly resets or disappears during this, say so — that is a jetsam kill, and it is itself the Q3 answer.

5. **Optional, and the only step for Q4.** Re-arm the probe (step 3), bring the keyboard up again, and this time **switch to another app after about five seconds**, while a generation is still running. *Answers Q4: what happens to an in-flight call when the extension is torn down.*

6. **Export and send.** Settings → Debug log → Export, for the persistent log. Also export the Polish debug JSON from step 2's screen — that is what pins the app's refusing state to the same window.

### What the log will say

Every line carries `component=AppleFMExtensionProbe` and one run token, so `grep AppleFMExtensionProbe` pulls a whole run out:

```
diagnosticProbe AppleFMExtensionProbe <token> started   availability=… memBeforeMB=… burst=10
diagnosticProbe AppleFMExtensionProbe <token> call      n=1/10 success outputChars=… engineMs=… memMB=… memPeakMB=…
…
diagnosticProbe AppleFMExtensionProbe <token> finished  memBeforeMB=… memPeakMB=… memAfterMB=…
```

How to read it:

| What the lines show | What it means |
| --- | --- |
| `availability=available`, ten `success` | **Q1b and Q2 both yes.** The extension is served while the app is refused. The outcome that closes #315 by moving the call. |
| `availability=available`, `failed reason=rateLimited` appearing partway through | **Q2 no**, subject to the burst caveat above. The extension is on the same budget. |
| `availability=unavailable:…` | **Q1b no.** Apple FM is not reachable from the extension at runtime, whatever the linker allows. |
| A `started` line with no `call` lines and no `finished` | The process died before completing a generation — a jetsam kill (Q3) or a teardown (Q4), told apart by whether step 5 was running. |
| `memPeakMB` across the burst | **Q3.** Both the delta over `memBeforeMB` and the absolute peak matter; the ceiling is absolute. |

### If nothing is run

Q1b, Q2, Q3 and Q4 stay unanswered, and the decision they gate stays blocked: whether #79 Smart Modes can ship on Apple FM, or whether #351 has to move onto the Dictus Pro critical path. No amount of further reading moves it — Apple's documentation does not contain the answer, which is finding 5 above.

---

## Recommendation

**Run the probe before re-ranking anything.** Concretely:

1. **Do not move #351 onto the Pro critical path yet.** Decision 15 of the #315 grilling suspended decision 6 on this measurement. The cheapest reason to assume "no" — that an extension cannot call Apple FM at all — is now disproved, so the pessimistic branch is no longer the default. One device session settles it either way.
2. **Do not start the move.** Even a clean "yes" on Q2 does not make this a small change, and #357 is explicit that it ends with the answer.
3. **Keep #315's decision 14 shipping regardless.** Honest degradation is worth having whatever Q2 says, and decision 1 already committed to it independently.

If Q2 comes back yes, the follow-up issue has to cost something this spike deliberately did not design: polish would move onto the keyboard's critical path, where a multi-second LLM call sits between the user finishing speaking and the text appearing, in a process iOS tears down aggressively (Q4) and holds to a hard memory ceiling (Q3). That is a real design problem, and a much better one to have than an engine that refuses.

---

## What I am not comfortable asserting

- **That Apple FM inference runs outside the calling process.** #357's body states it — "Apple FM inference does not run in the calling process; the model is hosted by a system daemon" — and it is the premise that makes Q3 look cheap. **I could not confirm it in any Apple documentation.** The framework pages say nothing about the process model. It is plausible, widely assumed, and unverified here. Q3 must be settled by measurement, not by this premise.
- **Anything about Q2's likely answer.** The mechanism is undocumented, and a keyboard extension's relationship to `UIApplication.state` is precisely what is at issue. Guessing here is what this spike exists to avoid.
- **That a clean build guarantees runtime behaviour.** Q1a and Q1b are separated throughout for this reason. The linker permitting a call says nothing about a system service serving it across the extension sandbox.
- **The Q4 half about raw transcription still reaching the document.** That is a property of an architecture that does not exist yet; today the app owns both the call and the insertion. The probe can only establish what happens to an in-flight `respond()`.
- **That ten is the right burst size.** It is reasoned — enough to land inside the refusal regime the app exhibits, short enough that a human will hold a keyboard open — but it is not calibrated against a measured extension refusal threshold, because none exists yet.
