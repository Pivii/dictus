---
phase: 07-keyboard-parity-visual
plan: 10
subsystem: ui
tags: [swift, swiftui, keyboard, accent, azerty, special-keys]

requires:
  - phase: 07-keyboard-parity-visual
    provides: "AdaptiveAccentKey, SpecialKeyButton, KeyboardView"
provides:
  - "Case-preserving accent insertion (uppercase vowel -> uppercase accent)"
  - "Apple-matching special key colors (systemGray5)"
  - "Apple-convention shift active styling (light bg, dark icon)"
affects: []

tech-stack:
  added: []
  patterns:
    - "Case derivation from lastTypedChar rather than isShifted (avoids auto-unshift timing bug)"

key-files:
  created: []
  modified:
    - DictusCore/Sources/DictusCore/AccentedCharacters.swift
    - DictusKeyboard/Views/SpecialKeyButton.swift

key-decisions:
  - "Accent case derived from lastTypedChar not isShifted -- isShifted auto-resets after typing, losing case info"

patterns-established:
  - "Case preservation: store original character, derive case at use site from stored value"

requirements-completed: [KBD-02, KBD-04]

duration: 4min
completed: 2026-03-08
---

# Phase 7 Plan 10: Accent Uppercase, Special Key Colors, Shift Styling Summary

**Case-preserving accent key (A->A not a), systemGray5 special key backgrounds, Apple-convention shift active state**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-08T14:14:30Z
- **Completed:** 2026-03-08T14:18:36Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Accent key now respects uppercase: typing "A" then tapping accent produces "A" not "a"
- All special keys (shift, delete, return, globe, emoji, layer switch) use Color(.systemGray5) matching Apple keyboard
- Shift active state uses light background + dark icon (Apple convention), simplified foreground to unconditional Color(.label)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix accent uppercase and special key colors** - `99973f9` (feat)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/AccentedCharacters.swift` - adaptiveKeyLabel preserves original case instead of lowercasing unconditionally
- `DictusKeyboard/Views/SpecialKeyButton.swift` - displayChar removes isShifted ternary, startLongPressTimer derives case from lastTypedChar, systemGray3->systemGray5 on all special keys, shift active state colors swapped

## Decisions Made
- Accent case derived from lastTypedChar (the stored character) rather than isShifted flag, because isShifted auto-resets after typing a character (auto-unshift), making it unreliable for determining the case of the most recently typed character

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- SpecialKeyButton.swift changes were already present in HEAD (from a prior partial execution). Only AccentedCharacters.swift needed the commit.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Keyboard visual parity with Apple AZERTY is complete for accent, special keys, and shift styling
- Ready for remaining phase 7 plans

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
