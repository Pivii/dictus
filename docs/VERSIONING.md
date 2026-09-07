# Versioning — Dictus

How we number releases and tags. Complements [GIT_WORKFLOW.md](GIT_WORKFLOW.md).

## TL;DR

- One marketing version line: `X.Y.Z` — [Semantic Versioning](https://semver.org/). **No `-beta` suffix** anywhere (not in the plist, not in tags). TestFlight is a *channel*, not a version status.
- `CFBundleVersion` (Apple build number) is a plain integer that **always increments, never resets** — shared identically across the 3 targets (App / Keyboard / Widgets).
- **Two kinds of tags, two purposes:**
  - **`build/N`** — a *lightweight* git tag on every TestFlight build. Cheap, not a GitHub Release. It answers "when did we cut build N and from which commit?" and is the anchor we promote from.
  - **`vX.Y.Z`** — an *annotated* tag + GitHub Release, created **only** when a build is promoted to the App Store. One per shipped version.
- **A release is pinned to a commit, never to "develop's current tip."** We promote the exact commit that produced the tested TestFlight build (its `build/N` tag), even if develop has moved on since.
- Two scripts make it deterministic: [`scripts/cut-testflight.sh`](../scripts/cut-testflight.sh) and [`scripts/promote-to-appstore.sh`](../scripts/promote-to-appstore.sh).

## WHEN the marketing version changes — read this before the table below

This is the question that has been got wrong more than once, so it is answered first and without judgement calls.

**The marketing version names a release, not a build.** It is chosen **once**, at the moment the previous version leaves for the App Store, and it then stays **frozen** across every TestFlight build of that cycle.

```
v1.7.2 promoted to the App Store
        │
        └── develop opens the next cycle → version becomes 1.8.0
                 TestFlight build 21 → 1.8.0 (21)
                 TestFlight build 23 → 1.8.0 (23)   same version, more builds
                 TestFlight build 24 → 1.8.0 (24)
                 TestFlight build 25 → 1.8.0 (25)   ← still 1.8.0, however much lands
                          │
                          └── one of them is promoted → App Store 1.8.0
                                   │
                                   └── only NOW does the next cycle open → 1.9.0
```

### The decision rule, in one line

> **Is the current marketing version already on the App Store?**
> **No → do not touch it.** Cut the build, bump the build number only.
> **Yes → this is a new cycle.** Pick the next version with the table below, comparing against that shipped version.

Check it, never remember it: `git show origin/main:DictusApp/Info.plist | grep -A1 CFBundleShortVersionString`. `main` is the App Store. If `develop` already reads higher, the cycle is open and the version is settled.

### Why it is not "bump whenever a feature lands"

Because the version is what a **user** sees, and a TestFlight tester is not a new user of a new version — they are trying out the version that is being built. Ten TestFlight builds of `1.8.0` are ten attempts at one release. Bumping on every feature would ship `1.8.0`, `1.9.0`, `1.10.0` to testers and never to anyone else, and the App Store would jump from `1.7.2` to `1.14.0` with nothing in between. The version line would stop meaning anything.

It is also what App Store Connect models: a *version* is a container, and builds attach to it. Several builds under one version is the normal shape.

**So a feature landing on `develop` never, on its own, changes the version.** It changes the *content* of the version already in flight. Which digit that version got was decided when the cycle opened.

## Which digit, once a cycle actually opens

Only ever asked at promotion time, and always against **the version just shipped**.

| Bump | When | Example |
| --- | --- | --- |
| **PATCH** `X.Y.Z → X.Y.(Z+1)` | Bug fix, polish, perf tweak, no new user-facing feature | Fix #134 keyboard freeze → `1.6.1` |
| **MINOR** `X.Y.Z → X.(Y+1).0` | New user-facing feature, new supported language, new model in catalog | German layout → `1.7.0` |
| **MAJOR** `X.Y.Z → (X+1).0.0` | Premium launch, breaking UX shift | Premium → `2.0.0` |

Rule of thumb: **ask "does a returning user notice something new?"** — if yes → MINOR at least. If they just notice things work better → PATCH.

Judge the **whole cycle**, not the last thing merged. A cycle that accumulated one new feature and nine fixes is a MINOR, because the feature is in it.

A cycle can also be re-judged at promotion: if `1.8.0` was opened expecting a feature that got cut, and only fixes shipped, promote it as `1.7.3` instead. The version is only binding once it is on the App Store.

> Note: the **first App Store release is not automatically a MAJOR**. We shipped `v1.x` on TestFlight for a long time; the first public App Store submission keeps the normal `1.Y.Z` line (it's the same product, same version line — just a new distribution channel).

### Emergency exception: a hotfix while a cycle is open

A production crash is fixed on a branch off `main`, not off `develop`, and it gets a PATCH on the **shipped** line — `1.7.2 → 1.7.3` — regardless of what `develop` is carrying. It never borrows the open cycle's number. Cherry-pick the fix back into `develop` afterwards; the open cycle keeps its own version.

## Build numbers vs. version — the two-axis model

```
CFBundleShortVersionString (marketing)  →  what users see: 1.8.0   (SemVer, no suffix)
CFBundleVersion            (build no.)  →  what Apple tracks: 18    (integer, ++ every upload)
```

- The **build number** increments on **every** upload (TestFlight or App Store), even if the marketing version is unchanged (re-upload after an entitlement tweak, a second beta of the same version, etc.). It is unique across the whole App Store Connect history for the app and never repeats.
- The **marketing version** only changes when you start a new user-facing version. Several TestFlight builds can share one marketing version (`1.8.0` builds 18, 19, 20…) before one of them is promoted.
- Both are kept identical across the 3 targets — `cut-testflight.sh` bumps all three plists together so they can never drift.

## Tags — `build/N` vs `vX.Y.Z`

| | `build/N` | `vX.Y.Z` |
| --- | --- | --- |
| Created | every TestFlight build (by `cut-testflight.sh`) | only at App Store promotion (by `promote-to-appstore.sh`) |
| Git type | lightweight | annotated (`-a`) |
| GitHub Release | no | yes |
| Points at | the `chore: bump…` commit on develop | the release merge commit on main |
| Answers | "when/what was build N" + promotion anchor | "exactly what is in production" |

Why two tiers: build tags give full per-build traceability **without** cluttering the GitHub Releases page (only the Tags page) — this is what CI systems do. Release tags stay rare and meaningful: each one is a real, shipped version. Runtime traceability is *also* covered independently by the git-SHA generated into every built bundle (a `Generate build info` build phase writes `GitCommitSHA` + `GitBranch` into `DictusBuildInfo.plist`), so even an untagged build is identifiable from the app's debug log.

## TestFlight → App Store: promote, don't rebuild

```
develop ──(cut-testflight.sh)──► TestFlight build N      [tag build/N]
                                       │
                                       │  (validated by testers)
                                       ▼
main ◄──(promote-to-appstore.sh N, pins commit build/N)── tag vX.Y.Z + GitHub Release
                                       │
                                       ▼
                                App Store: select build N (same binary), submit
```

- The binary submitted to the App Store is the **same** one testers ran on TestFlight — you select build N in App Store Connect, you do **not** archive again.
- The promotion **pins the commit** behind build N, so develop can keep moving freely. See the worked example in [GIT_WORKFLOW.md](GIT_WORKFLOW.md#runbook-b--promote-a-build-to-the-app-store).

## Runbooks (the only two deployment actions)

### Cut a TestFlight build (from `develop`)

```sh
scripts/cut-testflight.sh          # ← the normal case, and the one you want almost every time
scripts/cut-testflight.sh 1.9.0    # ← only when opening a new cycle, i.e. the current version already shipped
```

**The bare form is the default.** Passing a version is the exception, not a step to remember: it belongs at exactly one moment, the first cut after a promotion. If the version on `develop` is not yet on the App Store, the cycle is already open and passing a version would rename a release in flight.

Then:

```sh
scripts/upload-testflight.sh       # archive, sign for the store, upload, wait for processing
```

No tag to remember, `cut-testflight.sh` made `build/N`. Xcode → Product ▸ Archive still works and is the fallback, but the script is headless and does not steal the screen.

**It authenticates with the App Store Connect API key, not the Xcode account, and that is deliberate.** Xcode 26 keeps its signed-in Apple Account somewhere `xcodebuild` does not read: the CLI resolves the legacy `IDEProvisioningTeams` preference instead, finds a stale free-Personal-Team entry with no keychain token, and dies with `exportArchive No Accounts` / `No signing certificate "iOS Distribution" found` — while Xcode's own Settings ▸ Apple Accounts shows the right account, healthy. Nothing is broken and re-adding the account does not help, because the CLI never looks there. The API key bypasses the account system entirely. Measured 2026-09-07 while cutting 1.8.2 (30).

The key must be readable at `~/.asc/keys/AuthKey_<KEYID>.p8`. **Not** in `~/Downloads`, `~/Desktop` or `~/Documents`: macOS TCC blocks a terminal from reading those, and the symptom is `Operation not permitted` on a file `ls` displays perfectly. Move it with Finder, which is not subject to that restriction.

### Promote a TestFlight build to the App Store

```sh
scripts/promote-to-appstore.sh 18  # ship the build/18 candidate
```
Opens the `develop`→`main` PR pinned to build 18's commit, waits for CI, admin-merges, tags `v1.8.0` + GitHub Release, **back-merges main→develop**, and prints the App Store Connect checklist (the only manual part).

## What shipped so far (historical — do not rewrite)

| Tag | `CFBundleShortVersionString` | `CFBundleVersion` | Notes |
| --- | --- | --- | --- |
| `v1.6.0-beta.1` → `v1.6.0-beta.4` | `1.6.0` (frozen across 4 betas) | 10 → 13 | Pre-semver-switch. Kept as-is for release-note continuity; we do **not** retro-rename. |
| `v1.6.1` … `v1.7.1` | `1.6.1` … `1.7.1` | 14 → 17 | Clean single-line releases. `v1.7.1` (build 17) is the current production candidate. |

## Release-notes naming (GitHub + TestFlight)

- GitHub release title: `vX.Y.Z — short summary` (e.g. `v1.8.0 — Apple FM polish layer`).
- TestFlight "What to Test": user-facing bullets, English, no internal jargon, no un-clickable issue numbers. Keep technical notes for the GitHub release body.

## Common mistakes to avoid

- ❌ Re-using a build number for a re-upload — always bump `CFBundleVersion`. (`cut-testflight.sh` enforces this and refuses a duplicate `build/N`.)
- ❌ Adding `-beta.N` to a tag or to the marketing version — obsolete convention, dropped since `v1.6.1`.
- ❌ Promoting "develop's current tip" instead of the pinned `build/N` commit — ships untested code. Always promote via `build/N`.
- ❌ Forgetting the **main → develop** back-merge after a release — this is what caused the `v1.7.1` drift. The promote script does it automatically; if you release by hand, do it.
- ❌ Letting `CFBundleVersion` drift between targets — always bump all three together.

## Premium worktree sync (only while `feature/premium` is active)

After a release lands on `main`, sync it into the long-lived premium branch: open a `sync/main-to-premium-vX.Y.Z` branch from `feature/premium`, `git merge origin/main --no-ff`, resolve any `.planning/` conflicts in favour of premium, PR into `feature/premium`, merge with `--merge` (never squash). Drop this step if/when premium is retired or merged.
