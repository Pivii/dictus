---
status: complete
phase: 07-keyboard-parity-visual
source: 07-01-SUMMARY.md, 07-02-SUMMARY.md, 07-03-SUMMARY.md, 07-04-SUMMARY.md, 07-06-SUMMARY.md, 07-07-SUMMARY.md, 07-08-SUMMARY.md, 07-10-SUMMARY.md, 07-11-SUMMARY.md, 07-12-SUMMARY.md
started: 2026-03-08T00:00:00Z
updated: 2026-03-08T19:45:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Haptic feedback on key taps
expected: Each key press (letters, space, return, delete, globe, shift, 123, #+=, emoji, accent) produces a tactile haptic response with no perceptible latency
result: pass

### 2. Dynamic keyboard height adaptation
expected: Keyboard keys are 42pt tall on iPhone SE, 46pt on standard iPhones, 50pt on Plus/Max models
result: pass

### 3. Full Access banner opens Dictus app
expected: Tapping the Full Access banner opens the Dictus app (via dictus:// URL) to guide setup
result: issue
reported: "Ça ne marche toujours pas, il ne se passe rien du tout"
severity: blocker

### 4. Emoji key on all keyboard layers
expected: All 4 keyboard layers (AZERTY letters, QWERTY letters, numbers, symbols) show an emoji button instead of globe
result: pass

### 5. Adaptive accent key on AZERTY row 3
expected: AZERTY keyboard shows apostrophe key between N and delete; switches to accent after typing vowel; long-press shows accent variants
result: pass

### 6. Pill-shaped microphone button in toolbar
expected: Mic button in toolbar is capsule-shaped (56x36) with Liquid Glass styling, not circular
result: pass

### 7. Canvas-based waveform animation
expected: Waveform during recording animates smoothly at 60fps with bars that respond to audio energy
result: pass

### 8. Zero-energy waveform stillness
expected: When no speech is detected, waveform bars drop to minimum height (perfectly still, not pulsing)
result: pass

### 9. Recording overlay pill buttons
expected: Cancel and Validate buttons in recording overlay are pill-shaped with Liquid Glass appearance; Validate is green (dictusSuccess color)
result: pass

### 10. Spacebar trackpad mode activation
expected: Long-press spacebar for 400ms activates trackpad mode; keyboard greys out to show mode active
result: pass

### 11. Trackpad cursor horizontal movement
expected: While in trackpad mode, horizontal finger drag moves cursor character-by-character proportional to drag distance
result: pass

### 12. Trackpad cursor vertical movement
expected: While in trackpad mode, vertical finger drag moves cursor up/down by approximate line widths (~40 characters per line)
result: pass

### 13. Accent key replaces previous vowel
expected: Typing vowel (e.g., 'e') then tapping accent key replaces that vowel with accented version (e), not doubling it (ee)
result: pass

### 14. SF Symbol icons for special keys
expected: Delete key shows delete.backward symbol, Return shows return.left symbol, Emoji shows face.smiling symbol (matching Apple style)
result: pass

### 15. Smooth proportional trackpad acceleration
expected: Trackpad vertical movement is smooth (1 char per 15pt) with velocity-based acceleration (1x/1.5x/2x multiplier at speed thresholds)
result: issue
reported: "Le mouvement vertical est bridé, il bouge de ligne en ligne, il faudrait que le mouvement soit complètement libre dans tous les sens, pas attaché à une ligne"
severity: major

### 16. Delete key acceleration
expected: Holding delete key: first 10 taps delete character-by-character; after 10 taps, accelerates to word-level deletion with subtle haptic feedback per step
result: pass

### 17. Autocapitalisation after punctuation
expected: Shift auto-activates after typing '. ' '! ' or '? ', after newline, or in empty text fields; respects host app's autocapitalizationType setting
result: pass

### 18. Mic pill no longer clipped
expected: Mic pill button in toolbar is fully visible with no clipping at top edge; toolbar height increased to 48pt
result: pass

### 19. Waveform silence threshold filtering
expected: Waveform bars remain at zero height during silence or ambient noise below 0.05 energy threshold (perfectly still)
result: pass

### 20. Processing state sinusoidal animation
expected: While transcribing (processing state), waveform shows sinusoidal traveling wave animation instead of 3-bar logo pulsing
result: pass

### 21. Key tap sounds on all keys
expected: All key taps (letters, space, return, delete, shift, emoji, 123, #+= keys) produce audible click sounds that respect ringer/silent switch
result: pass

### 22. Accent key preserves uppercase
expected: Typing uppercase vowel (e.g., 'A') then tapping accent produces uppercase accented character (A with accent), not lowercase
result: pass

### 23. Special keys use Apple gray color
expected: Shift, delete, return, emoji, 123, #+= keys all have systemGray5 background matching Apple keyboard appearance
result: pass

### 24. Shift active state styling
expected: When shift is active (caps lock), shift key shows light gray background with dark arrow icon (Apple convention, not inverted colors)
result: pass

### 25. 3-category key sound differentiation
expected: Key sounds differentiate into 3 categories: letter keys use sound 1104, delete uses 1155, modifier keys (shift/space/return/emoji) use 1156
result: pass

### 26. Trackpad line-based vertical movement
expected: Vertical trackpad drags move cursor by estimated line widths (approximately 40 characters per line worth of vertical movement)
result: pass

### 27. Waveform remains active after cancel
expected: Canceling a recording mid-way (tapping X button) does not break audio engine; waveform works on subsequent recordings
result: pass

## Summary

total: 27
passed: 25
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "Tapping the Full Access banner opens the Dictus app (via dictus:// URL) to guide setup"
  status: failed
  reason: "User reported: Ça ne marche toujours pas, il ne se passe rien du tout"
  severity: blocker
  test: 3
  artifacts: []
  missing: []

- truth: "Trackpad vertical movement is smooth (1 char per 15pt) with velocity-based acceleration"
  status: failed
  reason: "User reported: Le mouvement vertical est bridé, il bouge de ligne en ligne, pas libre"
  severity: major
  test: 15
  artifacts: []
  missing: []
