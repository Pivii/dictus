---
phase: 15-design-polish
plan: 06
subsystem: ui
tags: [swiftui, model-cards, progress-bar, glass-design, list-sections]

requires:
  - phase: 15-design-polish
    provides: "Model card layout with gauges, glass styling, swipe-to-delete"
provides:
  - "Polished model card UX: border highlight, full-width progress, tap area, scrolling headers"
  - "Model state sync between onboarding and model manager"
  - "Correct model name display without engine prefix"
affects: [model-manager, home-screen, onboarding-sync]

tech-stack:
  added: []
  patterns: ["inline section headers for non-sticky scrolling", "contentShape for full card tap area"]

key-files:
  created: []
  modified:
    - DictusApp/Views/ModelCardView.swift
    - DictusApp/Views/ModelManagerView.swift
    - DictusApp/Views/HomeView.swift
    - DictusApp/Models/ModelManager.swift

key-decisions:
  - "Inline Text rows as section headers (not Section header: parameter) to prevent sticky behavior"
  - "Engine descriptions consolidated into single footer section instead of per-section duplicates"
  - "300ms spinner delay on model switch for visible feedback on near-instant operation"

patterns-established:
  - "Non-sticky headers: Use inline Text rows inside Section body, not header: parameter"
  - "Active item highlight: Border stroke overlay on glass, not background tint"

requirements-completed: [DSGN-02, DSGN-03]

duration: 4min
completed: 2026-03-13
---

# Phase 15 Plan 06: Model Card UX Polish Summary

**Full-width download progress replacing gauges, dark blue active border, scrolling section headers, and state sync for onboarding-downloaded models**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-13T12:11:21Z
- **Completed:** 2026-03-13T12:15:40Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Active model indicated by dark blue border stroke (no background tint, no green checkmark)
- Full-width progress bar replaces gauge bars during download/prewarming
- Card tap area covers entire surface via contentShape(Rectangle())
- Press animation more visible (0.95 scale instead of 0.97)
- Model switch shows brief loading spinner
- Swipe-to-delete button renders red
- Downloading models move immediately to Downloaded section
- Home screen shows correct model name without "Whisper" prefix for Parakeet models
- Model state syncs correctly after onboarding (no stale download icon)
- Section headers scroll with content (not sticky)
- Engine descriptions consolidated as fixed footer at bottom of model list

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix model card visuals** - `bc51fff` (feat)
2. **Task 2: Move downloading models to Downloaded section** - `b613e4e` (feat)
3. **Task 3: Fix model name, state sync, footer, headers** - `16baad7` (feat)

## Files Created/Modified
- `DictusApp/Views/ModelCardView.swift` - Active border overlay, full-width progress, contentShape, isSwitching spinner, 0.95 press scale
- `DictusApp/Views/ModelManagerView.swift` - State-aware section filters, inline scrolling headers, red swipe tint, consolidated footer descriptions
- `DictusApp/Views/HomeView.swift` - Removed "Whisper" prefix from model name display
- `DictusApp/Models/ModelManager.swift` - loadState() resyncs modelStates for onboarding-downloaded models

## Decisions Made
- Inline Text rows as section headers instead of Section header: parameter to avoid iOS sticky header behavior
- Engine descriptions consolidated into single footer section (was duplicated per section)
- 300ms spinner delay on model switch provides visible feedback for near-instant operation
- Active border uses overlay (after .dictusGlass()) so stroke renders on top of glass material

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Build destination changed from "iPhone 16 Pro" to "iPhone 17 Pro" (simulator not available) - resolved by using available simulator.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 11 must-have truths from UAT tests 5, 6, 7, 12, 14, 15, 16 addressed
- Model card UX polished and ready for next gap closure plans (15-07, 15-08)

---
*Phase: 15-design-polish*
*Completed: 2026-03-13*
