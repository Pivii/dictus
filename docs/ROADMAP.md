# Roadmap — Dictus

The ordered queue. One list, one order, and the first unfinished item is what happens next.

**Scope.** [RELEASE-PLAN.md](RELEASE-PLAN.md) says what a cycle *is* and why. This file says what to *do*, in what order. The tracker holds the detail; this file holds the sequence, because 80 open issues and 19 of them marked `priority:high` is not a sequence.

**How to use it.** Start a session by reading this file and taking the first unfinished item of the active lane. Do not re-derive the order from the tracker: the tracker sorts by how well an issue is written, not by how much it matters. When an item ships, tick it here. Revise the lanes at a version cut, not more often.

Last reviewed: 2026-09-07.

## The three lanes, in order

| Lane | What it is | Runs |
| --- | --- | --- |
| **A** | 1.8.2, the bug cycle | **Cut on 2026-09-07** as 1.8.2 (30) |
| **B** | 2.0.0, the Pro launch | **Now** |
| **C** | The keyboard session | After the `paywallVisible` flip |

They are sequential on purpose. Lane C is the one Pierre most wants to do and the one most likely to swallow the others, so it goes last and it gets a preparation step it can start on today.

## Lane 0 — the one thing that waits on Apple

**#215 — create the three products in App Store Connect.** Not in a lane because it belongs in all of them: nothing in Lane B is testable in sandbox until those products exist and StoreKit can fetch them. It is maintainer work at a desk, roughly an hour, and it has external latency. Do it the next time there is a computer.

## Lane A — 1.8.2, the bug cycle

A **closed list**. When these are done, cut. A fix that becomes ready mid-cycle waits for 2.1; that rule is what keeps a bug cycle from turning into a second campaign, and it is the same rule that closed 1.8.1.

Ordered by what a shipped user actually loses.

**Cut on 2026-09-07 as 1.8.2 (30)**, tag `build/30`, commit `d8e7494`. Verified before the bump: all eleven lane issues closed, the `1.8.2 — bug cycle` milestone empty, `develop` clean and in sync, 1666 tests green, `swiftlint --strict` at 0 violations across 255 files. Remaining steps are Xcode archive, upload, and `scripts/promote-to-appstore.sh 30` when it ships.

**One gap ships knowingly with it.** #417's fix removes `installTap NSException`, and #513 makes the keyboard refuse a mic tap during a *call*. Dictation while **Siri** holds the input still fails, now at `engine.start` with `-10868` (`FormatNotSupported`), and still costs a full app foreground before it says so. CallKit cannot see Siri, so the predicate has to be the interruption state itself. Not filed: it is a known limit, not a regression, and it waits for a user to hit it.

**#483 shipped on 2026-09-07** in PR #513, closing #459 with it. CallKit replaces the route heuristic: a call is detected on the earpiece, on speaker and on a bluetooth headset, and the keyboard now declines the mic tap in place instead of launching `DictusApp` to fail there. `CXCallObserver` was measured readable from the extension — the probe the brief made a blocking step — at `deltaKB=192` against a ~50 MB budget. `CallRoutePolicy` is deleted rather than kept as a fallback, because the fallback path was exactly where the Siri false positive lived.

The device test of that PR surfaced **#515**, which shipped in the same PR: the first activation after any interruption had to bring the input route back from `none`, and that attempt heard nothing. It is `replaceEngine()` that repairs the start, not the wait that precedes it — a capture with `waitedMs=1163 budgetMs=1000 route=none` succeeded, so raising the wait buys nothing. Recorded in the constant's doc comment, not only on the issue.


**#417 shipped on 2026-09-07** in PR #516, device-validated: `installTap NSException` is gone by construction, 0 occurrences across four mic taps made under an active interruption. What the fix does not reach is now written on the issue — while Siri holds the input, the failure moved to `engine.start` with `-10868` (`FormatNotSupported`), 8 times, and from the keyboard it still costs a full app foreground before failing. #513 answers that for a **call**; Siri is not a call and CallKit will never report it, so the Siri case needs the interruption state itself as its predicate. Not yet an issue.

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

Reordered on 2026-09-07: #518 did not exist that morning. It came out of a debug export while diagnosing #490, and it outranked everything below it. **It shipped the same evening** in PR #519, so the list now starts at #490.

**#518 shipped on 2026-09-07** in PR #519, merged as `2921618` and device-validated: 12 Normal polishes of ordinary French, zero `unsupportedLanguageOrLocale`. The fix is one deletion — the transcript no longer sits under an `Input:` label. The mechanism is narrower than the issue claimed: it is not short French inside English framing in general, since the imperative stays in English in every passing variant. It is **an English label immediately preceding the transcript**. Translating it to `Texte :` clears it; moving it onto the same line does not.

**#474 has its answer and it is a win.** `<TRANSCRIPT>` tagging clears the refusal as completely as the landed variant, 0/10, so the worry that tags would add the very scaffolding that triggers it is falsified. It was deliberately not landed under #518 — tagging the user turn without tagging the eleven system prompts is the half-tagged state #474's own first criterion forbids. #474 is now the generalisation work, with #518's two fixtures as its bench.

