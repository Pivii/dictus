# Release plan — Dictus

What ships next, and why. Complements [VERSIONING.md](VERSIONING.md), which says *how* to number a release; this file says *what* the current and next cycles are.

**Scope.** One page. It holds decisions that no issue owns and that the code cannot show. It does not list work in order — that is [ROADMAP.md](ROADMAP.md), which holds the ordered queue and points back here for the reasoning. When a decision here is superseded, edit the line rather than appending, so the file never becomes a log. Git history keeps the record.

Last reviewed: 2026-09-06.

## Where things stand

| | |
| --- | --- |
| App Store | **1.8.1 (build 29)**, released 2026-09-06, phased rollout day 1 of 7 |
| Next cycle | **1.8.2**, a PATCH: the bug backlog. Its App Store version record already exists, staged with corrected copy |
| Then | **2.0.0**, the Dictus Pro launch |
| `PremiumFlags.paywallVisible` | `false` |

Build 28 was cut and archived, then abandoned: it still advertised Dictus Pro in the keyboard (#460). 1.8.1 shipped as build 29. Build numbers never repeat, so 28 is simply spent.

1.8.1 went out with a **phased rollout**, which 1.8.0 did not have. The reason generalises: 1.8.1 changes model preparation, the one subsystem that can lock a user out of the whole app (#428), and phasing buys a pause button for exactly that. It costs nobody the fix, because it governs only *automatic* updates — a manual update from the product page lands immediately. Pause with `asc versions phased-release update --version-id <id> --state PAUSE`; finish early with `--state COMPLETE`.

## The two surfaces are not the same audience

This is the rule the rest of the plan follows from.

**TestFlight is where the product is built.** Its ~190 testers signed up to watch that happen. Unfinished Pro surfaces, greyed features and rough edges are the point, not a leak. StoreKit runs in sandbox there, so the paywall and the purchase flow can be exercised end to end, for real, before Apple ever sees them.

**The App Store is what has been announced.** It shows only what Dictus is prepared to claim publicly. The product page currently sells an app that is free, open source, and asks for no account. Until monetisation is announced deliberately, nothing on that surface may say otherwise. A user who long-presses the mic and reads "Dictus Pro" learns of a business model before its author has stated it, and the App Store page carries the reviews that mistake would cost.

`PremiumFlags.paywallVisible` is the valve between the two. One constant decides whether the product looks free or freemium, and it is the gate every Pro entry point must consult. #460 exists because the Smart Mode fan does not.

## 1.8.1 — the Turbo cycle (submitted, awaiting review)

Reason to ship at all: 1.8.0 carries a model-preparation bug that a TestFlight tester hit and reported, and that the App Store build has too. Turbo aborted its optimisation at 120 s (#406), and the timeout then deleted the downloaded model so Retry re-fetched ~950 MB (#405).

Fixed in the cycle: #405, #406, #408 (Turbo swapped to the 632 MB variant), #422, #426, #427, #428 (a stuck compile can no longer lock the user out of the app), #432, #433. Plus error copy (#313) and backspace cadence (#390, #419).

Blocking: **#460**. Nothing else, and this is now an execution rule rather than a preference.

1.8.0 ships a Turbo preparation bug that a tester hit and that every App Store user has. Every day 1.8.1 waits is a day that bug is live, so the cycle is closed the moment #460 is validated: **cut build 29 first, merge everything else after.** A fix that is ready but unreviewed does not join the cycle — it waits for the cut and ships in 1.8.2. This is what keeps 1.8.1 a one-fix release instead of a second campaign.

In flight at the time of writing and therefore *not* in 1.8.1: #456 (PR #463, open), #449, #438.

Not in it: **#417**, the `Failed to create tap due to format mismatch` failure, which is the second thing that tester reported. Still open, unfixed on every branch.

It stays a PATCH because everything user-visible in it is a fix. Smart Modes and transcription history are merged but sit behind the flag, so no returning user sees anything new.

## 1.8.2 — the bug backlog

The release 1.8.1 deliberately does not carry. It exists because the open-bug count is high enough that holding those fixes until 2.0.0 would mean shipping the Pro launch on top of a year of unfixed reports.

**Its contents are a closed list of nine, ordered in [ROADMAP.md](ROADMAP.md) Lane A**, plus **#488**, the App Store description's claim of four dictation languages — already corrected and staged on the 1.8.2 version record, so it needs no work at cut time.

The rule #488 produced is the part to keep. Description and keywords are version-scoped fields, and a *released* version rejects an edit to them: the API answers `Attribute 'description' cannot be edited at this time`. That is a lock, not a convention. **App Store copy therefore has no release schedule of its own** — it ships with a submission that exists for another reason, or it waits. 1.8.1 shipped a sentence known to be wrong because the mistake was spotted after `review submit`. Read the product page before submitting, not after.

Staged copy also goes stale silently, because nothing re-reads it. The language numbers now in the description (Parakeet v3: 25 European languages; Whisper: ≈99, in published quality tiers) were true on 2026-09-06. Re-check them against `ModelLanguageSupport.swift` at cut time.

The list being closed is the rule, not a preference: a fix that becomes ready mid-cycle joins 2.1, not this one. That is what kept 1.8.1 a one-fix release, and it is the only thing that stops a bug cycle from becoming a second campaign.

Still a PATCH: every line of it is a fix, and `paywallVisible` stays `false` throughout.

**#417** is in the list but not committed to the cycle. It has no identified cause, only a rejected format the pre-flight guards accept. It ships if a repro lands in time, and slips if it does not.

## 2.0.0 — the Pro launch

MAJOR, per VERSIONING.md's own table: *premium launch, breaking UX shift*. Not 1.9.0. The version is chosen once, when 1.8.1 reaches the App Store, and then stays frozen across every TestFlight build of the campaign — 2.0.0 (30), 2.0.0 (31), and so on.

**No App Store release between 1.8.2 and 2.0.0** unless a production bug forces one. The build-out should not be visible to users; the next thing they see after 1.8.2 should be the finished product.

How the campaign runs:

- Pro work stays on `develop`. **No long-lived Pro branch** — `feature/premium` was tried and cost merge pain no solo maintainer should pay twice.
- TestFlight builds go out as the work lands, not once at the end. Testers exercising a half-built paywall in sandbox is the cheapest bug-finding available.
- `paywallVisible` flips to `true` in the PR that ships the first reachable Pro feature, which is also the PR that turns this cycle into a MAJOR.
- A `#if DEBUG` entitlement override lets Smart Modes be tested on device while the flag is down (#460). It must not exist in a Release build.

Its scope was fixed on 2026-09-05 and is the ordered list in [ROADMAP.md](ROADMAP.md) Lane B. The feature count was never open: `ProFeature` declares three cases, the paywall renders a card for each, and only `vocabulary` (#80) is unbuilt. **#450, the onboarding rebuild, was descoped out of the launch the same day** — it was written as a product gate, it is a month of work, and the install base that reaches Pro has already completed onboarding. Its one launch-relevant point is #494.

Open, to settle before the flag flips: whether 2.0.0 or a later number is right if the scope grows, and the founder-window dates in #350, which depend on a release date that does not exist yet.

## Standing rules

- Never cut a TestFlight build while an App Store version of the same marketing version is awaiting review. A rejection ships as the same version plus the next build.
- The archive is pinned by `build/N`, never by a branch tip. `promote-to-appstore.sh N` enforces this; do not work around it.
- The App Store screenshots are 1.7.2's and show neither the polish layer nor the number row. Known, accepted, deliberately deferred. Not a release blocker.
