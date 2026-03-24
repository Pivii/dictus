---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Beta Ready
status: completed
stopped_at: Phase 15.4 context gathered
last_updated: "2026-03-24T22:43:42.480Z"
last_activity: 2026-03-22 -- Plan 15.3-03 execution (commits e00a70c, 427d791)
progress:
  total_phases: 10
  completed_phases: 8
  total_plans: 35
  completed_plans: 33
  percent: 91
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-11)

**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard -- no subscription, no cloud, no account.
**Current focus:** Phase 15.3 keyboard optimization -- Plan 01 complete (haptic cache, static KeyMetrics, background suggestions, touchDown pipeline, OSSignposter). Plans 02-04 remaining.

## Current Position

Phase: 15.3 (Keyboard Optimization and Responsiveness)
Plan: 4 of 4 in current phase
Status: Plan 15.3-03 complete. Device-adaptive KeyMetrics across 3 device classes, press feedback on special keys.
Last activity: 2026-03-22 -- Plan 15.3-03 execution (commits e00a70c, 427d791)

Progress: [█████████░] 91%

## Performance Metrics

**Velocity:**
- v1.0: 18 plans in 4 days (~25 min avg)
- v1.1: 29 plans in 5 days (~4 min avg)
- v1.2: 13 plans (~6 min avg)
- Total: 60 plans across 2 milestones

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
- [Phase 15-08]: Used structured LogEvent cases for onboarding logging instead of deprecated freeform API
- [Phase 15-08]: Increased keyboard detection debounce from 500ms to 800ms with 2s retry backoff
- [Phase 15-06]: Inline Text rows as section headers (not Section header: parameter) to prevent iOS sticky header behavior
- [Phase 15-06]: Active model highlight changed from background tint to border stroke overlay on glass
- [Phase 15-06]: Engine descriptions consolidated into single footer section instead of per-section duplicates
- [Phase 15]: Matched transcribingContent layout to recordingContent (reserved top bar + footer height) to eliminate waveform Y-jump
- [Phase 15]: Removed SettingsRowStyle ButtonStyle -- native List press highlight works for Button and NavigationLink without custom masking
- [Phase 15]: Replaced Link with Button for GitHub row to get native press feedback in scrollContentBackground(.hidden) context
- [Phase 15]: Active card uses both background tint (0.10 opacity) AND border stroke -- dual visual indicator for active model
- [Phase 15.1]: Used cairosvg for SVG-to-PNG rendering (ImageMagick MSVG renders gradients as grayscale)
- [Phase 15.1]: AudioServicesPlaySystemSound over AVAudioPlayer -- respects silent switch natively
- [Phase 15.1]: Start sound before configureAudioSession to avoid WhisperKit session suppression
- [Phase 15.1-03]: subdirectory:"Sounds" required for Bundle.main.url -- Xcode folder references nest files in subdirectory
- [Phase 15.1-03]: .pickerStyle(.menu) for inline sound picker layout -- .automatic renders stacked in List
- [Phase 15.1-03]: 5pt extra trailing padding on overlay HStack matches AnimatedMicButton ring-to-pill inset
- [Phase 16]: No logo SVG found -- used dictus-icon-512.png for README header
- [Phase 15.2]: renderTick @State counter forces Canvas re-evaluation after extension suspension -- avoids Timer-based approaches
- [Phase 15.2]: lastResult clearing before guard in startDictation ensures all 5 entry paths clear stale transcription cards
- [Phase 15.2]: LiveActivityPhase enum separate from ContentState.Phase -- adds .idle state and transition validation to prevent DI desync (#42)
- [Phase 15.2]: waveformRefreshID incremented inside refreshFromDefaults() to guarantee it fires on every keyboard reappear path
- [Phase 15.2]: .id(waveformRefreshID) pattern forces BrandWaveform recreation when keyboard returns from off-screen -- solves frozen TimelineView/CADisplayLink
- [Phase 15.3]: Audio+haptic moved to touchDown (not touchUp) matching Apple keyboard -- feedback on press, character insertion on release
- [Phase 15.3]: Synchronous update(proxy:) kept for delete/undo paths; new updateAsync(context:) for normal character insertion
- [Phase 15.3]: OSSignposter emitEvent for sub-interval markers within touchDown interval
- [Phase 15.3]: 3 device classes (compact/standard/large) based on screen height 667/852pt breakpoints for all KeyMetrics
- [Phase 15.3]: UIViewRepresentable touch overlay: transparent UIView captures touches, SwiftUI handles rendering -- zero gesture disambiguation delay

### Pending Todos

None.

### Roadmap Evolution

- Phase 15.1 inserted after Phase 15: UI polish fixes (#30, #33, #34, #24) (URGENT)
- Phase 15.2 inserted after Phase 15: Cleaning and fix github issues (URGENT)
- Phase 15.3 inserted after Phase 15: Keyboard optimization and responsiveness (URGENT)
- Phase 15.4 inserted after Phase 15.3: Zero Dead Zones — eliminate dead zones between keyboard keys (Issue #56) (URGENT)

### Blockers/Concerns

- Cold start auto-return has no public API -- Audio Bridge + UX messaging is the pragmatic path (Phase 13)
- CoreML compilation timing is device-specific -- need real-device calibration on 4GB/6GB/8GB tiers (Phase 14)
- Developer account not yet purchased -- blocks Phase 16 (TestFlight)
- App Group ID stability across team migration must be verified before shipping v1.2 code

## Session Continuity

Last session: 2026-03-24T22:43:42.478Z
Stopped at: Phase 15.4 context gathered
Resume file: .planning/phases/15.4-zero-dead-zones/15.4-CONTEXT.md

---
*State initialized: 2026-03-04*
*v1.1 shipped: 2026-03-11*
*v1.2 roadmap: 2026-03-11*
