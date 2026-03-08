---
phase: 07-keyboard-parity-visual
plan: 05
status: gaps_found
started: 2026-03-08
completed: 2026-03-08
duration: UAT session
tasks_completed: 0
tasks_total: 1

key-files:
  created: []
  modified: []

deviations: []
---

## What was done

Full Phase 7 UAT on device. User tested all 9 requirements and provided detailed feedback with screenshots.

## Results

### Passed
- **KBD-03** Haptics on all keys: OK
- **KBD-06** Performance: Slightly improved but still not Apple-level (see new features below)
- **VIS-02** Recording pills: OK, parfait

### Partial Pass (needs fixes)
- **KBD-01** Spacebar trackpad: Works but movement feels "locked to lines" vs Apple's free-flowing cursor. Needs better acceleration and smoother vertical movement.
- **KBD-02** Adaptive accent key: Positioned correctly, disappears on QWERTY. BUT: tapping inserts a NEW accented character instead of replacing the previous letter. Long-press doesn't work. Fallback: at minimum keep apostrophe key.
- **KBD-04** Emoji button: Shows emoji icon instead of Apple's SF Symbol smiley. Button doesn't switch to emoji keyboard — goes to Apple keyboard instead. Key icons for delete/return don't match Apple's design (see screenshots).
- **VIS-01** Mic pill: Top of pill clipped by keyboard edge (visible in zoomed screenshot).
- **VIS-03** Waveform: Not perfectly still on silence (may be ambient noise or sensitivity too high). Processing sinusoidal animation not working — still shows logo-based animation.

### Failed
- **KBD-05** Apple dictation mic: User asks if we can overlay-hide it like Whispr Flow does (screenshot provided showing their approach).
- Full Access banner URL: Still not opening app
- Top-row key popups: Still clipped

### New requirements from KEYBOARD_BRIEFING.md
User provided a full keyboard rebuild reference doc with features to implement:
1. Long press delete with acceleration (not yet implemented)
2. Autocapitalisation after `. ` `! ` `? ` and empty fields
3. Long press accents AZERTY popover (e/é/è/ê etc.)
4. Key tap sounds via `UIDevice.current.playInputClick()`
5. Performance: no global re-render, `drawingGroup()`, <20MB memory target
6. Special key icons should match Apple's SF Symbols (shift, delete, return, emoji)

## Self-Check: GAPS_FOUND

Multiple gaps identified across Phase 7 requirements. User recommends re-planning.
