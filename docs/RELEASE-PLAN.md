# Release plan — Dictus

What ships next, and why. Complements [VERSIONING.md](VERSIONING.md), which says *how* to number a release; this file says *what* the current and next cycles are.

**Scope.** One page. It holds decisions that no issue owns and that the code cannot show. It does not list work — that is what the tracker is for. When a decision here is superseded, edit the line rather than appending, so the file never becomes a log. Git history keeps the record.

Last reviewed: 2026-09-01.

## Where things stand

| | |
| --- | --- |
| App Store | **1.8.0 (build 27)**, live since 2026-08-28 |
| Next App Store release | **1.8.1**, a PATCH: the Turbo model-preparation campaign |
| Cycle after that | **2.0.0**, the Dictus Pro launch |
| `PremiumFlags.paywallVisible` | `false` |

Build 28 was cut and archived, then abandoned: it still advertised Dictus Pro in the keyboard (#460). 1.8.1 ships as build 29 or later. Build numbers never repeat, so 28 is simply spent.

## The two surfaces are not the same audience

This is the rule the rest of the plan follows from.

**TestFlight is where the product is built.** Its ~190 testers signed up to watch that happen. Unfinished Pro surfaces, greyed features and rough edges are the point, not a leak. StoreKit runs in sandbox there, so the paywall and the purchase flow can be exercised end to end, for real, before Apple ever sees them.

**The App Store is what has been announced.** It shows only what Dictus is prepared to claim publicly. The product page currently sells an app that is free, open source, and asks for no account. Until monetisation is announced deliberately, nothing on that surface may say otherwise. A user who long-presses the mic and reads "Dictus Pro" learns of a business model before its author has stated it, and the App Store page carries the reviews that mistake would cost.

`PremiumFlags.paywallVisible` is the valve between the two. One constant decides whether the product looks free or freemium, and it is the gate every Pro entry point must consult. #460 exists because the Smart Mode fan does not.

## 1.8.1 — the Turbo cycle

Reason to ship at all: 1.8.0 carries a model-preparation bug that a TestFlight tester hit and reported, and that the App Store build has too. Turbo aborted its optimisation at 120 s (#406), and the timeout then deleted the downloaded model so Retry re-fetched ~950 MB (#405).

Fixed in the cycle: #405, #406, #408 (Turbo swapped to the 632 MB variant), #422, #426, #427, #428 (a stuck compile can no longer lock the user out of the app), #432, #433. Plus error copy (#313) and backspace cadence (#390, #419).

Blocking: **#460**. Nothing else.

Not in it: **#417**, the `Failed to create tap due to format mismatch` failure, which is the second thing that tester reported. Still open, unfixed on every branch.

It stays a PATCH because everything user-visible in it is a fix. Smart Modes and transcription history are merged but sit behind the flag, so no returning user sees anything new.

## 2.0.0 — the Pro launch

MAJOR, per VERSIONING.md's own table: *premium launch, breaking UX shift*. Not 1.9.0. The version is chosen once, when 1.8.1 reaches the App Store, and then stays frozen across every TestFlight build of the campaign — 2.0.0 (30), 2.0.0 (31), and so on.

**No App Store release between 1.8.1 and 2.0.0** unless a production bug forces one. 1.8.1 exists to fix Turbo; the next thing users see should be the finished product, not the build-out.

How the campaign runs:

- Pro work stays on `develop`. **No long-lived Pro branch** — `feature/premium` was tried and cost merge pain no solo maintainer should pay twice.
- TestFlight builds go out as the work lands, not once at the end. Testers exercising a half-built paywall in sandbox is the cheapest bug-finding available.
- `paywallVisible` flips to `true` in the PR that ships the first reachable Pro feature, which is also the PR that turns this cycle into a MAJOR.
- A `#if DEBUG` entitlement override lets Smart Modes be tested on device while the flag is down (#460). It must not exist in a Release build.

Open, to settle before the flag flips: whether 2.0.0 or a later number is right if the scope grows, and the founder-window dates in #350, which depend on a release date that does not exist yet.

## Standing rules

- Never cut a TestFlight build while an App Store version of the same marketing version is awaiting review. A rejection ships as the same version plus the next build.
- The archive is pinned by `build/N`, never by a branch tip. `promote-to-appstore.sh N` enforces this; do not work around it.
- The App Store screenshots are 1.7.2's and show neither the polish layer nor the number row. Known, accepted, deliberately deferred. Not a release blocker.
