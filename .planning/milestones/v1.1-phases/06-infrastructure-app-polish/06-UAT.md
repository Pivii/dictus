---
status: complete
phase: 06-infrastructure-app-polish
source: [06-01-SUMMARY.md, 06-02-SUMMARY.md, 06-03-SUMMARY.md]
started: 2026-03-08T10:00:00Z
updated: 2026-03-08T10:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. App Icon on Home Screen
expected: The app icon shows 3 vertical bars on dark navy background. Bars are staggered (not bottom-aligned), with correct brand kit proportions. Center bar has blue gradient, side bars are white semi-transparent. Dark mode variant is visually distinct (darker surface gradient).
result: pass

### 2. HomeView — No Duplicate Title
expected: Opening the app shows the HomeView with the Dictus logo section at top. There is NO duplicate white "Dictus" navigation title bar above the logo area.
result: pass

### 3. HomeView — Model Card Display
expected: The model card on HomeView shows a human-readable name like "Whisper Small" and approximate size (e.g. "~250 MB") instead of a raw identifier like "openai_whisper-small".
result: pass

### 4. HomeView — Fresh State After Onboarding
expected: After completing onboarding (including model download), the HomeView immediately shows the correct downloaded model info without needing to relaunch the app. Content is vertically centered on screen.
result: pass

### 5. Recording Screen — Immersive UI
expected: Tapping the mic button opens an immersive recording screen. The nav bar stays hidden after transcription until user taps "Terminer" or "Nouvelle dictée". During processing, the waveform continues in a sinusoidal pattern (no logo animation interruption).
result: pass

### 6. Onboarding — No Swiping Between Steps
expected: During onboarding, swiping left/right does NOT change the step. Steps only advance via buttons. Step indicator dots show progress.
result: pass

### 7. Onboarding — Keyboard Auto-Detection
expected: On the keyboard setup page, after enabling "Dictus" in Settings > Keyboards and returning, the page auto-detects the keyboard is enabled and advances after a brief delay.
result: pass

### 8. Onboarding — Model Download Page
expected: The model download page shows clear French instructions. Download does NOT auto-advance — user controls when to proceed.
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
