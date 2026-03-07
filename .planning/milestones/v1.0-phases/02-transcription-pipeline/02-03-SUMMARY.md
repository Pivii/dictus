---
phase: 02-transcription-pipeline
plan: 03
subsystem: ui, transcription
tags: [whisperkit, swiftui, model-management, coreml, smart-routing, filler-filter]

requires:
  - phase: 02-01
    provides: "WhisperKit integration, AudioRecorder, TranscriptionService, DictationCoordinator"
  - phase: 02-02
    provides: "FillerWordFilter, SmartModelRouter, ModelInfo, SharedKeys extensions"
provides:
  - "ModelManager with full download/select/delete lifecycle and App Group persistence"
  - "ModelManagerView UI for model management"
  - "SmartModelRouter wired into DictationCoordinator for duration-based model selection"
  - "FillerWordFilter wired into TranscriptionService for automatic filler removal"
  - "modelReady flag in App Group signaling keyboard that transcription is available"
affects: [03-dictation-ux, 04-main-app]

tech-stack:
  added: []
  patterns:
    - "Serial CoreML prewarming to avoid ANE crashes"
    - "App Group model storage at containerURL/Models/"
    - "Loose coupling via SharedKeys defaults between ModelManager and DictationCoordinator"

key-files:
  created:
    - DictusApp/Models/ModelManager.swift
    - DictusApp/Views/ModelManagerView.swift
  modified:
    - DictusApp/Audio/TranscriptionService.swift
    - DictusApp/DictationCoordinator.swift
    - DictusApp/ContentView.swift
    - DictusCore/Sources/DictusCore/ModelInfo.swift
    - DictusCore/Sources/DictusCore/SmartModelRouter.swift
    - Dictus.xcodeproj/project.pbxproj

key-decisions:
  - "Serial model prewarming instead of parallel — ANE crashes when multiple CoreML compilations run concurrently"
  - "Removed large-v3-turbo from model list — ANE incompatible on many devices, no software fix possible"
  - "Added explicit delete button alongside swipe — swipe-to-delete not discoverable for most users"
  - "Double-start guard on dictus://dictate — iOS sometimes sends duplicate URL opens"

patterns-established:
  - "Serial CoreML prewarming: prewarm models one at a time to prevent ANE resource contention"
  - "Explicit delete button + swipe: dual affordance pattern for destructive actions in lists"

requirements-completed: [APP-02, STT-05]

duration: ~45min
completed: 2026-03-06
---

# Phase 2 Plan 3: Model Manager + Pipeline Integration Summary

**Model Manager UI with download/select/delete lifecycle, SmartModelRouter and FillerWordFilter wired into transcription pipeline, verified on physical device**

## Performance

- **Duration:** ~45 min (across multiple sessions including device testing)
- **Tasks:** 3/3 complete (2 auto + 1 human-verify checkpoint)
- **Files modified:** 9
- **Commits:** 6 (2 task commits + 4 bugfix commits)

## Accomplishments
- ModelManager handles full model lifecycle: download with progress, CoreML prewarming, selection, deletion with guards
- ModelManagerView shows all models with metadata (size, accuracy, speed), recommended badge, download progress, active selection
- SmartModelRouter integrated into DictationCoordinator — short audio routes to fast model, long audio to accurate model
- FillerWordFilter.clean() applied to all transcription output in TranscriptionService
- modelReady flag persisted to App Group after first model download
- Verified end-to-end on physical iPhone: model management, smart routing, filler removal, French transcription with punctuation

## Task Commits

Each task was committed atomically:

1. **Task 1: ModelManager + ModelManagerView** - `aef9d83` (feat)
2. **Task 2: Wire SmartModelRouter + FillerWordFilter into DictationCoordinator** - `1104409` (feat)
3. **Task 3: Verify full Phase 2 pipeline on device** - checkpoint approved by user

Post-checkpoint bugfixes:
- `e696ff2` (fix) - Model deletion path, double-start guard, ANE error recovery
- `bf356a7` (fix) - Serialize model prewarming to prevent ANE crashes
- `c73b8cd` (fix) - Add delete button for failed models, note UX improvements
- `9cbc243` (fix) - Remove large-v3-turbo model (ANE incompatible)

