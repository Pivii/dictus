---
phase: 14-model-pipeline
plan: 01
subsystem: models
tags: [whisperkit, parakeet, ram-detection, coreml, model-catalog]

# Dependency graph
requires:
  - phase: 13-cold-start-audio-bridge
    provides: Audio recording pipeline and model lifecycle
provides:
  - Large Turbo v3 removed from catalog
  - RAM-based dynamic model recommendation (ModelInfo.recommendedIdentifier)
  - Fixed prewarm progress label ("Optimisation en cours...")
  - Retry-with-cleanup on error state
affects: [14-02, onboarding, model-download]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "RAM-based model recommendation via ProcessInfo.physicalMemory in catalog layer"
    - "Catalog-level static methods for device-specific logic (not in ViewModel)"

key-files:
  created: []
  modified:
    - DictusCore/Sources/DictusCore/ModelInfo.swift
    - DictusApp/Models/ModelManager.swift
    - DictusApp/Views/ModelCardView.swift

key-decisions:
  - "Recommendation logic in ModelInfo (catalog layer), not ModelManager (state layer)"
  - "Kept badge text as 'Recommande' (short) instead of 'Recommande pour votre iPhone' (too long for pill badge)"
  - "Used DEBUG print for RAM diagnostics instead of PersistentLog (structured API has no freeform message support)"

patterns-established:
  - "Static methods on ModelInfo for device-specific catalog queries"

requirements-completed: [MODEL-01, MODEL-02, MODEL-05]

# Metrics
duration: 2min
completed: 2026-03-12
---

# Phase 14 Plan 01: Model Pipeline Catalog + UX Fixes Summary

**Removed Large Turbo v3 from catalog, added RAM-gated recommendation (Parakeet >=6GB, Small <=4GB), fixed prewarm label and retry cleanup**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-12T22:13:38Z
- **Completed:** 2026-03-12T22:15:56Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Large Turbo v3 completely removed from model catalog (prevents OOM on constrained devices)
- RAM-based recommendation: Parakeet v3 on >=6GB devices, Whisper Small on <=4GB
- Prewarm state now shows "Optimisation en cours..." with spinner instead of confusing "Optimisation..."
- Retry button on error state now cleans up corrupted files before resetting (was only resetting state)
- Removed redundant trash button from error state UI (retry now does both)

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove Large Turbo + add RAM-based recommendation to ModelInfo** - `d70d62a` (feat)
2. **Task 2: Update ModelManager + fix ModelCardView progress and retry** - `b9d2cf2` (fix)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/ModelInfo.swift` - Removed Large Turbo entry, added recommendedIdentifier() and isRecommended() static methods
- `DictusApp/Models/ModelManager.swift` - isRecommended() now delegates to ModelInfo.isRecommended()
- `DictusApp/Views/ModelCardView.swift` - Fixed prewarm label, retry calls cleanupFailedModel(), removed redundant trash button

## Decisions Made
- Kept recommendation logic in ModelInfo (catalog layer) rather than ModelManager -- accessible from both onboarding and model manager without passing ObservableObject
- Kept badge text as "Recommande" -- "Recommande pour votre iPhone" too long for a caption2 pill badge
- Used `#if DEBUG print()` for RAM diagnostics instead of PersistentLog, since PersistentLog only accepts structured LogEvent cases (no freeform messages)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] PersistentLog API incompatible with plan's suggested usage**
- **Found during:** Task 1 (RAM logging)
- **Issue:** Plan suggested `PersistentLog.log(.info, subsystem: .modelManager, message: ...)` but PersistentLog uses structured `LogEvent` enum cases, not freeform messages
- **Fix:** Used `#if DEBUG print()` for RAM diagnostics instead
- **Files modified:** DictusCore/Sources/DictusCore/ModelInfo.swift
- **Verification:** Build succeeds, RAM info printed in debug builds
- **Committed in:** d70d62a (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor logging adjustment. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Catalog cleanup and UX fixes ready for Plan 02 (Parakeet verification)
- ModelInfo.recommendedIdentifier() available for onboarding pre-selection

---
*Phase: 14-model-pipeline*
*Completed: 2026-03-12*
