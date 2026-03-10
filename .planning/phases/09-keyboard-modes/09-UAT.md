---
status: complete
phase: 09-keyboard-modes
source: 09-01-SUMMARY.md, 09-02-SUMMARY.md, 09-03-SUMMARY.md, 09-04-SUMMARY.md, 09-05-SUMMARY.md, 09-06-SUMMARY.md, commit d692616
started: 2026-03-10T20:00:00Z
updated: 2026-03-10T20:15:00Z
note: "Fresh UAT — previous 3-mode system replaced by DefaultKeyboardLayer (letters/numbers) in commit d692616"
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. Default Layer Picker in Settings
expected: In DictusApp Settings, the "Clavier" section shows a picker with two options: ABC (letters) and 123 (numbers). Tapping each option selects it and shows a miniature preview of the corresponding keyboard layout. The selection persists after closing Settings.
result: pass

### 2. Onboarding Layer Selection
expected: During onboarding, a step shows the default layer picker with ABC pre-selected. The "Continuer" button is always active (no blocking). User can change selection or skip ahead.
result: pass

### 3. Keyboard Opens on Correct Layer
expected: After selecting "123" in Settings, open the keyboard in any app (e.g. Messages). The keyboard should open directly on the numbers/symbols layer. Switch back to "ABC" in Settings — keyboard opens on the letters layer.
result: pass

### 4. Layer Persists Across Keyboard Shows
expected: Set default layer to "123". Open keyboard, close it, switch apps, open keyboard again. Each time, the keyboard opens on the numbers layer without needing to rebuild.
result: pass

### 5. Full Keyboard Always Available
expected: Regardless of which default layer is selected, the full keyboard is always shown (toolbar, all keys, emoji toggle, mic button). No stripped-down modes — just the starting layer changes.
result: pass

### 6. Shift Key Visibility
expected: On the letters layer, the shift key icon is clearly visible in both light and dark mode (no white-on-white issue).
result: pass

### 7. Recording from Both Layers
expected: Start dictation from the letters layer (tap mic). RecordingOverlay appears correctly. Repeat from the numbers layer. Overlay works identically from both layers.
result: pass

## Summary

total: 7
passed: 7
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]
