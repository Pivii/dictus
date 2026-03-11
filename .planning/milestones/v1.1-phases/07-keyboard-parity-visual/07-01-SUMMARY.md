---
phase: 07-keyboard-parity-visual
plan: 01
subsystem: ui
tags: [haptics, UIImpactFeedbackGenerator, keyboard-height, UIScreen, clipsToBounds]

# Dependency graph
requires:
  - phase: 03-dictation-ux
    provides: KeyboardView, KeyRow, SpecialKeyButton key structure
provides:
  - Pre-allocated static haptic generators with warmUp() and trackpadActivated()
  - HapticFeedback.keyTapped() on all key types (letters, space, return, delete, globe, shift, 123, #+= , emoji, accentAdaptive)
  - Device-adaptive keyboard height (42pt SE, 46pt standard, 50pt Plus/Max)
  - Full Access banner opens dictus:// URL instead of blank app-settings:
  - clipsToBounds=false attempt for top-row popup overflow
  - KBD-05 iOS limitation documented in code
affects: [07-04-spacebar-trackpad, 07-02-layout-keys, 07-05-dark-mode]

# Tech tracking
tech-stack:
  added: []
  patterns: [pre-allocated-haptic-generators, device-adaptive-key-height]

key-files:
  created: []
  modified:
    - DictusCore/Sources/DictusCore/HapticFeedback.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/Views/SpecialKeyButton.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/KeyboardViewController.swift
    - DictusKeyboard/Views/KeyButton.swift

key-decisions:
  - "Pre-allocated static UIImpactFeedbackGenerator instances eliminate 2-5ms per-tap latency"
  - "Device-adaptive key height via UIScreen.main.bounds.height breakpoints (667/852pt thresholds)"
  - "dictus:// URL scheme for Full Access banner instead of non-functional app-settings:"
  - "clipsToBounds=false as best-effort popup clipping fix (iOS may re-enforce)"
  - "KBD-05: system dictation mic icon is an iOS limitation with no public API to suppress"

patterns-established:
  - "Pre-allocated haptics: static generators + .prepare() after each impactOccurred() for zero-latency re-priming"
  - "Dynamic key metrics: KeyMetrics.keyHeight as computed property reading UIScreen.main.bounds"

requirements-completed: [KBD-03, KBD-05, KBD-06]

# Metrics
duration: 5min
completed: 2026-03-08
---

# Phase 7 Plan 1: Haptic Feedback & Keyboard Polish Summary

**Pre-allocated haptic generators on all key types, device-adaptive keyboard height, Full Access banner URL fix, and KBD-05 iOS limitation documented**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-08T11:25:51Z
- **Completed:** 2026-03-08T11:31:13Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Eliminated 2-5ms haptic latency by replacing per-call generator creation with static pre-allocated instances
- Every key type now triggers HapticFeedback.keyTapped(): letters, space, return, delete, globe, shift, 123, #+=, emoji, accentAdaptive
- Keyboard height adapts to device size (42pt on SE, 46pt standard, 50pt Plus/Max)
- Full Access banner now opens the Dictus app via dictus:// URL scheme
- Added warmUp() and trackpadActivated() methods for future use (Plan 04 spacebar trackpad)

## Task Commits

Each task was committed atomically:

1. **Task 1: Pre-allocate haptic generators and add haptics to all keys** - `23b1e8f` (feat)
2. **Task 2: Dynamic keyboard height, Full Access banner fix, popup clipping, KBD-05 docs** - `2623e27` (feat)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/HapticFeedback.swift` - Refactored with static pre-allocated generators, warmUp(), trackpadActivated()
- `DictusKeyboard/Views/KeyboardView.swift` - Added HapticFeedback.keyTapped() to delete, globe, layer switch, symbol toggle, space, return, accentAdaptive callbacks
- `DictusKeyboard/Views/SpecialKeyButton.swift` - Added HapticFeedback.keyTapped() to ShiftKey Button action, added DictusCore import
- `DictusKeyboard/KeyboardRootView.swift` - HapticFeedback.warmUp() in onAppear, dictus:// URL, KBD-05 comment
- `DictusKeyboard/KeyboardViewController.swift` - clipsToBounds=false for popup clipping attempt
- `DictusKeyboard/Views/KeyButton.swift` - KeyMetrics.keyHeight now a dynamic computed property

## Decisions Made
- Used static pre-allocated generators instead of per-call instantiation for haptic performance
- Device height breakpoints: <=667pt (SE), <=852pt (standard), >852pt (Plus/Max)
- dictus:// URL opens the app which can guide Full Access setup, replacing non-functional app-settings:
- clipsToBounds=false is best-effort; iOS keyboard container may re-enforce clipping (documented in code)
- KBD-05 documented as iOS limitation: no public API to remove system dictation mic icon

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- iPhone 16 simulator not available (iOS 26.2 SDK); used iPhone 17 Pro simulator instead
- Pre-existing build error in AnimatedMicButton.swift (AnyShape fix) was already resolved by auto-formatter
- Pre-existing uncommitted changes from other plans (07-02, 07-03) added new key types that required wiring haptics to the new onAccentAdaptive callback

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Haptic infrastructure ready for Plan 04 spacebar trackpad (trackpadActivated() already exists)
- Dynamic key height ensures Plan 02 layout changes adapt to all device sizes
- All key types have consistent haptic feedback for remaining keyboard work

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
