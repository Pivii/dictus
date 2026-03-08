---
phase: 07-keyboard-parity-visual
plan: 11
subsystem: ui
tags: [audio, audiotoolbox, trackpad, cursor, keyboard-sounds, system-sounds]

requires:
  - phase: 07-keyboard-parity-visual
    provides: "SpaceKey trackpad mode, DeleteKey repeat behavior, keyboard callbacks"
provides:
  - "Line-based vertical cursor movement in trackpad mode (~40 chars per line)"
  - "3-category key sounds: letter (1104), delete (1155), modifier (1156)"
affects: [07-keyboard-parity-visual]

tech-stack:
  added: [AudioToolbox]
  patterns: [AudioServicesPlaySystemSound for differentiated key sounds, line-estimated vertical cursor heuristic]

key-files:
  created: []
  modified:
    - DictusKeyboard/Views/SpecialKeyButton.swift
    - DictusKeyboard/Views/KeyboardView.swift

key-decisions:
  - "AudioServicesPlaySystemSound over UIDevice.playInputClick for 3-category sounds"
  - "40-char line estimate for vertical cursor jumps (iPhone body text heuristic)"
  - "Delete sound played in DeleteKey (not callback) to avoid duplication"

patterns-established:
  - "KeySound enum: centralized system sound IDs for keyboard click categories"
  - "AudioToolbox import in keyboard views for system sound playback"

requirements-completed: [KBD-01, KBD-03, KBD-06]

duration: 6min
completed: 2026-03-08
---

# Phase 7 Plan 11: Trackpad Line Movement & 3-Category Key Sounds Summary

**Line-estimated vertical cursor movement (~40 chars/line) and AudioToolbox-based 3-category key sounds (letter/delete/modifier)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-08T14:14:27Z
- **Completed:** 2026-03-08T14:20:33Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Vertical trackpad drag now moves cursor by estimated line widths (~40 characters per ~40pt of vertical drag) instead of single characters
- Key sounds differentiated into 3 categories matching Apple's native keyboard: letters (1104), delete (1155), modifier (1156)
- AudioToolbox imported for system sound playback; respects ringer/silent switch automatically

## Task Commits

Each task was committed atomically:

1. **Task 1: Improve trackpad vertical cursor movement** - `effdffc` (feat - bundled with concurrent linter commit)
2. **Task 2: Differentiate key sounds into 3 categories** - `c02b4b5` (feat)

**Bug fix:** `6447b90` (fix: remove duplicate delete sound from callbacks)

## Files Created/Modified
- `DictusKeyboard/Views/SpecialKeyButton.swift` - Line-based vertical trackpad movement, AudioToolbox import, delete/shift sounds
- `DictusKeyboard/Views/KeyboardView.swift` - KeySound enum, AudioServicesPlaySystemSound for all key categories

## Decisions Made
- AudioServicesPlaySystemSound chosen over UIDevice.playInputClick because playInputClick produces only one sound for all keys, while system sound IDs 1104/1155/1156 match Apple's 3-category differentiation
- 40 characters per line is a heuristic for iPhone body text in Messages/Notes; UITextDocumentProxy has no line-width API
- Delete sound placed in DeleteKey view (not in KeyboardView callbacks) since DeleteKey manages its own haptic+sound per tap/repeat

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed double delete sound**
- **Found during:** Task 2 (key sounds implementation)
- **Issue:** Delete sound was being played both in KeyboardView's onDelete callback AND in DeleteKey's DragGesture handler, causing duplicate clicks
- **Fix:** Removed AudioServicesPlaySystemSound from KeyboardView's onDelete/onWordDelete callbacks, keeping it only in DeleteKey
- **Files modified:** DictusKeyboard/Views/KeyboardView.swift
- **Verification:** Build succeeded
- **Committed in:** 6447b90

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential for correct audio behavior. No scope creep.

## Issues Encountered
- Task 1 commit was bundled with a concurrent linter commit (effdffc) that modified the same file; changes verified present in that commit

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Trackpad and key sound gaps closed
- Ready for remaining phase 07 plans

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
