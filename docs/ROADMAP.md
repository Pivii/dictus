# Roadmap — Dictus

The ordered queue. One list, one order, and the first unfinished item is what happens next.

**Scope.** [RELEASE-PLAN.md](RELEASE-PLAN.md) says what a cycle *is* and why. This file says what to *do*, in what order. The tracker holds the detail; this file holds the sequence, because 80 open issues and 19 of them marked `priority:high` is not a sequence.

**How to use it.** Start a session by reading this file and taking the first unfinished item of the active lane. Do not re-derive the order from the tracker: the tracker sorts by how well an issue is written, not by how much it matters. When an item ships, tick it here. Revise the lanes at a version cut, not more often.

Last reviewed: 2026-09-06.

## The three lanes, in order

| Lane | What it is | Runs |
| --- | --- | --- |
| **A** | 1.8.2, the bug cycle | Now |
| **B** | 2.0.0, the Pro launch | After A is cut |
| **C** | The keyboard session | After the `paywallVisible` flip |

They are sequential on purpose. Lane C is the one Pierre most wants to do and the one most likely to swallow the others, so it goes last and it gets a preparation step it can start on today.

## Lane 0 — the one thing that waits on Apple

**#215 — create the three products in App Store Connect.** Not in a lane because it belongs in all of them: nothing in Lane B is testable in sandbox until those products exist and StoreKit can fetch them. It is maintainer work at a desk, roughly an hour, and it has external latency. Do it the next time there is a computer.

## Lane A — 1.8.2, the bug cycle

A **closed list**. When these are done, cut. A fix that becomes ready mid-cycle waits for 2.1; that rule is what keeps a bug cycle from turning into a second campaign, and it is the same rule that closed 1.8.1.

Ordered by what a shipped user actually loses.

1. **#417** — dictation fails outright with `Failed to create tap due to format mismatch`. No longer diagnostic-only. The #483 device captures name the cause: an active interruption, a call **or Siri**, renegotiates the input node between the format read and the tap install, and it is `installTap` that throws, not `engine.start` — which is the distinction the issue said everything turned on, and it means the scoped fix is sufficient. `ready-for-agent` on 2026-09-06.
2. **#483** — a phone call is not detected. #459 shipped the bluetooth half (PR #476) and is now blocked on this one: a native call routes through `MicrophoneBuiltIn`, never `telephony`, and Siri is indistinguishable from a call at the session layer. `CXCallObserver` is the only thing that answers it, and it also lets the keyboard refuse the mic tap without launching the app. PR #513 open, under device test. It does **not** subsume #417 — Siri throws the same exception and is not a call. **#459 closes by hand when #513 merges.**

**Both are in flight, and nothing else is queued behind them. When #417 and #513 land, cut** — `scripts/cut-testflight.sh 1.8.2`.

**Closed out of this lane on 2026-09-06.** #492 and #438 shipped. #488, the App Store description's four-languages claim, is applied. #293 passed its device check: `audioHapticsAllowance allowed=true` on every active-session context, which is the line PR #367 added precisely so this could stop being a correlation. #362 and #370 are fixed and shipped in 1.8.0 (27); they were closed with the reporter contacted and unanswered, because their last criterion needs an iPhone 11 nobody here owns and that tier is not Dictus's target. They reopen on his word.

**Closed `not_planned` on 2026-09-06: #319 and #409.** Every capture of Whisper's subtitle artifacts was made on degraded audio — a room with a baby crying, and a Mandarin recording the maintainer describes as bad quality — which is the documented condition for them. Nothing shows the model mishandling a clean recording, no user has reported it, and China is not a market Dictus targets today. Closed rather than parked in `Someday`, deliberately: an issue nobody will touch until a user complains still costs attention at every triage pass. Both reopen on a user report or a clean-audio capture. Do not re-propose demoting Medium without one.

## Lane B — 2.0.0, the Pro launch

### The feature count is already decided, in code

`DictusCore/Sources/DictusCore/Subscription/ProFeature.swift` declares three cases and the paywall renders a card for each. Two are built:

| Feature | State |
| --- | --- |
| `smartMode` | Built — #79 blocks B and C merged and device-validated |
| `history` | Built — `History/TranscriptionHistoryStore.swift`, `HistoryView.swift`, gated by `HistoryAvailability` |
| `vocabulary` | **Missing.** The paywall promises "Teach Dictus your technical terms" and nothing delivers it. This is #80. |

So the launch scope is not a question of how many features to build. It is one hole to fill, plus making the two existing ones keep their promise.

### The order

1. **#490** — Translate refuses on device, Apple FM answers `unsupportedLanguageOrLocale` in 8 languages. A paid mode that does not run.
2. **#414** — a Smart Mode prompt's worked example was copied verbatim into the user's output.
3. **#80** — Vocabulary. The third feature, and the largest piece in this lane.
4. **#494** — offer Pro after the first successful dictation in onboarding.
5. **#215** — the ASC catalogue (see Lane 0; start it early, finish it here).
6. **#279** — flip `PremiumFlags.paywallVisible`, in the same PR as the first reachable Pro feature. Walk all four entry points; the flag is compile-time, so a site that was never wired to it stays silently hidden.

### What was deliberately cut from this lane

**#450, onboarding v2.** It asked for two complete prototypes and a PiP spike, about a month of work, and it was written as a launch gate. It is not one: the App Store install base has already completed onboarding and will never see those screens, and it reaches Pro through the entry points #279 unhides. Its one launch-relevant point is now #494. The rest moved to 2.1 on 2026-09-05.

**#216, the Pro hub.** Deferred on 2026-08-24: the hub's content *is* the feature list, so building it before the features exist means building it three times.

## Lane C — the keyboard session

After the flip. **Its preparation step is done: the ideas are written down.** On 2026-09-05 Pierre listed what he wants improved, and it became eight new issues plus six existing ones, gathered in the `Keyboard session` milestone — 14 in total, reachable with `gh issue list --milestone "Keyboard session"`.

Three themes came out of it, and they are not equal in size:

1. **Typing quality** — #114 (the n-gram thinness underneath everything), #498 (a learned word never reaches autocorrect), #499 (glued words from missed spacebar taps), #500 (a register of corrections that do not fit their sentence), #501 (`a` vs `à`). #114 is the root: #499 and #500 both depend on the same data being better, so sequence it first or accept that the others are guesses.
2. **Visual coherence** — #502, the suggestion bar pills. It is the step 2 that #224 wrote into its own acceptance criteria and never delivered.
3. **Page and mode behaviour** — #503, #504, #505. Small, independent, and each one a place where Dictus departs from Apple's keyboard in a way users feel as a bug.

Two things the lane must not re-litigate: **#138 is `wontfix`** — a keyboard extension cannot extend a key's hit area, it was measured, so the spacebar's touch target is not a lever. And **changing `KeyboardAreaMode` destroys SwiftUI gesture identity**, which #505 walks straight into.

## Someday

A GitHub milestone holding 29 issues, all `priority:low`. Not refused, not scheduled, and deliberately out of the default view — the open count went from 80 to 36 on 2026-09-05 by moving them there, and that number is the point.

Review it at each version cut. Anything that has become urgent leaves; anything that has been there through three cuts is a `wontfix` waiting to be admitted.

## What this file is not

- Not a log. Supersede a line by editing it. Git history keeps the record.
- Not a list of every open issue. Issues outside the three lanes and outside Someday are the fishing ground for 2.1, and they stay in the tracker.
- Not the release mechanics. Numbering is [VERSIONING.md](VERSIONING.md); what a cycle contains and why is [RELEASE-PLAN.md](RELEASE-PLAN.md).
