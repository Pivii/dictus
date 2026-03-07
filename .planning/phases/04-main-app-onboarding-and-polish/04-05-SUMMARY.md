---
phase: 04-main-app-onboarding-and-polish
plan: 05
subsystem: ui
tags: [keyboard, swiftui, waveform, dynamic-type, layout]

requires:
  - phase: 04-main-app-onboarding-and-polish
    provides: Design system, BrandWaveform, keyboard recording overlay
provides:
  - Native-feeling keyboard with 46pt keys and no Dynamic Type overflow
  - Layout-stable recording overlay covering full toolbar+keyboard area
  - Readable FullAccessBanner with dictus:// URL scheme
  - Large, fast, light-mode-safe waveform visualization
affects: []

tech-stack:
  added: []
  patterns:
    - "Fixed font sizes for keyboard keys (no @ScaledMetric) matching native iOS"
    - "RecordingOverlay covers full toolbar+keyboard height to prevent layout shift"

key-files:
  created: []
  modified:
    - DictusKeyboard/Views/KeyButton.swift
    - DictusKeyboard/KeyboardViewController.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/Views/FullAccessBanner.swift
    - DictusKeyboard/Views/RecordingOverlay.swift
    - DictusKeyboard/Design/BrandWaveform.swift

key-decisions:
  - "Fixed key font sizes (let vs @ScaledMetric) to match native iOS keyboard behavior"
  - "computeKeyboardHeight reads KeyMetrics constants instead of hardcoded values"
  - "dictus:// URL in FullAccessBanner instead of app-settings: which opens blank page"

patterns-established:
  - "Keyboard key labels use fixed sizes like native iOS keyboard"
  - "RecordingOverlay height = toolbarHeight + keyboardHeight for zero layout shift"

requirements-completed: [KBD-06, DSN-02, DSN-03]

duration: 3min
completed: 2026-03-07
---

# Phase 4 Plan 5: Keyboard UAT Gap Closure Summary

**Fixed 6 keyboard UAT issues: key sizing (46pt), Dynamic Type overflow, layout shift on recording, FullAccessBanner readability, waveform sizing (140pt/40 bars), and light mode bar colors**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-07T08:14:45Z
- **Completed:** 2026-03-07T08:17:51Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Key height increased to 46pt matching native iOS keyboard, font sizes fixed (no @ScaledMetric)
- Recording overlay covers full toolbar+keyboard area, eliminating layout shift on mic tap
- FullAccessBanner enlarged with .footnote font, 10pt padding, and dictus:// URL
- Waveform enlarged to 140pt height, 40 bars at 5pt width, 0.08s animation, gray bars in light mode

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix keyboard sizing, layout shift, Dynamic Type, and FullAccessBanner** - `eea360e` (fix)
2. **Task 2: Enlarge keyboard waveform and fix light mode colors** - `cbbf57f` (fix)

## Files Created/Modified
- `DictusKeyboard/Views/KeyButton.swift` - keyHeight 46pt, fixed font sizes
- `DictusKeyboard/KeyboardViewController.swift` - computeKeyboardHeight uses KeyMetrics constants
- `DictusKeyboard/KeyboardRootView.swift` - RecordingOverlay frame = totalContentHeight
- `DictusKeyboard/Views/FullAccessBanner.swift` - .footnote font, 10pt padding, dictus:// URL
- `DictusKeyboard/Views/RecordingOverlay.swift` - maxHeight 140pt, reduced horizontal padding
- `DictusKeyboard/Design/BrandWaveform.swift` - 40 bars, 5pt width, 0.08s animation, fixed let barWidth

## Decisions Made
- Fixed key font sizes (plain `let` instead of `@ScaledMetric`) to match native iOS keyboard -- native keyboard does not scale key labels with Dynamic Type
- Changed `computeKeyboardHeight` to read `KeyMetrics.keyHeight` and `KeyMetrics.rowSpacing` directly instead of hardcoded values, preventing future drift
- Used `dictus://settings` URL in FullAccessBanner instead of `app-settings:` which opens a blank iOS Settings page

## Deviations from Plan

None - plan executed exactly as written. Light mode bar color fix (gray instead of white) was already present from a prior plan (04-03).

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 6 UAT gaps from Tests 8, 9, and 10 are resolved
- Keyboard matches native iOS feel with proper key sizing and stable recording transitions

---
*Phase: 04-main-app-onboarding-and-polish*
*Completed: 2026-03-07*
