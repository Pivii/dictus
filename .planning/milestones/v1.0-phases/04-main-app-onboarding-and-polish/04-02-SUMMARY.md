---
phase: 04-main-app-onboarding-and-polish
plan: 02
subsystem: ui
tags: [swiftui, onboarding, settings, appstorage, avaudiosession, tabview]

# Dependency graph
requires:
  - phase: 04-main-app-onboarding-and-polish
    provides: "Design system (GlassModifier, DictusColors, BrandWaveform, AnimatedMicButton, DictusTypography), TabView structure, hasCompletedOnboarding placeholder"
provides:
  - "5-step onboarding flow (welcome, mic, keyboard, model, test)"
  - "SettingsView with 3 sections persisted via App Group"
  - "LicensesView with MIT attributions"
  - "Onboarding gate wired in DictusApp.swift"
affects: [04-03-polish, future-localization]

# Tech tracking
tech-stack:
  added: []
  patterns: ["@AppStorage with App Group suiteName for cross-process preferences", "paged TabView for multi-step wizard flows", "AVAudioSession.requestRecordPermission bridged to sync callback"]

key-files:
  created:
    - DictusApp/Onboarding/OnboardingView.swift
    - DictusApp/Onboarding/WelcomePage.swift
    - DictusApp/Onboarding/MicPermissionPage.swift
    - DictusApp/Onboarding/KeyboardSetupPage.swift
    - DictusApp/Onboarding/ModelDownloadPage.swift
    - DictusApp/Onboarding/TestRecordingPage.swift
    - DictusApp/Views/SettingsView.swift
    - DictusApp/Views/LicensesView.swift
  modified:
    - DictusApp/DictusApp.swift
    - DictusApp/Views/MainTabView.swift
    - Dictus.xcodeproj/project.pbxproj

key-decisions:
  - "Don't block onboarding on mic denial -- user can proceed and grant later"
  - "Manual keyboard detection fallback button always visible (UITextInputMode unreliable)"
  - "Pre-select whisper-small model for onboarding download (best accuracy/speed balance)"

patterns-established:
  - "Onboarding page pattern: each page receives onNext closure, manages own completion state"
  - "@AppStorage with App Group store for all user preferences"

requirements-completed: [APP-01, APP-03]

# Metrics
duration: 8min
completed: 2026-03-06
---

# Phase 4 Plan 2: Onboarding & Settings Summary

**5-step onboarding flow (welcome, mic, keyboard, model download, test recording) with iOS grouped-list Settings screen persisting preferences via App Group**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-06T22:15:30Z
- **Completed:** 2026-03-06T22:23:28Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Complete 5-step onboarding flow presented as non-dismissible fullScreenCover
- Each onboarding page validates completion before enabling advancement
- Settings screen with Transcription, Clavier, and A propos sections
- All preferences persist via @AppStorage with App Group UserDefaults
- Both targets build successfully, 52 DictusCore tests passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Onboarding flow -- 5-step guided sequence** - `2b3783e` (feat)
2. **Task 2: Settings screen with preferences persistence** - `effc017` (feat)

## Files Created/Modified
- `DictusApp/Onboarding/OnboardingView.swift` - Paged TabView container for 5 onboarding steps
- `DictusApp/Onboarding/WelcomePage.swift` - Animated BrandWaveform + wordmark + tagline
- `DictusApp/Onboarding/MicPermissionPage.swift` - Microphone permission request with grant/deny handling
- `DictusApp/Onboarding/KeyboardSetupPage.swift` - Settings deep-link + auto-detection + manual fallback
- `DictusApp/Onboarding/ModelDownloadPage.swift` - Whisper Small download with progress via ModelManager
- `DictusApp/Onboarding/TestRecordingPage.swift` - Live recording + transcription test via DictationCoordinator
- `DictusApp/Views/SettingsView.swift` - 3-section grouped List with App Group @AppStorage
- `DictusApp/Views/LicensesView.swift` - MIT license attribution for WhisperKit and Dictus
- `DictusApp/DictusApp.swift` - Wired OnboardingView, set hasCompletedOnboarding default to false
- `DictusApp/Views/MainTabView.swift` - Replaced settings placeholder with SettingsView

## Decisions Made
- Don't block onboarding on mic permission denial -- user can proceed and grant later in iOS Settings
- Manual "J'ai ajoute le clavier" button always visible as fallback (UITextInputMode auto-detection is unreliable)
- Pre-select whisper-small model for onboarding download (good accuracy/speed balance for most devices)
- SF Pro Rounded ultraLight for "dictus" wordmark instead of DM Sans (system font, no bundling needed)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Committed uncommitted keyboard Design files from Plan 04-01**
- **Found during:** Task 2 (build verification)
- **Issue:** DictusKeyboard/Design/ directory with 5 design system files existed on disk but was not committed. FullAccessBanner, KeyButton, RecordingOverlay, and ToolbarView referenced .dictusCaption, .dictusAccent, .dictusGlass() from these uncommitted files, causing build failure.
- **Fix:** Registered DictusKeyboard/Design files in pbxproj (auto-handled by project linter), committed the files.
- **Files modified:** Dictus.xcodeproj/project.pbxproj, DictusKeyboard/Design/*.swift, DictusKeyboard/Views/*.swift
- **Verification:** Build succeeds for both DictusApp and DictusKeyboard targets
- **Committed in:** effc017 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Pre-existing uncommitted files from prior plan. No scope creep.

## Issues Encountered
None beyond the deviation documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Onboarding and Settings are complete -- app is ready for first-time users
- Plan 04-03 (if any) can focus on polish and visual refinements
- The onboarding flow validates the full pipeline end-to-end before the user reaches the main app

---
*Phase: 04-main-app-onboarding-and-polish*
*Completed: 2026-03-06*

## Self-Check: PASSED
- All 8 created files verified on disk
- Both task commits (2b3783e, effc017) verified in git log
