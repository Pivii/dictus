---
phase: 01-cross-process-foundation
plan: 04
subsystem: keyboard, signaling
tags: [UIInputView, UIInputViewAudioFeedback, Darwin-notification, UserDefaults, keyboard-extension]

# Dependency graph
requires:
  - phase: 01-cross-process-foundation (plans 1-3)
    provides: "Keyboard shell, cross-process signaling, App Group infrastructure"
provides:
  - "Working keyboard click sounds on all key types"
  - "Reliable cross-process transcription display after dictation"
  - "Conditional StatusBar spinner (hidden on ready/failed)"
affects: [02-transcription-pipeline, 03-dictation-ux]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "UIInputView with .keyboard style as controller inputView for audio feedback"
    - "Single consolidated Darwin notification after all UserDefaults writes"
    - "Belt-and-suspenders: read lastTranscription in refreshFromDefaults when status is .ready"

key-files:
  created: []
  modified:
    - DictusKeyboard/InputView.swift
    - DictusKeyboard/KeyboardViewController.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/KeyboardState.swift
    - DictusApp/DictationCoordinator.swift

key-decisions:
  - "UIInputView subclass required for playInputClick — UIView with UIInputViewAudioFeedback is insufficient"
  - "Consolidated single Darwin notification eliminates race condition between status and transcription writes"
  - "Keep autoresizing masks on inputView — removing translatesAutoresizingMaskIntoConstraints breaks iOS keyboard sizing"

patterns-established:
  - "inputView must be UIInputView subclass assigned to self.inputView for system click sounds"
  - "Cross-process writes: set all UserDefaults values, synchronize once, then post notification"

requirements-completed: [KBD-01, KBD-04]

# Metrics
duration: ~45min (across two sessions with UAT checkpoint)
completed: 2026-03-05
---

# Phase 1 Plan 4: UAT Gap Closure Summary

**Fixed keyboard click sounds via UIInputView hierarchy and cross-process transcription display via notification consolidation and conditional spinner**

## Performance

- **Duration:** ~45 min (across two sessions with human verification checkpoint)
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint)
- **Files modified:** 6

## Accomplishments
- Keyboard click sounds now work on all key types (letters, space, return, delete) when Full Access and keyboard clicks are enabled
- Cross-process transcription reliably displays in keyboard after dictation completes in DictusApp
- StatusBar spinner only shows during active states (recording, transcribing), not on ready/failed
- Layout regression discovered and fixed during UAT (inputView autoresizing masks)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix keyboard click sounds** - `9a87cfb` (fix)
   - KeyboardInputView changed from UIView to UIInputView subclass
   - Assigned as self.inputView in KeyboardViewController
   - Added playInputClick() to space, return, delete handlers
2. **Task 2: Fix cross-process transcription display** - `abfc978` (fix)
   - Consolidated Darwin notifications in DictationCoordinator
   - refreshFromDefaults reads lastTranscription when status is .ready
   - StatusBar spinner conditional on active dictation states
3. **Task 3: Verify UAT fixes on device** - human checkpoint, approved by user

## Files Created/Modified
- `DictusKeyboard/InputView.swift` - Changed to UIInputView subclass with .keyboard style
- `DictusKeyboard/KeyboardViewController.swift` - Hosting view added as subview of KeyboardInputView, assigned to self.inputView
- `DictusKeyboard/Views/KeyboardView.swift` - Added playInputClick() calls to onSpace, onReturn, onDelete closures
- `DictusKeyboard/KeyboardRootView.swift` - StatusBar accepts showSpinner parameter, conditional ProgressView
- `DictusKeyboard/KeyboardState.swift` - refreshFromDefaults reads lastTranscription when status is .ready
- `DictusApp/DictationCoordinator.swift` - Single consolidated notification after both UserDefaults writes

## Decisions Made
- UIInputView subclass is required (not just UIView + UIInputViewAudioFeedback) because UIInputViewController.inputView is typed as UIInputView?
- Consolidated Darwin notification approach eliminates the race condition where keyboard reads UserDefaults between two separate notifications
- Belt-and-suspenders: refreshFromDefaults also reads lastTranscription on .ready status, ensuring data availability regardless of notification timing

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Restored full-width keyboard layout after inputView change**
- **Found during:** Task 3 (UAT verification)
- **Issue:** After changing KeyboardInputView to UIInputView subclass, setting translatesAutoresizingMaskIntoConstraints = false on the inputView prevented iOS from sizing the keyboard correctly, resulting in a narrow keyboard
- **Fix:** Removed the translatesAutoresizingMaskIntoConstraints = false line from KeyboardInputView, keeping the default autoresizing masks that iOS uses to size the inputView
- **Files modified:** DictusKeyboard/InputView.swift
- **Verification:** Keyboard displays at full screen width on device
- **Committed in:** `a2d847d`

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Essential fix discovered during UAT. The inputView sizing behavior is an iOS-specific detail not in the plan. No scope creep.

## Issues Encountered
None beyond the layout regression documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 1 is now fully complete with all UAT tests passing
- Cross-process architecture proven on device: keyboard triggers DictusApp, DictusApp writes transcription, keyboard displays result
- Ready to proceed to Phase 2 (Transcription Pipeline) with WhisperKit integration

## Self-Check: PASSED

- All 6 modified files verified on disk
- All 3 task commits verified in git history (9a87cfb, abfc978, a2d847d)

---
*Phase: 01-cross-process-foundation*
*Completed: 2026-03-05*
