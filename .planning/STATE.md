---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Beta Ready
status: completed
stopped_at: Completed 15-08-PLAN.md
last_updated: "2026-03-13T12:15:14.158Z"
last_activity: 2026-03-13 -- Plan 15-05 executed (French accent gap closure)
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 19
  completed_plans: 18
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-11)

**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard -- no subscription, no cloud, no account.
**Current focus:** Phase 15 complete -- Design Polish (all 5 plans done). Ready for Phase 16 (TestFlight).

## Current Position

Phase: 15 of 16 (Design Polish) -- COMPLETE
Plan: 5 of 5 in current phase (all plans done)
Status: Phase 15 complete, ready for Phase 16
Last activity: 2026-03-13 -- Plan 15-05 executed (French accent gap closure)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- v1.0: 18 plans in 4 days (~25 min avg)
- v1.1: 29 plans in 5 days (~4 min avg)
- v1.2: 12 plans (~6 min avg)
- Total: 59 plans across 2 milestones

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
- [Phase 14-02]: No code changes needed for Parakeet routing or display names -- verified correct as-is.
- [Phase 14-03]: Added assertFalse for large-v3_turbo in tests (explicit regression guard) rather than just removing assertTrue.
- [Phase 15-01]: AnimatedMicButton transcription opacity 0.5 confirmed appropriate -- consistent across pill and circle modes, no adjustment needed.
- [Phase 15-01]: Settings list rows already use native Button (no custom buttonStyle masking press highlight) -- no changes needed.
- [Phase 15-02]: Used List with transparent styling (not ScrollView+VStack) to enable native swipeActions on model cards.
- [Phase 15-02]: Active model highlight is background tint behind glass (not border, not badge) per user preference.
- [Phase 15-02]: Removed onDelete callback from ModelCardView -- deletion handled exclusively via swipe in parent.
- [Phase 15-03]: Used HapticFeedback.recordingStopped() (light impact) for both cancel and stop buttons -- consistent dismiss semantics.
- [Phase 15-03]: Waveform logging uses freeform PersistentLog.log() not LogEvent enum -- diagnostic only, avoids adding enum cases for temporary instrumentation.
- [Phase 15-03]: Animation value bound to showsOverlay Bool (not dictationStatus enum) for cleaner SwiftUI animation trigger.
- [Phase 15]: Success screen as ZStack overlay on TestRecordingPage, not navigation push
- [Phase 15]: 500ms debounce on keyboard detection after Settings return -- matches iOS Settings sync timing
- [Phase 15]: Fixed 'autorise' -> 'autorise' accent alongside planned 'Reglages' fix (Rule 2 auto-fix)
- [Phase 15]: Auto-advance after 1.5s delay in onboarding -- user sees transcription before success screen
- [Phase 15]: SettingsRowStyle ButtonStyle restores tap feedback without removing scrollContentBackground

### Pending Todos

None.

### Blockers/Concerns

- Cold start auto-return has no public API -- Audio Bridge + UX messaging is the pragmatic path (Phase 13)
- CoreML compilation timing is device-specific -- need real-device calibration on 4GB/6GB/8GB tiers (Phase 14)
- Developer account not yet purchased -- blocks Phase 16 (TestFlight)
- App Group ID stability across team migration must be verified before shipping v1.2 code

## Session Continuity

Last session: 2026-03-13T12:15:14.156Z
Stopped at: Completed 15-07-PLAN.md
Resume file: None

---
*State initialized: 2026-03-04*
*v1.1 shipped: 2026-03-11*
*v1.2 roadmap: 2026-03-11*
