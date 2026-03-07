---
phase: 03-dictation-ux
verified: 2026-03-06T14:00:00Z
status: human_needed
score: 14/14 must-haves verified
re_verification:
  previous_status: passed
  previous_score: 14/14
  gaps_closed:
    - "Mic button now uses Button with onMicTap callback instead of Link(destination:) -- UAT blockers 2 and 3 root cause fixed"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Full dictation round-trip from keyboard (UAT re-test for blockers 2 and 3)"
    expected: "Tap mic in keyboard -> recording overlay appears IN THE KEYBOARD (not app switch) -> speak -> tap stop -> text auto-inserts at cursor"
    why_human: "Requires real device with WhisperKit, cross-process IPC, and physical interaction to confirm overlay appears in-keyboard"
  - test: "Recording overlay visual experience"
    expected: "Waveform animates tracking voice energy, timer counts in MM:SS, smooth transition to Processing state"
    why_human: "Animation quality and timing require visual observation"
  - test: "Accent popup long-press UX"
    expected: "Long-press e -> popup after ~400ms with accented variants -> slide to select -> release inserts accent"
    why_human: "Gesture timing and touch tracking require physical interaction"
---

# Phase 3: Dictation UX Verification Report

**Phase Goal:** Wispr Flow-inspired dictation loop -- tap mic, record with immersive keyboard UI, auto-insert transcribed text -- works fluidly from the keyboard. Includes QWERTY layout, accented characters, and in-app test screen.
**Verified:** 2026-03-06T14:00:00Z
**Status:** human_needed
**Re-verification:** Yes -- after UAT gap closure (Plan 03-04 fixed mic button blockers)

## Context

The previous verification (2026-03-06T12:30:00Z) reported status: passed at 14/14. However, subsequent UAT testing (03-UAT.md) revealed 2 blockers: the mic button used `Link(destination: "dictus://dictate")` which opened DictusApp instead of showing the recording overlay within the keyboard. Plan 03-04 was executed to fix this by replacing the Link with a Button + onMicTap callback pattern.

This re-verification confirms the fix is in place and re-verifies all truths against the actual codebase.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Tapping mic button triggers in-keyboard recording flow (not app switch) | VERIFIED | ToolbarView line 57: `Button(action: onMicTap)`. No `Link(destination: "dictus://dictate")` remains (grep confirmed 0 matches). startRecording() calls markRequested() first (sets .requested status locally), THEN opens URL. |
| 2 | Recording overlay replaces keyboard letters during recording | VERIFIED | KeyboardRootView line 48: `if state.dictationStatus == .recording \|\| .transcribing` renders RecordingOverlay instead of KeyboardView |
| 3 | Recording overlay shows waveform, timer, cancel and stop buttons | VERIFIED | RecordingOverlay.swift: KeyboardWaveformView (30 bars), formattedTime (MM:SS), cancel (xmark.circle.fill) and stop (checkmark.circle.fill) buttons |
| 4 | Transcribed text auto-inserts into active text field | VERIFIED | KeyboardState line 145: `controller?.textDocumentProxy.insertText(transcription)` with 100ms retry fallback |
| 5 | Keyboard stop/cancel signals reach DictusApp via Darwin notifications | VERIFIED | KeyboardState.requestStop() posts DarwinNotificationName.stopRecording; DictationCoordinator line 266 observes it |
| 6 | DictusApp forwards waveform energy to App Group | VERIFIED | DictationCoordinator line 310: `defaults.set(data, forKey: SharedKeys.waveformEnergy)` |
| 7 | QWERTY layout structurally correct (10-9-7-5 keys per row) | VERIFIED | QWERTYLayout.lettersRows in KeyboardLayoutData.swift has exact row counts. Test file exists. |
| 8 | Accented character mappings for all French AZERTY keys | VERIFIED | AccentedCharacters.mappings has 8 entries (e,a,u,i,o,c,y,n) with precomposed Unicode. Test file exists. |
| 9 | Haptic feedback fires three distinct types | VERIFIED | HapticFeedback.swift: recordingStarted() medium, recordingStopped() light, textInserted() success notification |
| 10 | Toolbar with mic button always visible above keyboard | VERIFIED | KeyboardRootView body always renders ToolbarView regardless of dictation state |
| 11 | QWERTY layout used when preference set; AZERTY by default | VERIFIED | LayoutType.active defaults to .azerty; KeyboardLayout reads from App Group |
| 12 | Long-pressing AZERTY key shows accent popup with drag-to-select | VERIFIED | KeyButton.swift: 400ms Task.sleep, AccentedCharacters.accents(for:), AccentPopup overlay, selectedAccentIndex via drag |
| 13 | In-app test dictation screen allows recording and shows transcription | VERIFIED | TestDictationView with @EnvironmentObject coordinator, mic button (3 states), text area, clear button; linked from ContentView line 60 |
| 14 | startRecording() sets local state before opening app | VERIFIED | KeyboardState lines 187-190: startRecording() calls markRequested() (sets .requested + haptic) then openURL?() |

