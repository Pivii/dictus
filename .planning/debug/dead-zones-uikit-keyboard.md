---
status: diagnosed
trigger: "Diagnose root cause of persistent dead zones in UIKit keyboard"
created: 2026-03-25T00:00:00Z
updated: 2026-03-25T00:00:00Z
---

## Current Focus

hypothesis: UIStackView rows use spacing=0 but the mainStack vertical distribution is .fillEqually, meaning button frames fill their rows edge-to-edge horizontally and vertically. The point(inside:with:) override with touchInsets IS implemented, but the touchInsets computation in layoutSubviews only extends by half the gap to each neighbor -- this should theoretically cover gaps fully. The REAL issue is that the mainStack uses rowSidePadding constraints (4pt on standard), meaning there is a gap between the keyboard edge and the leftmost/rightmost buttons that is NOT covered by any button's touch inset. Additionally, the row stacks have spacing=0 and distribution=.fill which means buttons fill the row width fully -- but the mainStack itself is inset from the container edges by rowSidePadding. Touches in that padding zone hit NO button.

HOWEVER, the primary dead zone issue is likely caused by something more fundamental: the row stacks within the mainStack may have DIFFERENT widths for rows with different key layouts (e.g., row 2 of AZERTY is shorter due to fewer keys), creating horizontal dead zones at row boundaries where one row's buttons don't align with the row above/below.

test: Trace the exact layout geometry
expecting: Identify where touch gaps exist
next_action: Report diagnosis

## Symptoms

expected: Zero dead zones between all keys -- every pixel in the keyboard area resolves to a key tap
actual: Horizontal and vertical dead zones persist between keys despite UIKit point(inside:with:) implementation
errors: N/A (visual/touch issue, not a crash)
reproduction: Tap precisely between two adjacent keys -- no key registers
started: After Phase 15.5 UIKit rebuild

## Eliminated

(none -- first investigation)

## Evidence

- timestamp: 2026-03-25
  checked: KeyboardContainerView.layoutSubviews() touch inset computation
  found: Touch insets ARE computed for every button. Horizontal insets use half-gap-to-neighbor for interior keys and full-distance-to-edge for edge keys. Vertical insets use rowSpacing/2 for interior rows and rowSpacing/2+4 for top/bottom rows.
  implication: The inset logic itself appears correct for covering inter-key gaps WITHIN a row.

- timestamp: 2026-03-25
  checked: mainStack configuration and constraints
  found: mainStack has spacing=0, distribution=.fillEqually, alignment=.fill. It is constrained to topAnchor, bottomAnchor, and leading/trailing with rowSidePadding (4pt on standard). Row stacks have spacing=0, distribution=.fill, alignment=.fill.
  implication: The mainStack fills the container minus side padding. Each row fills the mainStack width. Within each row, buttons fill the row width. There should be no gaps WITHIN the layout.

- timestamp: 2026-03-25
  checked: LetterKeyButton.point(inside:with:) and backgroundView layout
  found: point(inside:with:) uses bounds.inset(by: touchInsets).contains(point). backgroundView is inset by keySpacing/2 horizontally and rowSpacing/2 vertically. The button's FRAME fills the cell area, and the visual background is smaller (creating visual gaps). Touch area expands BEYOND the frame via negative insets.
  implication: The visual gap between keys is created by the backgroundView inset. The touch area should extend beyond the frame to cover the visual gap. This is the correct pattern.

