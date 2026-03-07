---
phase: 01-cross-process-foundation
verified: 2026-03-05T12:00:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification:
  previous_status: human_needed
  previous_score: 5/5
  gaps_closed: []
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Round-trip smoke test after Plan 1.4 fixes"
    expected: "Tap mic in keyboard, DictusApp opens, stub transcription completes, switch back to keyboard, TranscriptionStub shows text with Inserer button"
    why_human: "Requires physical iPhone with both targets deployed and keyboard enabled"
  - test: "Keyboard click sounds after UIInputView fix"
    expected: "With Full Access on and keyboard clicks enabled in iOS Settings, all key types (letters, space, return, delete) produce click sound"
    why_human: "Audio feedback requires device hardware"
  - test: "Globe key keyboard switching"
    expected: "Globe key cycles through installed keyboards including Dictus"
    why_human: "advanceToNextInputMode() only functions on device with multiple keyboards"
  - test: "App Group diagnostic runtime logs"
    expected: "Both DictusApp init and KeyboardViewController DEBUG viewDidLoad log canWrite=true canRead=true"
    why_human: "Runtime App Group entitlements only resolve on signed device builds"
---

# Phase 1: Cross-Process Foundation Verification Report

**Phase Goal:** Prove the two-process dictation architecture works end-to-end on a real device before any other feature is built.
**Verified:** 2026-03-05
**Status:** human_needed
**Re-verification:** Yes -- after UAT gap closure (Plan 1.4)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Tapping mic button stub in keyboard launches Dictus main app via `dictus://dictate` on a physical iPhone | VERIFIED | `KeyboardView.swift` line 123: `Link(destination: URL(string: "dictus://dictate")!)` renders MicKey when `hasFullAccess` is true. `DictusApp/Info.plist` lines 23-33: `CFBundleURLSchemes` registers `dictus`. `DictusApp.swift` lines 28-42: `.onOpenURL` routes `dictus://dictate` to `coordinator.startDictation()`. UAT test 11: pass. |
| 2 | Main app records audio and writes transcription result to App Group shared container | VERIFIED | `DictationCoordinator.swift` lines 35-73: simulates 1.5s recording + 1s transcription, writes `lastTranscription` and `dictationStatus` to `AppGroup.defaults`, calls `synchronize()`, posts consolidated Darwin notifications. Stub by design (real audio deferred to Phase 2). UAT test 12: pass. |
| 3 | Keyboard extension reads result and displays it -- completing a round trip without crashing | VERIFIED | `KeyboardState.swift` lines 15-36: observes Darwin notifications, reads status and transcription from App Group UserDefaults with 100ms retry guard. `KeyboardRootView.swift` lines 30-33: renders `TranscriptionStub` with "Inserer" button when transcription is available. Plan 1.4 fixes: consolidated notification (eliminates race), `refreshFromDefaults` reads `lastTranscription` on `.ready` status, spinner hidden on terminal states. UAT test 13: initially failed, fixed in Plan 1.4 commit `abfc978`. |
| 4 | Basic AZERTY typing (characters, space, delete, return) works in any app without Full Access enabled | VERIFIED | `KeyboardLayout.swift`: full 3-layer AZERTY layout (letters, numbers, symbols). `KeyboardView.swift` lines 36-64: routes character to `insertText()`, delete to `deleteBackward()`, space to `insertText(" ")`, return to `insertText("\n")`. `playInputClick()` gated on `hasFullAccess` -- typing path unconditional. `FullAccessBanner.swift`: non-dismissible banner when Full Access off, mic disabled but typing works. UAT tests 3-8: all pass. |
| 5 | AppGroupDiagnostic logs confirm both targets can read and write to `group.com.pivi.dictus` | VERIFIED | `AppGroupDiagnostic.swift`: writes test value to shared UserDefaults, reads back, checks container URL, logs via `os_log`. `DictusApp.swift` line 10: calls `AppGroupDiagnostic.run()` in `init()`. `KeyboardViewController.swift` lines 13-19: calls in `#if DEBUG viewDidLoad()`. Both `.entitlements` files contain `group.com.pivi.dictus`. Runtime log confirmation requires device. |

