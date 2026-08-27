# Git & Release Workflow — Dictus

Guide for managing branches, releases, and TestFlight/App Store distribution.
Version-numbering policy lives in **[VERSIONING.md](VERSIONING.md)**.

## Branch strategy

```
main (production)              <- App Store + external TestFlight. Tagged vX.Y.Z.
  |
  +-- develop                  <- Daily integration, internal TestFlight builds
  |     |
  |     +-- feature/xxx        <- New feature (one branch per feature/issue)
  |     +-- fix/xxx            <- Bug fix
  |     +-- chore/xxx          <- Maintenance, refactoring, docs
  |
  +-- hotfix/xxx               <- Critical production fix (branches from main)
```

We deliberately **do not use `release/*` freeze branches** — for a solo/small
team they add ceremony without value. A release is pinned to a specific commit
via its `build/N` tag instead (see Runbook B). The promote script creates a
throwaway `release/X.Y.Z` branch only as a vehicle to open the PR; it is not a
QA-freeze phase and is deleted on merge.

## Branch roles

| Branch | Purpose | Merges in via | TestFlight | App Store |
|---|---|---|---|---|
| `main` | Stable production code | PR from develop (release) or hotfix/* | External (public) | Yes |
| `develop` | Integration of ongoing work | PR from feature/*, fix/*, chore/* | Internal | No |
| `feature/*` `fix/*` `chore/*` | One unit of work | Developer (PR to develop) | No | No |
| `hotfix/*` | Critical fix on production | Developer (PR to main) | If needed | Yes |

## Workflow: Feature development

```
1. git checkout develop && git pull origin develop
2. git checkout -b feature/my-feature      # or fix/ , chore/
3. ... work, commit frequently ...
4. git push -u origin feature/my-feature
5. Open PR → develop, CI green, merge (--merge, never squash)
```

## Runbook A — Cut a TestFlight build (from `develop`)

Internal TestFlight builds come from `develop`. One command does the version
bump across all three plists, the commit, the `build/N` tag, and the push:

```sh
git checkout develop && git pull origin develop

scripts/cut-testflight.sh          # build-number bump only (same marketing version)
scripts/cut-testflight.sh 1.8.0    # ALSO set the marketing version to 1.8.0

# then, in Xcode:
#   Product ▸ Archive  (scheme DictusApp, on develop)  →  Distribute  →  App Store Connect
```

The script refuses to run on a dirty / out-of-sync develop and refuses a
duplicate build number. After it runs, the build is traceable forever via its
`build/N` tag — no manual tagging, nothing to forget.

## Runbook B — Promote a build to the App Store

Key idea: **a release is pinned to the commit that produced the tested build,
not to develop's current tip.** develop keeps moving while a build is in
TestFlight; we ship the exact commit behind `build/N`.

### Worked example

```
develop:  …──X──A──B──C──D──Z        ← a month of work after the build
              │
              └─ X = "chore: bump to 1.8.0 (build 18)"   [tag build/18]  ← on TestFlight

# A month later we decide build 18 is good. We must bring ONLY X to main
# (A…Z are not ancestors of X, so a merge of X excludes them):

scripts/promote-to-appstore.sh 18
```

The script:
1. Resolves `build/18` → commit X and marketing version `1.8.0`.
2. Creates an ephemeral `release/1.8.0` branch at X and opens a PR → `main`.
3. Waits for required checks (`Build`, `SwiftLint`), then merges with `--admin`
   (you are in main's bypass list; you cannot self-approve, so `--admin` is how
   the merge lands).
4. Tags `v1.8.0` (annotated) on main + pushes, creates the GitHub Release.
5. **Back-merges `main → develop`** — the step whose omission caused the v1.7.1
   drift. Never skipped because the script owns it.
6. Prints the App Store Connect checklist.

### App Store Connect (the only manual part)

```
1. My Apps → Dictus → the X.Y.Z App Store version (create it on first launch).
2. Build section → select build N (already uploaded from TestFlight). No rebuild.
3. First submission only: complete the listing — screenshots (6.9" + 6.5"),
   description, keywords, support URL, privacy policy URL, category, age rating,
   price/availability, and the App Privacy questionnaire ("Data Not Collected",
   Dictus is offline).
4. App Review Information → Notes: explain the keyboard needs Full Access for the
   MICROPHONE (on-device dictation, no keystroke logging/transmission) and how to
   enable the keyboard. This is the #1 review risk for keyboard extensions.
5. Export compliance: ITSAppUsesNonExemptEncryption is set in Info.plist → no prompt.
6. Submit for Review (24–48h typical).
```

### Doing it by hand (if not using the script)

```sh
git checkout main && git pull origin main
git merge build/18 --no-ff -m "release: v1.8.0 (build 18)"   # brings ONLY X's history
git tag -a v1.8.0 -m "v1.8.0 — short one-liner" && git push origin main v1.8.0
gh release create v1.8.0 --title "v1.8.0 — …" --notes "…"
git checkout develop && git merge main --no-edit && git push origin develop   # resync
```

## Workflow: Hotfix (critical production bug)

```
1. git checkout main && git pull
2. git checkout -b hotfix/fix-crash
3. ... fix, commit ...
4. PR → main, CI green, merge (--admin)
5. Bump build number (and PATCH version) → cut/upload, then tag vX.Y.(Z+1) on main
6. git checkout develop && git merge main   # resync, always
```

## TestFlight distribution

| Group | Source branch | Apple review | Purpose |
|---|---|---|---|
| Internal — Dev team (≤100) | `develop` | None | Daily builds, fast iteration |
| External — Public beta (≤10k) | `main` | Beta App Review (light, <24h) | Stable public testing |

## Commit message convention

Format: `type: short description` — types: `feat`, `fix`, `chore`, `refactor`,
`docs`, `test`, `style`, `perf`. Scope an issue with `feat(#141): …`.

```
feat(#141): add Apple FM polish layer
fix: resolve crash on long dictation
chore: bump to 1.8.0 (build 18)
```

## Quick reference

```bash
# New unit of work
git checkout develop && git pull
git checkout -b feature/my-feature      # → PR to develop

# Cut a TestFlight build
git checkout develop && git pull
scripts/cut-testflight.sh 1.8.0         # then Xcode Archive → upload

# Ship a build to the App Store
scripts/promote-to-appstore.sh 18       # PR→main, tag, release, back-merge

# Emergency hotfix
git checkout main && git pull
git checkout -b hotfix/fix-crash        # → PR to main, then resync develop
```
