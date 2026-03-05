---
phase: 02-transcription-pipeline
plan: 02
subsystem: transcription
tags: [whisperkit, filler-words, regex, model-routing, swift, tdd]

# Dependency graph
requires:
  - phase: 01-project-scaffold
    provides: DictusCore SPM package with SharedKeys and test infrastructure
provides:
  - FillerWordFilter — regex-based French + English filler word removal
  - SmartModelRouter — duration-based model selection (5s threshold)
  - ModelInfo — metadata for 5 WhisperKit model variants
  - SharedKeys extended with activeModel, modelReady, downloadedModels
affects: [02-03-transcription-integration, 03-keyboard-ux]

# Tech tracking
tech-stack:
  added: []
  patterns: [TDD red-green, NSRegularExpression with lookahead/lookbehind, pure-logic DictusCore modules]

key-files:
  created:
    - DictusCore/Sources/DictusCore/FillerWordFilter.swift
    - DictusCore/Sources/DictusCore/SmartModelRouter.swift
    - DictusCore/Sources/DictusCore/ModelInfo.swift
    - DictusCore/Tests/DictusCoreTests/FillerWordFilterTests.swift
    - DictusCore/Tests/DictusCoreTests/SmartModelRouterTests.swift
    - DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift
  modified:
    - DictusCore/Sources/DictusCore/SharedKeys.swift

key-decisions:
  - "Lookahead/lookbehind regex instead of \\b for French apostrophe safety"
  - "5-second threshold for fast vs accurate model routing"
  - "Single-model fallback always returns the only downloaded model"

patterns-established:
  - "TDD in DictusCore: write failing XCTest first, then implement pure Swift logic"
  - "NSRegularExpression with lookahead/lookbehind for French text processing"

requirements-completed: [STT-02, STT-04]

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 2 Plan 02: Transcription Quality Logic Summary

**FillerWordFilter (French + English filler removal with false-positive protection) and SmartModelRouter (5s-threshold model selection) with 24 unit tests via TDD**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T22:15:06Z
- **Completed:** 2026-03-05T22:18:34Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- FillerWordFilter removes 8 filler words (euh, hm, bah, ben, voila, um, uh, er) without corrupting French words like "humain" or "errer"
- SmartModelRouter selects fast models (tiny/base) for audio under 5s, accurate models (small+) for longer audio, with single-model fallback
- ModelInfo provides metadata for 5 WhisperKit models (tiny through large-v3-turbo)
- SharedKeys extended with activeModel, modelReady, downloadedModels for Plan 2.3 integration
- Full TDD workflow: RED commits with failing tests, then GREEN commits with implementation

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: FillerWordFilter tests** - `a3ac658` (test)
2. **Task 1 GREEN: FillerWordFilter implementation** - `01b0f95` (feat)
3. **Task 2 RED: SmartModelRouter + ModelInfo tests** - `318df19` (test)
4. **Task 2 GREEN: SmartModelRouter, ModelInfo, SharedKeys** - `62e6409` (feat)

_TDD tasks: each has RED (test) then GREEN (feat) commit._

## Files Created/Modified
- `DictusCore/Sources/DictusCore/FillerWordFilter.swift` - Regex-based filler word removal with French apostrophe safety
- `DictusCore/Sources/DictusCore/SmartModelRouter.swift` - Duration-based model selection with 5s threshold
- `DictusCore/Sources/DictusCore/ModelInfo.swift` - Metadata for 5 WhisperKit models (identifier, size, accuracy, speed)
- `DictusCore/Tests/DictusCoreTests/FillerWordFilterTests.swift` - 12 test cases for filler removal
- `DictusCore/Tests/DictusCoreTests/SmartModelRouterTests.swift` - 8 test cases for model routing
- `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` - 4 test cases for model metadata
- `DictusCore/Sources/DictusCore/SharedKeys.swift` - Added 3 model-related keys

## Decisions Made
- Used lookahead/lookbehind regex (`(?<=\s|^)` and `(?=\s|$|[,.!?;:])`) instead of `\b` word boundaries because `\b` treats apostrophes as word boundaries, which would incorrectly match filler substrings in French contractions like "l'humain"
- 5-second duration threshold based on CONTEXT.md specification: short clips need speed, longer clips benefit from accuracy
- Single-model fallback always returns the only downloaded model regardless of duration, avoiding edge case where no model is selected

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
- DictusApp full project build has a pre-existing error in untracked `DictusApp/Audio/AudioRecorder.swift` (ContiguousArray/Array type mismatch). This is not related to Plan 02-02 changes and does not affect DictusCore which builds and tests independently.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- FillerWordFilter.clean() ready to be called after WhisperKit transcription in Plan 2.3
- SmartModelRouter.selectModel() ready to route audio to correct model in Plan 2.3
- ModelInfo.all provides UI-ready model list for model manager in Plan 2.3
- SharedKeys has all keys needed for cross-process model state sharing
- All 30 DictusCore tests pass (6 existing + 24 new)

---
*Phase: 02-transcription-pipeline*
*Completed: 2026-03-05*
