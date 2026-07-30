---
name: ship-issue
description: Run a sub-agent on a GitHub issue through a fixed five-phase sequence — context, plan, implement, verify, recap — with this repo's branching, linting and validation conventions baked in. Use whenever an issue is handed to an agent to implement ("lance un agent sur #N", "implement issue N", "attaque la 271"), so the phases never have to be restated.
---

# Ship an issue

## Quick start

`/ship-issue 271` — spawn one agent on issue #271 with the full phase sequence below.

Pass the issue number. Everything else comes from the issue and this file.

## When NOT to use this

- The issue is not `ready-for-agent`. Triage it first (`/triage`).
- The issue has no agent brief. A brief is the contract; without one the agent invents the spec.
- The work needs a design decision. Grill it first (`/grill-me`), then ship.

## The agent prompt

Spawn a `general-purpose` agent with the issue number substituted in. Do not shorten the phases — the point is that they are always the same.

> Implement GitHub issue #N in `getdictus/dictus-ios` (local clone: /Users/pierreviviere/dev/dictus).
>
> Follow these five phases in order. Do not skip a phase, and do not start implementing before phase 2 is written down.
>
> **Phase 1 — Context.** Read the issue in full including every comment (`gh issue view N --comments`), and every issue it references. **The agent brief is the contract**; the body is context, and where they disagree the brief wins. Read `CLAUDE.md`, plus `CONTEXT.md` and `docs/adr/` if present.
>
> **Phase 2 — Analyse and plan.** Locate every site the brief describes; briefs name types and behaviours, not paths, so find them yourself. Map every consumer of what you are about to change *before* changing anything. Write the plan: ordered changes, risks, and how each acceptance criterion will be verified. If the plan shows the brief is wrong or incomplete, **stop and report** rather than improvising.
>
> **Phase 3 — Implement.** Branch off `develop` (`feature/N-short-slug`); never work on `develop` or `main`. Atomic commits referencing `(refs #N)`. Match the surrounding code — this codebase documents *why* extensively in comments, keep that. No TODOs, no stubs, no partial implementations.
>
> **Phase 4 — Verify.** Build all three targets (DictusApp, DictusKeyboard, DictusCore). Run the test suite and add tests where the change is testable. Run SwiftLint and keep the baseline stable; if it shifts, regenerate it in its own commit. Walk the acceptance criteria one by one and record evidence for each. You cannot validate on a physical device — do what the simulator allows, then list precisely what remains for the maintainer, with exact steps.
>
> **Never launch the simulator GUI.** The maintainer works on the same machine and every launch of Simulator.app steals their focus. Do not run `open -a Simulator`. `xcrun simctl boot <udid>` on its own is headless and fine; `xcodebuild test -destination 'platform=iOS Simulator,name=...'` is the way to run tests. If something opens a window anyway, use `open -g` so it does not come to the front. If a check genuinely needs the GUI, do not run it — add it to the maintainer's device-validation list instead.
>
> **Phase 5 — Report.** Open a PR against `develop`. `Closes #N` does not auto-close on a merge into `develop` in this repo, so write `refs #N` and expect manual closing. Then recap: (1) what changed and why, in plain terms; (2) each acceptance criterion with status and evidence; (3) what you could not verify and exactly how to test it on device; (4) anything contradicting the issue, or any risk you are not comfortable with.
>
> Be honest in the recap. If something is untested, say untested. If a criterion is only partly met, say so. A recap that overstates what was verified is worse than one that reports a gap.

## Repo conventions the agent must not rediscover

- Branch off `develop`. PRs target `develop`. `main` is what is on the App Store.
- `Closes #N` does **not** auto-close issues on a merge into `develop`. Close them by hand.
- Three targets share one version and build number. Never bump them outside a TestFlight cut (`scripts/cut-testflight.sh`).
- After any "Reset Package Caches", `./scripts/patch-fluidaudio-swift5.sh` must be re-run or the build breaks.
- The keyboard extension has a ~50 MB ceiling, cannot use `UIApplication.shared`, and reaches the app through `extensionContext`.
- The keyboard's **declared** height constraint is a no-go zone (#166 and three regressions).
- UI strings ship in French and English. Code comments are English.

## After the agent reports

CI green is not validation. Every PR gets an independent review pass and a device test before merge. Merge, never squash.
