---
phase: 06-infrastructure-app-polish
type: polish-notes
created: 2026-03-08
status: pending
context: Issues noted during UAT of RecordingView redesign
---

# Polish Notes — RecordingView (post gap-closure)

3 issues to fix before phase verification.

## 1. X close button — too small + no haptic feedback

**File:** `DictusApp/Views/RecordingView.swift` (close button section, ~line 56)

**Problem:** The X button is small (36pt) and under the user's finger when tapped. No haptic confirmation that the tap registered.

**Fix:**
- Increase hit area: add `.frame(width: 44, height: 44)` (Apple's minimum 44pt touch target)
- Add haptic: `HapticFeedback.recordingStopped()` or `UIImpactFeedbackGenerator(style: .light).impactOccurred()` in the button action
- Consider making the visual circle slightly larger (40pt) while keeping the icon at 17pt

## 2. Overlay dismissal animation too abrupt

**File:** `DictusApp/Views/MainTabView.swift` (overlay condition, ~line 65)

**Problem:** When X is tapped, the RecordingView overlay disappears instantly — no transition, feels jarring.

**Fix proposal:** Wrap the status change in `withAnimation` so the `.transition(.opacity)` on RecordingView actually fires:
```swift
// In RecordingView's close button action:
withAnimation(.easeOut(duration: 0.25)) {
    coordinator.resetStatus()
}
```
Or use a two-step dismissal: set a local `@State var isDismissing = true` that triggers a fade-out animation, then after 0.25s actually call `coordinator.resetStatus()`.

Alternative: Add `.animation(.easeOut(duration: 0.25), value: coordinator.status)` to the ZStack in MainTabView around the overlay condition.

## 3. Mic button appears active during transcription processing

**File:** `DictusApp/Views/RecordingView.swift` (micOrStopButton, ~line 248-256)

**Problem:** When transcription is processing (status = `.transcribing`), the `AnimatedMicButton` shows with shimmer effect. But when status transitions to `.ready` (result received), the mic button reappears in full blue — identical to the idle/tappable state. The user sees the result + a blue mic button and thinks they can start a new recording, but tapping does nothing meaningful during the brief `.ready` display.

Actually the real issue: during `.transcribing`, the mic shows with shimmer (correct). But the button `else` branch catches both `.idle` and `.ready` states with the same blue mic appearance. When `showResult` is true and status is `.ready`, the mic should look slightly disabled since the user should first read/copy the result.

**Fix proposal:**
- When `showResult == true`, show the mic with reduced opacity (0.5) or a gray tint
- Or add a new visual state to AnimatedMicButton for "ready but secondary" — same blue but dimmer glow
- Simplest: in the `else` branch of micOrStopButton, check `showResult` and apply `.opacity(0.5)` if true
```swift
} else {
    AnimatedMicButton(status: .idle) {
        startRecording()
    }
    .opacity(showResult ? 0.5 : 1.0)
}
```
This visually communicates "you can tap but it's not the primary action right now".
