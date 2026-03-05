---
phase: 01-cross-process-foundation
plan: "1.3"
subsystem: ui
tags: [swiftui, keyboard-extension, azerty, uiinputviewcontroller, full-access]

# Dependency graph
requires:
  - phase: 01-cross-process-foundation/01-02
    provides: KeyboardState ObservableObject, DarwinNotificationCenter, App Group round-trip

provides:
  - Full AZERTY keyboard shell (letters, numbers, symbols layers)
  - KeyDefinition / KeyboardLayer / KeyboardLayout data model
  - KeyButton with popup preview, ShiftKey with 3-state machine
  - DeleteKey with async repeat-on-hold
  - KeyboardView composing all rows, routing to textDocumentProxy
  - FullAccessBanner persistent degradation UX
  - UIInputViewAudioFeedback (system click sound)
  - KeyboardRootView wiring KeyboardState + FullAccessBanner + StatusBar + KeyboardView

affects:
  - 03-dictation-ux (TranscriptionPreviewBar replaces TranscriptionStub; long-press accented chars)
  - 04-polish (design system pass on all keyboard views)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - KeyMetrics enum for shared key dimension constants
    - ShiftState enum for 3-state shift machine (off/shifted/capsLocked)
    - DragGesture(minimumDistance:0) for press/release detection on SwiftUI views
    - Task + Task.sleep for repeat-on-hold (avoids Timer.scheduledTimer RunLoop issues in extensions)
    - UIInputViewAudioFeedback via UIView subclass (required by UIKit protocol)

key-files:
  created:
    - DictusKeyboard/Models/KeyDefinition.swift
    - DictusKeyboard/Models/KeyboardLayer.swift
    - DictusKeyboard/Models/KeyboardLayout.swift
    - DictusKeyboard/Views/KeyButton.swift
    - DictusKeyboard/Views/SpecialKeyButton.swift
    - DictusKeyboard/Views/KeyRow.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/Views/FullAccessBanner.swift
    - DictusKeyboard/InputView.swift
  modified:
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/KeyboardViewController.swift
    - Dictus.xcodeproj/project.pbxproj
    - .gitignore

key-decisions:
  - "MicKey uses Link(destination: URL) not Button — only Link can open a URL scheme from keyboard extension without UIApplication.shared"
  - "playInputClick() gated on hasFullAccess — no-op path avoids hang when Full Access is off"
  - "KeyMetrics as enum (not struct) — prevents instantiation, acts as pure namespace"
  - "KeyboardHeight computed from row count — avoids fixed 216pt magic number, adapts if rows change"
  - ".gitignore Models/ changed to /Models/ — prevents DictusKeyboard/Models Swift source files from being ignored"
  - "TranscriptionStub is a Phase 1 placeholder explicitly labelled for replacement in Phase 3"

patterns-established:
  - "KeyDefinition: Identifiable with UUID id — enables ForEach over key arrays without index"
  - "KeyRow computes unitKeyWidth from sum of all widthMultipliers — proportional sizing fills screen exactly"
  - "SpecialKeyButton file owns ShiftState enum — enum lives near its primary consumer"
  - "MicKey embedded in KeyboardView.swift — co-located with its only consumer"

requirements-completed: [KBD-01, KBD-02, KBD-04]

# Metrics
duration: 35min
completed: 2026-03-05
---

# Plan 1.3: Keyboard Shell Summary

**Full AZERTY keyboard with 3-layer layout, shift/caps-lock, delete-repeat, popup preview, Full Access graceful degradation, and system click sound wired into KeyboardRootView**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-03-05
- **Completed:** 2026-03-05
- **Tasks:** 7
- **Files modified:** 13

## Accomplishments
- Complete AZERTY keyboard shell: letters, numbers, symbols layers with all iOS-native special keys
- Key tap popup preview matching native iOS keyboard behavior
- ShiftState 3-machine with double-tap caps lock and auto-unshift after single character
- DeleteKey async repeat-on-hold using `Task.sleep` (avoids Timer.scheduledTimer RunLoop issues in extensions)
- FullAccessBanner persistent degradation: typing always works, mic disabled, Settings deep-link shown
- System click sound via `UIInputViewAudioFeedback` on `KeyboardInputView` UIView subclass
- Full integration in `KeyboardRootView`: FullAccessBanner + StatusBar + TranscriptionStub + KeyboardView
- All Plan 1.2 + 1.3 files registered in `Dictus.xcodeproj/project.pbxproj` with Views/Models subgroups

## Task Commits

Each task was committed atomically:

