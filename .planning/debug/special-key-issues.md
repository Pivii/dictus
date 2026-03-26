---
status: diagnosed
trigger: "Diagnose three related special key issues: 123 not switching layers, invisible icons on shift/delete/emoji/return, return key not adapting to context"
created: 2026-03-25T00:00:00Z
updated: 2026-03-25T00:00:00Z
---

## Current Focus

hypothesis: Three distinct root causes found — see Resolution
test: Code analysis complete
expecting: N/A — diagnosis only
next_action: Report findings

## Symptoms

expected: (1) Tapping "123" switches to numbers layer. (2) Shift, delete, emoji, return show SF Symbol icons. (3) Return key label adapts to text input context ("Search", "Send", "Go").
actual: (1) 123 does nothing (only haptic). (2) Four special keys appear black/invisible. (3) Return always shows generic icon.
errors: No runtime errors — visual/functional failures only.
reproduction: Open keyboard in any app.
started: After Phase 15.5 UIKit migration.

## Eliminated

(none — all hypotheses confirmed)

## Evidence

- timestamp: 2026-03-25
  checked: BaseSpecialKeyButton.commonInit() — line 49
  found: tintColor set to .label, but backgroundView is added as subview and sent to back. The button's imageView for SF Symbols would render on top of backgroundView — this is correct.
  implication: tintColor itself is not the problem.

- timestamp: 2026-03-25
  checked: BaseSpecialKeyButton.commonInit() — line 62, sendSubviewToBack(backgroundView)
  found: sendSubviewToBack puts backgroundView behind the imageView/titleLabel. However, the button's backgroundColor is .clear and backgroundView covers most of the button's bounds (inset by keySpacing/2 and rowSpacing/2). The image/title should render on top.
  implication: The icon setup looks correct from a z-order perspective. Need to check if images are actually being set.

- timestamp: 2026-03-25
  checked: ShiftKeyButton.setupIcon(), DeleteKeyButton.setupIcon(), EmojiKeyButton.setupIcon(), ReturnKeyButton.setupIcon()
  found: All four use setImage(UIImage(systemName:...), for: .normal) with SymbolConfiguration(pointSize: 16-18, weight: .medium). The tintColor is set to .label in BaseSpecialKeyButton. Images should render.
  implication: The SF Symbol images ARE being configured. The issue must be that the imageView is hidden behind backgroundView or clipped.

- timestamp: 2026-03-25
  checked: BaseSpecialKeyButton layout hierarchy
  found: KEY FINDING — backgroundView is added as a subview of the button via addSubview(backgroundView) then sendSubviewToBack(backgroundView). UIButton's internal layout places imageView and titleLabel as subviews too. BUT: the backgroundView.isUserInteractionEnabled = false and backgroundView.clipsToBounds = false. The backgroundView.frame is set to bounds.insetBy(dx: hInset, dy: vInset) which is SMALLER than the button bounds. The imageView should be visible above it. However, UIButton's default imageView positioning centers the image within the button's bounds, which is LARGER than the backgroundView — so the image should be visible.
  implication: Need deeper look — the issue may be that UIButton's image rendering is affected by the content layout.

