---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_plan: 03-02
status: In Progress
last_updated: "2026-03-06T10:06:30.000Z"
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 10
  completed_plans: 8
---

# Project State: Dictus

## Project Reference
See: .planning/PROJECT.md (updated 2026-03-04)
**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 3 (Dictation UX)

## Current Phase
Phase: 3
Status: In Progress
Plans completed: 1/3
Current plan: 03-02

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

### Plan 2.1: WhisperKit Integration — COMPLETED (2026-03-05)
- WhisperKit SPM dependency added to DictusApp target (not DictusKeyboard — 50MB memory limit)
- AudioRecorder wraps WhisperKit AudioProcessor with live energy levels for waveform visualization
- TranscriptionService with French language hint, greedy decoding (temperature 0.0)
- RecordingView with animated waveform, stop button, elapsed time counter
- DictationCoordinator fully rewritten — no stubs remain, real recording + transcription pipeline
- Verified on physical iPhone: French speech produces accurate transcription with automatic punctuation
- ContiguousArray/Array type mismatch auto-fixed (WhisperKit API compatibility)

### Plan 2.2: Transcription Quality Logic — COMPLETED (2026-03-05)
- FillerWordFilter: regex-based removal of 8 filler words (euh, hm, bah, ben, voila, um, uh, er)
- Lookahead/lookbehind regex preserves French words with filler substrings (humain, errer)
- SmartModelRouter: 5s threshold, fast models (tiny/base) vs accurate (small+), single-model fallback
- ModelInfo: metadata for 5 WhisperKit models with identifiers, display names, size/accuracy/speed labels
- SharedKeys extended with activeModel, modelReady, downloadedModels
- 24 new unit tests via TDD (30 total DictusCore tests all passing)

### Plan 2.3: Model Manager + Pipeline Integration — COMPLETED (2026-03-06)
- ModelManager with full download/select/delete lifecycle and App Group persistence
- ModelManagerView shows all models with metadata, download progress, active selection, delete confirmation
- SmartModelRouter wired into DictationCoordinator — short audio routes to fast model, long audio to accurate model
- FillerWordFilter.clean() applied to all transcription output in TranscriptionService
- modelReady flag persisted to App Group after first model download
- 5 post-checkpoint bugfixes: deletion path, double-start guard, serial prewarming, error-state delete, large-v3-turbo removal
- Verified end-to-end on physical iPhone: model management, smart routing, filler removal, French transcription with punctuation

### Plan 3.1: Cross-Process Contracts — COMPLETED (2026-03-06)
- SharedKeys extended with 5 new keys: keyboardLayout, waveformEnergy, stopRequested, cancelRequested, recordingElapsedSeconds
- DarwinNotificationName extended with 3 new names: stopRecording, cancelRecording, waveformUpdate
- KeyboardLayoutData: QWERTY layout rows and LayoutType enum with App Group persistence
- AccentedCharacters: French accented character mappings (8 base letters, precomposed Unicode) with case-insensitive lookup
- HapticFeedback: 3 distinct haptic patterns with canImport(UIKit) guard for SPM test compatibility
- DictationCoordinator: observes keyboard stop/cancel Darwin notifications, forwards waveform energy at ~5Hz
- cancelDictation() method discards audio and resets state
- Audio background mode added to Info.plist for background recording
- 16 new unit tests (6 QWERTY + 10 accented), 46 total DictusCore tests passing

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

### Auto-insert transcription into active text field (Phase 3 UX)
Instead of displaying transcription text in a keyboard banner, insert it directly into the active text field via `textDocumentProxy.insertText()`. This is the standard iOS dictation UX — user speaks, text appears where the cursor is. To implement in Phase 3 when wiring the keyboard extension.

### Pre-load WhisperKit on app launch (UX improvement)
First dictation after app launch has a visible delay (~2-5s) while WhisperKit loads the model into RAM. Could pre-load the active model when the app starts or when returning from model selection. Currently loading happens on first `dictus://dictate` call.

### Onboarding flow: permissions before models (Phase 4)
User must configure: (1) install keyboard, (2) enable Full Access, (3) grant microphone permission — BEFORE downloading models. Current flow doesn't guide this. Phase 4 onboarding should make this the first thing the user sees.

