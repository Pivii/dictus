---
phase: 03-dictation-ux
plan: 03
subsystem: ui
tags: [swift, swiftui, keyboard, azerty, qwerty, accents, dictation]

# Dependency graph
requires:
  - phase: 03-01
    provides: "DictusCore contracts: LayoutType, QWERTYLayout, AccentedCharacters, SharedKeys"
provides:
  - "QWERTY layout switching via App Group preference in keyboard extension"
  - "Accented character long-press popup on AZERTY keys with drag-to-select"
  - "In-app test dictation screen with direct coordinator access"
affects: [04-polish-onboarding]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Long-press timer via Task.sleep with cancellation for gesture detection", "Horizontal drag-to-select accent picker overlay"]

key-files:
  created:
    - DictusKeyboard/Views/AccentPopup.swift
    - DictusApp/Views/TestDictationView.swift
  modified:
    - DictusKeyboard/Models/KeyboardLayout.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/Views/KeyButton.swift
    - DictusApp/ContentView.swift
    - Dictus.xcodeproj/project.pbxproj

key-decisions:
  - "Task 1 code was bundled into 03-02 commit (107e7fe) by the previous executor -- no separate Task 1 commit"
  - "DUX-02 (undo button) intentionally omitted per user decision"
  - "Mic keys filtered from all letter rows for forward compatibility with toolbar (Plan 03-02)"

patterns-established:
  - "Long-press accent pattern: 400ms Task.sleep timer + DragGesture tracking + AccentedCharacters lookup"
  - "Dynamic layout selection: static function reading App Group preference, returning pre-built KeyDefinition arrays"

requirements-completed: [KBD-02, KBD-03, APP-04, DUX-02]

# Metrics
duration: 61min
completed: 2026-03-06
---

# Phase 3 Plan 3: Keyboard Features & Test Dictation Summary

**QWERTY/AZERTY layout switching, French accented character long-press popups, and in-app test dictation screen**

## Performance

- **Duration:** 61 min
- **Started:** 2026-03-06T10:09:52Z
- **Completed:** 2026-03-06T11:10:60Z
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint)
- **Files modified:** 7

## Accomplishments
- KeyboardLayout supports both AZERTY (default) and QWERTY layouts, switchable via App Group preference
- KeyButton shows AccentPopup on 400ms long-press for AZERTY letters with French accented variants (e, a, u, i, o, c, y, n)
- TestDictationView provides in-app recording and transcription without URL scheme, gated on model readiness
- All 46 DictusCore tests pass, both DictusApp and DictusKeyboard targets build cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: QWERTY layout + accented character long-press popup** - `107e7fe` (feat, bundled in 03-02 commit)
2. **Task 2: In-app test dictation screen (APP-04)** - `7f91674` (feat)
3. **Task 3: Human verification** - approved by user

## Files Created/Modified
- `DictusKeyboard/Views/AccentPopup.swift` - Horizontal accent picker popup with highlighted selection
- `DictusApp/Views/TestDictationView.swift` - In-app test dictation screen with 3-state mic button and accumulated text
- `DictusKeyboard/Models/KeyboardLayout.swift` - Added QWERTY rows and currentLettersRows() dynamic selection
- `DictusKeyboard/Views/KeyboardView.swift` - Uses dynamic layout, filters out mic keys from letter rows
- `DictusKeyboard/Views/KeyButton.swift` - Added long-press timer, accent lookup, drag-to-select gesture
- `DictusApp/ContentView.swift` - Navigation link to TestDictationView when model is ready
- `Dictus.xcodeproj/project.pbxproj` - Registered AccentPopup.swift and TestDictationView.swift

## Decisions Made
- Task 1 files were already committed by the 03-02 executor in `107e7fe` (they were on disk as uncommitted work). No duplicate commit needed.
- DUX-02 (undo button) intentionally not implemented per user decision documented in plan.
- Mic keys filtered from letter rows proactively -- the toolbar (Plan 03-02) now owns the mic button.
- Exhaustive DictationStatus switch handling added to TestDictationView (including `.requested` state) to prevent compiler errors.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added missing .requested case to DictationStatus switches**
- **Found during:** Task 2 (TestDictationView implementation)
- **Issue:** DictationStatus enum has 6 cases including `.requested`, but plan only mentioned 5 states for the mic button
- **Fix:** Added `.requested` handling in micButtonColor (gray) and statusLabel ("Demarrage..."), disabled button during requested state
- **Files modified:** DictusApp/Views/TestDictationView.swift
- **Verification:** DictusApp builds cleanly with exhaustive switches
- **Committed in:** 7f91674 (Task 2 commit)

**2. [Rule 3 - Blocking] Fixed pbxproj registration for both new files**
- **Found during:** Task 1/2 (build verification)
- **Issue:** Python script for pbxproj editing partially failed -- missing PBXFileReference, PBXGroup membership, and PBXSourcesBuildPhase entries
- **Fix:** Manually added all missing entries for AccentPopup.swift and TestDictationView.swift
- **Files modified:** Dictus.xcodeproj/project.pbxproj
- **Verification:** Both targets build successfully
- **Committed in:** 7f91674 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered
- Task 1 code was already committed by 03-02 executor -- detected via `git diff HEAD` showing no changes. No re-commit needed.
- iPhone 16 simulator unavailable -- used iPhone 17 simulator instead.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 3 keyboard features complete (layout switching, accents, toolbar, recording overlay, test dictation)
- Ready for Phase 4 (polish and onboarding)
- QWERTY layout preference currently requires manual UserDefaults editing -- Phase 4 should add a settings UI

---
*Phase: 03-dictation-ux*
*Completed: 2026-03-06*
