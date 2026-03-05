---
status: diagnosed
phase: 01-cross-process-foundation
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md]
started: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:00:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. App Launches with Diagnostics
expected: DictusApp opens on device/simulator. Screen shows diagnostic indicators (green checkmarks or red X) for App Group health: canRead, canWrite, containerExists.
result: pass

### 2. Keyboard Extension Installs
expected: After building DictusApp to device, go to Settings > General > Keyboard > Keyboards > Add New Keyboard. "Dictus" appears in the list. After adding, it appears in your keyboard list.
result: pass

### 3. Keyboard Activates and Displays
expected: Open any text field (e.g. Notes, Safari). Switch to Dictus keyboard via globe key. The AZERTY keyboard layout appears with French letter arrangement (AZERTYUIOP first row).
result: pass

### 4. Basic Typing Works
expected: Tapping letter keys inserts the correct characters into the text field. Space key inserts a space. Return key inserts a newline.
result: pass

### 5. Layer Switching (Numbers/Symbols)
expected: Tapping "123" switches to numbers layer. Tapping "#+=" switches to symbols layer. Tapping "ABC" returns to letters layer. Each layer shows appropriate keys.
result: pass

### 6. Shift and Caps Lock
expected: Single tap on Shift capitalizes the next typed letter, then auto-unshifts back to lowercase. Double-tap on Shift activates Caps Lock (all subsequent letters uppercase until tapped again).
result: pass

### 7. Delete Key with Repeat
expected: Tapping delete removes one character. Holding delete continuously removes characters (repeat-on-hold behavior).
result: pass

### 8. Key Popup Preview
expected: When tapping a letter key, a popup preview appears above the key showing the character being typed (similar to native iOS keyboard).
result: pass

### 9. System Click Sound
expected: With Full Access enabled and keyboard clicks turned on in iOS Settings, tapping keys produces the native iOS keyboard click sound.
result: issue
reported: "Non, ça ne marche pas, je n'ai pas de bruit quand je clique sur les touches."
severity: major

### 10. Full Access Banner (No Full Access)
expected: If Full Access is NOT granted to Dictus keyboard, a persistent banner appears explaining the limitation with a link to Settings. The mic button appears disabled. Typing still works normally.
result: pass

### 11. Dictation URL Trigger
expected: Tapping the mic button on the keyboard opens DictusApp via the dictus://dictate URL scheme. iOS shows a back chevron in status bar to return to previous app.
result: pass

### 12. Dictation State Sequence in App
expected: After dictus://dictate triggers, DictusApp UI shows a state sequence: recording (with icon) -> transcribing -> ready. This is a stub simulation lasting ~2.5 seconds total.
result: pass

### 13. Cross-Process Transcription
expected: After dictation completes in DictusApp (stub reaches "ready" state), switch back to the keyboard. The keyboard should have received the stub transcription text and inserted it into the text field.
result: issue
reported: "Le texte stub n'est pas recu dans le clavier. Le retour est manuel (pas automatique). La status bar affiche 'transcription ready' avec un spinner qui tourne, mais le texte n'est pas insere dans le champ texte."
severity: major

## Summary

total: 13
passed: 11
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "With Full Access enabled and keyboard clicks turned on, tapping keys produces the native iOS keyboard click sound."
  status: failed
  reason: "User reported: Non, ça ne marche pas, je n'ai pas de bruit quand je clique sur les touches."
  severity: major
  test: 9
  root_cause: "KeyboardInputView is added as a subview but never set as the controller's inputView. Apple's playInputClick() only works on the actual inputView, not a random subview. Secondary: only character keys call playInputClick(), space/return/delete do not."
  artifacts:
    - path: "DictusKeyboard/KeyboardViewController.swift"
      issue: "KeyboardInputView added as subview instead of being the inputView"
    - path: "DictusKeyboard/Views/KeyboardView.swift"
      issue: "Missing playInputClick() calls in onSpace, onReturn, onDelete"
  missing:
    - "Set KeyboardInputView as the controller's inputView (or host SwiftUI inside it)"
    - "Add playInputClick() to space, return, delete handlers"
  debug_session: ".planning/debug/keyboard-click-sound.md"

- truth: "After dictation completes in DictusApp, switching back to keyboard shows the stub transcription text inserted into the text field."
  status: failed
  reason: "User reported: Le texte stub n'est pas recu dans le clavier. Le retour est manuel (pas automatique). La status bar affiche 'transcription ready' avec un spinner qui tourne, mais le texte n'est pas insere dans le champ texte."
  severity: major
  test: 13
  root_cause: "Three issues: (1) TranscriptionStub requires manual tap on 'Inserer' button — no auto-insertion logic exists. (2) StatusBar spinner is unconditional — keeps spinning on .ready status, confusing UX. (3) Race condition: two Darwin notifications posted sequentially, refreshFromDefaults() only reads status, not lastTranscription."
  artifacts:
    - path: "DictusKeyboard/KeyboardRootView.swift"
      issue: "TranscriptionStub requires manual tap; StatusBar spinner unconditional"
    - path: "DictusKeyboard/KeyboardState.swift"
      issue: "refreshFromDefaults() does not read lastTranscription"
    - path: "DictusApp/DictationCoordinator.swift"
      issue: "Two notifications posted in sequence create race condition"
  missing:
    - "Auto-insert transcription text or make Inserer button more prominent"
    - "Make StatusBar spinner conditional (hide on .ready/.failed)"
    - "Consolidate Darwin notifications or read lastTranscription in refreshFromDefaults()"
  debug_session: ".planning/debug/cross-process-transcription-not-received.md"