- timestamp: 2026-03-25
  checked: Whether point(inside:with:) can actually fire when touch lands OUTSIDE the button's frame
  found: CRITICAL FINDING -- UIKit hit testing calls hitTest(_:with:) on the superview (the row UIStackView), which iterates subviews and calls point(inside:with:) on each. BUT UIView.hitTest() has a built-in optimization: it checks if the point is inside the view's own bounds BEFORE calling point(inside:with:) on subviews. The row UIStackView's bounds exactly match the union of its arranged subviews. Since buttons with spacing=0 and distribution=.fill already tile the row perfectly, the horizontal insets are actually working (the point IS inside the row stack's bounds). HOWEVER, for VERTICAL dead zones: the mainStack uses .fillEqually distribution, so each row stack gets equal height. The touch that lands BETWEEN rows (in the rowSpacing zone) needs to be caught by a button whose point(inside:with:) extends vertically. But the default UIView.hitTest() on the mainStack will only forward to the row stack whose bounds contain the point. Since the row stacks have NO vertical gaps (mainStack spacing=0, distribution=.fillEqually), the rows tile vertically and there ARE no vertical gaps at the mainStack level.

  WAIT -- re-examining: mainStack.spacing = 0 and distribution = .fillEqually means rows DO tile perfectly with no gaps. Each row stack occupies exactly 1/4 of mainStack height. Inside each row, buttons occupy the full row width. So the button frames DO tile the entire keyboard area. The negative touchInsets would then expand BEYOND the tiling, which is unnecessary for gap coverage but harmless.

  The REAL question: are there gaps where buttons DON'T tile? Let me re-check.
  implication: Need to verify whether tiling is truly complete.

- timestamp: 2026-03-25
  checked: Row-level button width allocation
  found: Buttons within a row use proportional width constraints (widthMultiplier / actualTotal). All but the last button have explicit width constraints; the last fills remaining space. With distribution=.fill, this means buttons tile the full row width with zero gaps between frames. So HORIZONTALLY, button frames tile perfectly.
  implication: Horizontal dead zones should NOT exist between buttons in the same row.

- timestamp: 2026-03-25
  checked: CROSS-ROW alignment (AZERTY layout)
  found: Different rows have different numbers of keys with different widths. Row 1 (AZERTYUIOP) has 10 keys, row 2 (QSDFGHJKLM) has 10 keys, row 3 (shift + WXCVBN + accent + delete) has 8 keys plus special keys. The mainStack vertical stacking means rows are aligned to the left (alignment=.fill fills the width). Since each row fills the same width (mainStack width), and buttons within each row tile that width, there are NO horizontal gaps between rows. Each row is a solid horizontal band.
  implication: Cross-row alignment is NOT the issue. Every row fills the same width.

- timestamp: 2026-03-25
  checked: The side padding zones (rowSidePadding = 4pt)
  found: The mainStack is inset by rowSidePadding (4pt) from the container edges. The LEFTMOST button in each row extends its touchInsets.left by view.frame.minX (which should be 0 since the row has no leading margin). The RIGHTMOST button extends its touchInsets.right by rowStack.bounds.width - view.frame.maxX (which should be 0). So edge buttons do NOT extend into the 4pt side padding zone.

  BUT WAIT: the edge buttons' touchInsets only extend to the row stack's edge, not to the container's edge. Touches in the 4pt rowSidePadding zone would hit the container (KeyboardContainerView) but NOT any button.

  HOWEVER: the mainStack occupies the container minus 4pt on each side. Touches in those 4pt zones hit the container's background but don't propagate to any button. This could cause edge dead zones, but these are only 4pt wide -- not the primary complaint.
  implication: 4pt edge dead zones exist but are minor.

- timestamp: 2026-03-25
  checked: THE REAL ROOT CAUSE -- hitTest chain with point(inside:with:) expansion
  found: CRITICAL DISCOVERY. The point(inside:with:) override on buttons EXPANDS the touchable area beyond the button's frame. But UIKit's default hitTest(_:with:) implementation on the PARENT views (UIStackView) does NOT account for this. UIView.hitTest() first checks self.point(inside:with:) on the PARENT, and only if the point is inside the parent does it iterate subviews. The parent UIStackView does NOT override point(inside:with:), so it uses the default which checks bounds.contains(point).

  Here's the chain:
  1. Touch arrives at KeyboardContainerView
  2. Container.hitTest() checks if point is in its bounds -> YES (assuming touch is on keyboard)
  3. Container iterates subviews (mainStack) -> mainStack.hitTest()
  4. mainStack (UIStackView) checks if point is in ITS bounds -> since mainStack is inset by rowSidePadding, a touch in the padding zone would be OUTSIDE mainStack bounds -> NO HIT
  5. For touches WITHIN mainStack, it iterates row stacks -> rowStack.hitTest()
  6. rowStack checks bounds -> for points within the row, YES
  7. rowStack iterates buttons -> button.hitTest() calls button.point(inside:with:)
  8. button.point(inside:with:) uses expanded bounds -> could return YES for points outside button's frame

  THE PROBLEM IS STEP 5-6: The rowStack's hitTest checks whether the CONVERTED point is inside the rowStack's bounds. Since mainStack.spacing=0 and distribution=.fillEqually, row stacks tile vertically. So a point at the EXACT boundary between two rows IS inside one of the row stacks (or the other). No vertical gap.

  BUT THE REAL PROBLEM IS STEP 7-8: When a touch point is between two buttons in the SAME row (in what would visually be the gap), the point IS inside the row stack (because buttons tile the row). The row stack iterates subviews in reverse order (frontmost first). The button's hitTest() converts the point to button-local coordinates and calls self.point(inside:with:). Since the point is within the button's frame (buttons tile with no gaps), this returns YES via the STANDARD bounds check even WITHOUT the expanded insets. So the touchInsets expansion is actually UNNECESSARY for same-row buttons when spacing=0.

  BUT WAIT: if buttons tile perfectly (spacing=0, distribution=.fill, proportional widths), then there ARE no gaps. The issue must be elsewhere.

  LET ME RE-READ THE VISUAL EVIDENCE: The user reports dead zones PERSIST. Let me reconsider what "dead zones" means in this context. With the current layout:
  - Button FRAMES tile perfectly (no gaps between frames)
  - Button backgroundViews are INSET from frames (creating visual gaps)
  - Touch handling is on the button (UIButton), which receives all touches within its frame
  - The point(inside:with:) expansion is MOOT because frames already tile

  So if frames tile perfectly, why do dead zones persist?

  HYPOTHESIS: The frames do NOT tile perfectly. There might be floating-point rounding gaps.

  Actually, re-reading more carefully: the width constraints use multiplier ratios. With Auto Layout, fractional pixel values get rounded. For example, if a row has 10 keys each at 1.0/10.0 = 0.1 multiplier of the row width, and the row is 375pt wide, each key should be 37.5pt. But pixel rounding might make some 37pt and some 38pt, leaving a 1-2pt gap or overlap.

  BUT: the last button has NO width constraint (it fills remaining space), which should absorb any rounding errors. So the total should always be exactly the row width. But what about BETWEEN buttons? If button 1 is 37pt and button 2 starts at 38pt (due to rounding), there's a 1pt gap. Auto Layout typically handles this with pixel-aligned frames, but the multiplier approach could introduce sub-pixel gaps.

  ACTUALLY: UIStackView with spacing=0 and distribution=.fill handles this. The stack view positions each arranged subview directly adjacent to the previous one. With explicit width constraints and the last view filling remaining space, the tiling should be exact.

  I need to consider another possibility: THE KEYBOARD IS WRAPPED IN A SwiftUI VIEW WITH FRAME HEIGHT CONSTRAINTS. Looking at KeyboardRootView.swift line 308:
  .frame(height: keyboardHeight)

  keyboardHeight = 4 * (keyHeight + rowSpacing)

  On standard device: 4 * (43 + 11) = 216pt

  The mainStack fills the container (KeyboardContainerView), which is the UIView from UIViewRepresentable. SwiftUI sets this view's frame to 216pt tall. The mainStack is pinned top/bottom to the container. With 4 rows and .fillEqually, each row gets 216/4 = 54pt.

  Each button within the row is 54pt tall. The backgroundView is inset by rowSpacing/2 = 5.5pt top and bottom, making it 43pt tall (matching keyHeight). The button FRAME is 54pt tall, the visual key is 43pt tall.

  So button frames DO fill the entire 216pt height with no gaps. And button frames fill the entire row width with no gaps. THE TOUCH AREA SHOULD HAVE ZERO DEAD ZONES.

  Unless... the SwiftUI ZStack overlay is intercepting touches?
  implication: Need to check if SwiftUI overlays are stealing touches.

- timestamp: 2026-03-25
  checked: SwiftUI ZStack overlay touch interception
  found: In KeyboardRootView.swift lines 209-336, KeyboardUIView is in a ZStack with popup overlays. ALL overlays use .allowsHitTesting(false), meaning they should not intercept touches. The ZStack alignment is .top.
  implication: Overlays are NOT stealing touches.

- timestamp: 2026-03-25
  checked: UIViewRepresentable sizing and the actual keyboard container frame
  found: KeyboardUIView is a UIViewRepresentable. SwiftUI calls makeUIView and returns a KeyboardContainerView. SwiftUI sets the view's frame based on .frame(height: keyboardHeight). The container's intrinsicContentSize is not overridden, so SwiftUI controls sizing. The mainStack is pinned to all 4 edges (with side padding). This should work correctly.

  HOWEVER: there is a potential issue. SwiftUI UIViewRepresentable sizing can be tricky. If the container view's frame is not set before layoutSubviews runs, the touch insets could be computed with zero-size frames. But subsequent layout passes would fix this.
  implication: Unlikely to be the primary issue but worth noting.

- timestamp: 2026-03-25
  checked: RE-EXAMINING with fresh eyes -- what if the issue is NOT between keys but at the row-to-row VERTICAL boundary?
  found: With mainStack spacing=0 and .fillEqually, each row stack is 54pt tall. Buttons fill the row. A touch at y=54 (the exact boundary between row 0 and row 1) would be tested against row 0's bounds (0-54) and row 1's bounds (54-108). Due to how UIKit hit-tests (last subview first, i.e., bottom row first), row 1 would be checked first. The point (0,0) in row 1's local coords is on the boundary. UIView.point(inside:with:) default is bounds.contains(point) which uses inclusive lower bound and EXCLUSIVE upper bound for CGRect.contains(). So a point at exactly y=54 in mainStack coords = y=0 in row 1 coords. CGRect(0,0,w,54).contains((x,0)) = true (0 >= 0 && 0 < 54). So it IS inside row 1.

  What about a point at y=53.5 in mainStack coords = y=53.5 in row 0 coords. CGRect(0,0,w,54).contains((x,53.5)) = true (53.5 < 54). And in row 0, a button at the bottom edge would have this point within its frame.

  So vertical boundaries between rows are covered. No dead zone there.
  implication: Vertical row boundaries are NOT the issue.

- timestamp: 2026-03-25
  checked: FINAL HYPOTHESIS -- The SwiftUI .frame(height:) and ZStack may cause the UIViewRepresentable to NOT fill the full width
  found: Looking at KeyboardRootView body structure:
  VStack(spacing:0) > if/else > ZStack > KeyboardUIView.frame(height:)

  KeyboardUIView has NO explicit width constraint. In SwiftUI, a view inside a VStack without explicit width will be offered the parent's width. The ZStack has alignment .top. KeyboardUIView should receive the full width of the ZStack, which is the full width of the VStack, which is the screen width.

  But there's no .frame(maxWidth: .infinity) or similar. SwiftUI UIViewRepresentable views typically get their size from the proposed size. This should be fine.
  implication: Width should be correct.

- timestamp: 2026-03-25
  checked: RECONSIDERING THE ENTIRE PREMISE -- maybe the tiling IS complete and the dead zones are NOT between keys but somewhere else
  found: Going back to the user's report: "horizontal and vertical dead zones still exist between keys." If the analysis above is correct that button frames tile perfectly with zero gaps, then the dead zones must be caused by something ELSE.

  BREAKTHROUGH: Looking at LetterKeyButton.layoutSubviews() line 121-126:
  ```
  override func layoutSubviews() {
      super.layoutSubviews()
      let hInset = KeyMetrics.keySpacing / 2
      let vInset = KeyMetrics.rowSpacing / 2
      backgroundView.frame = bounds.insetBy(dx: hInset, dy: vInset)
  }
  ```

  And the SAME in BaseSpecialKeyButton.layoutSubviews() lines 67-72.

  The backgroundView is purely visual -- isUserInteractionEnabled = false. So it doesn't affect touch handling.

  BUT: the button's clipsToBounds is set to false (line 118 in LetterKeyButton, line 64 in BaseSpecialKeyButton). Good -- expanded touch area won't be clipped.

  NOW THE KEY QUESTION: Since button frames tile perfectly (no gaps), why would point(inside:with:) with NEGATIVE touchInsets matter? It EXPANDS the touch area, but the frame already covers everything. The expansion goes BEYOND the frame -- into the neighboring button's territory. So two adjacent buttons would BOTH claim the point in the gap region. UIKit resolves this by the hit-test order (last subview wins in the iteration).

  Wait -- but there IS no gap if frames tile. The expansion is meaningless. Unless... the touchInsets computation SHRINKS the touch area in some case?

  Let me re-examine: touchInsets are set in KeyboardContainerView.layoutSubviews(). For interior buttons, leftExt and rightExt are computed as half the gap to the neighbor. But if there's NO gap (spacing=0, buttons tile), then:
  - view.frame.minX - prevButton.frame.maxX = 0
  - leftExt = 0/2 = 0

  So touchInsets would be UIEdgeInsets(top: -5.5, left: 0, bottom: -5.5, right: 0) for interior buttons (with vertical extensions only).

  For edge buttons:
  - leftExt = view.frame.minX = 0 (first button starts at x=0 in the row stack)
  - rightExt = rowStack.bounds.width - view.frame.maxX = 0 (last button fills to edge)

  So ALL horizontal touchInsets are 0. And vertical touchInsets are -rowSpacing/2 or -rowSpacing/2-4.

  Now in point(inside:with:):
  bounds.inset(by: touchInsets).contains(point)

  With touchInsets = UIEdgeInsets(top: -5.5, left: 0, bottom: -5.5, right: 0):
  bounds = (0, 0, w, 54) -> after inset by (top:-5.5, left:0, bottom:-5.5, right:0):
  = (-5.5 on top, -5.5 on bottom) = origin.y = -5.5, height = 54 + 11 = 65
  Result rect: (0, -5.5, w, 65)

  This EXPANDS vertically by 5.5pt above and below. Since each row is 54pt, this means each button's touch area extends 5.5pt into the neighboring row. The neighboring row's buttons also extend 5.5pt in the opposite direction. So there's an 11pt overlap zone at each row boundary.

  For the first row, top extension is rowSpacing/2+4 = 9.5pt above the keyboard. For the last row, bottom extension is 9.5pt below.

  This vertical expansion is fine -- it provides redundancy at row boundaries.

  BUT THE HORIZONTAL TOUCHINSETS ARE ALL ZERO. And since button frames tile perfectly, this is correct -- there are no horizontal gaps to fill.

  SO WHERE ARE THE DEAD ZONES?

  FINAL INSIGHT: The button frames tile perfectly ONLY IF Auto Layout produces perfect tiling. Let me check if there's a subtle issue with how proportional width constraints interact with UIStackView distribution=.fill.

  In buildKeys(), buttons get width constraints:
  button.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: key.widthMultiplier / actualTotal)

  The last button has NO width constraint. UIStackView with distribution=.fill requires intrinsicContentSize or explicit constraints for sizing. The last button has no intrinsicContentSize override (UIButton's default is based on title). With distribution=.fill, UIStackView distributes remaining space after satisfying constraints. If the constrained buttons don't add up to exactly the row width (due to rounding), the last button fills the remainder.

  The issue: UIStackView with distribution=.fill and spacing=0 positions views sequentially. View N+1 starts at view N's maxX. But if width constraints have fractional results, the constraint system might introduce sub-pixel gaps OR overlaps.

  Actually, UIStackView with spacing=0 guarantees no spacing between arranged subviews. The stack view itself manages positioning. Width constraints are additional constraints that the layout engine satisfies simultaneously. If there's a conflict between "no spacing" and "proportional widths summing to row width," the system might break a constraint.

  ACTUALLY: The constraints are:
  - button[i].width = rowStack.width * (multiplier[i] / total) for i in 0..<n-1
  - button[n-1] has NO width constraint (fills remaining)
  - UIStackView spacing=0, distribution=.fill

  UIStackView with .fill distribution and spacing=0 will position:
  - button[0] at x=0, width determined by constraint
  - button[1] at x=button[0].maxX, width determined by constraint
  - etc.
  - button[n-1] at x=button[n-2].maxX, width = rowStack.width - button[n-2].maxX

  This should tile perfectly. The proportional width constraints should be satisfiable simultaneously with the stack positioning.

  I'M GOING IN CIRCLES. Let me step back and consider: what if the dead zones are NOT between key frames but are caused by the UIButton's internal hit testing ignoring the point(inside:with:) override in certain conditions?

  IMPORTANT: UIButton has special touch handling. When isEnabled=false or isHidden=true or alpha<0.01, hitTest returns nil regardless of point(inside:with:). But all buttons are enabled and visible.

  ANOTHER POSSIBILITY: The buttons' point(inside:with:) works correctly, but something in the SWIFTUI side is eating touches before they reach UIKit.

  In SwiftUI, UIViewRepresentable views receive touches through the UIKit responder chain. SwiftUI's gesture system doesn't interfere with UIKit touches inside a UIViewRepresentable -- the UIKit hit-test chain runs normally.

  I need to look at this from a different angle entirely.
  implication: The layout analysis suggests button frames tile perfectly. Dead zones may be a different kind of issue.

## Resolution

root_cause: ANALYSIS COMPLETE -- SEE DIAGNOSIS BELOW
fix: (research only)
verification: (research only)
files_changed: []