**Score:** 5/5 truths verified (code-level). Device confirmation pending for truths 1, 3, 5.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `DictusCore/Sources/DictusCore/AppGroup.swift` | App Group identifier and shared defaults accessor | VERIFIED | Single source of truth for `group.com.pivi.dictus`, fatalError guard on misconfiguration |
| `DictusCore/Sources/DictusCore/DarwinNotifications.swift` | Cross-process notification helper | VERIFIED | Thread-safe C callback registry, post/addObserver/removeObserver implemented |
| `DictusCore/Sources/DictusCore/DictationStatus.swift` | Codable status enum | VERIFIED | 6 states: idle/requested/recording/transcribing/ready/failed |
| `DictusCore/Sources/DictusCore/SharedKeys.swift` | UserDefaults key constants | VERIFIED | `dictus.` prefix, 4 unique keys |
| `DictusCore/Sources/DictusCore/AppGroupDiagnostic.swift` | Health check for App Group | VERIFIED | DiagnosticResult with canRead/canWrite/containerExists, os_log output |
| `DictusApp/DictusApp.swift` | App entry point with URL handling | VERIFIED | `@main`, `.onOpenURL`, diagnostic in init |
| `DictusApp/DictationCoordinator.swift` | Dictation state machine | VERIFIED | Stub recording + transcription, writes to App Group, posts Darwin notifications |
| `DictusApp/DictationView.swift` | Status display component | VERIFIED | DictationStatusView with SF Symbols per state |
| `DictusApp/Info.plist` | URL scheme registration | VERIFIED | `CFBundleURLSchemes: [dictus]` |
| `DictusKeyboard/KeyboardViewController.swift` | Extension entry point | VERIFIED | UIInputViewController with UIHostingController, KeyboardInputView as inputView |
| `DictusKeyboard/KeyboardState.swift` | Cross-process observer | VERIFIED | Darwin notification listeners, UserDefaults reads, 100ms retry guard |
| `DictusKeyboard/KeyboardRootView.swift` | Root composition view | VERIFIED | FullAccessBanner + StatusBar + TranscriptionStub + KeyboardView |
| `DictusKeyboard/Views/KeyboardView.swift` | Main keyboard with AZERTY layout | VERIFIED | 3-layer support, shift/caps, all textDocumentProxy operations, MicKey with Link |
| `DictusKeyboard/Views/FullAccessBanner.swift` | Degradation banner | VERIFIED | Non-dismissible, Settings deep-link via `app-settings:` |
| `DictusKeyboard/Views/SpecialKeyButton.swift` | Shift, Delete, Space, Return, Globe keys | VERIFIED | ShiftState 3-machine, delete repeat-on-hold via Task.sleep, globe via advanceToNextInputMode |
| `DictusKeyboard/Models/KeyboardLayout.swift` | AZERTY layout data | VERIFIED | Full French AZERTY: letters (10-10-8 + function row), numbers, symbols layers |
| `DictusKeyboard/InputView.swift` | UIInputView for audio feedback | VERIFIED | UIInputView subclass with UIInputViewAudioFeedback, assigned as controller inputView |
| `DictusApp/DictusApp.entitlements` | App Group entitlement | VERIFIED | `group.com.pivi.dictus` |
| `DictusKeyboard/DictusKeyboard.entitlements` | App Group entitlement | VERIFIED | `group.com.pivi.dictus` |
| `DictusKeyboard/Info.plist` | Extension config | VERIFIED | RequestsOpenAccess=true, PrimaryLanguage=fr-FR, IsASCIICapable=true |
| `DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift` | Unit tests | VERIFIED | 6 tests covering AppGroup, DictationStatus, SharedKeys, diagnostic |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| MicKey (KeyboardView.swift) | DictusApp | `Link(destination: URL("dictus://dictate"))` | WIRED | Line 123: Link with URL literal, only shown when hasFullAccess |
| DictusApp.onOpenURL | DictationCoordinator | `coordinator.startDictation()` | WIRED | Line 36: routes `url.host == "dictate"` to startDictation() |
| DictationCoordinator | App Group | `AppGroup.defaults.set()` + `synchronize()` | WIRED | Lines 61-64: writes lastTranscription + status + timestamp, synchronizes |
| DictationCoordinator | KeyboardState | Darwin notification post | WIRED | Lines 67-68: posts statusChanged + transcriptionReady after all writes |
| KeyboardState | App Group | `AppGroup.defaults.string(forKey:)` | WIRED | Lines 48-56: reads dictationStatus and lastTranscription on notification |
| KeyboardState | KeyboardRootView | `@StateObject` + `@Published` | WIRED | RootView line 9: `@StateObject state = KeyboardState()`, binds to UI |
| KeyboardRootView | TranscriptionStub | Conditional render | WIRED | Lines 30-33: shows stub when lastTranscription != nil and status == .ready |
| KeyboardView | textDocumentProxy | `controller.textDocumentProxy.insertText()` | WIRED | Lines 57-63, 88: insertText for chars, space, return; deleteBackward for delete |
| KeyboardInputView | UIInputViewController | `self.inputView = kbInputView` | WIRED | KeyboardViewController line 55: assigned as controller inputView for click sounds |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DUX-05 | 1.2 | Dictation flow uses two-process architecture | SATISFIED | MicKey triggers `dictus://dictate` from keyboard extension, DictationCoordinator handles in DictusApp, writes result to App Group, KeyboardState reads back via Darwin notification. Full round-trip implemented. |
| APP-05 | 1.2 | App handles `dictus://dictate` URL scheme to receive dictation requests from keyboard extension | SATISFIED | Info.plist registers URL scheme, DictusApp.swift `.onOpenURL` routes to `startDictation()` |
| APP-06 | 1.1 | All shared data passes through App Group (`group.com.pivi.dictus`) | SATISFIED | `AppGroup.swift` is single access point, both entitlements configured, DictationCoordinator writes and KeyboardState reads exclusively via `AppGroup.defaults` |
| KBD-01 | 1.3 | User can switch to Dictus keyboard via globe key | SATISFIED | `GlobeKey` in `SpecialKeyButton.swift` calls `advanceToNextInputMode()`, Info.plist registers as keyboard service. UAT test 3: pass. |
| KBD-04 | 1.3 | Keyboard remains functional without Full Access | SATISFIED | `FullAccessBanner` shown but typing unconditional, `playInputClick()` gated on hasFullAccess, MicKey disabled when no Full Access. UAT test 10: pass. |

