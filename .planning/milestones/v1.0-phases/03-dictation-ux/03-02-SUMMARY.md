---
phase: 03-dictation-ux
plan: 02
subsystem: ui
tags: [swiftui, keyboard-extension, dictation, waveform, haptic-feedback, darwin-notifications]

# Dependency graph
requires:
  - phase: 03-01
    provides: "SharedKeys (waveformEnergy, stopRequested, cancelRequested), DarwinNotificationName (stopRecording, cancelRecording, waveformUpdate), HapticFeedback, DictationCoordinator stop/cancel observers"
provides:
  - "ToolbarView with mic button and gear icon above keyboard"
  - "RecordingOverlay replacing keyboard during active recording with waveform, timer, controls"
  - "KeyboardState.requestStop()/requestCancel() for keyboard-to-app signaling"
  - "Auto-insert transcription into active text field via textDocumentProxy"
  - "Haptic feedback on recording start, stop, and text insertion"
affects: [03-03, 04-onboarding]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Conditional view rendering (keyboard vs recording overlay) based on dictation state"
    - "weak controller reference for textDocumentProxy access from ObservableObject"
    - "JSON-decoded waveform energy from App Group UserDefaults"

key-files:
  created:
    - DictusKeyboard/Views/ToolbarView.swift
    - DictusKeyboard/Views/RecordingOverlay.swift
  modified:
    - DictusKeyboard/KeyboardState.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/Views/KeyRow.swift
    - Dictus.xcodeproj/project.pbxproj

key-decisions:
  - "Auto-insert transcription via textDocumentProxy.insertText() instead of preview banner"
  - "Conditional rendering (if/else) instead of ZStack overlay for keyboard/recording swap"
  - "weak controller reference on KeyboardState set via .onAppear to avoid retain cycles"

patterns-established:
  - "Conditional view swap: recording/transcribing states show RecordingOverlay, all others show KeyboardView"
  - "Keyboard-to-app commands: write Bool flag to UserDefaults, then post Darwin notification"

requirements-completed: [DUX-01, DUX-03, DUX-04, KBD-05]

# Metrics
duration: 61min
completed: 2026-03-06
---

# Phase 3 Plan 2: Keyboard Recording UX Summary

**Wispr Flow-inspired recording UX with toolbar mic button, immersive recording overlay replacing keyboard, waveform visualization, and auto-insert transcription via textDocumentProxy**

## Performance

- **Duration:** 61 min (including checkpoint wait)
- **Started:** 2026-03-06T10:10:09Z
- **Completed:** 2026-03-06T11:11:16Z
- **Tasks:** 3 (2 auto + 1 checkpoint)
- **Files modified:** 8

## Accomplishments
- ToolbarView with gear icon (left) and state-dependent mic button (right) -- idle/recording/transcribing visual states
- RecordingOverlay with 30-bar animated waveform, MM:SS timer, cancel/stop controls, and "Processing..." transcribing state
- KeyboardState rewritten for Phase 3: requestStop/requestCancel commands, waveform data observation at ~5Hz, auto-insert transcription directly into active text field
- KeyboardRootView restructured: toolbar always visible, conditional rendering swaps KeyboardView for RecordingOverlay during recording
- Removed Phase 1 leftovers: StatusBar, TranscriptionStub, MicKey struct
- Haptic feedback at 3 trigger points: recording start, recording stop, text insertion

## Task Commits

Each task was committed atomically:

1. **Task 1: Build ToolbarView, RecordingOverlay, and update KeyboardState** - `107e7fe` (feat)
2. **Task 2: Rewire KeyboardRootView and KeyboardView** - `741645c` (feat)
3. **Task 3: Checkpoint human-verify** - approved by user

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `DictusKeyboard/Views/ToolbarView.swift` - Toolbar with gear icon + state-dependent mic button
- `DictusKeyboard/Views/RecordingOverlay.swift` - Immersive recording UI with waveform, timer, cancel/stop
- `DictusKeyboard/KeyboardState.swift` - requestStop/requestCancel, waveform observation, auto-insert
- `DictusKeyboard/KeyboardRootView.swift` - Conditional rendering: toolbar + keyboard OR toolbar + recording overlay
- `DictusKeyboard/Views/KeyboardView.swift` - Removed MicKey struct (mic now in toolbar)
- `DictusKeyboard/Views/KeyRow.swift` - Updated .mic case to EmptyView (filtered out upstream)
- `Dictus.xcodeproj/project.pbxproj` - Added ToolbarView, RecordingOverlay; fixed missing TestDictationView ref
- `DictusKeyboard/Views/AccentPopup.swift` - Pre-existing file included in commit (from Plan 3.1 work)

## Decisions Made
- **Auto-insert via textDocumentProxy**: Transcribed text goes directly into the active text field without preview or confirmation, matching standard iOS dictation behavior
- **Conditional rendering over ZStack**: Using if/else fully removes inactive views from hierarchy, preventing ghost touches and freeing memory
- **weak controller reference**: KeyboardState holds a weak reference to UIInputViewController, set via .onAppear, to access textDocumentProxy without retain cycles
- **Shared keyboardHeight**: Both KeyboardView and RecordingOverlay use the same computed height to prevent jarring resize during state transitions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed missing TestDictationView.swift reference from pbxproj**
- **Found during:** Task 1 (build verification)
- **Issue:** project.pbxproj was externally modified to reference DictusApp/Views/TestDictationView.swift which does not exist on disk, causing build failure
- **Fix:** Removed all 4 pbxproj references (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase)
- **Files modified:** Dictus.xcodeproj/project.pbxproj
- **Verification:** xcodebuild build succeeds
- **Committed in:** 107e7fe (Task 1 commit)

**2. [Rule 3 - Blocking] Added AccentPopup.swift to Views group in pbxproj**
- **Found during:** Task 1 (project file inspection)
- **Issue:** External modification added AccentPopup.swift to Sources phase but not the PBXGroup hierarchy, causing Xcode project inconsistency
- **Fix:** Added AA100070 to Views group children
- **Files modified:** Dictus.xcodeproj/project.pbxproj
- **Verification:** xcodebuild build succeeds, file visible in Xcode navigator
- **Committed in:** 107e7fe (Task 1 commit)

**3. [Rule 3 - Blocking] Included pre-existing uncommitted Phase 3 changes**
- **Found during:** Task 1 (git status)
- **Issue:** KeyboardLayout.swift (QWERTY), KeyButton.swift (accents), KeyboardView.swift (mic filtering), AccentPopup.swift were uncommitted from Plan 3.1 work
- **Fix:** Included in Task 1 commit since they are part of Phase 3 and the build depends on them
- **Files modified:** KeyboardLayout.swift, KeyButton.swift, KeyboardView.swift, AccentPopup.swift
- **Committed in:** 107e7fe (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (3 blocking)
**Impact on plan:** All auto-fixes necessary to unblock the build. No scope creep.

## Issues Encountered
None beyond the deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Core dictation UX is complete: mic -> record -> transcribe -> auto-insert
- Plan 03-03 (accented characters + QWERTY toggle) builds on the keyboard infrastructure established here
- Phase 4 onboarding can reference the toolbar mic button as the primary interaction point

---
*Phase: 03-dictation-ux*
*Completed: 2026-03-06*
