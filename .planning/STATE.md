---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_plan: done
status: completed
last_updated: "2026-03-07T08:18:33.704Z"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 16
  completed_plans: 15
---

# Project State: Dictus

## Project Reference
See: .planning/PROJECT.md (updated 2026-03-04)
**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 3 (Dictation UX)

## Current Phase
Phase: 4
Status: Complete
Plans completed: 3/3
Current plan: done

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

### Plan 3.2: Keyboard Recording UX — COMPLETED (2026-03-06)
- ToolbarView with gear icon (left) and state-dependent mic button (right) -- idle/recording/transcribing visual states
- RecordingOverlay replaces keyboard during active recording: 30-bar waveform, MM:SS timer, cancel/stop controls
- KeyboardState: requestStop/requestCancel via Darwin notification + Bool flag, waveform data at ~5Hz, auto-insert via textDocumentProxy
- KeyboardRootView: conditional rendering swaps KeyboardView for RecordingOverlay
- Removed Phase 1 leftovers: StatusBar, TranscriptionStub, MicKey struct
- Haptic feedback on recording start, stop, and text insertion
- Fixed pre-existing pbxproj issues: missing TestDictationView reference, AccentPopup group membership

### Plan 3.3: Keyboard Features & Test Dictation — COMPLETED (2026-03-06)
- QWERTY layout switching via App Group preference (LayoutType.active)
- Accented character long-press popups on AZERTY keys with drag-to-select
- TestDictationView for in-app recording and transcription testing
- DUX-02 (undo button) intentionally omitted per user decision

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

### Plan 3.4: Mic Button Gap Closure — COMPLETED (2026-03-06)
- ToolbarView mic button changed from Link(destination:) to Button with onMicTap callback
- KeyboardState.startRecording() sets local state to .requested then opens dictus://dictate via injected openURL closure
- KeyboardRootView wires @Environment(\.openURL) to KeyboardState and passes onMicTap to ToolbarView
- Fixes UAT blockers 2 and 3: mic button now triggers in-keyboard recording overlay instead of opening DictusApp

### Plan 4.1: Design System + TabView Restructure — COMPLETED (2026-03-06)
- Design system: GlassModifier (iOS 26 Liquid Glass + fallback), DictusColors (adaptive light/dark with hex init), BrandWaveform (3-bar logo), AnimatedMicButton (4 states), DictusTypography (SF Pro Rounded)
- App restructured from NavigationStack to 3-tab TabView (Home, Models, Settings placeholder)
- HomeView dashboard with brand waveform, model status card, transcription preview, test dictation link
- RecordingView overlay covers entire screen including tab bar via ZStack
- 4 new SharedKeys (language, hapticsEnabled, fillerWordsEnabled, hasCompletedOnboarding) with 6 unit tests (52 total)
- Onboarding gate placeholder in DictusApp.swift with fullScreenCover
- DiagnosticView extracted to DiagnosticDetailView for Settings reuse

### Plan 4.2: Onboarding Flow & Settings Screen — COMPLETED (2026-03-06)
- 5-step onboarding flow: welcome, mic permission, keyboard setup, model download, test recording
- OnboardingView as paged TabView with non-dismissible fullScreenCover
- Mic permission page doesn't block on denial (user can grant later)
- Keyboard setup page: Settings deep-link + auto-detection + manual fallback button
- Model download page: pre-selects whisper-small, shows progress via ModelManager
- Test recording page: validates pipeline end-to-end with live transcription
- SettingsView: 3 sections (Transcription, Clavier, A propos) with @AppStorage via App Group
- LicensesView: MIT attribution for WhisperKit and Dictus
- hasCompletedOnboarding default changed from true to false

### Plan 4.3: Design System Pass — COMPLETED (2026-03-06)
- Glass + multi-bar waveform + AnimatedMicButton + Dynamic Type applied across all screens
- RecordingView: replaced 50-bar WaveformView with BrandWaveform, removed old struct
- RecordingOverlay: replaced 30-bar KeyboardWaveformView with BrandWaveform
- ToolbarView: replaced inline micIcon with AnimatedMicButton (4 animation states)
- 5 Design files copied into DictusKeyboard/Design/ and registered in pbxproj
- KeyButton: glass background via dictusGlass, @ScaledMetric for Dynamic Type
- FullAccessBanner: dictusGlass replacing tertiarySystemBackground
- All hardcoded Color literals replaced with DictusColors equivalents
- BrandWaveform redesigned from 3-bar to 30-bar after visual verification
- Human verification passed on device

### Plan 4.5: Keyboard UAT Gap Closure — COMPLETED (2026-03-07)
- keyHeight 42->46pt matching native iOS keyboard
- Key/popup font sizes changed from @ScaledMetric to fixed let (native keyboard behavior)
- RecordingOverlay covers full toolbar+keyboard height (no layout shift on mic tap)
- FullAccessBanner enlarged with .footnote font, 10pt padding, dictus:// URL
- Waveform enlarged to 140pt height, 40 bars at 5pt width, 0.08s animation
- barWidth changed from @ScaledMetric to fixed let

