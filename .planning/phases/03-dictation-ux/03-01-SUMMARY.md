---
phase: 03-dictation-ux
plan: 01
subsystem: core
tags: [darwin-notifications, app-group, qwerty, azerty, accented-characters, haptic-feedback, waveform]

# Dependency graph
requires:
  - phase: 02-transcription
    provides: DictationCoordinator with recording + transcription pipeline, SharedKeys, DarwinNotifications
provides:
  - Cross-process stop/cancel contracts (keyboard -> app via Darwin notifications)
  - Waveform energy forwarding (app -> keyboard via App Group at ~5Hz)
  - QWERTY layout data and LayoutType enum for keyboard extension
  - Accented character mappings for French long-press popups
  - HapticFeedback helper with three distinct patterns
affects: [03-02-keyboard-recording-ui, 03-03-accented-chars]

# Tech tracking
tech-stack:
  added: []
  patterns: [throttled-app-group-writes, darwin-notification-signal-with-flag-pattern, canImport-guard-for-spm-tests]

key-files:
  created:
    - DictusCore/Sources/DictusCore/KeyboardLayoutData.swift
    - DictusCore/Sources/DictusCore/AccentedCharacters.swift
    - DictusCore/Sources/DictusCore/HapticFeedback.swift
    - DictusCore/Tests/DictusCoreTests/QWERTYLayoutTests.swift
    - DictusCore/Tests/DictusCoreTests/AccentedCharacterTests.swift
  modified:
    - DictusCore/Sources/DictusCore/SharedKeys.swift
    - DictusCore/Sources/DictusCore/DarwinNotifications.swift
    - DictusApp/DictationCoordinator.swift
    - DictusApp/Info.plist

key-decisions:
  - "Use #if canImport(UIKit) for HapticFeedback to allow macOS SPM test runs"
  - "Throttle waveform App Group writes to 5Hz (200ms interval) to avoid excessive disk I/O"
  - "Store QWERTY layout as raw string arrays in DictusCore, not KeyDefinition (which is keyboard-only)"
  - "Use precomposed Unicode characters for accented mappings, not combining characters"
  - "Audio background mode required so DictusApp continues recording when user returns to their app"

patterns-established:
  - "Darwin notification + Bool flag pattern for keyboard -> app signaling"
  - "Throttled App Group forwarding pattern for high-frequency data (waveform)"
  - "canImport guard for UIKit-dependent code in shared SPM packages"

requirements-completed: [KBD-03, KBD-02, DUX-03]

# Metrics
duration: 4min
completed: 2026-03-06
---

# Phase 3 Plan 1: Cross-Process Contracts Summary

**Extended DictusCore with keyboard-app stop/cancel signals, waveform forwarding at 5Hz, QWERTY layout data, French accented character mappings, and haptic feedback helpers -- all tested with 16 new unit tests**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-06T10:02:30Z
- **Completed:** 2026-03-06T10:06:30Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- 5 new SharedKeys and 3 new Darwin notification names establishing cross-process contracts
- DictationCoordinator observes keyboard stop/cancel signals and forwards waveform energy to App Group at ~5Hz
- QWERTY layout data and LayoutType enum ready for keyboard consumption
- French accented character mappings (8 base letters, all precomposed Unicode) with case-insensitive lookup
- HapticFeedback helper with 3 distinct patterns (recordingStarted, recordingStopped, textInserted)
- 16 new unit tests (6 QWERTY + 10 accented characters), all 46 DictusCore tests passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend DictusCore contracts and create QWERTY/accent data with tests** - `cee4871` (feat, TDD)
2. **Task 2: Wire DictationCoordinator to observe keyboard stop/cancel and forward waveform energy** - `30a5496` (feat)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/SharedKeys.swift` - Added 5 new cross-process keys
- `DictusCore/Sources/DictusCore/DarwinNotifications.swift` - Added 3 new notification names
- `DictusCore/Sources/DictusCore/KeyboardLayoutData.swift` - NEW: QWERTY layout rows and LayoutType enum
- `DictusCore/Sources/DictusCore/AccentedCharacters.swift` - NEW: French accented character mappings
- `DictusCore/Sources/DictusCore/HapticFeedback.swift` - NEW: Haptic feedback helpers with canImport guard
- `DictusCore/Tests/DictusCoreTests/QWERTYLayoutTests.swift` - NEW: 6 tests for QWERTY layout structure
- `DictusCore/Tests/DictusCoreTests/AccentedCharacterTests.swift` - NEW: 10 tests for accented character mappings
- `DictusApp/DictationCoordinator.swift` - Added stop/cancel observers, waveform forwarding, cancelDictation()
- `DictusApp/Info.plist` - Added UIBackgroundModes audio for background recording

## Decisions Made
- Used `#if canImport(UIKit)` guard for HapticFeedback.swift because DictusCore is an SPM package that compiles on macOS for `swift test`, where UIKit is not available
- Throttled waveform App Group writes to ~5Hz (200ms interval) using a timestamp check -- AudioRecorder publishes at ~60Hz but that would overwhelm UserDefaults cross-process
- Stored QWERTY layout as `[[String]]` not `[KeyDefinition]` because KeyDefinition is a keyboard-only UI type that shouldn't leak into the shared framework
- Used precomposed Unicode (e.g., `\u{00E9}`) not combining characters (e.g., `e\u{0301}`) for reliable string comparison and display
- Added `audio` background mode so DictusApp stays alive when user returns to their app via status bar chevron during recording

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added #if canImport(UIKit) guard to HapticFeedback.swift**
- **Found during:** Task 1 (GREEN phase of TDD)
- **Issue:** `import UIKit` fails during macOS-based SPM test runs (`swift test`) because UIKit is iOS-only
- **Fix:** Wrapped import and method bodies with `#if canImport(UIKit) && !os(macOS)`
- **Files modified:** DictusCore/Sources/DictusCore/HapticFeedback.swift
- **Verification:** `swift test` passes all 46 tests
- **Committed in:** cee4871 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix for SPM test compatibility. No scope creep.

## Issues Encountered
- iPhone 16 simulator not available in Xcode 26 -- used iPhone 17 Pro instead (pre-existing environment difference)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All cross-process contracts defined and tested -- Plan 03-02 (keyboard recording UI) can consume SharedKeys, DarwinNotifications, and HapticFeedback directly
- QWERTY layout data and AccentedCharacters ready for Plan 03-03 (accented characters + test screen)
- DictationCoordinator now handles keyboard-initiated stop/cancel -- keyboard extension just needs to set flags and post notifications

---
*Phase: 03-dictation-ux*
*Completed: 2026-03-06*