No orphaned requirements found. All 5 IDs from phase plans match REQUIREMENTS.md mappings.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| DictusKeyboard/KeyboardRootView.swift | 68 | `TranscriptionStub` -- named placeholder for Phase 3 replacement | Info | Intentional Phase 1 scope -- explicitly labelled for replacement by TranscriptionPreviewBar in Phase 3 |

No TODO, FIXME, PLACEHOLDER, or empty implementation patterns found in any phase files.

### Human Verification Required

### 1. Post-Fix Round-Trip Smoke Test

**Test:** Tap mic button in keyboard, DictusApp opens and runs stub dictation, switch back to keyboard via iOS back chevron, verify TranscriptionStub shows "Bonjour, ceci est un test de dictee." with "Inserer" button.
**Expected:** Full round-trip completes without crash. StatusBar shows spinner only during recording/transcribing, no spinner on ready state.
**Why human:** Requires physical iPhone with both targets deployed, keyboard enabled, and Full Access granted.

### 2. Keyboard Click Sounds (Post Plan 1.4 Fix)

**Test:** Enable Full Access, enable keyboard clicks in iOS Settings > Sounds & Haptics, type on Dictus keyboard.
**Expected:** All key types (letters, space, return, delete) produce native iOS click sound.
**Why human:** UAT test 9 failed initially; fixed in commit `9a87cfb` (UIInputView as inputView). Needs device audio verification.

### 3. Globe Key Switching

**Test:** Open any text field, long-press globe key or tap to cycle keyboards.
**Expected:** Dictus keyboard appears in rotation and can be switched to/from.
**Why human:** `advanceToNextInputMode()` only functions on physical device with multiple keyboards installed.

### 4. App Group Diagnostic Runtime Logs

**Test:** Build DictusApp in DEBUG mode, check Xcode console on launch for AppGroupDiagnostic output. Then open keyboard, check debug console for keyboard diagnostic.
**Expected:** Both show `canWrite=true canRead=true container=true`.
**Why human:** App Group entitlements only resolve on signed device builds. Simulator/unsigned builds may show false negatives.

### UAT History

Initial UAT completed 13 tests: 11 passed, 2 issues found.

**Issue 1 (test 9):** Keyboard click sounds not working. Root cause: `KeyboardInputView` was a `UIView` subclass added as a subview, not assigned as the controller's `inputView`. Fixed in Plan 1.4 commit `9a87cfb` by changing to `UIInputView` subclass and assigning as `self.inputView`.

**Issue 2 (test 13):** Cross-process transcription not displayed in keyboard. Root cause: race condition from sequential Darwin notifications, `refreshFromDefaults()` not reading `lastTranscription`, unconditional spinner. Fixed in Plan 1.4 commit `abfc978` by consolidating notifications, reading transcription on `.ready` status, and making spinner conditional.

**Regression fix:** Commit `a2d847d` restored full-width keyboard layout after the `UIInputView` change broke autoresizing masks.

Post-fix device verification has not been explicitly documented as re-run.

### Gaps Summary

No code-level gaps found. All five success criteria are verified at the code level:

1. URL scheme registered, MicKey uses Link, DictusApp handles .onOpenURL -- architecture proven
2. DictationCoordinator writes stub transcription to App Group with consolidated notifications
3. KeyboardState reads transcription via Darwin notification + UserDefaults, TranscriptionStub renders result
4. Full AZERTY keyboard (3 layers, all special keys) works unconditionally, Full Access only gates mic and click sounds
5. AppGroupDiagnostic runs in both targets with os_log output, both entitlements match

The phase goal "prove the two-process dictation architecture works end-to-end" is structurally fulfilled. Status is `human_needed` because the core behaviors (cross-process communication, keyboard switching, audio feedback) can only be fully confirmed on a physical iPhone with valid provisioning.

---

_Verified: 2026-03-05_
_Verifier: Claude (gsd-verifier)_
