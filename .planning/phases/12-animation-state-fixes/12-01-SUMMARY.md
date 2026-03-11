---
phase: 12-animation-state-fixes
plan: 01
subsystem: ui
tags: [swiftui, animation, state-machine, logging, dictation]

requires:
  - phase: 11-logging-foundation
    provides: PersistentLog structured logging API and LogEvent enum
provides:
  - Recording overlay appears immediately on mic tap via .requested status inclusion
  - 3-state RecordingOverlay (requested/recording/transcribing) with distinct visuals
  - Race-safe AnimatedMicButton with no asyncAfter patterns
  - 5 new animation/watchdog LogEvent cases for diagnostics
  - DictationCoordinator accepts .requested in startDictation guard
affects: [12-02-PLAN, animation, dictation-pipeline]

tech-stack:
  added: []
  patterns:
    - "withAnimation for timed state transitions instead of asyncAfter (race-free)"
    - "Animation @State reset before each transition to prevent stacking"
    - "Status-based .disabled modifier for tap rejection"

key-files:
  created: []
  modified:
    - DictusCore/Sources/DictusCore/LogEvent.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/Views/RecordingOverlay.swift
    - DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift
    - DictusApp/DictationCoordinator.swift

key-decisions:
  - "Replace asyncAfter with withAnimation for success flash to eliminate timer race condition"
  - "Reset all animation @State properties to concrete values before starting new animations to prevent stacking"
  - "Use isTappable computed property for both .disabled and guard-based rapid tap rejection (belt-and-suspenders)"

patterns-established:
  - "Animation state reset pattern: always set concrete values without animation before starting new animations"
  - "Status-based overlay visibility: include all active statuses in the condition (.requested OR .recording OR .transcribing)"

requirements-completed: [ANIM-01, ANIM-02]

duration: 4min
completed: 2026-03-11
---

# Phase 12 Plan 01: Animation State Fixes Summary

**Fix overlay visibility for .requested state, eliminate asyncAfter race conditions in AnimatedMicButton, and add 5 animation diagnostic log events**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-11T20:12:53Z
- **Completed:** 2026-03-11T20:17:19Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Recording overlay now appears immediately on mic tap by including .requested in visibility condition
- RecordingOverlay renders 3 distinct visual states: .requested (flat bars, "Demarrage...", cancel only), .recording (live waveform, timer, cancel+stop), .transcribing (shimmer)
- AnimatedMicButton eliminates asyncAfter race condition using withAnimation for success flash
- Mic button disabled during .requested/.recording/.transcribing -- rapid taps rejected
- All status transitions logged with from/to/source for diagnostics

## Task Commits

Each task was committed atomically:

1. **Task 1: Add animation log events and fix overlay visibility + RecordingOverlay .requested state** - `bc844b7` (feat)
2. **Task 2: Fix AnimatedMicButton race conditions and DictationCoordinator .requested guard** - `d990bc5` (feat)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/LogEvent.swift` - 5 new animation/watchdog log event cases with all computed properties
- `DictusKeyboard/KeyboardRootView.swift` - Overlay visibility includes .requested, onChange logger for transitions
- `DictusKeyboard/Views/RecordingOverlay.swift` - Refactored to accept dictationStatus with 3-way switch for visual states
- `DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift` - Race-safe animation transitions, .requested disable, rapid tap rejection
- `DictusApp/DictationCoordinator.swift` - startDictation guard accepts .requested, status transition logging

## Decisions Made
- Replaced asyncAfter with withAnimation for the success flash transition (SwiftUI animates the boolean change over 0.3s, no timer needed)
- Reset all animation @State properties to concrete values (pulseScale=1.0, glowOpacity=0.3, shimmerOffset=-1.0) before starting new animations to prevent stacking from repeating animations
- Used isTappable computed property for both .disabled modifier and guard inside action closure as belt-and-suspenders protection against rapid taps

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 12-02 (transcription timeout watchdog + state recovery) can build on the statusChanged and watchdogReset log events added here
- Animation state machine is now race-safe and ready for watchdog integration

---
*Phase: 12-animation-state-fixes*
*Completed: 2026-03-11*
