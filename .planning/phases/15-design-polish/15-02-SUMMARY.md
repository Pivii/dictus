---
phase: 15-design-polish
plan: 02
subsystem: ui
tags: [swiftui, model-manager, swipe-to-delete, glass-ui, tap-interaction]

# Dependency graph
requires:
  - phase: 14-model-pipeline
    provides: ModelManager with selectModel, downloadModel, deleteModel, loadState
provides:
  - Tap-to-select/download model cards (no separate buttons)
  - Active model blue highlight tint
  - Swipe-to-delete on downloaded non-active cards
  - Blue-only gauge palette (Vitesse + Precision)
  - Onboarding model sync via loadState on appear
affects: [15-design-polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tap-to-act card pattern: entire card is a Button routing action by state"
    - "List with transparent styling for swipe-to-delete on glass cards"
    - "Background tint layer behind dictusGlass for active state indication"

key-files:
  created: []
  modified:
    - DictusApp/Views/ModelCardView.swift
    - DictusApp/Views/ModelManagerView.swift

key-decisions:
  - "Used List with transparent styling (not ScrollView+VStack) to enable native swipeActions"
  - "Active highlight is background tint (not border, not badge) per user decision"
  - "Removed onDelete callback from ModelCardView -- deletion handled entirely by parent swipe"

patterns-established:
  - "Tap-to-act cards: wrap card in Button with GlassPressStyle, route via handleCardTap"
  - "Swipe-to-delete: List > ForEach > .swipeActions with canDelete guard"

requirements-completed: [DSGN-02, DSGN-03, DSGN-04]

# Metrics
duration: 2min
completed: 2026-03-13
---

# Phase 15 Plan 02: Model Card UX Summary

**Tap-to-select/download model cards with active blue highlight, swipe-to-delete, blue gauge palette, and onboarding sync fix**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-13T10:37:53Z
- **Completed:** 2026-03-13T10:39:59Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Entire model card is now a single tappable surface (select, download, or retry based on state)
- Active model distinguished by subtle blue background tint (dictusAccent at 0.10 opacity)
- Swipe-to-delete on downloaded non-active cards with confirmation alert
- Vitesse gauge bar uses blue highlight instead of green (blue-only palette)
- French accent fixes applied (Recommande, Precision, Reessayer)
- Onboarding model state syncs on appear via loadState() (Bug #25 half-fix)

## Task Commits

Each task was committed atomically:

1. **Task 1: Model card redesign** - `44fd151` (feat)
2. **Task 2: Swipe-to-delete + onboarding sync** - `af4c1f7` (feat)

## Files Created/Modified
- `DictusApp/Views/ModelCardView.swift` - Full card redesign: tap interaction, active highlight, gauge colors, accent fixes
- `DictusApp/Views/ModelManagerView.swift` - Swipe-to-delete, delete guards, loadState on appear, List conversion

## Decisions Made
- Used List with transparent styling instead of ScrollView+VStack to enable native .swipeActions
- Active highlight implemented as background tint behind glass (not border, not badge) per user preference
- Removed onDelete callback from ModelCardView init -- deletion is now exclusively via swipe in parent view
- Delete alert message updated to simpler French text

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Model cards fully redesigned with new interaction model
- Ready for remaining Phase 15 plans (onboarding, settings polish)
- Bug #25 half-fixed here (loadState on appear); Plan 04 handles the other half (onboarding persist)

---
*Phase: 15-design-polish*
*Completed: 2026-03-13*
