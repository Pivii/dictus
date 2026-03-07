---
status: complete
phase: 05-wire-settings-and-code-hygiene
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md]
started: 2026-03-07T11:00:00Z
updated: 2026-03-07T11:20:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Key Tap Haptics
expected: Open Dictus keyboard in any app. Tap several letter keys. You should feel a light haptic tap on each key press.
result: issue
reported: "Haptics work initially but break as soon as DictusApp is launched. After opening the app, all haptic feedback stops — both in Dictus keyboard and system-wide. Requires full phone reboot to restore. Also slight delay compared to native iOS keyboard haptics."
severity: blocker

### 2. Accent Key Haptics
expected: Long-press a letter that has accents (e.g. "e"). When the accent popup appears, tap one of the accent options. You should feel a haptic tap when selecting the accent character.
result: issue
reported: "Same as Test 1 — haptics work before DictusApp launches, then break completely. When working, accent haptics function but with slight delay."
severity: blocker

### 3. Haptics Toggle Off
expected: Open Dictus app > Settings. Toggle "Haptics" OFF. Go back to keyboard and tap keys. You should feel NO haptic feedback on key presses.
result: issue
reported: "Toggling haptics off in Dictus settings disables haptics system-wide (all apps, all keyboards). Cannot re-enable without full phone reboot. The toggle is affecting the system Taptic Engine, not just Dictus haptics."
severity: blocker

### 4. Language Setting Wired
expected: Open Dictus app > Settings. Change the language setting (e.g. from French to English). Start a new dictation. The transcription should use the newly selected language for recognition.
result: pass

### 5. Filler Words Toggle Off
expected: Open Dictus app > Settings. Toggle "Filler Words" OFF. Dictate something with natural filler words (e.g. "euh", "hum"). The transcription should keep filler words as-is (no filtering). Toggle back ON and dictate again - filler words should be removed from output.
result: issue
reported: "Filler words are always filtered regardless of toggle state. Likely the Whisper model itself removes filler words natively, making the FillerWordFilter and its toggle redundant. User suggests removing the toggle entirely."
severity: minor

### 6. Accent Popup Brand Color
expected: Long-press a letter with accents on Dictus keyboard. The accent popup highlight/selection color should be the brand blue (#3D7EFF), not a plain default blue.
result: pass

### 7. BrandWaveform Consistency
expected: Start a dictation and observe the waveform animation. It should show 30 bars that fill the available width (adaptive sizing). The bars should animate smoothly with the audio input.
result: pass

## Summary

total: 7
passed: 3
issues: 4
pending: 0
skipped: 0

## Gaps

- truth: "Key tap haptics work reliably alongside DictusApp"
  status: failed
  reason: "User reported: Haptics break system-wide when DictusApp launches. AVAudioSession .playAndRecord blocks Taptic Engine."
  severity: blocker
  test: 1
  root_cause: "AVAudioSession configured with .playAndRecord missing .allowHapticsAndSystemSoundsDuringRecording option in AudioRecorder.swift:103"
  artifacts:
    - path: "DictusApp/Audio/AudioRecorder.swift"
      issue: "Missing .allowHapticsAndSystemSoundsDuringRecording in session options"
  missing:
    - "Add .allowHapticsAndSystemSoundsDuringRecording to AVAudioSession options"
  debug_session: ""

- truth: "Accent key haptics work reliably"
  status: failed
  reason: "User reported: Same root cause as Test 1 — haptics blocked by AVAudioSession"
  severity: blocker
  test: 2
  root_cause: "Same as Test 1 — AVAudioSession missing .allowHapticsAndSystemSoundsDuringRecording"
  artifacts:
    - path: "DictusApp/Audio/AudioRecorder.swift"
      issue: "Missing .allowHapticsAndSystemSoundsDuringRecording in session options"
  missing:
    - "Add .allowHapticsAndSystemSoundsDuringRecording to AVAudioSession options"
  debug_session: ""

- truth: "Haptics toggle only affects Dictus haptics, not system-wide"
  status: failed
  reason: "User reported: Toggling haptics off in Dictus disables haptics for entire phone, requires reboot"
  severity: blocker
  test: 3
  root_cause: "Same AVAudioSession issue — when session is active without .allowHapticsAndSystemSoundsDuringRecording, any haptic call can jam the Taptic Engine"
  artifacts:
    - path: "DictusApp/Audio/AudioRecorder.swift"
      issue: "Missing .allowHapticsAndSystemSoundsDuringRecording in session options"
  missing:
    - "Add .allowHapticsAndSystemSoundsDuringRecording to AVAudioSession options"
  debug_session: ""

- truth: "Filler words toggle controls filtering behavior"
  status: failed
  reason: "User reported: Filler words always filtered regardless of toggle. Whisper model may natively remove them."
  severity: minor
  test: 5
  root_cause: "Whisper model likely removes filler words during transcription before FillerWordFilter runs — toggle has no effect"
  artifacts:
    - path: "DictusApp/Audio/TranscriptionService.swift"
      issue: "FillerWordFilter redundant if model removes fillers natively"
  missing:
    - "Investigate if Whisper model removes fillers natively"
    - "If confirmed, remove FillerWordFilter and filler words toggle from Settings"
  debug_session: ""