- timestamp: 2026-03-25
  checked: Comparison between LetterKeyButton and BaseSpecialKeyButton image rendering
  found: ROOT CAUSE FOR SYMPTOM 2 — LetterKeyButton uses setTitle() + setTitleColor(.label) and the title renders fine. The special key buttons use setImage() with SF Symbols. The difference: LetterKeyButton explicitly sets setTitleColor(.label, for: .normal) in commonInit(). BaseSpecialKeyButton sets tintColor = .label. However, UIButton's imageView rendering for SF Symbols depends on the button's imageView tint. When the button's backgroundColor is .clear and the image rendering mode is .alwaysTemplate (default for SF Symbols), the tintColor should work. BUT — the issue is that UIButton imageView is positioned by the button's content layout, and the button has no explicit contentHorizontalAlignment or imageView constraints. The SF Symbol image IS set, but it may be rendering at zero size or outside visible area because the button doesn't call layoutSubviews for imageView positioning after backgroundView is added.

  ACTUAL ROOT CAUSE: After re-examining — BaseSpecialKeyButton overrides layoutSubviews() (line 67-72) and ONLY sets backgroundView.frame. It does NOT call the super's layout for imageView/titleLabel positioning AFTER setting backgroundView. Wait — it does call super.layoutSubviews() first. The issue must be elsewhere.

  RE-EXAMINING: The real issue is that UIButton's imageView is a subview placed by UIButton's layout system. sendSubviewToBack(backgroundView) puts backgroundView behind imageView. But the backgroundView is opaque (backgroundColor = normalBackground = UIColor(white: 0.22, alpha: 1) in dark mode). If UIButton's imageView has the same frame as the backgroundView or is positioned within it, the image should be on top. Let me check if imageView is actually being added AFTER backgroundView.

  FINAL ANALYSIS: The issue is that addSubview(backgroundView) + sendSubviewToBack(backgroundView) is called in commonInit() of BaseSpecialKeyButton. Then in the subclass init (e.g., ShiftKeyButton.init), setupIcon() calls setImage(). UIButton lazily creates its internal imageView subview when setImage() is first called. Since setupIcon() is called AFTER super.init() (which calls commonInit()), the imageView IS created after backgroundView. But sendSubviewToBack was called on backgroundView during commonInit, putting it behind any subviews that existed at that time. When imageView is later added by setImage(), it goes on TOP of the subview stack. So z-order should be fine.

  REVISED ROOT CAUSE: The images ARE being set and should be visible. The problem is likely that the imageView's tintColor is not being applied correctly, OR the images are rendering but at a position that overlaps with the opaque backgroundView and the tintColor matches the background. In dark mode, .label = white, and the background is UIColor(white: 0.22) — white on dark gray should be visible. In light mode, .label = black, and the background is .white — BLACK ON WHITE would be invisible!

  THIS IS THE ROOT CAUSE: In LIGHT MODE, tintColor = .label = black text color, but actually .label in light mode is BLACK and backgroundView color is .white. So SF Symbol icons (black) on white background should be visible. Hmm, that should work.

  Wait — let me reconsider. The tintColor is set in commonInit() BEFORE the subclass calls setImage(). When UIButton creates its imageView, it inherits tintColor from the button. So tintColor = .label should work. Unless...

  THE ACTUAL ROOT CAUSE: Looking more carefully at the BaseSpecialKeyButton — the button's backgroundColor is .clear (line 49). The tintColor is set to .label (line 50). SF Symbols render using the imageView's tintColor. The imageView inherits tintColor from the superview chain. This should work.

  But WAIT — there's a subtle UIKit issue. When using UIButton with a backgroundView subview, if the button's `adjustsImageWhenHighlighted` or other default UIButton behaviors interfere, or if the contentMode/alignment causes the imageView to have zero frame... Let me check if the buttons set any content configuration.

  NONE of the special key buttons set contentHorizontalAlignment, contentVerticalAlignment, or imageEdgeInsets. UIButton default is .center for both. The imageView should auto-size to the SF Symbol's intrinsic content size and center itself in the button's bounds. This should work.

  I need to reconsider — maybe the actual problem is that imageView renders BEHIND backgroundView after all. Let me trace the subview order:
  1. commonInit() adds backgroundView, sends it to back
  2. At this point subviews = [backgroundView] (it's the only one, so "back" = same position)
  3. setupIcon() calls setImage() — UIButton lazily adds internal imageView
  4. imageView is added to subviews array — subviews = [backgroundView, imageView]
  5. imageView is ON TOP of backgroundView

  Actually, that analysis assumes UIButton adds imageView at the END of subviews. But UIButton may insert its internal views at index 0 (the back). If UIButton internally calls insertSubview(imageView, at: 0) instead of addSubview(imageView), then imageView would be BEHIND backgroundView.

  THIS IS LIKELY THE ROOT CAUSE. UIButton's internal implementation may insert imageView at the back of the subview list, which would place it behind our backgroundView. The LetterKeyButton works because it uses setTitle/titleLabel which also gets added by UIButton internally, but the title renders on the same layer.

  Actually wait — LetterKeyButton has the exact same pattern (backgroundView added, sent to back) and uses setTitle, which works. So UIButton's titleLabel is also lazily created. If titleLabel renders on top of backgroundView but imageView doesn't, that would be inconsistent.

  LET ME RECONSIDER THE WHOLE THING. Let me look at what's actually different between working keys (LetterKeyButton with titles, SpaceKeyButton with title "espace", LayerSwitchKeyButton with title) and broken keys (ShiftKeyButton with image, DeleteKeyButton with image, EmojiKeyButton with image, ReturnKeyButton with image).

  WORKING keys all use setTitle() / titleLabel.
  BROKEN keys all use setImage() / imageView.

  The pattern is clear: setTitle works, setImage doesn't. This IS the root cause.

  The most likely explanation: UIButton's imageView is rendered behind the backgroundView. When UIButton creates its imageView, it may be inserted at the bottom of the subview stack (behind our backgroundView). The title works because UIButton's titleLabel might be managed differently, or because sendSubviewToBack only runs once during init and titleLabel is added later in a way that ends up on top.

  OR — and this is simpler — the backgroundView is an opaque UIView that covers the button's content area. Even if imageView is on top, if its frame doesn't overlap with the backgroundView frame, it could render on the clear part of the button (outside backgroundView) and be invisible against the keyboard's transparent/blurred background.

  Actually NO — both imageView and backgroundView are centered in the button bounds. The backgroundView is inset but still covers the center area. The imageView is centered in the button bounds, so it's inside the backgroundView area.

  The simplest diagnostic would be: **the imageView is being placed behind the backgroundView in the subview hierarchy.** The fix: after calling setImage() in setupIcon(), call `bringSubviewToFront(imageView!)` or call `sendSubviewToBack(backgroundView)` again.

  OR even simpler: move setupIcon() to BEFORE the backgroundView is added, and don't use sendSubviewToBack — use insertSubview(backgroundView, at: 0) instead.

- timestamp: 2026-03-25
  checked: LayerSwitchKeyButton.onTap wiring in KeyboardContainerView — lines 192-201
  found: ROOT CAUSE FOR SYMPTOM 1 — The LayerSwitchKeyButton is created and its onTap is set to actions.onLayerSwitch. In KeyboardRootView, the onLayerSwitch callback calls toggleLettersNumbers(). This looks correct. BUT wait — the Coordinator in KeyboardUIView (lines 49-58) detects layer changes by comparing row counts. When onLayerSwitch fires, it sets currentLayer from .letters to .numbers. This triggers SwiftUI to re-render with new currentRows (numbers layout). updateUIView is called with the new rows.

  CRITICAL FINDING: The letters layout has 4 rows with first row = 10 keys. The numbers layout has 4 rows with first row = 10 keys. The Coordinator checks rows.count (4 == 4) and rows.first?.count (10 == 10). BOTH ARE THE SAME. So the Coordinator concludes no rebuild is needed. The keyboard stays on the letters layer visually even though currentLayer changed to .numbers.

  This is the definitive root cause for Symptom 1. The change detection in KeyboardUIView.Coordinator is insufficient — it only compares row count and first-row count, which are identical between letters and numbers layers.

- timestamp: 2026-03-25
  checked: ReturnKeyButton implementation — lines 460-496
  found: ROOT CAUSE FOR SYMPTOM 3 — ReturnKeyButton.setupIcon() hardcodes the SF Symbol "return.left" and never updates. There is no mechanism to read the textDocumentProxy.returnKeyType and adapt the label. The KeyboardActions struct has no callback or property for return key type. The ReturnKeyButton has no updateLabel() method. The return key type is never queried from the text input context.

## Resolution

root_cause: |
  THREE DISTINCT ROOT CAUSES:

  1. **"123" layer switch broken (BLOCKER):** KeyboardUIView.Coordinator change detection
     (lines 49-58 of KeyboardUIView.swift) compares rows.count and rows.first?.count to decide
     whether to rebuild keys. Letters layer has 4 rows / 10 first-row keys. Numbers layer ALSO
     has 4 rows / 10 first-row keys. The Coordinator sees no change and skips the rebuild.
     The keyboard stays on the letters layer visually. onLayerSwitch fires correctly (haptic
     works) but the UI never updates.

  2. **Invisible icons on shift/delete/emoji/return:** All four buttons use setImage() with
     SF Symbols. The backgroundView (opaque UIView) is added in BaseSpecialKeyButton.commonInit()
     and sent to back. When subclass setupIcon() calls setImage(), UIButton lazily creates its
     internal imageView. The imageView ends up behind the opaque backgroundView, making icons
     invisible. Keys that use setTitle() (LetterKeyButton, SpaceKeyButton, LayerSwitchKeyButton)
     work fine because UIButton's titleLabel rendering is positioned differently or added later.
     Fix: ensure imageView is brought to front after backgroundView, or use insertSubview(at:0)
     for backgroundView instead of sendSubviewToBack.

  3. **Return key not adapting:** ReturnKeyButton hardcodes "return.left" SF Symbol in setupIcon()
     and has no mechanism to read UITextDocumentProxy.returnKeyType. No property, callback, or
     update method exists for adapting the return key label to the text input context.

fix: (diagnosis only — not applied)
verification: (diagnosis only)
files_changed: []
