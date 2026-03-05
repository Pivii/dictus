---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_plan: 02-03
status: in-progress
last_updated: "2026-03-05T22:19:27.294Z"
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 7
  completed_plans: 5
---

# Project State: Dictus

## Project Reference
See: .planning/PROJECT.md (updated 2026-03-04)
**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 2 (Transcription Pipeline)

## Current Phase
Phase: 2
Status: In Progress
Plans completed: 2/3
Current plan: 02-03

## Phase History

### Plan 1.1: Project Scaffold — COMPLETED (2026-03-05)
- Xcode project created with DictusApp + DictusKeyboard targets
- DictusCore local SPM package with 7 source files + 6 unit tests (all passing)
- Both targets build successfully (iOS 16.0, iPhone 17 simulator)
- App Group entitlements configured on both targets
- DictusKeyboard: RequestsOpenAccess=true, PrimaryLanguage=fr-FR
- APPLICATION_EXTENSION_API_ONLY=YES on DictusKeyboard
- AppGroupDiagnostic wired into both launch paths

### Plan 1.2: Cross-Process Signaling — COMPLETED (2026-03-05)

- `dictus://` URL scheme registered in DictusApp Info.plist
- `DictationCoordinator` (ObservableObject) in DictusApp: handles URL, stubs recording+transcription, writes to App Group, posts Darwin notifications
- `DictusApp.swift` updated with `.onOpenURL` routing `dictus://dictate` to coordinator
- `ContentView.swift` updated with `DictationStatusView` shown when status != .idle
- `DictationView.swift` created: `DictationStatusView` component with icon+label per status
- `KeyboardState` (ObservableObject) in DictusKeyboard: observes Darwin notifications, reads App Group data, 100ms retry guard for race condition, deinit cleanup
- `MicButtonDisabled` view in DictusKeyboard/Views: popover with Full Access instructions
- `KeyboardViewController` updated with viewDidDisappear + textDidChange lifecycle hooks

### Plan 1.3: Keyboard Shell — COMPLETED (2026-03-05)
- Full AZERTY 3-layer keyboard (letters, numbers, symbols) with all iOS-native special keys
- `KeyDefinition` / `KeyboardLayer` / `KeyboardLayout` data model separating layout from rendering
- `KeyButton` with DragGesture press-popup preview matching native iOS keyboard feel
- `ShiftKey` with 3-state machine (off/shifted/capsLocked), double-tap caps lock, auto-unshift
- `DeleteKey` with async repeat-on-hold using `Task.sleep` (avoids RunLoop issues in extensions)
- `KeyboardView` composing all rows dynamically filling screen width via `unitKeyWidth` calculation
- `FullAccessBanner` persistent non-dismissible degradation UX with Settings deep-link
- `KeyboardInputView` (UIView + UIInputViewAudioFeedback) enabling system click sounds
- `KeyboardRootView` fully integrated: FullAccessBanner + StatusBar + TranscriptionStub + KeyboardView
- All Plan 1.2 + 1.3 source files registered in `Dictus.xcodeproj/project.pbxproj`

### Plan 1.4: UAT Gap Closure — COMPLETED (2026-03-05)
- Fixed keyboard click sounds: KeyboardInputView changed to UIInputView subclass, assigned to self.inputView, playInputClick() added to space/return/delete
- Fixed cross-process transcription display: consolidated Darwin notifications, refreshFromDefaults reads lastTranscription on .ready, StatusBar spinner conditional
- Layout regression fix: removed translatesAutoresizingMaskIntoConstraints = false from inputView to restore full-width keyboard
- Both UAT tests 9 (click sounds) and 13 (cross-process transcription) pass on device

### Plan 2.2: Transcription Quality Logic — COMPLETED (2026-03-05)
- FillerWordFilter: regex-based removal of 8 filler words (euh, hm, bah, ben, voila, um, uh, er)
- Lookahead/lookbehind regex preserves French words with filler substrings (humain, errer)
- SmartModelRouter: 5s threshold, fast models (tiny/base) vs accurate (small+), single-model fallback
- ModelInfo: metadata for 5 WhisperKit models with identifiers, display names, size/accuracy/speed labels
- SharedKeys extended with activeModel, modelReady, downloadedModels
- 24 new unit tests via TDD (30 total DictusCore tests all passing)

