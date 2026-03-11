---
phase: 07-keyboard-parity-visual
plan: 09
status: complete
gap_closure: true
started: 2025-03-08
completed: 2025-03-08
---

# 07-09 SUMMARY — UAT Gap Closure Verification

## What Was Done

Full UAT of gap closure fixes (07-06, 07-07, 07-08) on device.

## UAT Results

### Passed
- **Long-press accent popup** — works correctly
- **Delete acceleration** — char-by-char then word-by-word on hold
- **Autocapitalisation** — triggers after `. ` `! ` `? ` and empty fields
- **Mic pill clipping** — fixed, no longer clipped in toolbar
- **Key tap sounds** — all keys produce clicks

### Partial / Gaps Found
1. **Accent key ignores uppercase** — typing "A" then accent produces "à" instead of "À". Must preserve original case.
2. **Special key colors too dark** — shift, delete, emoji, 123, return have dark gray backgrounds. Apple keyboard uses light gray. Need to match Apple style.
3. **Emoji button broken** — tapping emoji key switches to previous keyboard instead of opening emoji keyboard.
4. **Trackpad vertical movement missing** — cursor moves left/right only, cannot move between lines. Apple trackpad allows free 2D movement.
5. **Shift/caps lock styling inverted** — when caps lock active, Dictus shows black background + white arrow. Apple shows white background + black filled arrow. Need to invert colors.
6. **Waveform breaks after cancel** — canceling a recording mid-way breaks the audio/animation system. Subsequent recordings have no waveform animation at all.
7. **Key sounds need 3 categories** — Apple keyboard has 3 distinct sounds: (a) letter keys, (b) delete key, (c) other special keys (space, return, shift, emoji). Currently all keys use same sound.

### Not Tested
- Processing animation (blocked by waveform bug)
- Dictation mic overlay (user didn't understand / N/A)

## Key Files
- No files modified (UAT checkpoint only)

## Decisions
- These gaps need another round of gap closure plans (07-10+)
