---
status: resolved
trigger: "Investigate 5 sub-issues in the onboarding flow (Test 3 from UAT)"
created: 2026-03-07T00:00:00Z
updated: 2026-03-07T00:00:00Z
---

## Current Focus

hypothesis: All 5 root causes identified through code analysis
test: n/a (diagnosis only)
expecting: n/a
next_action: Return structured findings

## Symptoms

expected: Onboarding flow works correctly with animations, readable text, persistent state, and adaptive colors
actual: 5 distinct issues: static waveform, poor button contrast, state reset on Settings return, invisible waveform bars in light mode
errors: none (visual/UX issues)
reproduction: Walk through onboarding steps, toggle light/dark mode, leave to Settings and return
started: Since initial implementation

## Evidence

- timestamp: 2026-03-07
  checked: WelcomePage.swift lines 19-21
  found: WelcomePage uses DictusLogo (static 3-bar logo), NOT BrandWaveform. The comment on line 7 mentions "BrandWaveform with animated energy" but the implementation on line 20 is `DictusLogo(height: 100)`. No animation state, no energy levels, no timer — just a static logo render.
  implication: Issue 1 root cause — the animated waveform was never implemented, only documented in comments.

- timestamp: 2026-03-07
  checked: WelcomePage.swift line 42, KeyboardSetupPage.swift line 70, TestRecordingPage.swift lines 118/135
  found: All buttons use `.foregroundStyle(.primary)` for text color. `.primary` is black in light mode, white-ish in dark mode. The buttons have colored backgrounds (`.dictusAccent` blue or `.dictusSuccess` green). Only WelcomePage line 42 uses `.foregroundColor(.white)` — the others use `.foregroundStyle(.primary)`. In dark mode, `.primary` is near-white which works. In light mode, `.primary` is black text on blue/green background — poor contrast.
  implication: Issue 2 root cause — button text uses `.foregroundStyle(.primary)` instead of hardcoded `.white`.

- timestamp: 2026-03-07
  checked: OnboardingView.swift lines 20-21, 30, 63-68
  found: `currentPage` is `@State private var currentPage: Int = 0`. When user taps "Ouvrir les Reglages" on KeyboardSetupPage (step index 2), the app backgrounds. On return, the view may re-initialize because fullScreenCover content can be recreated by SwiftUI when scene phase changes. `@State` initializer runs again on view re-creation, resetting `currentPage` to 0. There is no persistence of the current page (no @AppStorage, no @SceneStorage).
  implication: Issue 3 root cause — `currentPage` is ephemeral @State with initial value 0, no persistence across app backgrounding/foregrounding.

- timestamp: 2026-03-07
  checked: BrandWaveform.swift lines 91-94
  found: Outer bars (60% of bars) use `Color.white.opacity(...)` hardcoded. No color scheme adaptation. On light backgrounds (light mode), white bars are invisible.
  implication: Issue 4 root cause — BrandWaveform outer bar color is hardcoded white, not adaptive.

- timestamp: 2026-03-07
  checked: DictusLogo.swift line 42
  found: DictusLogo side bars also use `Color.white.opacity(opacities[index])` hardcoded. Same issue — invisible on light backgrounds.
  implication: DictusLogo has the same light-mode invisibility issue (bonus finding).

- timestamp: 2026-03-07
  checked: TestRecordingPage.swift lines 28-33
  found: TestRecordingPage uses BrandWaveform which has the same hardcoded white outer bars from BrandWaveform.swift line 93.
  implication: Issue 5 root cause — same as Issue 4, BrandWaveform.colorForBar() uses hardcoded white.

## Resolution

root_cause: See per-issue breakdown below
fix: Not applied (diagnosis only)
verification: n/a
files_changed: []
