---
phase: 03-dictation-ux
plan: 04
subsystem: ui
tags: [swiftui, keyboard-extension, button, callback, url-scheme]

# Dependency graph
requires:
  - phase: 03-dictation-ux (plan 02)
    provides: RecordingOverlay, ToolbarView, KeyboardState with requestStop/requestCancel
provides:
  - Mic button triggers in-keyboard recording flow instead of opening DictusApp
  - KeyboardState.startRecording() method with openURL closure injection
  - ToolbarView.onMicTap callback pattern replacing Link
affects: [phase-04-onboarding, UAT-retest]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "openURL closure injection from @Environment into non-View ObservableObject"
    - "Button callback pattern replacing Link for controlled flow"

key-files:
  created: []
  modified:
    - DictusKeyboard/KeyboardState.swift
    - DictusKeyboard/Views/ToolbarView.swift
    - DictusKeyboard/KeyboardRootView.swift

key-decisions:
  - "openURL closure injection: KeyboardState cannot access @Environment, so KeyboardRootView captures openURL and injects it via .onAppear"
  - "Revised Phase 2 Link-based approach: Button gives keyboard control over recording flow (set local state first, then trigger app)"

patterns-established:
  - "Environment-to-ObservableObject injection: capture @Environment action in View, inject into non-View class via closure property in .onAppear"

requirements-completed: [DUX-01, DUX-03]

# Metrics
duration: 3min
completed: 2026-03-06
---

# Phase 3 Plan 4: Mic Button Gap Closure Summary

**Mic button changed from Link to Button with startRecording() flow, fixing UAT blockers 2 and 3**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-06T11:38:03Z
- **Completed:** 2026-03-06T11:41:26Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Mic button in ToolbarView now uses Button with onMicTap callback instead of Link(destination:)
- KeyboardState.startRecording() sets local state to .requested (triggering overlay) before opening DictusApp
- openURL environment action injected from KeyboardRootView into KeyboardState via closure
- Full chain verified: mic tap -> startRecording -> markRequested + open dictus://dictate

## Task Commits

Each task was committed atomically:

1. **Task 1: Add startRecording() to KeyboardState and onMicTap callback to ToolbarView** - `4687800` (feat)
2. **Task 2: Wire onMicTap from KeyboardRootView through ToolbarView to KeyboardState** - `f157620` (feat)

## Files Created/Modified
- `DictusKeyboard/KeyboardState.swift` - Added openURL closure property and startRecording() method
- `DictusKeyboard/Views/ToolbarView.swift` - Replaced Link with Button, added onMicTap callback parameter
- `DictusKeyboard/KeyboardRootView.swift` - Wired @Environment(\.openURL), passes onMicTap and openURL to state

## Decisions Made
- **openURL closure injection pattern:** Since KeyboardState is an ObservableObject (not a View), it cannot use @Environment(\.openURL). The cleanest pattern is to have KeyboardRootView capture the environment action and inject it as a closure property, same as the existing controller reference pattern.
- **Revised Link to Button:** Phase 2 used Link(destination:) which bypassed keyboard control entirely. Button + callback lets the keyboard set local state first (showing the recording overlay immediately) before signaling the app to start recording.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- iPhone 16 simulator not available (only iPhone 17 on iOS 26.2) -- used iPhone 17 instead. No impact on build verification.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- UAT blockers 2 and 3 (mic button opens app instead of recording overlay) should now be resolved
- Ready for UAT re-test on physical device to confirm end-to-end flow
- Phase 4 (onboarding) can proceed independently

---
*Phase: 03-dictation-ux*
*Completed: 2026-03-06*
