---
name: testflight-build
description: Cut a Dictus version, upload it to TestFlight, and put it in the right tester group. Use when Pierre asks to cut a version, ship a build to testers, or publish to the public beta ("coupe 1.8.2", "monte un build", "envoie ça aux testeurs", "publie au public"). It stops at TestFlight. The App Store is a separate skill only Pierre starts.
---

# Cut a build and put it on TestFlight

Four steps, in order: cut, upload, write the notes, distribute. The last one is a decision, not a formality, and it is the one that goes wrong.

## "Public" means the Public Beta group, never the App Store

On this project there are two TestFlight groups:

| Group | Type | Who is in it | How a build reaches it |
| --- | --- | --- | --- |
| `Team PIVI` | internal | Pierre, plus maybe one other | automatic, every build |
| `Public Beta` | external, public link, 250 seats | strangers | explicit, and only after Apple's beta review |

When Pierre says *"publie au public"*, he means **`Public Beta`**. He does not mean the App Store. Shipping to the App Store is `appstore-promote`, it is user-invoked, and he types it himself.

This is written down because the confusion has already happened once, on 2026-09-07, and it got as far as an open PR against `main` before he caught it. If a request is ambiguous between the two, ask. One question costs a sentence; the wrong reading costs a merge to `main` and a submission to Apple's review queue.

## 1. Cut

```sh
scripts/cut-testflight.sh          # bumps the build number, keeps the version
scripts/cut-testflight.sh 1.8.2    # only when opening a new cycle
```

The bare form is the default and is right almost always. Pass a version only when the current one has already shipped to the App Store; passing it mid-cycle renames a release in flight. [`docs/VERSIONING.md`](../../../docs/VERSIONING.md) is the authority on which case you are in.

The script bumps all three plists together, commits, tags `build/N` and pushes. It refuses a dirty tree, a branch other than `develop`, and a duplicate `build/N`.

**Before cutting, the lane must be empty.** [`docs/ROADMAP.md`](../../../docs/ROADMAP.md) holds the ordered queue and says what a cycle contains. Check the milestone has no open issues, run `cd DictusCore && swift test`, and run `swiftlint lint --strict --no-cache`. CI does not run the tests, so nobody else will.

## 2. Upload

```sh
scripts/upload-testflight.sh
```

Archive, sign for the store, upload, wait for processing. Headless, so no window steals Pierre's screen. The script's header explains why it authenticates with the App Store Connect API key rather than the Xcode account; read it before you debug a signing failure, because the obvious diagnosis is wrong.

## 3. Write the What to Test

Not optional, and not a changelog. Testers need **instructions**: what to go and do, in what state, and what should happen. A bullet list of fixes tells them nothing they can act on.

```sh
asc builds test-notes create --app 6761262378 --latest --locale en-GB --whats-new "…"
```

English, user-facing, no issue numbers (they are not clickable in TestFlight). Name any known limit that ships with the build. A tester who hits a known bug and reports it as new costs a triage round.

## 4. Distribute, and gate it

`Team PIVI` gets every build automatically. Nothing to do.

`Public Beta` is explicit, and **it needs a device smoke test first**:

> Install the build from TestFlight, open any app, switch to the Dictus keyboard, type one letter, dictate one sentence.

A green build does not mean the keyboard extension launches. That gate exists because the two have come apart before, and Pierre is the only one who can run it. Ask him, wait for the answer, and do not read a merged PR or a passing test suite as a substitute.

Then:

```sh
asc builds add-groups --build-id <id> --group "44ee61cb-fbdf-43d9-90b0-c31c922d0d70" --submit --confirm
```

`--submit --confirm` sends the build to Apple's **beta app review**, which every external group requires. It usually clears in hours. Testers are notified when it does, not when you run the command.

Confirm it landed, and expect to retry:

```sh
ASC_TIMEOUT=90s asc builds beta-app-review-submission view --build-id <id> --output json
```

Wanted: `betaReviewState: WAITING_FOR_REVIEW`, then `APPROVED`.

## Two states, two tabs, and Pierre reads the other one

Distributing to `Public Beta` moves **TestFlight** state. It does not move the App Store version, which sits at `PREPARE_FOR_SUBMISSION` — *"Finaliser avant soumission"* in his French UI — and stays there until he runs `appstore-promote`.

That wording sounds like something is stuck. It is not. When he reports it, name the tab he is looking at before answering, or you will debug a state that is already correct.

## Traps

**`betaAppReviewSubmission` times out and needs retrying.** It is the one `asc` endpoint measured doing this: two `i/o timeout` failures against Apple's IP before a clean answer, `ASC_TIMEOUT=90s` and all. Retry two or three times before concluding anything. Reading the first timeout as an answer means reporting that a submission does not exist when it does.

**A `.p8` under `~/Downloads` is unreadable from a terminal.** macOS TCC protects that folder, and the failure is `Operation not permitted` on a file `ls` displays perfectly. `sudo` does not help: TCC is per-application, not per-privilege. The key belongs at `~/.asc/keys/`, moved there with Finder, which is not subject to the restriction.

**`asc` returns JSON on stdout for some commands and plain text for others.** Piping blindly into `json.load` fails on the text ones. Read the command's `--help` before parsing it.

**The version and build number live in three plists.** Never edit them by hand and never bump them outside a cut. `cut-testflight.sh` moves all three together so they cannot drift.

## Report

Tell Pierre four things:

- the version and build number, and that processing reached `VALID`
- which groups the build is in, named
- whether beta review is pending, if it went to `Public Beta`
- what the What to Test asks testers to do, in one line, so he can correct it before strangers read it

Then tick the lane in `docs/ROADMAP.md` and commit it directly on `develop` — that file is exempt from the PR rule.