**Score:** 14/14 truths verified

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `DictusCore/Sources/DictusCore/SharedKeys.swift` | VERIFIED | 28 lines, 5 cross-process keys present (keyboardLayout, waveformEnergy, stopRequested, cancelRequested, recordingElapsedSeconds) |
| `DictusCore/Sources/DictusCore/KeyboardLayoutData.swift` | VERIFIED | 44 lines, LayoutType enum with .active computed property, QWERTYLayout.lettersRows |
| `DictusCore/Sources/DictusCore/AccentedCharacters.swift` | VERIFIED | 36 lines, 8 base letters, precomposed Unicode, case-insensitive accents(for:) |
| `DictusCore/Sources/DictusCore/HapticFeedback.swift` | VERIFIED | 51 lines, 3 methods with #if canImport(UIKit) guard |
| `DictusCore/Tests/DictusCoreTests/QWERTYLayoutTests.swift` | VERIFIED | Test file exists |
| `DictusCore/Tests/DictusCoreTests/AccentedCharacterTests.swift` | VERIFIED | Test file exists |
| `DictusKeyboard/Views/ToolbarView.swift` | VERIFIED | 99 lines, Button with onMicTap callback (NOT Link), 4 visual states. Gap fix confirmed. |
| `DictusKeyboard/Views/RecordingOverlay.swift` | VERIFIED | 150 lines, waveform (30 bars), timer, cancel/stop, transcribing state |
| `DictusKeyboard/KeyboardState.swift` | VERIFIED | 200 lines, startRecording() with openURL closure, requestStop/Cancel, auto-insert via textDocumentProxy. Gap fix confirmed. |
| `DictusKeyboard/KeyboardRootView.swift` | VERIFIED | 74 lines, @Environment(\.openURL), onMicTap wired to state.startRecording(), openURL injected in .onAppear. Gap fix confirmed. |
| `DictusKeyboard/Views/AccentPopup.swift` | VERIFIED | 52 lines, horizontal cells with selection highlighting |
| `DictusKeyboard/Views/KeyButton.swift` | VERIFIED | 200 lines, 400ms long-press, AccentedCharacters lookup, drag-to-select |
| `DictusApp/Views/TestDictationView.swift` | VERIFIED | 190 lines, 3-state mic button, transcription area, clear button, .onChange watcher |
| `DictusApp/DictationCoordinator.swift` | VERIFIED | Stop/cancel observers (lines 266, 278), cancelDictation(), waveform energy writes (line 310) |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| ToolbarView.micButton | KeyboardRootView | `onMicTap` closure parameter | WIRED |
| KeyboardRootView | KeyboardState.startRecording() | `onMicTap: { state.startRecording() }` (line 44) | WIRED |
| KeyboardState.startRecording | markRequested + openURL | `markRequested()` then `openURL?(URL(...))` (lines 188-190) | WIRED |
| KeyboardRootView.onAppear | KeyboardState.openURL | `state.openURL = { url in openURL(url) }` (line 71) | WIRED |
| KeyboardState.requestStop | DarwinNotifications | Posts `stopRecording` notification (line 85) | WIRED |
| DictationCoordinator | DarwinNotifications | Observes `stopRecording`/`cancelRecording` (lines 266, 278) | WIRED |
| DictationCoordinator | SharedKeys.waveformEnergy | Writes JSON-encoded [Float] (line 310) | WIRED |
| KeyboardState.handleTranscriptionReady | textDocumentProxy.insertText | `controller?.textDocumentProxy.insertText(transcription)` (line 145) | WIRED |
| KeyButton | AccentedCharacters | `AccentedCharacters.accents(for: key.label.lowercased())` (line 139) | WIRED |
| ContentView | TestDictationView | NavigationLink (line 60) | WIRED |
| KeyboardRootView | RecordingOverlay | Conditional rendering when `dictationStatus == .recording` (line 48) | WIRED |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| KBD-02 | Full AZERTY keyboard layout | SATISFIED | AZERTY is default layout, AccentedCharacters provides French accents |
| KBD-03 | QWERTY keyboard layout as alternative | SATISFIED | QWERTYLayout.lettersRows + currentLettersRows() reads preference from App Group |
| KBD-05 | Mic button with clear visual states | SATISFIED | ToolbarView.micButton has 4 states: idle (gray Button), requested (blue pulse), recording (red pulse), transcribing (ProgressView) |
| DUX-01 | Transcribed text auto-inserted via textDocumentProxy | SATISFIED | KeyboardState.handleTranscriptionReady() calls insertText() |
| DUX-02 | Undo button (DROPPED by user decision) | SATISFIED | Intentionally omitted per user decision |
| DUX-03 | Haptic feedback on recording start, stop, text insertion | SATISFIED | HapticFeedback called in markRequested(), requestStop(), handleTranscriptionReady() |
| DUX-04 | Animated waveform during active recording | SATISFIED | RecordingOverlay contains KeyboardWaveformView with 30 animated bars |
| APP-04 | In-app test dictation screen | SATISFIED | TestDictationView with coordinator access, linked from ContentView |

