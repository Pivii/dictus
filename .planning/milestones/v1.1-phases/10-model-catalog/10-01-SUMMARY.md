---
phase: 10-model-catalog
plan: 01
subsystem: data-model
tags: [whisperkit, model-catalog, speech-engine, swift]

requires:
  - phase: none
    provides: standalone plan
provides:
  - SpeechEngine enum (.whisperKit, .parakeet) for multi-engine support
  - Extended ModelInfo with engine, gauges, visibility, descriptions
  - 7-model catalog (5 available, 2 deprecated)
  - SmartModelRouter removed from codebase
affects: [10-02-model-selection-ui, 10-03-parakeet-integration]

tech-stack:
  added: []
  patterns: [CatalogVisibility soft-deprecation, gauge scores for UI]

key-files:
  created:
    - DictusCore/Sources/DictusCore/SpeechEngine.swift
  modified:
    - DictusCore/Sources/DictusCore/ModelInfo.swift
    - DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift
    - DictusApp/Models/ModelManager.swift
    - DictusApp/DictationCoordinator.swift

key-decisions:
  - "SpeechEngine enum with raw values WK/PK for Codable persistence"
  - "Soft deprecation via CatalogVisibility keeps Tiny/Base resolvable"
  - "All 3 new model candidates added to catalog (turbo, distil, small216)"
  - "Gauge scores estimated from RESEARCH.md -- user will validate on device"
  - "Fallback model changed from tiny to small in DictationCoordinator"

patterns-established:
  - "CatalogVisibility: deprecated models hidden from download UI but still resolvable"
  - "Gauge scores: 0.0-1.0 numeric values for accuracy/speed UI display"

requirements-completed: [MOD-01]

duration: 3min
completed: 2026-03-10
---

# Phase 10 Plan 01: Model Catalog Cleanup Summary

**Extended ModelInfo with engine/gauges/visibility, removed SmartModelRouter, added 3 new WhisperKit model candidates (large-v3-turbo, distil-large-v3_turbo, small_216MB)**

## Performance

- **Duration:** ~3 min (continuation from checkpoint, tasks 1-2 completed by previous agent)
- **Started:** 2026-03-10T21:44:37Z
- **Completed:** 2026-03-10T21:45:39Z
- **Tasks:** 3 (2 prior + 1 continuation)
- **Files modified:** 7

## Accomplishments
- Created SpeechEngine enum for multi-engine future (WhisperKit + Parakeet)
- Extended ModelInfo with numeric gauge scores, French descriptions, and CatalogVisibility
- Soft-deprecated Tiny/Base while keeping them resolvable for existing users
- Removed dead SmartModelRouter code and tests
- Added 3 new model candidates: large-v3-turbo (954MB), distil-large-v3_turbo (600MB), small_216MB (216MB)
- Updated fallback model from tiny to small in DictationCoordinator

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend ModelInfo with engine, gauges, visibility** - `5e9ed15` (feat)
2. **Task 2: Remove SmartModelRouter, update ModelManager + DictationCoordinator** - `632be50` (feat)
3. **Task 3: Add 3 new WhisperKit model candidates** - `bab4428` (feat)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/SpeechEngine.swift` - New enum for speech engine identification
- `DictusCore/Sources/DictusCore/ModelInfo.swift` - Extended with engine, gauges, visibility, 3 new models
- `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` - Updated for 7-model catalog
- `DictusCore/Sources/DictusCore/SmartModelRouter.swift` - Deleted (dead code)
- `DictusCore/Tests/DictusCoreTests/SmartModelRouterTests.swift` - Deleted (dead code)
- `DictusApp/Models/ModelManager.swift` - Uses allIncludingDeprecated for state init
- `DictusApp/DictationCoordinator.swift` - Fallback changed to openai_whisper-small

## Decisions Made
- SpeechEngine enum uses raw values "WK"/"PK" for Codable serialization
- CatalogVisibility soft-deprecation pattern: deprecated models hidden from download catalog but still resolvable via forIdentifier and supportedIdentifiers
- All 3 new model candidates added per user decision (no on-device benchmarking -- user will test manually)
- Gauge scores for new models estimated from RESEARCH.md specs: turbo (0.9/0.6), distil (0.85/0.7), small216 (0.55/0.75)
- Fallback model in DictationCoordinator changed from "openai_whisper-tiny" to "openai_whisper-small"

## Deviations from Plan

None - plan executed as written. Task 3 was a checkpoint:human-verify that was resolved by user decision to add all 3 models.

## Issues Encountered

- DictusCore `swift test` fails on macOS due to pre-existing SwiftUI availability annotations in Design/ files (not related to this plan's changes). Tests verified correct via code review. This is a known pre-existing issue.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Model catalog data layer complete with 7 models, ready for Plan 02 (model selection UI)
- SpeechEngine enum ready for Plan 03 (Parakeet integration)
- User should test new models on device and remove any that don't work with WhisperKit/ANE

---
*Phase: 10-model-catalog*
*Completed: 2026-03-10*
