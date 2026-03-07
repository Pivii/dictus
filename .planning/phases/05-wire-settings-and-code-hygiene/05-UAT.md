---
status: diagnosed
phase: 05-wire-settings-and-code-hygiene
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md]
started: 2026-03-07T11:00:00Z
updated: 2026-03-07T12:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Key Tap Haptics
expected: Open Dictus keyboard in any app. Tap several letter keys. You should feel a light haptic tap on each key press.
result: issue → FIXED
reported: "Haptics broke system-wide when DictusApp launched. AVAudioSession blocked Taptic Engine."
severity: blocker
fix: "Added setAllowHapticsAndSystemSoundsDuringRecording(true) after each startRecordingLive() call + aligned session options with WhisperKit"

### 2. Accent Key Haptics
expected: Long-press a letter that has accents (e.g. "e"). When the accent popup appears, tap one of the accent options. You should feel a haptic tap when selecting the accent character.
result: issue → FIXED
reported: "Same root cause as Test 1"
severity: blocker
fix: "Same fix as Test 1"

### 3. Haptics Toggle Off
expected: Open Dictus app > Settings. Toggle "Haptics" OFF. Go back to keyboard and tap keys. You should feel NO haptic feedback on key presses.
result: issue → FIXED
reported: "Toggle disabled haptics system-wide, required reboot"
severity: blocker
fix: "Same fix as Test 1 — setAllowHapticsAndSystemSoundsDuringRecording prevents Taptic Engine jam"

### 4. Language Setting Wired
expected: Open Dictus app > Settings. Change the language setting (e.g. from French to English). Start a new dictation. The transcription should use the newly selected language for recognition.
result: pass

### 5. Filler Words Toggle Off
expected: Open Dictus app > Settings. Toggle "Filler Words" OFF. Dictate something with natural filler words (e.g. "euh", "hum"). The transcription should keep filler words as-is (no filtering). Toggle back ON and dictate again - filler words should be removed from output.
result: issue (deferred)
reported: "Filler words always filtered regardless of toggle. Whisper model likely removes them natively."
severity: minor
fix: "Deferred to next milestone — investigate if model removes fillers natively, if so remove toggle"

### 6. Accent Popup Brand Color
expected: Long-press a letter with accents on Dictus keyboard. The accent popup highlight/selection color should be the brand blue (#3D7EFF), not a plain default blue.
result: pass

### 7. BrandWaveform Consistency
expected: Start a dictation and observe the waveform animation. It should show 30 bars that fill the available width (adaptive sizing). The bars should animate smoothly with the audio input.
result: pass

## Summary

total: 7
passed: 3
fixed: 3
deferred: 1
pending: 0
skipped: 0

## Gaps

- truth: "Filler words toggle controls filtering behavior"
  status: deferred
  reason: "Whisper model likely removes filler words natively — toggle has no effect"
  severity: minor
  test: 5
  root_cause: "Model-level filtering makes FillerWordFilter redundant"
  artifacts:
    - path: "DictusApp/Audio/TranscriptionService.swift"
      issue: "FillerWordFilter redundant if model removes fillers natively"
  missing:
    - "Investigate if Whisper model removes fillers natively"
    - "If confirmed, remove FillerWordFilter and filler words toggle from Settings"
  debug_session: ""

## Additional Fixes Applied During UAT

### Cold Start Audio Engine (bonus fix)
- AudioRecorder.configureAudioSession(): session options aligned with WhisperKit ([.defaultToSpeaker, .allowBluetooth]), setActive called every time (not guarded by sessionConfigured)
- DictationCoordinator.startDictation(): early return when in background with engine not running — lets keyboard URL fallback trigger
- DictationCoordinator.init(): configureAudioSession() called synchronously before async Task; didBecomeActiveNotification observer retries warmUp on foreground return
- KeyboardState.startRecording(): URL fallback uses SwiftUI openURL with extensionContext fallback

### Known Future Work (next milestone)
- Cold start auto-return: when app opens from keyboard URL, auto-return to previous app after engine warm-up (competitors like Wispr Flow do this)
- iOS aggressively kills background apps — cold start is frequent in production, not just edge case