1. **Task 1.3.1: Define AZERTY keyboard layout data model** - `6f8afd5` (feat)
2. **Task 1.3.2: Build KeyButton and key popup preview** - `f1e252b` (feat)
3. **Task 1.3.3: Build special key views** - `cf314ea` (feat)
4. **Task 1.3.4: Build KeyRow and main KeyboardView** - `fd17a4d` (feat)
5. **Task 1.3.5: Build FullAccessBanner** - `425b8b9` (feat)
6. **Task 1.3.6: Enable system keyboard click sound** - `4ab724d` (feat)
7. **Task 1.3.7: Integrate KeyboardView into KeyboardRootView** - `855354c` (feat)
8. **Xcode project registration** - `f7dc5cb` (chore)

## Files Created/Modified
- `DictusKeyboard/Models/KeyDefinition.swift` — KeyType enum + KeyDefinition struct with widthMultiplier
- `DictusKeyboard/Models/KeyboardLayer.swift` — KeyboardLayerType enum + KeyboardLayer struct
- `DictusKeyboard/Models/KeyboardLayout.swift` — Full AZERTY lettersRows, numbersRows, symbolsRows
- `DictusKeyboard/Views/KeyButton.swift` — Character key with DragGesture popup preview + KeyMetrics
- `DictusKeyboard/Views/SpecialKeyButton.swift` — ShiftKey, ShiftState, DeleteKey, SpaceKey, ReturnKey, GlobeKey, LayerSwitchKey
- `DictusKeyboard/Views/KeyRow.swift` — Single row renderer with proportional unitKeyWidth calculation
- `DictusKeyboard/Views/KeyboardView.swift` — Main composition: layer state, shift state, textDocumentProxy routing, MicKey
- `DictusKeyboard/Views/FullAccessBanner.swift` — Non-dismissible banner with Settings deep-link
- `DictusKeyboard/InputView.swift` — KeyboardInputView: UIView + UIInputViewAudioFeedback
- `DictusKeyboard/KeyboardRootView.swift` — Full integration replacing placeholder
- `DictusKeyboard/KeyboardViewController.swift` — Added KeyboardInputView to view hierarchy
- `Dictus.xcodeproj/project.pbxproj` — All Plan 1.2 + 1.3 files registered with Views/Models subgroups
- `.gitignore` — Fixed `Models/` to `/Models/` to avoid ignoring Swift source files

## Decisions Made
- **MicKey uses `Link` not `Button`**: Only `Link` can trigger a URL scheme from a keyboard extension without `UIApplication.shared` (which is unavailable in extensions).
- **`playInputClick()` gated on `hasFullAccess`**: The system click sound silently no-ops when Full Access is off, but gating avoids potential hangs on older devices.
- **`Task.sleep` for delete repeat**: `Timer.scheduledTimer` is unreliable in keyboard extensions where the main RunLoop may not be in `.default` mode. Async `Task` with `@MainActor` is the correct pattern.
- **`/Models/` in .gitignore**: The original `Models/` pattern matched `DictusKeyboard/Models/`. Changed to `/Models/` to scope the exclusion to the repo root (where downloaded Whisper model files would live).
- **`TranscriptionStub` is a named placeholder**: Explicitly labelled for Phase 3 replacement, not a TODO to avoid.

## Deviations from Plan
None — plan executed exactly as written, with one necessary .gitignore fix discovered during execution.

### Auto-fixed Issues

**1. .gitignore scope bug — DictusKeyboard/Models/ ignored**
- **Found during:** Task 1.3.1 (git add DictusKeyboard/Models/*.swift)
- **Issue:** `.gitignore` had `Models/` which matched any `Models/` directory, including the Swift source directory
- **Fix:** Changed to `/Models/` to scope to repo root only
- **Files modified:** `.gitignore`
- **Verification:** `git add DictusKeyboard/Models/*.swift` succeeded after fix
- **Committed in:** `6f8afd5` (part of Task 1.3.1 commit)

---

**Total deviations:** 1 auto-fixed (gitignore scope)
**Impact on plan:** Required fix for correctness. No scope creep.

## Issues Encountered
None beyond the gitignore issue above.

## User Setup Required
None — no external service configuration required. Keyboard must be installed and enabled on a physical device via Settings > General > Keyboard > Keyboards to verify runtime behavior.

## Next Phase Readiness
- Phase 1 complete: cross-process architecture proven, AZERTY keyboard shell functional
- Phase 2 (Transcription Pipeline): WhisperKit SPM integration, AVAudioEngine recording, model pre-compilation
- TranscriptionStub in KeyboardRootView will be replaced by TranscriptionPreviewBar in Phase 3
- Long-press accented characters deferred to Phase 3 (popup infrastructure is in place via KeyPopup)

---
*Phase: 01-cross-process-foundation*
*Completed: 2026-03-05*
