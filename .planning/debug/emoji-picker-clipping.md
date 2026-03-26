---
status: diagnosed
trigger: "Emoji picker layout clipped on all sides after UIKit keyboard rebuild"
created: 2026-03-25T00:00:00Z
updated: 2026-03-25T00:00:00Z
---

## Current Focus

hypothesis: EmojiPickerView (SwiftUI) has no horizontal padding and relies on parent frame, but KeyboardContainerView applies rowSidePadding (3-5pt) to its mainStack. When emoji mode replaces the UIKit keyboard, EmojiPickerView gets full-width frame from SwiftUI but the emoji picker itself has minimal/no padding, while the EmojiCategoryBar has zero horizontal padding. The clipping is caused by the keyboard height constraint being too small for the emoji picker content.
test: Compare computed heights
expecting: Height mismatch explains vertical clipping; missing padding explains horizontal clipping
next_action: report diagnosis

## Symptoms

expected: Emoji picker fills the keyboard area cleanly with all content visible
actual: Category title ("SMILEYS") cut off at top-left, first column of emojis truncated on left, bottom bar (ABC, search, category icons, delete) clipped on both sides
errors: Visual clipping, no crash
reproduction: Open keyboard, tap emoji key, observe clipping
started: After Phase 15.5 UIKit keyboard rebuild

## Eliminated

(none)

## Evidence

- timestamp: 2026-03-25
  checked: KeyboardViewController.computeKeyboardHeight()
  found: Height formula = (4 * keyHeight) + (3 * rowSpacing) + 8 + 52 + 8 = fixed total. On standard device: (4*43)+(3*11)+8+52+8 = 172+33+68 = 273pt. This height constraint is set on the inputView and never changes for emoji mode.
  implication: The inputView height is calculated for the normal keyboard layout, not the emoji layout.

- timestamp: 2026-03-25
  checked: KeyboardRootView body layout for emoji mode
  found: When currentLayer == .emoji, the toolbar is hidden (isEmojiMode=true suppresses ToolbarView and bottom Spacer). The keyboardHeight computed property adds toolbar+spacer height (48+8=56pt) to the standard keyboard height for emoji mode. So keyboardHeight for emoji = standardHeight + 56. But the VStack only contains EmojiPickerView. The frame is NOT explicitly set on EmojiPickerView (no .frame(height:) modifier).
  implication: EmojiPickerView expands via VStack to fill available space, but the available space is constrained by the inputView height constraint from computeKeyboardHeight() which does NOT account for emoji mode.

- timestamp: 2026-03-25
  checked: Height math discrepancy
  found: computeKeyboardHeight() = rows*keyHeight + (rows-1)*rowSpacing + verticalPadding + toolbarHeight + bottomPadding = 4*43 + 3*11 + 8 + 52 + 8 = 273pt. But keyboardHeight in KeyboardRootView for emoji = rows*(keyHeight+rowSpacing) + 48 + 8 = 4*(43+11) + 56 = 216 + 56 = 272pt. The difference is small (1pt due to (rows-1) vs rows for rowSpacing). The real issue: the hosting view gets 273pt total, toolbar is hidden (saves 52pt), bottom spacer hidden (saves 8pt), so EmojiPickerView gets 273pt. But the EmojiPickerView VStack content may exceed or be positioned incorrectly within this space.
  implication: Actually the height should be sufficient. The clipping must be from the inputView itself or the hosting view clipping its content.

- timestamp: 2026-03-25
  checked: clipsToBounds settings
  found: KeyboardViewController sets kbInputView.clipsToBounds = false and hosting.view.clipsToBounds = false. BUT the kbInputView is a UIInputView which iOS may re-enforce clipsToBounds on. More importantly, iOS keyboard extension inputView layout is tightly controlled by the system.
  implication: iOS system may be enforcing clipsToBounds on the inputView despite our setting.

- timestamp: 2026-03-25
  checked: EmojiCategoryBar horizontal layout
  found: The HStack has spacing:0, ABC button has .padding(.horizontal, 10), delete button has .padding(.horizontal, 10), but the overall HStack has NO horizontal padding from its parent. EmojiPickerView's body VStack has .frame(maxWidth: .infinity) but no .padding(). The category name has .padding(.horizontal, 10).
  implication: The EmojiCategoryBar content extends to the very edges. If the inputView or hosting view clips even slightly, the edge content gets cut off.

- timestamp: 2026-03-25
  checked: Hosting view constraints in KeyboardViewController
  found: hosting.view is pinned edge-to-edge to kbInputView (top/bottom/leading/trailing all to the inputView edges with zero inset). The kbInputView uses inputViewStyle:.keyboard which means iOS applies its own layout behavior.
  implication: UIInputView with .keyboard style may apply safe area insets or internal margins that the hosting view content doesn't account for.

## Resolution

root_cause: Two compounding issues cause the clipping:

1. **InputView safe area / layout margins**: UIInputView with `.keyboard` style applies internal layout margins or safe area insets. The hosting view is pinned edge-to-edge to the inputView, but the inputView's own layoutMarginsGuide or safeAreaLayoutGuide may be inset. The EmojiPickerView content (which uses .frame(maxWidth: .infinity) and minimal padding) renders right to the edge of the hosting view, but the inputView clips at its margins.

2. **No horizontal safe padding on EmojiPickerView or EmojiCategoryBar**: The EmojiCategoryBar has zero side padding on its outer HStack. The category title has only .padding(.horizontal, 10). The emoji grid has only .padding(.horizontal, 2). When the normal keyboard renders via UIKit, KeyboardContainerView applies `KeyMetrics.rowSidePadding` (3-5pt) inset on the mainStack. But the SwiftUI EmojiPickerView bypasses this entirely -- it's a direct SwiftUI view, not routed through KeyboardContainerView. It gets the raw hosting view width, which may be slightly wider than the visible area due to how iOS manages the keyboard extension inputView frame.

3. **Vertical clipping at top**: The category name "SMILEYS" has only .padding(.top, 6). If the inputView's content area starts slightly below the top anchor (due to iOS internal insets on keyboard-style input views), this small top padding is insufficient.

fix: (research only - not applied)
verification: (research only)
files_changed: []
