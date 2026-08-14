# Can the keyboard extension call Apple Foundation Models? — spike findings

**Issue:** [#357](https://github.com/getdictus/dictus-ios/issues/357)
**Scope:** measurement only. No feature work, no move of the polish call, no change to what a normal dictation does.
**Date:** 2026-08-13 (desk work), 2026-08-14 (device run).

**The plan below was committed before any measurement was taken** (commit `de3b2fb`), so the findings can be checked against criteria that were not written to fit them. Follows the convention set by [`287-user-dictionary-learning.md`](287-user-dictionary-learning.md).

## The answer, in four lines

| | Question | Answer |
| --- | --- | --- |
| **Q1a** | Is `FoundationModels` usable from an app extension, statically? | **Yes.** The extension target compiles and links it, under a compiler setting proven to reject extension-unsafe API. Apple documents no prohibition. |
| **Q1b** | Does it work at runtime inside the extension? | **Yes.** `availability=available` read from inside the extension process, and ten generations returned real text. |
| **Q2** | Does a keyboard extension count as foreground for the limiter? | **Yes.** Ten consecutive successes from the extension, fired ten seconds after the app's last instant `rateLimited` refusal, same device, same minute. |
| **Q3** | What does the call cost in the extension's budget? | **7 MB peak delta** (15 → 22 MB), no degradation across ten calls. **Measured on an idle keyboard — see the caveat, it is the top open risk.** |
| **Q4** | Teardown mid-generation? | **Still not measured.** The optional step was not run. |

**The keyboard extension is served while the app is refused.** That is the finding, and it is the one #315 was waiting on. Moving the polish call there does not work around Apple's rate limit — it stops meeting it. Follow-up work is #361.

Two things fell out that were not the question: there is **no latency penalty**, and Apple FM inference **does not run in the calling process** — a claim #357's own body made without evidence, which the 7 MB delta now supports.

Jump to [Findings](#findings), [the measured results](#q1b-q2-q3--measured-on-device), or [what remains unasserted](#what-i-am-still-not-comfortable-asserting).

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
| **[device]** | Measured on the maintainer's iPhone. Nothing carried this label until he ran the probe on 2026-08-14; the results that now do are in [Q1b, Q2, Q3](#q1b-q2-q3--measured-on-device). |
| **[derived]** | Inference on top of a labelled fact. The input is sourced; the output is not. |

---

## The constraint that shapes this plan

`docs/agents/simulator.md` §7 establishes **by experiment, not by assumption**, that the Dictus keyboard cannot be enabled in any iOS simulator. Four methods were tried and all four failed; the extension registers with the plug-in system but never appears in `UITextInputMode.activeInputModes`.

Therefore:

- **Q2 and Q3 are not measurable by an agent on this machine.** They require the extension's process to actually run.
- **An app-target measurement cannot stand in for either.** The entire question is whether the *extension's process* is treated differently from the app's. Running the same code in DictusApp answers nothing, and reporting it as an extension result would be worse than reporting nothing.
- Q4 likewise requires a live extension.

So this spike splits into **what is answerable now by build and by SDK** (Q1's static half), and **a probe plus a written procedure** for everything else. The probe is the deliverable for Q2/Q3/Q4; the answers arrive when the maintainer runs it.

*(He ran it on 2026-08-14. Q1b, Q2 and Q3 are answered below; Q4 was skipped and is still open.)*

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
## Q1b, Q2, Q3 — measured on device

Run by the maintainer on 2026-08-14. Build 1.8.0 (26), `rev a3662ef@HEAD`, iPhone16,2, iOS 26.6, Parakeet `parakeet-tdt-0.6b-v3`, polish on, French. **[device]**

### The app was refusing, and that is pinned independently

The confound this whole experiment had to avoid was a probe that runs while the app is quietly succeeding. It did not happen. The app's own log, in the four minutes before the probe:

```text
07:28:18  <APP>  polishEngineFailed  other:NSError  engineMs=905   <-- slow: the arming failure
07:28:27  <APP>  polishEngineFailed  rateLimited    engineMs=10
07:28:45  <APP>  polishEngineFailed  rateLimited    engineMs=9
07:28:52  <APP>  polishEngineFailed  rateLimited    engineMs=10
```

That is the exact latch signature #315 documented four times: one slow failure that runs the model and then fails, followed by instant refusals. The polish export from the same session agrees — `success: 11, engineFailed: 4`, reasons `{other:NSError: 1, rateLimited: 3}`, every dictation at `appState=2` (background).

**Ten seconds after the app's last instant refusal**, the extension ran.

### The burst

```text
07:29:02  <KBD>  AppleFMExtensionProbe  started  availability=available memBeforeMB=15 inputChars=462 burst=10
07:29:06  <KBD>  n=1/10   success  outputChars=471  engineMs=4414  memMB=19  memPeakMB=22
07:29:11  <KBD>  n=2/10   success  outputChars=468  engineMs=4600  memMB=19  memPeakMB=22
07:29:16  <KBD>  n=3/10   success  outputChars=463  engineMs=5066  memMB=19  memPeakMB=22
07:29:21  <KBD>  n=4/10   success  outputChars=471  engineMs=4948  memMB=19  memPeakMB=22
07:29:26  <KBD>  n=5/10   success  outputChars=471  engineMs=4890  memMB=19  memPeakMB=22
07:29:31  <KBD>  n=6/10   success  outputChars=464  engineMs=4892  memMB=19  memPeakMB=22
07:29:36  <KBD>  n=7/10   success  outputChars=472  engineMs=4880  memMB=19  memPeakMB=22
07:29:41  <KBD>  n=8/10   success  outputChars=472  engineMs=4890  memMB=19  memPeakMB=22
07:29:46  <KBD>  n=9/10   success  outputChars=470  engineMs=4914  memMB=19  memPeakMB=22
07:29:50  <KBD>  n=10/10  success  outputChars=470  engineMs=4825  memMB=19  memPeakMB=22
07:29:50  <KBD>  AppleFMExtensionProbe  finished  memBeforeMB=15 memPeakMB=22 memAfterMB=19
```

### Scored against the criteria written before the run

The criteria in [Falsifiable criteria](#falsifiable-criteria-written-before-measuring) are unchanged from commit `de3b2fb`. Scoring against them, verbatim:

| | Criterion as written | Result |
| --- | --- | --- |
| **Q1b YES** | `SystemLanguageModel.default.availability` reports `.available` inside the extension, **and** a `respond()` returns generated text | **Met.** `availability=available`, and ten responses of 463–472 characters. |
| **Q2 YES** | While DictusApp is **demonstrably** in the refusing state, a burst of ten generations from the extension succeeds with no `rateLimited` | **Met.** Ten of ten, zero refusals, with the app's refusal pinned in the same log window. |
| **Q2 INCONCLUSIVE** | The app is not actually refusing when the probe runs | **Excluded**, by the four refusals at 07:28:18–07:28:52 and the export. |
| **Q3 ROOM** | Peak stays clearly below the ceiling with the keyboard's footprint loaded, no memory warning, no process death | **Met at 15 MB baseline only.** 22 MB peak, all ten calls completed, no kill. **The "with the keyboard's footprint already loaded" half was not satisfied — see the caveat.** |
| **Q4** | Start line with no completion line means the process died in flight | **Not run.** |

### Q2 — the answer, and how strong it is

**The extension is served while the app is refused.** Same device, same model, ten seconds apart, opposite outcomes. The only variable is which process issued the call.

This is the result #315 was waiting on, and it makes the mechanism plain: Apple's "your app is running in the background" is applied to **the process that makes the call**, and a keyboard extension holding the screen is not that.

**How strong: strong, not airtight.** Two things support it and one bounds it.

- The app latches after roughly a dozen calls in a dense session; the extension took ten back-to-back without a single refusal or any sign of degradation — call 10 was as fast as call 1. Under the "fresh process, unspent budget" alternative the burst should have started refusing partway through, as the app does. It did not.
- **The second argument, which survives even if the first is soft.** Suppose the extension does have its own background budget. It would still not produce the app's failure mode, because iOS tears down and recreates keyboard extensions constantly during normal use — this project has measured roughly nine controller instances across a dictation. A budget that resets that often never accumulates. What makes the limit a *product* problem in DictusApp is precisely that the app process persists for a whole working session and its budget never refills; that condition does not exist in the extension.
- **The bound.** Ten is not twenty. A 20-call burst in one extension process would settle it outright, and it is cheap now that the instrument exists. Recorded as owed work in #361.

### Q3 — 7 MB, and the caveat that matters more than the number

Peak delta **7 MB** (15 → 22), settling at 19. Flat across all ten calls: no growth, no leak, no memory warning, no jetsam kill.

**This also settles something #357 asserted without evidence.** The issue body claimed "Apple FM inference does not run in the calling process; the model is hosted by a system daemon", and this report declined to assert it because no Apple documentation says so. A 7 MB peak for ten generations of a multi-billion-parameter model is only consistent with the weights living somewhere else. The claim was unsupported when it was made; the measurement happens to confirm it. It is now **[device]**-backed rather than assumed.

**Now the caveat, and it is the top open risk on #361.**

`memBefore` was **15 MB — an idle keyboard**. The probe fires on keyboard appearance, with no dictation in progress, no recording overlay, no waveform, no transcription handoff. During a real dictation the extension carries its full working set, which this project's own notes put near **60 MB, against a ceiling in the same region**.

**7 MB of headroom at 15 MB says nothing about 7 MB of headroom at 55 MB.** The measurement was taken at the wrong moment for the decision it will be used to justify. It is not wrong, it is narrow, and reading it as "the call is cheap, ship it" would be the mistake this report exists to prevent. Re-measuring at the instant the call would actually happen is the first thing #361 has to do.

### Latency — no penalty, and the figure is pessimistic

4414–5066 ms on 462 characters, tight distribution. Against the app on comparable input in the same export: 485 characters in 4231 ms, 622 characters in 4501 ms. **The extension is in the same band as the app.**

And it is the pessimistic figure. The extension does not prewarm, and the engine builds a fresh session for every call. The app's numbers benefit from a `prewarm()` at recording start — though Apple documents that prewarm "does not guarantee that the system loads your assets immediately, particularly if your app is running in the background", so the app may not have been getting much from it either. From the extension, on screen, prewarm would actually do something. Whatever the truth there, moving the call does not cost latency.

### Q4 — still open

The optional teardown step was not run. Nothing in this spike says what happens to an in-flight `respond()` when the extension is torn down, and the probe's start/completion pairing is still the instrument for it.

This matters more after the move than before it: today the app owns the call and survives the keyboard going away. #361 makes the raw transcription durable before any generation starts, precisely so the worst case stays "raw text inserted" rather than "nothing inserted" — and that design needs Q4's answer to be validated rather than assumed.

---

## Should the probe stay on `develop`? — yes, argued

Diagnostic code landing on `develop` deserves a reason, so here it is.

**Keep it.** #361 needs exactly two more measurements, and this probe is the instrument for both:

1. **Memory at a realistic working set** — the caveat above, and the risk most likely to kill the whole approach.
2. **A 20-call burst**, to convert Q2 from strong to settled.

Deleting the probe now means rewriting it in a fortnight, rediscovering the same design constraints — the burst, the flush-per-line, the arming channel that survives without a relaunch — and re-reviewing it. That is waste.

The safety argument is the same one it shipped with, now with a device run behind it:

- **Inert by default.** Armed by an App Group bool defaulting to false. Disarmed, the cost is one `Bool` read per keyboard appearance; nothing is allocated on the dictation path.
- **One-shot**, consumed before the run.
- **Not user-reachable.** The only arming surface is a toggle on a debug screen reached by a three-second long-press on the Version row in Settings.
- **Observed harmless.** The device run exercised it end to end: ten Apple FM calls inside the extension, peak 22 MB, no kill, no memory warning, no effect on the keyboard.

The one honest cost: it is a live code path in a shipping binary, and the `SharedKeys` entry outlives it. Both are marked "delete with the spike" in the source, and the pbxproj entries use issue-tied IDs (`AA357001` / `AA357002`) so removal is mechanical.

**Delete it when #361's two measurements are taken**, not before.

### How to re-run it

The procedure that produced the results above, kept because #361 needs it twice more.

1. **Drive the app into the refusing state:** polish on, one ordinary dictation every one to two minutes, for roughly twenty-five minutes.
2. **Confirm it is actually refusing.** Settings → long-press the Version row 3 s → Polish debug. You need a run of `engineFailed` / `rateLimited` with the latest returning in single-digit milliseconds. **Skipping this is what makes a result inconclusive.**
3. **Arm the probe** on that screen, section "#357 spike". From here on, do not force-quit the app and do not restart the phone — a fresh process resets the state being measured.
4. **Bring the Dictus keyboard up in any text field and leave it up** for about ninety seconds. The probe fires on appearance.
5. **Export** the persistent log (Settings → Debug log → Export) and the Polish debug JSON, which is what pins the app's state to the same window.

For #361's two outstanding measurements, the changes are small and both are one-line edits to `AppleFMExtensionProbe.swift`:

- **Memory at a realistic working set** — the call site has to move from `KeyboardRootView.onAppear` to the moment a dictation's text comes back, so the extension is carrying its real footprint rather than an idle 15 MB. This is the measurement that could still reverse the decision.
- **A 20-call burst** — raise `burstSize` from 10 to 20.

---

## Recommendation

**The direction is settled: move the polish call into the keyboard extension.** That is #361, and it should be treated as a Dictus Pro prerequisite rather than an optimisation — #315 decision 3 holds paid features to a higher reliability bar than free polish, and this is the only measured path to clearing it.

1. **Do not move #351 or #268 onto the Pro critical path.** Decision 15 of the #315 grilling suspended decision 6 on this measurement; the measurement came back yes. Apple FM is viable for #79 Smart Modes, from the extension.
2. **Re-measure memory before committing to #361.** The 7 MB figure was taken on a 15 MB idle keyboard, and the real moment is around 55 MB. This is the one result that could still reverse the decision.
3. **Take Q4 early in #361**, not late. The durability design depends on it.
4. **Keep #315's decision 14 shipping regardless.** Honest degradation stays worth having: it is the fallback while #361 is built, it covers `guardrailViolation` and the other non-`rateLimited` reasons which the move does not address, and decision 1 committed to it independently.

---

## What I am still not comfortable asserting

- **That Q3 generalises to a real dictation.** Stated above and repeated here because it is the claim most likely to be quoted out of context. 7 MB at a 15 MB baseline is not 7 MB at a 55 MB baseline, and only a re-measurement at the real moment settles it.
- **That Q2 is airtight.** Ten calls against an app-side latch threshold of roughly a dozen is strong, and the teardown-frequency argument backs it independently, but a 20-call burst is what would close it. Recorded as owed.
- **Anything about Q4.** Not measured, not inferred.
- **That the latency finding survives the architecture change.** The probe measured a generation in isolation. In #361 the call sits between the transcription arriving and the text being inserted, with an App Group round trip and a Darwin notification around it. The generation will cost what it costs here; the end-to-end wait is a different number that nobody has measured.
- **That prewarm will help from the extension.** Apple's wording makes it plausible and the app's own use of it may have been doing nothing, but "would actually do something" is an inference from documentation, not a measurement.
