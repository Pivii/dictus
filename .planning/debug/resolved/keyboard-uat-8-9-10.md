---
status: resolved
trigger: "Investigate 6 keyboard-related issues from UAT Tests 8, 9, 10"
created: 2026-03-07T00:00:00Z
updated: 2026-03-07T00:00:00Z
---

## Current Focus

hypothesis: All 6 issues have identified root causes
test: n/a — diagnosis only
expecting: n/a
next_action: return structured findings

## Symptoms

expected: Keyboard matches native iOS keyboard in height/feel, recording overlay transitions cleanly, FullAccessBanner is readable with correct deep link, key labels don't scale, waveform is prominent
actual: Layout shifts on mic tap, keyboard too short, banner too small, deep link wrong, keys scale with Dynamic Type, waveform too small
errors: none (visual/UX issues)
reproduction: Open Dictus keyboard in any text field
started: Since initial implementation

## Eliminated

(none — all hypotheses confirmed)

## Evidence

- timestamp: 2026-03-07
  checked: Issue 1 — Layout shift on mic tap (RecordingOverlay.swift, KeyboardRootView.swift)
  found: Root cause is the conditional rendering in KeyboardRootView (lines 41-62). When recording starts, ToolbarView (44px) + KeyboardView are replaced by RecordingOverlay alone. The RecordingOverlay is constrained to `keyboardHeight` (194px) which does NOT include the toolbar's 44px. So the total VStack height drops by 44px, causing everything to shift up. Additionally, RecordingOverlay's recordingContent uses VStack with .padding(.top, 8) and no bottom padding — the cancel/validate buttons at the top have minimal top margin and can get clipped.
  implication: The height mismatch between (toolbar+keyboard) and (overlay alone) causes the layout jump

- timestamp: 2026-03-07
  checked: Issue 2 — Keyboard too short / keys too small (KeyMetrics, KeyboardViewController.swift)
  found: KeyMetrics.keyHeight is 42pt (KeyButton.swift line 217). Native iOS keyboard key height is approximately 46-47pt. The total computed keyboard height is 4*42 + 3*6 + 8 + 44 = 238pt (KeyboardViewController.swift line 88-94). The standard iOS keyboard is approximately 260-271pt (depending on device). The 42pt key height and 6pt row spacing produce a keyboard that is noticeably shorter than native.
  implication: keyHeight should be ~46pt and possibly adjust rowSpacing to match native feel

- timestamp: 2026-03-07
  checked: Issue 3 — FullAccessBanner barely visible (FullAccessBanner.swift)
  found: The banner uses `.font(.dictusCaption)` for both the icon and text (line 15, 18), which maps to `.system(.caption)` — approximately 12pt text. The vertical padding is only 6pt (line 32). Combined, the banner is roughly 24-26pt tall total. This is very compressed. The icon also uses `.dictusCaption` which makes the warning icon tiny.
  implication: Font size too small, padding too tight — needs larger font, more padding, and a bigger icon

- timestamp: 2026-03-07
  checked: Issue 4 — FullAccessBanner deep link wrong (FullAccessBanner.swift line 25)
  found: The URL `"app-settings:"` opens the app's own Settings.bundle page in iOS Settings. However, Dictus likely does NOT have a Settings.bundle (keyboard enable/Full Access is under Settings > General > Keyboard > Keyboards, not in an app-specific settings page). So `app-settings:` opens either a blank settings page or the top level of iOS Settings. The correct approach for keyboard extensions is either (a) use `UIApplication.openSettingsURLString` (but unavailable in extensions), (b) deep link to DictusApp via `dictus://settings` URL scheme so the app can guide the user, or (c) accept that iOS provides no direct deep link to keyboard settings and improve the banner text with instructions.
  implication: `app-settings:` doesn't navigate to keyboard-specific settings — it opens the app's Settings.bundle page which likely doesn't exist or is empty

- timestamp: 2026-03-07
  checked: Issue 5 — Dynamic Type scales key labels (KeyButton.swift line 50)
  found: `@ScaledMetric private var keyFontSize: CGFloat = 22` on line 50 of KeyButton.swift. This makes key labels grow/shrink with Dynamic Type. The native iOS keyboard does NOT scale its key labels — they remain fixed regardless of the user's text size preference. Same issue in KeyPopup (line 200: `@ScaledMetric private var popupFontSize: CGFloat = 32`). The ScaledMetric was applied with good accessibility intent but diverges from native keyboard behavior.
  implication: Replace @ScaledMetric with plain CGFloat constants for key label font sizes

- timestamp: 2026-03-07
  checked: Issue 6 — Keyboard waveform too small (BrandWaveform.swift, RecordingOverlay.swift)
  found: In RecordingOverlay.swift line 84, BrandWaveform is called with `maxHeight: 100` and `.padding(.horizontal, 8)`. The waveform uses 30 bars of `barWidth: 4` (ScaledMetric, line 19) with spacing 3 (line 25). Total waveform width = 30*4 + 29*3 = 207pt — far less than screen width (~375pt+). The maxHeight of 100 is modest given the overlay has ~194pt of usable space. The waveform also uses @ScaledMetric for barWidth which is unnecessary for a visualization element. The 0.15s animation duration (line 31) may feel sluggish for real-time audio reactivity.
  implication: Waveform needs wider bars or more bars to fill width, taller maxHeight, and consider removing ScaledMetric from barWidth

## Resolution

root_cause: See per-issue findings above — 6 distinct root causes identified
fix: (not applied — diagnosis only)
verification: (not applicable)
files_changed: []
