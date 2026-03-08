---
phase: 07-keyboard-parity-visual
plan: 07
subsystem: ui
tags: [swiftui, keyboard-extension, trackpad, autocapitalisation, delete-acceleration]

requires:
  - phase: 07-keyboard-parity-visual
    provides: "SpaceKey trackpad mode, DeleteKey repeat, KeyboardView shift state"
provides:
  - "Smooth proportional trackpad cursor movement with velocity acceleration"
  - "Word-level delete acceleration after sustained hold"
  - "Autocapitalisation after sentence punctuation and empty fields"
affects: [keyboard-ux, keyboard-parity]

tech-stack:
  added: [Combine]
  patterns: [velocity-based-acceleration, word-boundary-deletion, autocapitalisation-notification]

key-files:
  created: []
  modified:
    - DictusKeyboard/Views/SpecialKeyButton.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/KeyboardViewController.swift
    - DictusKeyboard/Views/KeyRow.swift

key-decisions:
  - "Proportional vertical movement (1 char per 15pt) replaces 40-char line jumps for smooth trackpad feel"
  - "Word-level delete uses manual word boundary detection since UITextDocumentProxy lacks deleteWordBackward()"
  - "Autocap uses NotificationCenter for textDidChange bridging between UIKit controller and SwiftUI view"

patterns-established:
  - "Velocity-based acceleration curve: multiplier tiers at 10pt and 20pt thresholds"
  - "Word boundary deletion: trim trailing spaces, then delete to previous space"
  - "checkAutocapitalize pattern: only auto-shift (never auto-unshift), respect autocapitalizationType"

requirements-completed: [KBD-01, KBD-06]

duration: 4min
completed: 2026-03-08
---

# Phase 7 Plan 07: Trackpad smoothing, delete acceleration, and autocapitalisation Summary

**Smooth proportional trackpad with velocity acceleration, word-level delete after sustained hold, and autocap after sentence punctuation**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-08T12:47:52Z
- **Completed:** 2026-03-08T12:52:18Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Trackpad vertical movement is now smooth and proportional (1 char per 15pt) instead of jarring 40-char line jumps
- Both horizontal and vertical trackpad movement have velocity-based acceleration (1x/1.5x/2x multiplier)
- Delete key accelerates from character-by-character to word-level after 10 deletions with subtle haptic on each step
- Autocapitalisation activates shift after ". ", "! ", "? ", newline, and empty text fields
- Autocap respects host app autocapitalizationType (.none disables it for email/password fields)

## Task Commits

Each task was committed atomically:

1. **Task 1: Smooth trackpad acceleration and delete word-level acceleration** - `411bfab` (feat)
2. **Task 2: Autocapitalisation after sentence punctuation** - `9ee2026` (feat)

## Files Created/Modified
- `DictusKeyboard/Views/SpecialKeyButton.swift` - Smooth trackpad acceleration curve, word-level delete with counter
- `DictusKeyboard/Views/KeyboardView.swift` - Autocap logic, deleteWordBackward helper, onWordDelete callback
- `DictusKeyboard/KeyboardViewController.swift` - textDidChange notification for autocap recheck
- `DictusKeyboard/Views/KeyRow.swift` - Pass onWordDelete to DeleteKey

## Decisions Made
- Replaced 40-char vertical line jumps with proportional 1-char-per-15pt movement -- UAT found "locked to lines" feel was caused by discrete jumps
- Word-level delete implemented manually (read documentContextBeforeInput, find last space, delete to boundary) because UITextDocumentProxy has no deleteWordBackward()
- Used NotificationCenter.default for textDidChange bridging -- simplest approach for UIKit-to-SwiftUI communication within same process
- Autocap only auto-shifts (never auto-unshifts) to avoid fighting manual shift taps

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Keyboard now has smooth trackpad, accelerating delete, and autocapitalisation
- Ready for remaining gap closure plans (07-08, 07-09)

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
