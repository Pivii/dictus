---
name: appstore-promote
disable-model-invocation: true
description: Ship a TestFlight build to the App Store — git promotion, App Store Connect submission, phased release.
---

# Promote a TestFlight build to the App Store

**Only Pierre starts this.** It has no model-facing description on purpose: an agent must not be able to reach a merge into `main` and a submission to Apple's review queue by interpreting a sentence. Apple has no rollback, and a cancelled submission loses its place in the queue.

The binary is **not** rebuilt. Build N is already uploaded and already tested; this moves source, tags, and App Store Connect state around a binary that does not change.

## What must be true before anything

- Build N has been on TestFlight and someone ran it. Not "the PRs merged", not "CI is green".
- `main` is fully back-merged into `develop`: `git merge-base --is-ancestor origin/main origin/develop`. A skipped back-merge conflicts the release PR.
- The tag `build/N` exists and `vX.Y.Z` does not.

## The git side

```sh
scripts/promote-to-appstore.sh N
```

Release branch pinned at `build/N`'s exact commit, PR to `main`, wait for checks, admin merge, tag `vX.Y.Z`, GitHub Release, back-merge into `develop`. The pin is the point: `develop` can have moved on, and the bits users get must be the bits testers ran.

Two things stop it, both measured on 2026-09-07.

**The script watches the wrong CI run.** `ci.yml` sets `cancel-in-progress: true`, so a push to `develop` cancels the previous push's run at the same SHA. `gh pr checks` sees that cancelled run alongside the PR's own passing run and reports failure. Do not trust it. Read the runs directly and find the one whose event is `pull_request`:

```sh
gh run list --repo getdictus/dictus-ios --limit 6 \
  --json databaseId,status,conclusion,event,headBranch \
  --jq '.[] | "\(.databaseId) \(.event) \(.headBranch) \(.status)/\(.conclusion)"'
```

**`main` cannot be merged by an admin.** It carries classic branch protection with `enforce_admins: true` and one required approving review, so `gh pr merge --admin` is refused and Pierre cannot approve his own PR. There is no second reviewer on this repo. The only way through is to disable admin enforcement, merge, and restore it:

```sh
gh api -X DELETE repos/getdictus/dictus-ios/branches/main/protection/enforce_admins
gh pr merge <PR> --merge --admin --delete-branch
gh api -X POST   repos/getdictus/dictus-ios/branches/main/protection/enforce_admins
```

**Ask Pierre before the first line and verify the flag is back to `true` after the third.** Disabling the guardrail on the branch that represents the App Store is his decision, and leaving it off is the kind of mistake nobody notices for months.

## The App Store Connect side

App ID `6761262378`. Version `X.Y.Z` must exist and be in `PREPARE_FOR_SUBMISSION`.

1. **Attach the build.** `asc versions attach-build --version-id <v> --build-id <b>`
2. **Release notes.** Pull the canonical metadata, set `whatsNew`, dry-run, push:
   ```sh
   asc metadata pull --app 6761262378 --version X.Y.Z --dir <dir>
   asc metadata push --app 6761262378 --version X.Y.Z --dir <dir> --dry-run
   ```
   The dry run names every field it would change. Read it: `adds`, `updates` and `deletes` should contain exactly what you meant and nothing else.
3. **Check the description and keywords.** They are version-scoped, so this submission is the only chance to fix them until the next one. A copy fix that misses its version waits a whole cycle.
4. **Arm the phased release before releasing.**
   ```sh
   asc versions phased-release create --version-id <v> --state INACTIVE
   ```
   Every App Store release goes out phased. Decided 2026-09-06, and the reasoning is in [`docs/RELEASE-PLAN.md`](../../../docs/RELEASE-PLAN.md): Apple has no withdrawal, so limiting exposure is the only protection that exists. It costs no user the fix, because phasing governs automatic updates only.
5. **Submit for review.**

## The ordering is wrong, and knowing that is the point

`promote-to-appstore.sh` merges into `main` **before** Apple approves. So between submission and approval, `main` claims a version is on the App Store that is not, and a rejection leaves it lying for days.

`main` is supposed to mean *what is on the App Store*. Until the script is changed, either promote the source after approval rather than before, or accept the gap knowingly. Do not discover it mid-release.

## Report

- the tag and the GitHub Release URL
- the App Store version's state after submission
- that the phased release is armed, and how to pause it: `asc versions phased-release update --version-id <v> --state PAUSE`
- whether `enforce_admins` is back to `true`, quoted from a read, not from memory