## Key Decisions

### DarwinNotifications C callback
Module-level registry (`_darwinCallbacks: [String: () -> Void]`) protected by `NSLock`, exposed via a `let _darwinCallback: CFNotificationCallback` constant. This is the required pattern — `CFNotificationCenterAddObserver` takes a C function pointer that cannot capture Swift context.

### Logger availability
`DictusLogger` uses `@available(iOS 14.0, macOS 11.0, *)`. `AppGroupDiagnostic` uses `os_log()` for the hot path to avoid availability gates in test targets (macOS runner). All call sites in DictusApp/DictusKeyboard wrap logger usage with `#available(iOS 14.0, *)`.

### No Xcode workspace
Local SPM package reference (`XCLocalSwiftPackageReference`) in the `.xcodeproj` is sufficient. No workspace needed.

### No `dictus://return`
No App Store-approved API exists on iOS 16-18 to programmatically return to the previous app. iOS automatically shows `< [Previous App]` status bar chevron when DictusApp opens via URL scheme. No code required.

### `KeyboardState` owned by `KeyboardRootView` as `@StateObject`
Ties `KeyboardState` lifetime to the SwiftUI view. `deinit` removes Darwin observers automatically when hosting controller is deallocated — prevents leaks across keyboard show/hide cycles.

### 100ms UserDefaults retry in `KeyboardState`
Darwin notifications are posted immediately after `defaults.synchronize()`, but cross-App-Group UserDefaults propagation can lag on-device. A 100ms deferred read guards against receiving the notification before the value is readable.

### MicKey uses `Link` not `Button`
Only `Link(destination:)` can open a URL scheme from inside a keyboard extension without `UIApplication.shared` (unavailable in extensions). Using `Button` + `openURL` environment does not work in extensions.

### `Task.sleep` for delete key repeat
`Timer.scheduledTimer` is unreliable in keyboard extensions — the main RunLoop is not always in `.default` mode. `Task { @MainActor in try? await Task.sleep(...) }` is the correct pattern for async repeat in extensions.

### `.gitignore /Models/` scope fix
The original `Models/` pattern matched any `Models/` directory recursively, including `DictusKeyboard/Models/` which contains Swift source files. Changed to `/Models/` to restrict exclusion to the repo root (where downloaded Whisper model binaries would live).

### Plan 1.3 delivers KBD-02 early
KBD-02 ("Full AZERTY keyboard layout") was assigned to Phase 3 in REQUIREMENTS but delivered in Phase 1 Plan 1.3 as the keyboard shell. Phase 3 will add long-press accented characters (é, è, â, etc.) on top of the existing infrastructure.

### UIInputView required for playInputClick
UIView with UIInputViewAudioFeedback conformance is insufficient. UIInputViewController.inputView is typed as UIInputView?, so the custom view must extend UIInputView with .keyboard style for system click sounds to work.

### Consolidated Darwin notifications
Writing both lastTranscription and status to UserDefaults before posting a single Darwin notification eliminates the race condition where the keyboard reads defaults between two separate notifications.

### Keep autoresizing masks on inputView
Setting translatesAutoresizingMaskIntoConstraints = false on the keyboard inputView prevents iOS from sizing it correctly. The default autoresizing masks must be preserved.

### Lookahead/lookbehind for French text regex
`\b` word boundaries treat apostrophes as boundaries, which would match filler substrings inside French contractions like "l'humain". Using `(?<=\s|^)` and `(?=\s|$|[,.!?;:])` ensures whole-word matching that respects French orthography.

### 5-second model routing threshold
Audio under 5 seconds routes to fast models (tiny/base) for low latency; 5 seconds or longer routes to accurate models (small+). When only one model is downloaded, it is always used regardless of duration.

---
*State initialized: 2026-03-04*
*Plan 1.1 completed: 2026-03-05*
*Plan 1.2 completed: 2026-03-05*
*Plan 1.3 completed: 2026-03-05*
*Phase 1 completed: 2026-03-05*
*Plan 2.2 completed: 2026-03-05*
