---
status: complete
phase: 03-dictation-ux
source: [03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md]
started: 2026-03-06T11:30:00Z
updated: 2026-03-06T11:45:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Toolbar Above Keyboard
expected: Open any app with a text field. Activate the Dictus keyboard. A toolbar row appears above the keyboard with a gear icon on the left and a microphone button on the right.
result: pass

### 2. Start Recording
expected: Tap the mic button in the toolbar. The keyboard disappears and is replaced by a recording overlay showing an animated waveform visualization (30 bars), a MM:SS timer counting up, and cancel/stop control buttons. A haptic tap is felt when recording starts.
result: issue
reported: "Quand je clique sur le micro ca ouvre l'application Dictus et ca lance le recording process dans Dictus directement. Ca ne montre pas le recording overlay dans le clavier."
severity: blocker

### 3. Stop Recording and Auto-Insert
expected: While recording, tap the stop button. Recording stops (haptic feedback felt), the overlay shows "Processing..." briefly, then transcribed text is automatically inserted into the active text field. The keyboard reappears.
result: issue
reported: "Impossible de tester - bloque par le bug du test 2. Le recording se fait dans l'app Dictus, la transcription fonctionne bien dans l'app mais pas d'auto-insert dans le champ texte au niveau du clavier."
severity: blocker

### 4. Cancel Recording
expected: While recording, tap the cancel button. Recording is discarded -- no text is inserted into the text field. The keyboard reappears immediately.
result: skipped
reason: Blocked by Test 2 -- mic button opens app instead of recording overlay in keyboard

### 5. Accented Character Long-Press (AZERTY)
expected: With AZERTY layout active, long-press on a letter that has French accents (e.g., 'e', 'a', 'u', 'c'). After ~400ms, a horizontal popup appears showing accented variants. Drag finger to select a variant, release to insert it.
result: pass

### 6. In-App Test Dictation Screen
expected: Open the Dictus app. When a model is downloaded and ready, a navigation link to "Test Dictation" appears. Tap it to open a screen with a mic button. Tap to record, tap again to stop -- transcribed text appears on screen.
result: pass

## Summary

total: 6
passed: 3
issues: 2
pending: 0
skipped: 1

## Gaps

- truth: "Mic button in keyboard toolbar starts recording overlay within the keyboard extension"
  status: failed
  reason: "User reported: Mic button opens Dictus app instead of showing recording overlay in keyboard. Recording happens in the app, not in the keyboard extension."
  severity: blocker
  test: 2
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Stop recording auto-inserts transcribed text into active text field via textDocumentProxy"
  status: failed
  reason: "User reported: Blocked by test 2. Recording/transcription works in app but no auto-insert into keyboard text field since recording is not happening in keyboard context."
  severity: blocker
  test: 3
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