## Files Created/Modified
- `DictusApp/Models/ModelManager.swift` - Full model lifecycle manager (download, select, delete, App Group persistence)
- `DictusApp/Views/ModelManagerView.swift` - Model list UI with download progress, active selection, delete confirmation
- `DictusApp/Audio/TranscriptionService.swift` - Added FillerWordFilter integration
- `DictusApp/DictationCoordinator.swift` - Added SmartModelRouter integration, double-start guard
- `DictusApp/ContentView.swift` - Navigation to Model Manager screen
- `DictusCore/Sources/DictusCore/ModelInfo.swift` - Removed large-v3-turbo, made Identifiable
- `DictusCore/Sources/DictusCore/SmartModelRouter.swift` - Minor adjustment for model list
- `Dictus.xcodeproj/project.pbxproj` - Registered new files

## Decisions Made
- Serial model prewarming instead of parallel — ANE crashes when multiple CoreML compilations run concurrently
- Removed large-v3-turbo from available models — ANE incompatible on many devices (TextDecoder too large for Neural Engine), no software fix possible
- Added explicit delete button alongside swipe-to-delete — swipe gesture not discoverable enough
- Added double-start guard on dictus://dictate URL handling — iOS sometimes fires duplicate URL open events

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Model deletion path went one level too high**
- **Found during:** Post-checkpoint device testing
- **Issue:** `deletingLastPathComponent()` on model path removed one directory too many, failing to delete model files
- **Fix:** Corrected path calculation for model directory deletion
- **Files modified:** DictusApp/Models/ModelManager.swift
- **Committed in:** e696ff2

**2. [Rule 1 - Bug] Duplicate dictus://dictate URL caused double-start**
- **Found during:** Post-checkpoint device testing
- **Issue:** iOS sends duplicate URL open events, causing DictationCoordinator to start recording twice
- **Fix:** Added guard to ignore dictate requests while already recording/transcribing
- **Files modified:** DictusApp/DictationCoordinator.swift
- **Committed in:** e696ff2

**3. [Rule 1 - Bug] Parallel CoreML prewarming crashed ANE**
- **Found during:** Post-checkpoint device testing
- **Issue:** Prewarming multiple models concurrently caused Neural Engine resource contention and crashes
- **Fix:** Serialized prewarming — models are prewarmed one at a time in sequence
- **Files modified:** DictusApp/Models/ModelManager.swift
- **Committed in:** bf356a7

**4. [Rule 2 - Missing Critical] No delete option for failed model downloads**
- **Found during:** Post-checkpoint device testing
- **Issue:** Models stuck in error state had no way to be removed or retried
- **Fix:** Added explicit delete button visible for error-state models
- **Files modified:** DictusApp/Views/ModelManagerView.swift
- **Committed in:** c73b8cd

**5. [Rule 1 - Bug] large-v3-turbo ANE incompatibility**
- **Found during:** Post-checkpoint device testing
- **Issue:** openai_whisper-large-v3_turbo fails ANE compilation on many devices (TextDecoder.mlmodelc too large)
- **Fix:** Removed from ModelInfo.all — model is not usable on most hardware
- **Files modified:** DictusCore/Sources/DictusCore/ModelInfo.swift, DictusCoreTests/ModelInfoTests.swift
- **Committed in:** 9cbc243

---

**Total deviations:** 5 auto-fixed (3 bugs, 1 missing critical, 1 bug/incompatibility)
**Impact on plan:** All fixes necessary for correct device operation. No scope creep — all relate directly to model management and transcription pipeline correctness.

## Issues Encountered
- ANE (Apple Neural Engine) resource contention is undocumented — discovered only through on-device crashes. Serial prewarming is the safe approach.
- large-v3-turbo model incompatibility is hardware-dependent. Future version could detect device capability and show/hide models accordingly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 2 complete: full transcription pipeline from recording to clean text output
- Phase 3 can begin: keyboard preview bar, text insertion via textDocumentProxy, undo, haptics, waveform animation, layout switcher
- Known improvement for Phase 4: onboarding should guide permissions before model download

## Self-Check: PASSED

All 5 key files verified on disk. All 6 commit hashes verified in git log.

---
*Phase: 02-transcription-pipeline*
*Completed: 2026-03-06*