## Key Decisions

### Fixed key font sizes (native iOS keyboard behavior)
Key labels and popup labels use `private let` instead of `@ScaledMetric`. Native iOS keyboard does NOT scale key labels with Dynamic Type -- scaling causes layout overflow on larger text sizes.

### dictus:// URL in FullAccessBanner
Changed from `app-settings:` (opens blank iOS Settings page) to `dictus://settings` (opens DictusApp which can show keyboard setup instructions).

### BrandWaveform 30-bar redesign
The original 3-bar logo-inspired waveform was too sparse for meaningful audio energy feedback. Redesigned to 30 bars maintaining brand identity (blue gradient center band, white opacity edges) while providing better visualization.

### Design file duplication for keyboard extension
DictusKeyboard cannot import DictusApp code. Moving design files to DictusCore would add UIKit/SwiftUI dependency to the shared package (breaks macOS SPM tests). Copying ~200 lines into DictusKeyboard/Design/ is the pragmatic solution. Both copies must be updated together.

### AnimatedMicButton 0.45x scale in toolbar
AnimatedMicButton is designed at 72pt for the main app. Scaling to 0.45x in the keyboard toolbar fits the 32pt space while preserving all 4 animation states.

### Don't block onboarding on mic denial
Apple HIG and research best practices recommend against blocking progress on permission denial. The user can still set up the keyboard and download a model without mic access. They can grant mic permission later from iOS Settings.

### Manual keyboard detection fallback
UITextInputMode.activeInputModes is unreliable for detecting keyboard installation -- it may not update immediately. A manual "J'ai ajoute le clavier" button is always visible as a reliable fallback path.

### Pre-select whisper-small for onboarding
The "small" model offers the best accuracy/speed balance for most modern iPhones (A12+). Users can change models later in the Models tab. The onboarding gets users started with quality transcription.

### Color(hex:) over Asset Catalog
Used Color(hex:UInt) initializer instead of Asset Catalog ColorSets because DictusApp has no .xcassets directory. Hex init provides compile-time validation of color values. Adaptive light/dark colors use UIColor dynamicProvider bridge since SwiftUI Color lacks a built-in light/dark initializer on iOS 16.

### dictusGlass() modifier pattern
Centralized glass effect modifier: `.dictusGlass()` applies `.glassEffect(.regular)` on iOS 26+ and `.regularMaterial` on iOS 16-25. Every glass surface in the app calls this one modifier, so the iOS 26 upgrade is automatic.

### hasCompletedOnboarding defaults to true during dev
Set to true so the app is immediately usable without onboarding. Plan 04-02 will flip to false and build the real OnboardingView.

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

### MicKey uses `Button` with injected openURL closure (revised from Phase 2)
Phase 2 used `Link(destination:)` which opened DictusApp but gave the keyboard no control over the flow. Phase 3 revised this: ToolbarView uses `Button(action: onMicTap)` which calls `KeyboardState.startRecording()`. This sets local state to `.requested` first (triggering the recording overlay immediately), then opens the URL via an `openURL` closure injected from `@Environment(\.openURL)` in KeyboardRootView. The `@Environment(\.openURL)` action works in keyboard extensions because it uses the responder chain, not `UIApplication.shared`.

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

### Long-press accent gesture pattern
400ms Task.sleep timer inside DragGesture.onChanged. If timer completes without onEnded, check AccentedCharacters.accents(for:). Show AccentPopup overlay, track horizontal drag to highlight cells. On release: insert selected accent or dismiss. Timer cancelled in onEnded for normal taps.

### Dynamic layout selection via static function
KeyboardLayout.currentLettersRows() reads LayoutType.active from App Group on every call. Returns pre-built static arrays (no re-creation). Function (not property) signals I/O side effect to callers.

### DUX-02 intentionally omitted
Undo button requirement (DUX-02) was deliberately not implemented per user decision. Marked as complete in requirements tracking.

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

### Conditional rendering over ZStack for keyboard/recording swap
Using `if/else` in SwiftUI body fully removes the inactive view from the hierarchy when switching between KeyboardView and RecordingOverlay. This prevents ghost touches on hidden keyboard keys and frees memory. A ZStack or overlay would keep both views alive.

### weak controller reference on KeyboardState
KeyboardState holds `weak var controller: UIInputViewController?` set via `.onAppear` in KeyboardRootView. This avoids a retain cycle (controller -> hosting view -> @StateObject -> controller) while allowing KeyboardState to call `textDocumentProxy.insertText()` for auto-insert.

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
*Plan 3.2 completed: 2026-03-06*
*Plan 3.3 completed: 2026-03-06*
*Plan 3.4 completed: 2026-03-06*
*Phase 3 completed: 2026-03-06*
*Plan 4.1 completed: 2026-03-06*
*Plan 4.2 completed: 2026-03-06*
*Plan 4.3 completed: 2026-03-06*
*Plan 4.4 completed: 2026-03-07*
*Plan 4.5 completed: 2026-03-07*
*Phase 4 completed: 2026-03-06*
*All phases complete: 2026-03-06*
