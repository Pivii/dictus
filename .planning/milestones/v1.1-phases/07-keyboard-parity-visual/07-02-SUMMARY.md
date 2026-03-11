---
phase: 07-keyboard-parity-visual
plan: 02
subsystem: ui
tags: [swiftui, keyboard-extension, azerty, accent, emoji, adaptive-key]

# Dependency graph
requires:
  - phase: 03-dictation-ux
    provides: KeyButton long-press pattern, AccentPopup component, KeyboardLayout model
provides:
  - .emoji KeyType replacing .globe across all keyboard layers
  - .accentAdaptive KeyType with context-sensitive apostrophe/accent on AZERTY row 3
  - AdaptiveAccentKey view with long-press accent popup support
  - AccentedCharacters.adaptiveKeyLabel() and adaptiveKeyVowel() methods
affects: [07-keyboard-parity-visual, keyboard-extension]

# Tech tracking
tech-stack:
  added: []
  patterns: [adaptive-key-context-tracking, drag-gesture-reuse-for-accent-popup]

key-files:
  created: []
  modified:
    - DictusKeyboard/Models/KeyDefinition.swift
    - DictusKeyboard/Models/KeyboardLayout.swift
    - DictusCore/Sources/DictusCore/AccentedCharacters.swift
    - DictusKeyboard/Views/SpecialKeyButton.swift
    - DictusKeyboard/Views/KeyRow.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift

key-decisions:
  - "Apostrophe as adaptive key default -- most common non-letter char in French"
  - "Long-press only shows variants when displaying an accent, not for apostrophe"
  - "AnyShape fix for AnimatedMicButton pre-existing build error (blocking)"

patterns-established:
  - "lastTypedChar tracking: KeyboardView tracks last inserted char, passes to KeyRow for adaptive key context"
  - "DragGesture+Task.sleep accent pattern reuse: AdaptiveAccentKey copies KeyButton's long-press gesture"

requirements-completed: [KBD-02, KBD-04]

# Metrics
duration: 5min
completed: 2026-03-08
---

# Phase 7 Plan 2: Emoji & Adaptive Accent Keys Summary

**Emoji button replacing globe on all layers + context-sensitive apostrophe/accent key on AZERTY row 3 with long-press accent variants**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-08T11:25:41Z
- **Completed:** 2026-03-08T11:31:19Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Emoji key replaces globe across all 4 keyboard layers (AZERTY letters, QWERTY letters, numbers, symbols)
- Adaptive accent key on AZERTY row 3 between N and delete shows apostrophe by default, switches to most common accent after typing a vowel
- Long-press on adaptive key when showing accent opens AccentPopup with all variants for that vowel
- lastTypedChar tracking in KeyboardView resets on space, delete, return for correct accent context

## Task Commits

Each task was committed atomically:

1. **Task 1: Add emoji and adaptive accent key types, update layouts** - `5a6404e` (feat)
2. **Task 2: Create AdaptiveAccentKey view, wire into KeyRow** - `12e1c12` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `DictusKeyboard/Models/KeyDefinition.swift` - Added .emoji and .accentAdaptive to KeyType enum
- `DictusKeyboard/Models/KeyboardLayout.swift` - Updated all row 4s (emoji replaces globe), AZERTY row 3 (added accent key)
- `DictusCore/Sources/DictusCore/AccentedCharacters.swift` - Added adaptiveKeyLabel(), adaptiveKeyVowel(), defaultAccents
- `DictusKeyboard/Views/SpecialKeyButton.swift` - New EmojiKey and AdaptiveAccentKey views
- `DictusKeyboard/Views/KeyRow.swift` - Added lastTypedChar, onAccentAdaptive params, wired new key types
- `DictusKeyboard/Views/KeyboardView.swift` - lastTypedChar state tracking, reset on space/delete/return
- `DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift` - Fixed @ViewBuilder -> AnyShape build error

## Decisions Made
- Apostrophe as adaptive key default: most common non-letter character in French (l', d', n', j', c', s')
- Long-press popup only when showing accent (not apostrophe): no meaningful variants for apostrophe
- adaptiveKeyVowel() helper: returns the triggering vowel for accent variant lookup on long-press

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed AnimatedMicButton AnyShape build error**
- **Found during:** Task 1 (build verification)
- **Issue:** Pre-existing build error in AnimatedMicButton.swift -- @ViewBuilder on mainShape() returning `some Shape` wraps in _ConditionalContent which doesn't conform to Shape
- **Fix:** Changed from `@ViewBuilder private func mainShape() -> some Shape` to `private func mainShape() -> AnyShape` with explicit AnyShape wrapping
- **Files modified:** DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift
- **Verification:** Build succeeds for both DictusKeyboard and DictusApp schemes
- **Committed in:** 5a6404e (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Fix was necessary -- DictusKeyboard depends on DictusCore, so the pre-existing error blocked all builds. No scope creep.

## Issues Encountered
None beyond the AnimatedMicButton fix documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Emoji and adaptive accent keys are functional and build-verified
- Ready for Plan 03 (toolbar/toolbar mic refinements) or Plan 04 (visual polish)
- QWERTY layout correctly does NOT have the adaptive accent key (Apple convention)

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