No orphaned requirements found. All 8 IDs from the phase are accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No anti-patterns detected |

No TODO/FIXME/PLACEHOLDER comments found in DictusKeyboard. No empty implementations. No stub returns. No residual `Link(destination: "dictus://dictate")` in ToolbarView (the UAT root cause is fully removed).

### Human Verification Required

### 1. Full Dictation Round-Trip from Keyboard (UAT Re-test -- Critical)

**Test:** Build and deploy to physical iPhone. Open any text field, switch to Dictus keyboard, tap mic button. Verify the recording overlay appears IN THE KEYBOARD (not switching to DictusApp). Speak French, tap stop, verify text auto-inserts at cursor.
**Expected:** Mic tap shows recording overlay within the keyboard area with waveform and timer. Stop inserts transcribed text at cursor position. Haptic feedback at start, stop, and insertion.
**Why human:** This was the UAT blocker (tests 2 and 3). The code fix is verified (Button replaced Link, startRecording() added, openURL injected), but the cross-process IPC flow requires a real device with WhisperKit to confirm end-to-end behavior.

### 2. Recording Overlay Visual Experience

**Test:** Trigger recording from keyboard. Observe waveform animation, timer counting, and transition to "Processing..." state.
**Expected:** Smooth waveform animation tracking voice energy, timer in MM:SS format, clean transition to transcribing state.
**Why human:** Visual animation quality and timing cannot be verified programmatically.

### 3. Accent Popup Long-Press UX

**Test:** Long-press "e" key on AZERTY keyboard. Slide finger to select accented variant. Release.
**Expected:** Popup appears after ~400ms with 4 accented characters. Sliding highlights correct cell. Releasing inserts selected accent.
**Why human:** Gesture timing, touch tracking accuracy, and popup positioning require physical interaction.

### Gaps Summary

No code-level gaps found. All 14 observable truths verified at all three levels (exists, substantive, wired). All 8 requirement IDs satisfied. The UAT blocker (mic button using Link instead of Button) has been fixed in Plan 03-04 with commits `4687800` and `f157620`.

Status is `human_needed` because the critical UAT fix must be re-tested on a physical device. The previous UAT (03-UAT.md) showed that the mic button opened DictusApp instead of showing the recording overlay in the keyboard. The code fix (Button + startRecording() + openURL injection) is verified correct in the codebase, but the cross-process behavior can only be confirmed on-device.

---

_Verified: 2026-03-06T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
