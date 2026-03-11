---
phase: 06-infrastructure-app-polish
plan: 02
subsystem: ui
tags: [swiftui, homeview, modelinfo, navigation]

requires:
  - phase: 06-01
    provides: Design tokens and DictusCore public extensions
provides:
  - Clean HomeView without duplicate navigation title
  - Human-readable model display using ModelInfo lookup
  - Stale state fix via onAppear loadState refresh
affects: []

tech-stack:
  added: []
  patterns: [ModelInfo.forIdentifier for display-name resolution, onAppear state refresh for cross-instance sync]

key-files:
  created: []
  modified: [DictusApp/Views/HomeView.swift]

key-decisions:
  - "Used onAppear loadState() rather than shared singleton to fix stale model state after onboarding"
  - "Prefixed display name with 'Whisper' (e.g. 'Whisper Small') for brand clarity"

patterns-established:
  - "ModelInfo.forIdentifier pattern: always use ModelInfo lookup for user-facing model names instead of raw identifiers"

requirements-completed: [VIS-06, VIS-07]

duration: 1min
completed: 2026-03-07
---

# Phase 6 Plan 2: HomeView Visual Fixes Summary

**Removed duplicate navigation title and fixed model card to show human-readable name/size via ModelInfo.forIdentifier with onAppear state refresh**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-07T21:08:37Z
- **Completed:** 2026-03-07T21:09:25Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Removed `.navigationTitle("Dictus")` that created a duplicate white title bar above the logo section
- Model card now shows "Whisper Small" + "~250 MB" instead of raw "openai_whisper-small" identifier
- Added `.onAppear { modelManager.loadState() }` to fix stale state after onboarding completes

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove duplicate navigation title and fix model card display** - `c128552` (fix)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `DictusApp/Views/HomeView.swift` - Removed nav title, added ModelInfo lookup for display name/size, added onAppear state refresh

## Decisions Made
- Used `onAppear { modelManager.loadState() }` rather than converting to a shared singleton -- simpler fix that addresses the root cause (separate ModelManager instances in onboarding vs home)
- Prefixed model display name with "Whisper" (e.g. "Whisper Small") for brand clarity since ModelInfo.displayName is just "Small"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- HomeView visual bugs resolved, ready for Plan 03 (keyboard auto-detection)
- No blockers

---
*Phase: 06-infrastructure-app-polish*
*Completed: 2026-03-07*
