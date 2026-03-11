---
phase: 06-infrastructure-app-polish
plan: 03
subsystem: ui
tags: [swiftui, onboarding, recording, haptics, auto-detection]

requires:
  - phase: 06-01
    provides: DictusCore design components (AnimatedMicButton, BrandWaveform, ProcessingAnimation, HapticFeedback)
provides:
  - Shared immersive RecordingView used from onboarding and HomeView
  - Swipe-blocked onboarding with programmatic step advancement
  - Auto-detecting keyboard setup page (UITextInputMode)
  - Improved model download UX with clear French copy
affects: [06-infrastructure-app-polish]

tech-stack:
  added: []
  patterns: [shared-view-with-mode-enum, auto-detection-on-foreground]

key-files:
  created: []
  modified:
    - DictusApp/Views/RecordingView.swift
    - DictusApp/Onboarding/TestRecordingPage.swift
    - DictusApp/Views/TestDictationView.swift
    - DictusApp/Views/MainTabView.swift
    - DictusApp/Onboarding/OnboardingView.swift
    - DictusApp/Onboarding/ModelDownloadPage.swift
    - DictusApp/Onboarding/KeyboardSetupPage.swift

key-decisions:
  - "RecordingMode enum (.onboarding/.standalone) controls post-transcription buttons"
  - "Used HapticFeedback.recordingStarted/recordingStopped instead of generic impact"
  - "switch/case with .id(currentPage) for proper SwiftUI transition animations"
  - "Auto-advance after 0.5s delay on keyboard detection to show checkmark feedback"

patterns-established:
  - "Shared view with mode enum: single view serves multiple contexts via mode parameter"
  - "Auto-detection on foreground: .onChange(of: scenePhase) + .onAppear for detection"

requirements-completed: [VIS-04, VIS-05, VIS-08]

duration: 4min
completed: 2026-03-07
---

# Phase 6 Plan 3: Onboarding & Recording UX Summary

**Immersive Voice Memos-style RecordingView shared between onboarding and HomeView, with swipe-blocked onboarding, keyboard auto-detection, and improved model download UX**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-07T21:08:29Z
- **Completed:** 2026-03-07T21:15:00Z
- **Tasks:** 3/3 (2 auto + 1 checkpoint approved)
- **Files modified:** 7

## Accomplishments
- Rewrote RecordingView as immersive screen with centered mic button, ambient waveform at 30% opacity, and fade-to-text transcription
- Added RecordingMode enum so the same view serves onboarding (Terminer button) and standalone (Nouvelle dictee + Terminer)
- Replaced TabView paging with switch/case to block swiping between onboarding steps
- Added step indicator dots and slide transitions for onboarding navigation
- Removed manual keyboard confirm button; auto-detects via UITextInputMode.activeInputModes on foreground return
- Reworded model download page with clearer French copy; removed auto-advance

## Task Commits

Each task was committed atomically:

1. **Task 1: Create shared RecordingView and rewire both consumers** - `b1622ae` (feat)
2. **Task 2: Fix onboarding blocking, keyboard auto-detection, and model download UX** - `d3d909f` (feat)
3. **Task 3: Verify onboarding flow and recording screen** - APPROVED (checkpoint:human-verify)

## Files Created/Modified
- `DictusApp/Views/RecordingView.swift` - Immersive recording screen with mode enum, haptics, waveform-to-text fade
- `DictusApp/Onboarding/TestRecordingPage.swift` - Thin wrapper: RecordingView(mode: .onboarding)
- `DictusApp/Views/TestDictationView.swift` - Thin wrapper: RecordingView(mode: .standalone)
- `DictusApp/Views/MainTabView.swift` - Updated overlay to pass mode: .standalone
- `DictusApp/Onboarding/OnboardingView.swift` - switch/case replacing TabView, step dots, slide transitions
- `DictusApp/Onboarding/ModelDownloadPage.swift` - Reworded UX, removed auto-advance
- `DictusApp/Onboarding/KeyboardSetupPage.swift` - Auto-detection, removed manual confirm button

## Decisions Made
- Used HapticFeedback.recordingStarted()/recordingStopped() (existing API) instead of generic HapticFeedback.impact(.medium) referenced in plan
- Fixed MainTabView.swift overlay (deviation Rule 3) — it also used RecordingView and needed the new mode parameter
- Used .id(currentPage) on the Group to force SwiftUI to treat each onboarding page as unique for proper slide transitions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed MainTabView RecordingView call**
- **Found during:** Task 1 (Build verification)
- **Issue:** MainTabView.swift also instantiates RecordingView as a full-screen overlay. Adding the required `mode` parameter broke this call site.
- **Fix:** Added `mode: .standalone` to the RecordingView call in MainTabView
- **Files modified:** DictusApp/Views/MainTabView.swift
- **Verification:** Build succeeds
- **Committed in:** b1622ae (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix for compilation. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 6 complete -- all 3 plans executed and verified
- DictusCore shared design package available for all subsequent phases
- App icon, HomeView fixes, onboarding flow, and recording UX all polished
- Ready for Phase 7 (Keyboard Parity & Visual) which depends on Phase 6 infrastructure

## Self-Check: PASSED

- All 6 modified files exist on disk
- Commits b1622ae and d3d909f verified in git history

---
*Phase: 06-infrastructure-app-polish*
*Completed: 2026-03-07*
