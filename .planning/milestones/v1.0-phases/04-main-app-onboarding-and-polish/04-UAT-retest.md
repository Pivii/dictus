---
status: complete
phase: 04-main-app-onboarding-and-polish
source: [04-04-SUMMARY.md, 04-05-SUMMARY.md]
started: 2026-03-07T10:00:00Z
updated: 2026-03-07T10:00:00Z
---

## Current Test

[testing complete]
expected: |
  Reset onboarding (or fresh install). Welcome page shows an animated BrandWaveform (bars breathing/pulsing), not a static logo. All buttons throughout onboarding have white text on colored backgrounds — readable in both light and dark mode.
awaiting: user response

## Tests

### 1. Onboarding — Animated Waveform & Button Contrast
expected: Reset onboarding (or fresh install). Welcome page shows an animated BrandWaveform (bars breathing/pulsing), not a static logo. All buttons throughout onboarding have white text on colored backgrounds — readable in both light and dark mode.
result: issue
reported: "Animated waveform OK. But button text contrast still bad on step 2 (Autoriser le micro) and step 4 (Telecharger) — text barely visible. MicPermissionPage and ModelDownloadPage were missed in the original fix."
severity: major
hotfix: "Changed .foregroundStyle(.primary) to .foregroundColor(.white) on all 4 buttons in MicPermissionPage.swift and ModelDownloadPage.swift"

### 2. Onboarding — Keyboard Setup Doesn't Reset Progress
expected: Reach step 3 (Keyboard Setup). Tap the link to open iOS Settings. After enabling the keyboard, return to Dictus. Onboarding should resume at step 3 (or later), NOT reset to step 1.
result: pass

### 3. Onboarding — Waveform Visible in Light Mode
expected: Switch to light mode. Open onboarding. The waveform bars on Welcome page and Test Recording page should be visible (gray bars on light background, not invisible white-on-white).
result: pass

### 4. Glass Effect on Models & Settings Tabs
expected: Go to Models tab — model cards should have frosted glass styling (matching Home tab cards). Go to Settings tab — section backgrounds should have a glass tint with transparent scroll background.
result: pass

### 5. Keyboard — Key Size & No Layout Shift
expected: Open Dictus keyboard. Keys should feel native-sized (46pt height, comparable to standard iOS keyboard). Tap the mic button — recording overlay appears covering the full keyboard+toolbar area with NO upward shift or clipped buttons.
result: issue
reported: "Key size OK but key colors too dark (nearly black vs native gray) and corners too rectangular. Need to match native iOS keyboard appearance more closely."
severity: cosmetic
hotfix: "Changed letter key fill from Color(.systemBackground) to adaptive gray (22% white in dark mode, white in light mode). Increased cornerRadius from 5pt to 6pt across all key types."

### 6. Keyboard — FullAccessBanner Readable & Deep Link
expected: If FullAccessBanner is visible, it should be clearly readable (footnote-size font, proper padding). Tapping "Activer" should open iOS Settings to the Full Access toggle.
result: issue
reported: "Design fixed (visible, rounded corners, OK). But 'Activer' button does nothing — tried SwiftUI Link, openURL environment, responder chain, and extensionContext.open(). None work from keyboard extension. Needs deeper research."
severity: major
deferred: true

### 7. Keyboard — Large Reactive Waveform
expected: Start recording via keyboard mic. The waveform should be large (nearly full keyboard width, ~140pt tall), with ~40 bars animating fast and reactively to audio input. In light mode, bars should be gray (not invisible white).
result: issue
reported: "Waveform visible and OK in both modes. But cancel/validate buttons clipped at top and 'Listening' text clipped at bottom — structural overflow issue."
severity: major
hotfix: "Restructured RecordingOverlay: buttons fixed at top, timer+status fixed at bottom, waveform uses GeometryReader to fill remaining space (70% of available height). No more overflow."

### 8. Keyboard — Dynamic Type Does Not Scale Keys
expected: Go to iOS Settings > Accessibility > Larger Text, set to maximum. Open Dictus keyboard. Key labels should remain fixed size (like native iOS keyboard) — no overflow, no giant letters.
result: pass

## Summary

total: 8
passed: 4
issues: 4
pending: 0
skipped: 0

## Gaps

[none yet]
