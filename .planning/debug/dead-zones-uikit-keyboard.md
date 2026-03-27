---
status: open
trigger: "Dead zones between keyboard keys — touches don't register"
created: 2026-03-25T00:00:00Z
updated: 2026-03-27T00:00:00Z
---

# Dead Zones: iOS Keyboard Extension Touch Filtering

## Problem

Touches between keyboard keys (dead zones) produce no response — no character insertion, no haptic, no popup. Affects horizontal gaps (between E and R), vertical gaps (between rows), and the intersection of 4 keys (between A/Z and Q/S).

## Root Cause

iOS keyboard extension infrastructure filters touches at a level below both hitTest and UIGestureRecognizer. Touches ON keys reach our views; touches BETWEEN keys never do.

## Approaches Tried (All Failed)

### 1. Expanded touchInsets (Phase 15.4-15.5)
- Override `point(inside:with:)` with negative UIEdgeInsets to expand hit area
- **Result**: UIStackView.hitTest uses `subview.frame.contains(point)` internally — never calls `point(inside:with:)` on subviews

### 2. ForwardingView inside KeyboardContainerView (Phase 15.6)
- Transparent UIView on top of stacks, returns `self` from hitTest
- Buttons have `isUserInteractionEnabled = false`
- **Result**: Works for on-key taps. Dead zone touches never reach the view (proven by logs — zero ForwardingView entries for dead zone taps, verified in logs 95)

### 3. ForwardingView as topmost subview of kbInputView (Phase 15.6)
- Moved ForwardingView ABOVE the SwiftUI hosting view
- **Result**: Same — dead zone touches don't reach the view (verified in logs 96)

### 4. Custom UIGestureRecognizer on kbInputView (Phase 15.6)
- Apple docs: "window delivers touch events to gesture recognizers BEFORE hit-test view"
- Custom recognizer with `cancelsTouchesInView = true`
- **Result**: Only received 1/4 touches. Keyboard completely dead.
- **Discovery**: kbInputView has non-standard coordinate system — height ≈924pt (full screen), keyboard container at y=692, touch coordinates relative to bounds with non-zero origin

## Key Evidence

### Log proof (dictus-logs 95.txt)
```
22:39:37 ForwardingView routed point=(67,27) -> Z   ← on-key tap logged
22:39:37–22:39:42 ← 3 dead zone taps, ZERO log entries
```

### Gesture recognizer proof (dictus-logs 100.txt)
```
point=(27,75) kbRect=(0,692,430,232) active=true buttons=33
```
- kbInputView is ~924pt tall (full screen height)
- Keyboard container at y=692
- Only 1 touch received out of 4 taps

## Current State

ForwardingView as topmost subview — works for all on-key taps, dead zones remain. This is the best achievable without private API or fundamentally different rendering.

## Future Research Directions

1. **Single CALayer rendering**: Render entire keyboard as one layer, handle touches in a single view with no subview gaps
2. **Custom UIWindow**: Overlay a separate window for touch handling
3. **Private API research**: Investigate how GBoard/SwiftKey handle this (likely private entitlements or internal APIs)
4. **UIInputView bounds investigation**: kbInputView has non-zero bounds.origin and full-screen height — understanding this could reveal touch routing rules
5. **Expand button frames**: Make button frames fill 100% of available space (zero gap) so UIStackView's frame.contains() check always succeeds