### large-v3-turbo ANE incompatibility
The `openai_whisper-large-v3_turbo` model fails ANE compilation on some devices (TextDecoder.mlmodelc). This is a hardware limitation — the model's TextDecoder is too large for the device's Neural Engine. No software fix possible. Consider hiding this model on incompatible devices in a future version.

### Keep autoresizing masks on inputView
Setting translatesAutoresizingMaskIntoConstraints = false on the keyboard inputView prevents iOS from sizing it correctly. The default autoresizing masks must be preserved.

### Lookahead/lookbehind for French text regex
`\b` word boundaries treat apostrophes as boundaries, which would match filler substrings inside French contractions like "l'humain". Using `(?<=\s|^)` and `(?=\s|$|[,.!?;:])` ensures whole-word matching that respects French orthography.

### WhisperKit AudioProcessor for recording
WhisperKit's built-in AudioProcessor handles 16kHz mono Float32 conversion internally. No custom AVAudioEngine pipeline needed — just call `startRecordingLive` and read `audioSamples` + `relativeEnergy`.

### ContiguousArray wrapping for WhisperKit
`audioProcessor.audioSamples` returns `ContiguousArray<Float>`, not `[Float]`. Wrap with `Array()` initializer when passing to methods expecting `[Float]`.

### 5-second model routing threshold
Audio under 5 seconds routes to fast models (tiny/base) for low latency; 5 seconds or longer routes to accurate models (small+). When only one model is downloaded, it is always used regardless of duration.

### Serial CoreML prewarming
Parallel prewarming of multiple CoreML models crashes the ANE (Apple Neural Engine) due to resource contention. Models must be prewarmed one at a time in sequence. This is undocumented Apple behavior discovered through on-device testing.

### large-v3-turbo ANE incompatibility
The `openai_whisper-large-v3_turbo` model fails ANE compilation on some devices (TextDecoder.mlmodelc). This is a hardware limitation — the model's TextDecoder is too large for the device's Neural Engine. No software fix possible. Consider hiding this model on incompatible devices in a future version.

### canImport(UIKit) for shared SPM packages
HapticFeedback.swift uses `#if canImport(UIKit) && !os(macOS)` because DictusCore compiles on macOS for `swift test`. UIKit is iOS-only — the guard prevents build failures during SPM test runs while keeping the code available on iOS targets.

### Throttled waveform forwarding at 5Hz
AudioRecorder publishes energy updates at ~60Hz. Writing to UserDefaults + synchronize + Darwin notification at 60Hz would cause excessive disk I/O and cross-process overhead. A 200ms timestamp check throttles to ~5Hz which is smooth enough for waveform animation.

### Precomposed Unicode for accented characters
Use precomposed Unicode (e.g., `\u{00E9}` = e-acute) not combining characters (e.g., `e\u{0301}`). Combining characters can cause string comparison issues and display inconsistencies. Precomposed forms are single code points matching iOS system keyboard behavior.

### Audio background mode for recording continuity
Added `UIBackgroundModes: audio` to DictusApp Info.plist. When user taps mic in keyboard, DictusApp opens and starts recording. User returns to their app via status bar chevron. The active AVAudioSession + audio background mode keeps iOS from suspending DictusApp during recording.

### Darwin notification + Bool flag pattern
Keyboard sets a Bool flag in App Group UserDefaults (e.g., stopRequested = true), then posts a Darwin notification. App observes the notification, reads the flag, resets it to false, and acts. This two-step pattern is necessary because Darwin notifications carry no payload.

---
*State initialized: 2026-03-04*
*Plan 1.1 completed: 2026-03-05*
*Plan 1.2 completed: 2026-03-05*
*Plan 1.3 completed: 2026-03-05*
*Phase 1 completed: 2026-03-05*
*Plan 2.1 completed: 2026-03-05*
*Plan 2.2 completed: 2026-03-05*
*Plan 2.3 completed: 2026-03-06*
*Phase 2 completed: 2026-03-06*
*Plan 3.1 completed: 2026-03-06*
