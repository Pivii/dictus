---
status: diagnosed
trigger: "Diagnose key popup preview issues (no stem, clipping, too high)"
created: 2026-03-25T00:00:00Z
updated: 2026-03-25T00:00:00Z
---

## Current Focus

hypothesis: Three separate issues — missing stem shape, ZStack clipping, and hardcoded Y offset
test: code review of KeyPopup, KeyboardRootView ZStack, and positioning logic
expecting: confirm root causes for all three symptoms
next_action: report diagnosis

## Symptoms

expected: Key popup shows a bubble with a "neck/stem" connecting to the pressed key (Apple-style). First-row popups visible above keyboard bounds. Popup positioned naturally above key.
actual: Popup is a floating rectangle with no stem. First-row popups clipped by keyboard top edge. Popup appears too high above the key.
errors: none (visual issue)
reproduction: press any letter key — observe popup
started: since Phase 15.5 UIKit migration

## Eliminated

(none — first pass diagnosis)

## Evidence

- timestamp: 2026-03-25
  checked: KeyPopup view (KeyboardTypes.swift lines 105-122)
  found: KeyPopup is a plain Text inside a RoundedRectangle. No stem/neck shape at all — just a 50x56pt rounded rect with shadow.
  implication: ROOT CAUSE for symptom 1 (no stem). The shape needs a custom Path with a tapered neck extending downward toward the pressed key.

- timestamp: 2026-03-25
  checked: KeyboardRootView ZStack popup positioning (lines 209-316)
  found: The popup overlay lives INSIDE a ZStack(alignment: .top) that is constrained to `.frame(height: keyboardHeight)` (line 308). SwiftUI clips content to the frame by default in layout, and .position() places the view's center at the given point. For top-row keys, `pressedKeyFrame.minY - 36` yields a negative Y value (above the ZStack's top edge), which gets clipped.
  implication: ROOT CAUSE for symptom 2 (first-row clipping). The ZStack's frame acts as a clipping boundary. The popup overlay needs to either: use .clipped(false) / set clipsToBounds, or be moved outside the height-constrained ZStack.

- timestamp: 2026-03-25
  checked: Popup Y positioning (KeyboardRootView line 314)
  found: `.position(y: touchState.pressedKeyFrame.minY - 36)` — hardcoded 36pt offset above key's minY. The popup height is 56pt, so its center is at 28pt. Subtracting 36pt means the popup's bottom edge is at `minY - 36 + 28 = minY - 8`, which is 8pt above the key top. With a stem, this gap would look natural, but WITHOUT a stem it appears to float too high.
  implication: ROOT CAUSE for symptom 3 (too high). The offset doesn't account for the popup's actual height or a connecting stem. Should be closer to `minY - (popupHeight/2)` plus stem length.

- timestamp: 2026-03-25
  checked: frameInKeyboardCoordinateSpace() in LetterKeyButton (lines 273-278)
  found: Walks up 3 superview levels (button -> rowStack -> mainStack -> container) to convert coordinates. This should correctly map to the KeyboardContainerView's coordinate space. The KeyboardContainerView is the UIView embedded by KeyboardUIView (UIViewRepresentable). Since the ZStack positions the popup using these coordinates, and the UIView fills the ZStack frame, coordinate mapping appears correct.
  implication: Frame reporting is not a separate issue — coordinates are in the right space.

## Resolution

root_cause: |
  THREE distinct root causes:

  1. NO STEM: KeyPopup (KeyboardTypes.swift:105-122) renders a plain RoundedRectangle with no stem/neck shape. Apple's popup has a balloon shape with a tapered extension pointing down to the pressed key. This requires a custom Shape (Path) that draws the rounded bubble + stem.

  2. FIRST-ROW CLIPPING: The popup overlay is inside a ZStack with `.frame(height: keyboardHeight)` (KeyboardRootView.swift:308). SwiftUI lays out the ZStack at exactly keyboardHeight. The popup positioned at `pressedKeyFrame.minY - 36` goes above Y=0 for first-row keys, and SwiftUI clips it to the frame. The ZStack does not explicitly set `.clipped(false)`, and the default layout behavior constrains content.

  3. TOO HIGH: The Y offset is hardcoded at -36 from key's minY (KeyboardRootView.swift:314). The popup is 56pt tall (center at 28pt from top). The bottom edge ends up 8pt above the key with no visual connection. With a proper stem shape, the offset should place the stem's tip at or near the key's top edge, and the bubble above that.

fix: (research only — not applied)
verification: (research only)
files_changed: []
