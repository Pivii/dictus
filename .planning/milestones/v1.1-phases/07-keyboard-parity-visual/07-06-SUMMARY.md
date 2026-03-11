---
phase: 07-keyboard-parity-visual
plan: 06
subsystem: ui
tags: [swift, swiftui, sf-symbols, keyboard-extension, azerty, accented-characters]

requires:
  - phase: 07-keyboard-parity-visual
    provides: "Adaptive accent key, special keys (Plan 02), keyboard layout"
provides:
  - "Accent key replacement behavior (vowel replaced, not doubled)"
  - "SF Symbol icons for delete, return, emoji keys"
  - "AccentedCharacters.shouldReplace() helper"
affects: [08-testing, uat]

tech-stack:
  added: []
  patterns: ["deleteBackward+insert pattern for character replacement in keyboard extension"]

key-files:
  created: []
  modified:
    - DictusCore/Sources/DictusCore/AccentedCharacters.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/Views/SpecialKeyButton.swift

key-decisions:
  - "Replacement logic lives in KeyboardView onAccentAdaptive handler, not in AdaptiveAccentKey -- keeps callback signature simple"
  - "SF Symbol face.smiling for emoji key matches Apple native AZERTY visual style"

patterns-established:
  - "deleteBackward+insert: to replace a character in keyboard extension, call proxy.deleteBackward() then insertText()"

requirements-completed: [KBD-02, KBD-04]

duration: 4min
completed: 2026-03-08
---

# Phase 7 Plan 6: Accent Key Fix & SF Symbol Icons Summary

**Accent key now replaces previous vowel instead of doubling it, plus delete/return/emoji keys use Apple SF Symbols**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-08T12:47:50Z
- **Completed:** 2026-03-08T12:51:34Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- Fixed accent key replacement: typing "e" then tapping accent now produces "e" (not "ee")
- Added AccentedCharacters.shouldReplace() to detect when replacement is needed vs apostrophe insertion
- Updated DeleteKey SF Symbol from delete.left.fill to delete.backward (Apple standard)
- Updated ReturnKey from text "retour" to SF Symbol return.left icon
- Updated EmojiKey from emoji character to SF Symbol face.smiling

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix accent key replacement and add SF Symbol icons** - `4a314f2` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/AccentedCharacters.swift` - Added shouldReplace() helper method
- `DictusKeyboard/Views/KeyboardView.swift` - onAccentAdaptive now calls deleteBackward() before insert when replacing vowel
- `DictusKeyboard/Views/SpecialKeyButton.swift` - DeleteKey, ReturnKey, EmojiKey updated to SF Symbols

## Decisions Made
- Replacement logic kept in KeyboardView's onAccentAdaptive handler rather than changing AdaptiveAccentKey's onTap signature -- both normal tap and long-press selection flow through the same handler, which already knows lastTypedChar
- Used face.smiling SF Symbol for emoji key to match Apple's native AZERTY keyboard appearance

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All keyboard parity fixes for Phase 07 complete
- Ready for UAT validation of accent replacement and SF Symbol icons

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
