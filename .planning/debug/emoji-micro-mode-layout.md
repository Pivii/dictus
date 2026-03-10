---
status: diagnosed
trigger: "Investigate the layout overflow issues in EmojiMicroModeView for the Dictus keyboard extension"
created: 2026-03-10T00:00:00Z
updated: 2026-03-10T00:00:00Z
---

## Current Focus

hypothesis: Four distinct issues, all rooted in EmojiMicroModeView's container structure differing from full mode
test: Compare full mode emoji embedding vs EmojiMicroModeView container
expecting: Identify width/height/structural differences
next_action: Return diagnosis

## Symptoms

expected: Emoji grid fits within keyboard bounds, category bar visible, settings gear instead of globe
actual: Grid overflows horizontally, category bar cut off at top, globe button instead of settings
errors: None (layout issue, not crash)
reproduction: Open keyboard in emojiMicro mode
started: Since EmojiMicroModeView was created

## Eliminated

(none needed -- root causes identified on first analysis)

## Evidence

- timestamp: 2026-03-10
  checked: Full mode emoji embedding in KeyboardView.swift
  found: Full mode uses GeometryReader wrapping a ZStack. EmojiPickerView gets geometry.size.width implicitly. KeyboardView.keyboardHeight expands to standardHeight + 48 + 8 = full area when emoji layer active. No toolbar shown (isEmojiMode hides it in KeyboardRootView line 92).
  implication: Full mode gives EmojiPickerView the entire keyboard+toolbar+spacer height

- timestamp: 2026-03-10
  checked: EmojiMicroModeView.swift container structure
  found: VStack with HStack toolbar (48pt) + EmojiPickerView, all constrained to .frame(height: totalHeight). No GeometryReader. No .clipped(). The EmojiPickerView has .frame(maxWidth: .infinity) but no explicit width constraint. The 48pt toolbar eats into the totalHeight, leaving less vertical space for the picker than in full mode.
  implication: Vertical space is squeezed and no horizontal clipping exists

- timestamp: 2026-03-10
  checked: EmojiPickerView width calculation (line 36-38)
  found: emojiCellWidth = (UIScreen.main.bounds.width - 4) / 8. The grid has .padding(.horizontal, 2). This assumes the parent is full screen width with no additional horizontal padding.
  implication: EmojiMicroModeView adds NO extra horizontal padding to EmojiPickerView itself, so the grid width should theoretically fit. But the toolbar HStack has .padding(.horizontal, 12) which does NOT propagate to EmojiPickerView.

- timestamp: 2026-03-10
  checked: Category bar visibility
  found: EmojiCategoryBar is at the BOTTOM of EmojiPickerView's normalMode (line 142). The user reports it's "cut off at the top" -- this suggests the VStack's totalHeight constraint is too tight. The 48pt toolbar + EmojiPickerView (which has category label + grid + category bar) must all fit in totalHeight. If totalHeight is tight, the bottom category bar gets clipped.
  implication: The category bar is cut off at the BOTTOM (not top) due to vertical overflow within the fixed totalHeight

- timestamp: 2026-03-10
  checked: Globe button vs settings module
  found: EmojiMicroModeView has a globe button (controller.advanceToNextInputMode()). Full mode's ToolbarView has a gear icon linking to dictus:// (settings). The EmojiCategoryBar already has an "ABC" dismiss button that could serve as the keyboard-switch function.
  implication: Globe in EmojiMicroModeView toolbar should be replaced with settings gear (Link to dictus://)

- timestamp: 2026-03-10
  checked: How full mode avoids overflow
  found: In full mode, when emoji layer is active: (1) toolbar is hidden (KeyboardRootView line 92), (2) bottom spacer is hidden (line 116), (3) KeyboardView.keyboardHeight expands by 48+8=56pt to compensate. EmojiPickerView gets the FULL totalContentHeight. No separate toolbar competes for space.
  implication: Full mode gives 100% of height to EmojiPickerView. EmojiMicroModeView splits the same height between its toolbar and the picker.

## Resolution

root_cause: |
  Four issues with distinct root causes:

  1. HORIZONTAL OVERFLOW: EmojiPickerView calculates emojiCellWidth using UIScreen.main.bounds.width.
     This is correct and matches full mode. The actual overflow is likely caused by the ScrollView
     content exceeding bounds without .clipped() on the container. In full mode, GeometryReader
     naturally clips content. EmojiMicroModeView's VStack has no clipping modifier.

  2. CATEGORY BAR CUT OFF: EmojiMicroModeView allocates 48pt to its own toolbar, then gives
     the remaining (totalHeight - 48) to EmojiPickerView. But EmojiPickerView was designed to
     use the full totalContentHeight (toolbar 48 + keyboard ~208 + spacer 8 = ~264pt). With only
     ~216pt available, the bottom EmojiCategoryBar (40pt) + category label (~24pt) leaves
     insufficient space for the grid, or the category bar itself gets clipped.

  3. GLOBE BUTTON: EmojiMicroModeView's toolbar has a globe button for input method switching.
     The user wants it replaced with the settings gear (Link to dictus://) matching ToolbarView.
     The globe/input-switching function is already available via the "ABC" button in
     EmojiCategoryBar -- but in emojiMicro mode, onDismiss is a no-op, so ABC does nothing.
     Either the ABC button should become the globe (advanceToNextInputMode), or the toolbar
     globe should become the gear.

  4. NOT REUSING SAME LAYOUT: The fundamental design difference is that full mode hides its
     toolbar when in emoji mode and gives EmojiPickerView the full height. EmojiMicroModeView
     keeps a separate toolbar visible, splitting the height.

fix: |
  Recommended approach -- make EmojiMicroModeView mirror full mode's pattern:

  A) Replace the 48pt toolbar with a modified approach:
     - Replace globe button with settings gear (Link to dictus://)
     - Keep mic pill on the right
     - Add .clipped() to the overall VStack or EmojiPickerView container

  B) Fix the vertical space issue:
     - Option 1: Remove the separate toolbar entirely. Add the mic pill and gear icon
       INTO the EmojiCategoryBar (customize it for emojiMicro mode). This gives
       EmojiPickerView the full totalHeight.
     - Option 2: Keep the toolbar but increase totalHeight for emojiMicro mode to
       account for the extra 48pt.
     - Option 3 (simplest): Keep current structure, add .clipped(), and ensure
       EmojiPickerView's internal layout uses .frame(maxHeight: .infinity) to
       let the grid shrink to fit available space.

  C) Fix the ABC button in emojiMicro context:
     - Change onDismiss from no-op to controller.advanceToNextInputMode()
     - This way ABC = switch keyboard (replaces globe), toolbar gear = settings

  D) Add .clipped() to the EmojiPickerView container to prevent horizontal overflow.

verification: Not yet applied
files_changed: []
