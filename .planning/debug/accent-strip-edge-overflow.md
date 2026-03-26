---
status: diagnosed
trigger: "Accent strip overflow for edge keys (A key top-left, P key top-right)"
created: 2026-03-25T00:00:00Z
updated: 2026-03-25T00:00:00Z
---

## Current Focus

hypothesis: AccentPopup is positioned using `.position(x: accentKeyFrame.midX)` with no clamping to keyboard bounds — edge keys overflow
test: Read AccentPopup.swift and KeyboardRootView.swift positioning code
expecting: No edge-clamping logic exists
next_action: Report diagnosis

## Symptoms

expected: Long-pressing A key shows accent strip fully visible, shifted right so it doesn't overflow left edge. Same for P key on right edge.
actual: Accent strip is centered on the key's midX, causing left overflow for A and right overflow for P.
errors: Visual overflow — accents clipped off-screen
reproduction: Long-press A key (top-left) or P key (top-right)
started: Since accent popup was implemented (Phase 15.5)

## Eliminated

(none — root cause found on first hypothesis)

## Evidence

- timestamp: 2026-03-25
  checked: KeyboardRootView.swift lines 319-327 (accent popup overlay)
  found: AccentPopup positioned with `.position(x: touchState.accentKeyFrame.midX, y: touchState.accentKeyFrame.minY - 40)` — no clamping to keyboard width
  implication: The x position is always the key's center, regardless of proximity to edges

- timestamp: 2026-03-25
  checked: AccentPopup.swift (full file)
  found: AccentPopup is a simple HStack of cells, no awareness of parent bounds or screen edges. totalWidth computed property exists but is unused externally.
  implication: The popup itself has no self-correction logic

- timestamp: 2026-03-25
  checked: KeyboardTouchState.swift showAccents() method (line 62)
  found: Only stores keyFrame and accent options — no keyboard width or edge info passed
  implication: Touch state has no data to compute clamping even if it wanted to

- timestamp: 2026-03-25
  checked: LetterKeyButton.swift touchesMoved() lines 184-186
  found: Hit-testing for accent selection also uses `bounds.midX - totalWidth / 2` as popupStartX — same centered assumption with no edge offset
  implication: Even if the popup were visually clamped, the touch hit-testing would still be wrong unless it uses the same offset

## Resolution

root_cause: |
  The accent popup strip is positioned at `x: touchState.accentKeyFrame.midX` (KeyboardRootView.swift line 324) with no clamping to the keyboard's visible bounds. The popup is always centered on the pressed key.

  For "A" (leftmost key), midX is ~20pt. The accent strip for "a" has ~7 options (a, à, â, ä, æ, á, ã) = 252pt wide. Centered on midX=20pt means the strip starts at x = 20 - 126 = -106pt — far off the left edge.

  Same problem mirrored for "P" on the right edge.

  Additionally, LetterKeyButton.touchesMoved() (line 185) computes `popupStartX = bounds.midX - totalWidth / 2` for accent selection hit-testing. This uses the same centered logic, so if the visual popup is clamped, the touch target calculation must be updated to match.

fix: (not applied — diagnosis only)
verification: (not applied — diagnosis only)
files_changed: []
