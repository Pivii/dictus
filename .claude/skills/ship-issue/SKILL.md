---
name: ship-issue
description: Run a sub-agent on a GitHub issue in its own git worktree, through a fixed five-phase sequence — context, plan, implement, verify, recap — with this repo's branching, linting and validation conventions baked in. Use whenever an issue is handed to an agent to implement ("lance un agent sur #N", "implement issue N", "attaque la 271"), so the phases never have to be restated.
---

# Ship an issue

## Quick start

`/ship-issue 271` — one agent, one worktree, on issue #271.

`/ship-issue 255 252 241` — several issues, one agent and one worktree each, in parallel.

Pass issue numbers. Everything else comes from the issues and this file.

## When NOT to use this

- The issue is not `ready-for-agent`. Triage it first (`/triage`).
- The issue has no agent brief. A brief is the contract; without one the agent invents the spec.
- The work needs a design decision. Grill it first (`/grill-me`), then ship.

## Step 1 — Give the agent its own worktree. Always.

**Never run a ship-issue agent in the main clone.** One git checkout has one set of files on one branch; an agent working there edits the files the maintainer is looking at and switches the branch under them. Two agents there destroy each other.

So before spawning anything, create a worktree per issue:

```bash
cd /Users/pierreviviere/dev/dictus
git fetch -q && git checkout develop -q && git pull -q
git worktree add -b <type>/<N>-<slug> /Users/pierreviviere/dev/dictus-wt/<N> develop
```

- `<type>` is `fix` for a bug, `feature` for an enhancement, `chore` for tooling — matching the issue's category.
- Worktrees live in `/Users/pierreviviere/dev/dictus-wt/`, **outside** the repo, so they can never be swept into a commit.
- If `dictus-wt/<N>` already exists, reuse it: `cd` in and `git merge develop` to bring it up to date. Do not force-remove another agent's work.

Then spawn the agent with that directory as its working directory, and state the path in its prompt.

Do not use the Agent tool's automatic worktree isolation here: those are temporary and throwaway-named, and this work has to end as a PR on a branch named to the repo's convention.

## Step 2 — The agent prompt

Spawn a `general-purpose` agent per issue, with the number and worktree path substituted in. Run them in parallel when there are several. Do not shorten the phases — the point is that they are always the same.

> Implement GitHub issue #N in `getdictus/dictus-ios`.
>
> **Your working directory is `/Users/pierreviviere/dev/dictus-wt/N`.** It is a git worktree, already on the branch for this issue. Stay inside it: never touch `/Users/pierreviviere/dev/dictus` or any other worktree, and never create a branch — yours exists.
>
> Follow these five phases in order. Do not skip a phase, and do not start implementing before phase 2 is written down.
>
> **Phase 1 — Context.** Read the issue in full including every comment (`gh issue view N --comments`), and every issue it references. **The agent brief is the contract**; the body is context, and where they disagree the brief wins. Read `CLAUDE.md`, plus `CONTEXT.md` and `docs/adr/` if present.
>
> **Phase 2 — Analyse and plan.** Locate every site the brief describes; briefs name types and behaviours, not paths, so find them yourself. Map every consumer of what you are about to change *before* changing anything. Write the plan: ordered changes, risks, and how each acceptance criterion will be verified. If the plan shows the brief is wrong or incomplete, **stop and report** rather than improvising.
>
> **Phase 3 — Implement.** Atomic commits referencing `(refs #N)`. Match the surrounding code — this codebase documents *why* extensively in comments, keep that. No TODOs, no stubs, no partial implementations.
>
> **Phase 4 — Verify.** Build all three targets (DictusApp, DictusKeyboard, DictusCore). A fresh worktree resolves packages from scratch, so run `./scripts/patch-fluidaudio-swift5.sh` before the first build or it will fail. Run the test suite and add tests where the change is testable. Run `swiftlint lint --strict` and leave it green — there is no baseline or exemption file, so any violation you introduce must be fixed or carry a `swiftlint:disable` directive with a written reason. Walk the acceptance criteria one by one and record evidence for each. You cannot validate on a physical device — do what the simulator allows, then list precisely what remains for the maintainer, with exact steps.
>
> **Never launch the simulator GUI.** The maintainer works on the same machine and every launch of Simulator.app steals their focus. Do not run `open -a Simulator`. `xcrun simctl boot <udid>` on its own is headless and fine; `xcodebuild test -destination 'platform=iOS Simulator,name=...'` is the way to run tests. If something opens a window anyway, use `open -g` so it does not come to the front. If a check genuinely needs the GUI, do not run it — add it to the maintainer's device-validation list instead.
>
> **Phase 5 — Report.** Push your branch and open a PR against `develop`. `Closes #N` does not auto-close on a merge into `develop` in this repo, so write `refs #N` and expect manual closing. **Do not merge.** Then recap: (1) what changed and why, in plain terms; (2) each acceptance criterion with status and evidence; (3) what you could not verify and exactly how to test it on device; (4) anything contradicting the issue, or any risk you are not comfortable with.
>
> Be honest in the recap. If something is untested, say untested. If a criterion is only partly met, say so. A recap that overstates what was verified is worse than one that reports a gap.

## Running several at once

Parallel agents are safe once each has its own worktree, with one thing to expect:

- **Never run two issues that own the same file in parallel.** Agents conflict on shared files, not on their own code.

The SwiftLint baseline used to be the worst of these shared files — every agent regenerated it and every PR but the first conflicted. It was deleted in #146; `swiftlint lint --strict` now passes on its own.

## Repo conventions the agent must not rediscover

- Branch off `develop`. PRs target `develop`. `main` is what is on the App Store.
- `Closes #N` does **not** auto-close issues on a merge into `develop`. Close them by hand.
- Three targets share one version and build number. Never bump them outside a TestFlight cut (`scripts/cut-testflight.sh`).
- A fresh worktree needs `./scripts/patch-fluidaudio-swift5.sh` before its first build, as does any "Reset Package Caches".
- The keyboard extension has a ~50 MB ceiling, cannot use `UIApplication.shared`, and reaches the app through `extensionContext`.
- The keyboard's **declared** height constraint is a no-go zone (#166 and three regressions).
- Xcode regenerates `Localizable.xcstrings` on build (a `stale` extraction state, a dropped trailing newline). That is build noise — discard it, never commit it.
- UI strings ship in French and English. Code comments are English.

## After the agent reports

CI green is not validation. Every PR gets an independent review pass and a device test before merge. Merge, never squash.

Once a PR is merged and its issue closed by hand, retire the worktree:

```bash
git worktree remove /Users/pierreviviere/dev/dictus-wt/<N>
```
