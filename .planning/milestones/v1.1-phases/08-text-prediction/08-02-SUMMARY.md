---
phase: 08-text-prediction
plan: 02
subsystem: ui
tags: [suggestion-bar, autocorrect, undo, swiftui, keyboard-extension]

# Dependency graph
requires:
  - phase: 08-text-prediction
    plan: 01
    provides: "TextPredictionEngine, SuggestionState, FrequencyDictionary"
provides:
  - "SuggestionBarView for 3-slot suggestion display in toolbar"
  - "Autocorrect on space with undo on backspace"
  - "Keystroke-driven suggestion updates"
  - "Settings toggle for autocorrect"
affects: [08-03-prediction-polish]

# Tech tracking
tech-stack:
  added: []
  patterns: [ObservedObject for cross-view state sharing, DispatchQueue.main.async for proxy freshness]

key-files:
  created:
    - DictusKeyboard/Views/SuggestionBarView.swift
  modified:
    - DictusKeyboard/Views/ToolbarView.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusApp/Views/SettingsView.swift
    - Dictus.xcodeproj/project.pbxproj

key-decisions:
  - "Gear icon hidden during suggestions to maximize horizontal space for 3 slots"
  - "DispatchQueue.main.async for suggestion updates after keystroke to avoid stale proxy reads"
  - "Autocorrect undo stores original word and restores on immediate backspace"

patterns-established:
  - "ObservedObject pattern: KeyboardRootView owns @StateObject, KeyboardView observes via @ObservedObject"
  - "replaceCurrentWord helper: deleteBackward loop + insertText for proxy-based word replacement"

requirements-completed: [PRED-01, PRED-02, PRED-03]

# Metrics
duration: 12min
completed: 2026-03-09
---

# Phase 08 Plan 02: Suggestion Bar UI Integration Summary

**3-slot suggestion bar in toolbar with autocorrect on space, undo on backspace, accent variant taps, and settings toggle**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-09T18:34:38Z
- **Completed:** 2026-03-09T18:46:40Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- SuggestionBarView with 3 equal-width slots, bold center slot, thin dividers, and opacity transitions
- ToolbarView conditionally shows suggestion bar (hiding gear icon) or reverts to gear+mic when idle
- Every keystroke triggers SuggestionState.update(proxy:) with async delay for proxy freshness
- Autocorrect on space replaces misspelled words with frequency-ranked corrections
- Immediate backspace after autocorrect undoes correction and restores original word
- Correction automatique toggle in Settings > Clavier section (default ON)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SuggestionBarView and integrate into ToolbarView** - `14a9335` (feat)
2. **Task 2: Wire keystroke events, autocorrect, undo, and settings toggle** - `330c8d6` (feat)

## Files Created/Modified
- `DictusKeyboard/Views/SuggestionBarView.swift` - 3-slot horizontal suggestion bar with dividers and tap handlers
- `DictusKeyboard/Views/ToolbarView.swift` - Conditionally shows suggestion bar or gear icon based on suggestion state
- `DictusKeyboard/Views/KeyboardView.swift` - Keystroke forwarding to SuggestionState, autocorrect on space, undo on backspace
- `DictusKeyboard/KeyboardRootView.swift` - Owns SuggestionState, wires suggestion taps, word replacement helper
- `DictusApp/Views/SettingsView.swift` - Correction automatique toggle with AppGroup persistence
- `Dictus.xcodeproj/project.pbxproj` - SuggestionBarView added to DictusKeyboard target

## Decisions Made
- Gear icon hidden during suggestions: maximizes horizontal space for 3 suggestion slots, gear rarely needed during active typing
- DispatchQueue.main.async for suggestion updates: UITextDocumentProxy reads can be stale immediately after insertText(), deferring by one runloop tick ensures accurate context
- Autocorrect undo with AutocorrectState: stores original word, corrected word, and whether space was inserted, enabling precise restoration on immediate backspace
- @ObservedObject for KeyboardView: KeyboardRootView owns SuggestionState via @StateObject, KeyboardView observes it to avoid duplicate instances

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Xcode scheme named "DictusApp" not "Dictus" -- used correct scheme for full build verification

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Suggestion bar fully wired and visible during typing
- Autocorrect and undo functional with settings control
- Ready for Plan 03 polish (if any) or Phase 9

## Self-Check: PASSED

All 5 created/modified files verified on disk. Both task commits (14a9335, 330c8d6) verified in git log.

---
*Phase: 08-text-prediction*
*Completed: 2026-03-09*