**Criterion 4 was decided rather than built: a Normal-polish engine failure says nothing to the user, and #313's contract is explicitly declined for this path.** The words are never lost — the deterministic floor is inserted, correctly punctuated — and a notice would also fire on the background `rateLimited` case, which is architectural and frequent from the keyboard. The log line carrying `detected` and `mix` is what replaces it.

**Its device test opened a Normal-polish quality question, and Pierre settled the sequencing on 2026-09-07.** Two issues came out of the session: **#520**, where Apple FM deletes what the deterministic pre-pass placed — six line-break markers in, zero out, plus one dropped `!` — measured **not** to be caused by #518's reframing (1/12 preserved under the old framing against 3/12 under the new); and **#521**, Normal polish ending every dictation with a period, fragments included.

His verdict was that Normal polish is not at the level and wants work before the Smart Modes ship. **What that promoted, and what it did not:**

- **#437 moves into this lane** (item 4). It is the one whose absence blocks something else — #523 needs its paired Typeless fixtures to answer whether it is a distinct mode or a rendering of `List`.
- **#520 and #521 stay out of the lane, deliberately.** Agents were already running on every other Lane B item when the question came up, and reordering under them buys nothing. They are the first fishing ground after the flip.
- **#439** stays out for the same reason, and because it is a calibration campaign rather than a fix.

**#523 is new and it is a launch item**: a Smart Mode for the long vocal, which structures a ramble into paragraphs and is allowed to come out shorter than what was said. Pierre wants it before the Smart Modes launch and ranks it above `List` for his own use. It carries one question that has to be answered before a prompt is written — whether it is a fourth mode at all, or `List` rendered as prose with a title — and #393's paired-output bar is how that gets settled. `List` is not reopened by it.

1. **#490** — Traduction refuses on the dictated language. Not a broken mode: 11 successes against 1 failure on device, and reproduced deliberately with a Czech sentence. Apple's check is a language classifier on the user turn, so a pre-flight *before* the dictation cannot exist — that acceptance criterion is dropped. What is left is a specific sentence and one that survives an immediate re-dictation. Cheaper now that #518's reframing has landed.
2. **#414** — a Smart Mode prompt's worked example was copied verbatim into the user's output. Mostly shipped already: `PolishGrounding` was added by this issue and the Notes examples are neutralised. Threshold decided on 2026-09-07 at **0.15**, with false rejections counted on the 48 outputs a user can actually see accepted rather than all 57 — the other 9 are already refused upstream by the language check. `Z1-sophie-reoccurrence` ships knowingly open; closing it costs 1 false rejection in 48 at 0.25.
3. **#80** — Vocabulary. The third feature, and the largest piece in this lane. Its body is wrong on the mechanism: WhisperKit 0.16.0 has no public `initialPrompt`, and Parakeet — the default engine at ≥6 GB — has a purpose-built boosting API whose CTC judge is **English-only** (`FluidInference/parakeet-ctc-110m-coreml`, `language: ["en"]`) while our TDT speaks 25. The only stage that treats French and English alike is a post-transcription text replacement. Grill it before planning: #512 declares itself a hard dependency of #80 and assumes six deliverables its body never mentions.
4. **#439** — the Natural contract broken three ways: rule 8 never fires, the register is rewritten, dictated content is deleted. In the lane because **#437 cannot start without it**: the two edit the same prompt and #437's own sequencing says #439 lands and is measured first, so the fidelity baseline underneath is the one that ships. One calibration round, six fixtures, bars already declared on the issue.
5. **#437** — lift the `<<NL>>` ban at discourse boundaries so long dictations get paragraphs. **Not blocked on anything, and it ships the fix** — rescoped on 2026-09-07 from a benchmark that stopped at a recommendation. Its diagnostic half was done on 2026-08-27: six paired Dictus/Typeless fixtures, baseline measured at 0 line breaks in 6 of 6, contract decided (*may add whitespace, may never remove words or change their grammar*), bars declared per fixture. The machinery is not missing either — the `<<NL>>` round-trip works and every prompt bans the model from emitting one. **What is left is one clause, the harness round, and merging it if it holds.** A candidate that fails is a legitimate outcome, recorded with its numbers. Its `Current status` section claimed it was still waiting for data until 2026-09-07; it was eight days stale.
6. **#523** — a Smart Mode for the long vocal: paragraphs, and an output allowed to be shorter than the speech. The transformative counterpart of #437, and the two must not be built in the same round. The first Dictus contract that may drop a dictated clause, so it needs its own never-drop classes and its own guardrail band (`PolishGuardrail` refuses below a 0.5 length ratio today, which a real condensation blows straight through). First acceptance step is the paired-output comparison against `List`.
7. **#494** — offer Pro after the first successful dictation in onboarding.
8. **#215** — the ASC catalogue (see Lane 0; start it early, finish it here).
9. **#279** — flip `PremiumFlags.paywallVisible`, in the same PR as the first reachable Pro feature. Walk all four entry points; the flag is compile-time, so a site that was never wired to it stays silently hidden.

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
