---
phase: 12-animation-state-fixes
plan: 02
subsystem: ui
tags: [swiftui, animation, watchdog, timer, state-recovery, dictation]

requires:
  - phase: 12-animation-state-fixes
    plan: 01
    provides: LogEvent cases (watchdogReset, statusChanged), overlay visibility fix, animation race fixes
  - phase: 11-logging-foundation
    provides: PersistentLog structured logging API
provides:
  - KeyboardState watchdog timer with 5s stale-state detection and forceResetToIdle recovery
  - KeyboardRootView reset-on-appear via refreshFromDefaults + 5s watchdog (not instant reset)
  - DictationCoordinator 30s transcription timeout watchdog calling cancelDictation
  - All watchdog resets logged with source and staleState for post-hoc diagnosis
affects: [13-cold-start-audio-bridge, dictation-pipeline, animation]

tech-stack:
  added: []
  patterns:
    - "Timer-based watchdog with [weak self] and deinit cleanup for keyboard extension memory safety"
    - "refreshFromDefaults on keyboard appear + delayed watchdog instead of instant forceResetToIdle (prevents killing legitimate recordings during URL scheme transitions)"
    - "Non-repeating Timer for one-shot transcription timeout (30s)"

key-files:
  created: []
  modified:
    - DictusKeyboard/KeyboardState.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusApp/DictationCoordinator.swift

key-decisions:
  - "Do NOT instant-reset on keyboardAppear -- URL scheme flow causes keyboardDidDisappear then keyboardDidAppear within ~2s, which would kill legitimate recordings"
  - "Use refreshFromDefaults on appear + 5s waveform watchdog as the stale state recovery mechanism instead"
  - "Watchdog timer starts on recording lifecycle, checks lastWaveformUpdate age"

patterns-established:
  - "Keyboard appear = refreshFromDefaults + watchdog, never instant force reset (URL scheme causes rapid disappear/appear)"
  - "All Timer closures use [weak self] with deinit invalidation in keyboard extension"

requirements-completed: [ANIM-03]

duration: ~20min (across 2 sessions with device verification)
completed: 2026-03-12
---

# Phase 12 Plan 02: Watchdog Recovery Summary

**Watchdog timers for keyboard (5s stale waveform) and app (30s transcription timeout) with reset-on-appear via refreshFromDefaults, all logged for diagnostics**

## Performance

- **Duration:** ~20 min (across 2 sessions with device verification checkpoint)
- **Started:** 2026-03-11T20:20:00Z (estimated)
- **Completed:** 2026-03-12T08:15:00Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 3

## Accomplishments
- KeyboardState has forceResetToIdle() that resets all dictation state and writes idle to App Group
- Watchdog timer runs during .recording/.transcribing, fires after 5s of no waveform updates to auto-recover
- KeyboardRootView refreshes from App Group on each keyboard appear, with watchdog catching stale states
- DictationCoordinator has 30s transcription timeout that calls cancelDictation() to prevent hanging
- All timer closures use [weak self] with deinit cleanup for memory safety in keyboard extension
- Device verification confirmed: 4 consecutive normal recordings work perfectly, all ANIM requirements pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Add watchdog timers to KeyboardState and DictationCoordinator + reset-on-appear** - `97b41d2`, `eaa5456`, `f2928a0`, `c06f811` (feat + 3 fixes for edge cases discovered during iteration)
2. **Task 2: Verify complete animation state fix on device** - APPROVED by user (checkpoint, no commit)

## Files Created/Modified
- `DictusKeyboard/KeyboardState.swift` - forceResetToIdle(), watchdog timer (5s stale threshold), lastWaveformUpdate tracking, deinit cleanup
- `DictusKeyboard/KeyboardRootView.swift` - onReceive for keyboardWillAppear does refreshFromDefaults (not instant reset), watchdog catches stale states
- `DictusApp/DictationCoordinator.swift` - 30s transcription timeout watchdog, cancelDictation on fire, deinit cleanup

## Decisions Made
- Do NOT instant-reset on keyboardAppear: URL scheme flow causes keyboardDidDisappear then keyboardDidAppear within ~2s, which would kill legitimate recordings that just started. Instead, refreshFromDefaults + 5s watchdog handles stale states safely.
- Watchdog timer lifecycle tied to recording state changes, not keyboard appearance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] keyboardAppear instant forceResetToIdle killed legitimate recordings**
- **Found during:** Task 1 (device testing iteration)
- **Issue:** Plan specified instant forceResetToIdle on keyboardWillAppear, but URL scheme dictation flow triggers keyboardDidDisappear then keyboardDidAppear within ~2s, immediately killing the recording that was just requested
- **Fix:** Replaced instant forceResetToIdle with refreshFromDefaults on appear + rely on 5s waveform watchdog for actual stale states
- **Files modified:** DictusKeyboard/KeyboardRootView.swift, DictusKeyboard/KeyboardState.swift
- **Verification:** 4 consecutive recordings work without false resets
- **Committed in:** eaa5456, f2928a0

**2. [Rule 1 - Bug] Watchdog timer never started on recording lifecycle**
- **Found during:** Task 1 (device testing iteration)
- **Issue:** Watchdog timer was not being started when dictationStatus changed to .recording
- **Fix:** Ensured watchdog starts/stops correctly based on status transitions
- **Files modified:** DictusKeyboard/KeyboardState.swift
- **Committed in:** c06f811

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes were essential for correctness. The keyboardAppear instant reset was fundamentally incompatible with the URL scheme dictation flow. The watchdog approach is more robust.

## Issues Encountered
- Rapid mic spam (< 1s recordings) produces "Invalid audio data - must be at least 1 second" errors from Parakeet. This is expected behavior, not a bug. Will add minimum recording duration guard in Phase 13.
- Keyboard watchdog fires during URL scheme transitions (issue #21). Will be reworked in Phase 13 with new workflow.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 12 complete: all 3 ANIM requirements validated on device
- Phase 13 (Cold Start Audio Bridge) can proceed with stable animation foundation
- Known items for Phase 13: minimum recording duration guard, keyboard watchdog rework for URL scheme flow

---
*Phase: 12-animation-state-fixes*
*Completed: 2026-03-12*

## Self-Check: PASSED
- 12-02-SUMMARY.md: FOUND
- Commit 97b41d2: FOUND
- Commit eaa5456: FOUND
- Commit f2928a0: FOUND
- Commit c06f811: FOUND
