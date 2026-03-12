---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Beta Ready
status: in-progress
stopped_at: Completed 14-01-PLAN.md
last_updated: "2026-03-12T22:15:56Z"
last_activity: 2026-03-12 -- Plan 14-01 executed (Large Turbo removed, RAM recommendation, UX fixes)
progress:
  total_phases: 6
  completed_phases: 3
  total_plans: 9
  completed_plans: 8
  percent: 89
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-11)

**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard -- no subscription, no cloud, no account.
**Current focus:** Phase 14 in progress -- Model Pipeline (plan 1 of 2 done).

## Current Position

Phase: 14 of 16 (Model Pipeline)
Plan: 1 of 2 in current phase (14-01 done)
Status: Phase 14 in progress, plan 02 next
Last activity: 2026-03-12 -- Plan 14-01 executed (Large Turbo removed, RAM recommendation, UX fixes)

Progress: [████████░░] 89%

## Performance Metrics

**Velocity:**
- v1.0: 18 plans in 4 days (~25 min avg)
- v1.1: 29 plans in 5 days (~4 min avg)
- v1.2: 8 plans (~8 min avg)
- Total: 55 plans across 2 milestones

## Accumulated Context

### Decisions

All decisions logged in PROJECT.md Key Decisions table.

- Phase 11-02: Level color/icon defined in DebugLogView (UI concern) not LogLevel enum (keeps DictusCore framework-agnostic)
- [Phase 12]: Replace asyncAfter with withAnimation for success flash to eliminate timer race condition
- [Phase 12]: Reset all animation @State properties before new animations to prevent stacking
- [Phase 12-02]: Do NOT instant-reset on keyboardAppear -- URL scheme causes rapid disappear/appear within ~2s, killing legitimate recordings. Use refreshFromDefaults + 5s watchdog instead.
- [Phase 13-01]: Dual onOpenURL pattern -- DictusApp sets App Group flag (cross-process), MainTabView drives local @State (SwiftUI reactivity). Both fire on same URL event.
- [Phase 13-01]: Cold start state cleared on .background (not .inactive) to avoid premature cleanup during URL scheme app transitions.
- [Phase 13-02]: Pure SwiftUI animation (no Lottie) for swipe-back overlay -- locked decision from CONTEXT.md, keeps dependencies minimal.
- [Phase 13-02]: Color(hex: UInt) from DictusColors used for brand gradient -- consistent with existing color system.
- [Phase 13-03]: Auto-return removed -- attemptAutoReturn() always opened first installed app (WhatsApp), not actual source app. Swipe-back overlay is correct UX.
- [Phase 13-03]: Audio-thread waveform writes bypass iOS main thread throttling in background -- write from installTap callback, not main-thread timer.
- [Phase 14-01]: Recommendation logic in ModelInfo (catalog layer), not ModelManager -- accessible from onboarding and model manager without ObservableObject.
- [Phase 14-01]: PersistentLog uses structured LogEvent enum, not freeform messages -- used #if DEBUG print() for RAM diagnostics.

### Pending Todos

None.

### Blockers/Concerns

- Cold start auto-return has no public API -- Audio Bridge + UX messaging is the pragmatic path (Phase 13)
- CoreML compilation timing is device-specific -- need real-device calibration on 4GB/6GB/8GB tiers (Phase 14)
- Developer account not yet purchased -- blocks Phase 16 (TestFlight)
- App Group ID stability across team migration must be verified before shipping v1.2 code

## Session Continuity

Last session: 2026-03-12T22:15:56Z
Stopped at: Completed 14-01-PLAN.md
Resume file: .planning/phases/14-model-pipeline/14-02-PLAN.md

---
*State initialized: 2026-03-04*
*v1.1 shipped: 2026-03-11*
*v1.2 roadmap: 2026-03-11*
