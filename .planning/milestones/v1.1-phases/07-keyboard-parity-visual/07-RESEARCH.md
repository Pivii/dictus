# Phase 7: Keyboard Parity & Visual - Research

**Researched:** 2026-03-08
**Domain:** iOS Keyboard Extension UX parity, haptic performance, SwiftUI Canvas animation
**Confidence:** HIGH

## Summary

Phase 7 brings the Dictus keyboard to parity with Apple's native French AZERTY keyboard across six interaction dimensions (trackpad cursor, adaptive accents, universal haptics, emoji/globe cleanup, dictation mic removal, performance) and three visual polish items (mic pill, recording pills, waveform rework). The codebase is well-structured for these changes -- KeyDefinition/KeyType enum, KeyboardLayout static arrays, and SpecialKeyButton views provide clean extension points.

The primary technical risks are: (1) performance optimization requiring real-device profiling (not simulatable), (2) the key popup clipping issue which is a known iOS keyboard extension limitation with no guaranteed clean solution, and (3) the Apple dictation mic removal which has no documented public API for suppression from within a keyboard extension.

**Primary recommendation:** Tackle performance optimization (KBD-06) after all functional features are in place, since adding haptics/trackpad/accent key will change the performance profile. Pre-allocate UIImpactFeedbackGenerator instances as a known quick win before profiling.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Spacebar trackpad: long-press activates, greyed-out overlay (labels fade, shapes remain), free 4-directional movement, 1:1 sensitivity (~8-10pt/char), Apple-matching haptic pattern (tap on press, different haptic on mode activate, no haptics during drag), cursor via adjustTextPosition(byCharacterOffset:)
- Adaptive accent key: between N and delete on AZERTY row 3 only (not QWERTY), context logic matches Apple French AZERTY (apostrophe default, accent after vowel), long-press shows all variants
- Haptics: uniform HapticFeedback.keyTapped() on ALL key taps (letters, space, return, delete, symbols, emoji, 123, shift), keep playInputClick() where already present
- Bottom row: globe replaced with emoji button (face icon), tap = advanceToNextInputMode(), no long-press, bottom row becomes: emoji | 123 | space | return
- Apple dictation mic: remove system-provided mic icon at bottom-right -- research needed for approach
- Performance: fix input lag and haptic latency, pre-allocate UIImpactFeedbackGenerator, reduce SwiftUI rendering overhead
- Mic pill (VIS-01): pill-shaped, icon only, Liquid Glass style adapted from AnimatedMicButton circle, same 4 visual states
- Recording pills (VIS-02): cancel (X) and validate (checkmark) as pill-shaped, icon only, Liquid Glass
- Waveform (VIS-03): perfectly still at zero energy, reuse BrandWaveform sinusoidal processing, target 60fps via TimelineView + Canvas
- Key popup clipping fix: top row popups clipped by container bounds -- fix via clipsToBounds or higher z-level
- Keyboard height: dynamic per device (Apple varies: ~216pt SE, ~226pt standard, ~271pt Plus/Max)
- Full Access banner fix: "Activer" button opens dictus:// URL scheme instead of app-settings:

### Claude's Discretion
- Recording pill button colors (may differ from mic pill to indicate different functions)
- Exact trackpad overlay animation (fade transition timing)
- Waveform Canvas rendering approach details
- Performance profiling strategy and specific optimizations found
- Key popup overflow rendering technique

### Deferred Ideas (OUT OF SCOPE)
- Mic start/stop sound effect -- requires sound design, future milestone
- Accuracy/speed gauges in model catalog -- Phase 10 (MOD-03)
- "FR EN" language indicator on spacebar -- cosmetic polish, not core parity
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| KBD-01 | Spacebar trackpad mode (long-press, cursor drag, haptic, grey overlay) | SpaceKey refactor from Button to DragGesture, adjustTextPosition API, trackpad overlay state in KeyboardView |
| KBD-02 | Adaptive accent key next to N (apostrophe/accent by context) | New .accentAdaptive KeyType, AccentedCharacters context logic extension, KeyboardLayout row 3 modification |
| KBD-03 | Haptic feedback on all key taps | HapticFeedback.keyTapped() calls added to onSpace/onReturn/onDelete/onGlobe/onLayerSwitch callbacks + pre-allocated generator |
| KBD-04 | Emoji button replaces globe, cycles to system emoji keyboard | New .emoji KeyType, EmojiKey view, advanceToNextInputMode(), KeyboardLayout row 4 changes |
| KBD-05 | Apple dictation mic removed | No documented API -- best approach is accepting iOS shows it or testing undocumented behavior |
| KBD-06 | Performance optimization (input lag, haptic latency) | Pre-allocate UIImpactFeedbackGenerator, reduce SwiftUI re-renders, profile on device |
| VIS-01 | Mic button pill redesign | Adapt AnimatedMicButton from Circle to Capsule shape, keep 4 states |
| VIS-02 | Recording cancel/validate pill redesign | Replace SF Symbol circles with Liquid Glass pill buttons in RecordingOverlay |
| VIS-03 | Waveform rework (60fps, still at zero) | Canvas rendering replaces RoundedRectangle ForEach, minHeight removed for zero-energy stillness |
</phase_requirements>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 16+ | All keyboard UI, Canvas, TimelineView | Framework requirement |
| UIKit | iOS 16+ | UIImpactFeedbackGenerator, UIInputViewController, textDocumentProxy | Keyboard extension APIs |
| DictusCore | local | HapticFeedback, AccentedCharacters, design tokens, GlassModifier | Shared framework |

### No Additional Libraries Needed
This phase is purely SwiftUI/UIKit API work. No new SPM dependencies required.

## Architecture Patterns

### Recommended Modifications

```
DictusKeyboard/
  Models/
    KeyDefinition.swift      # Add .emoji, .accentAdaptive KeyType cases
    KeyboardLayout.swift     # Row 3: insert accent key (AZERTY only), Row 4: emoji replaces globe
  Views/
    KeyboardView.swift       # Add trackpad mode state, overlay, cursor movement
    SpecialKeyButton.swift   # Add EmojiKey, refactor SpaceKey (Button -> DragGesture)
    KeyRow.swift             # Add .emoji and .accentAdaptive cases
    RecordingOverlay.swift   # Replace icon buttons with pill buttons
    ToolbarView.swift        # Replace AnimatedMicButton circle with pill variant
    KeyButton.swift          # (mostly unchanged, popup clipping fix)
  KeyboardRootView.swift     # Fix FullAccessBanner URL
  KeyboardViewController.swift  # Dynamic height, clipsToBounds fix attempt

DictusCore/
  Sources/DictusCore/
    HapticFeedback.swift     # Pre-allocated generators for performance
    AccentedCharacters.swift # Add adaptive context logic (vowel -> accent mapping)
    Design/
      AnimatedMicButton.swift  # Refactor to support pill shape variant
      BrandWaveform.swift      # Canvas rendering, zero-energy fix
```

### Pattern 1: Spacebar Trackpad Mode

**What:** Transform SpaceKey from a Button to a DragGesture-based view (matching DeleteKey pattern) with long-press detection, trackpad overlay, and cursor movement.

**When to use:** When implementing KBD-01.

**Example:**
```swift
// SpaceKey refactored with trackpad mode
struct SpaceKey: View {
    let width: CGFloat
    let onTap: () -> Void
    let onCursorMove: (Int) -> Void  // character offset

    @State private var isPressed = false
    @State private var isTrackpadMode = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var lastDragX: CGFloat = 0
    @State private var accumulatedOffset: CGFloat = 0

    // Sensitivity: ~8-10pt per character
    private let pointsPerCharacter: CGFloat = 9.0

    var body: some View {
        Text("espace")
            .font(.system(size: 15))
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(/* ... */)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isPressed {
                            isPressed = true
                            lastDragX = value.location.x
                            HapticFeedback.keyTapped()  // Initial tap haptic
                            startTrackpadTimer()
                        }
                        if isTrackpadMode {
                            let deltaX = value.location.x - lastDragX
                            accumulatedOffset += deltaX
                            lastDragX = value.location.x

                            let characters = Int(accumulatedOffset / pointsPerCharacter)
                            if characters != 0 {
                                onCursorMove(characters)
                                accumulatedOffset -= CGFloat(characters) * pointsPerCharacter
                            }
                        }
                    }
                    .onEnded { _ in
                        if !isTrackpadMode {
                            onTap()  // Normal space tap
                        }
                        isPressed = false
                        isTrackpadMode = false
                        longPressTask?.cancel()
                        longPressTask = nil
                        accumulatedOffset = 0
                    }
            )
    }

    private func startTrackpadTimer() {
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400ms
            guard !Task.isCancelled else { return }
            isTrackpadMode = true
            HapticFeedback.trackpadActivated()  // Different haptic for mode activation
        }
    }
}
```

### Pattern 2: Pre-allocated Haptic Generators

**What:** Keep UIImpactFeedbackGenerator instances alive and pre-prepared instead of creating new ones per call.

**When to use:** KBD-06 performance optimization -- this is the likely fix for haptic latency.

**Example:**
```swift
public enum HapticFeedback {
    #if canImport(UIKit) && !os(macOS)
    // Pre-allocated generators -- created once, reused for every tap
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Call once at keyboard load to prime the Taptic Engine
    public static func warmUp() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    public static func keyTapped() {
        guard isEnabled() else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()  // Re-prepare for next tap
    }
    #endif
}
```

### Pattern 3: Canvas Waveform Rendering

**What:** Replace the current ForEach + RoundedRectangle approach with Canvas for GPU-accelerated drawing.

**When to use:** VIS-03 waveform rework for 60fps.

**Example:**
```swift
// Inside BrandWaveform, replace waveformContent with Canvas
TimelineView(.animation) { timeline in
    let phase = isProcessing ? timeline.date.timeIntervalSinceReferenceDate / 2.0 : 0

    Canvas { context, size in
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 2)

        for index in 0..<barCount {
            let energy = energyForBar(at: index, processingPhase: phase)
            let minHeight: CGFloat = isProcessing ? 4 : 0  // Zero at zero energy when not processing
            let height = minHeight + CGFloat(energy) * (maxHeight - minHeight)

            let x = CGFloat(index) * (barWidth + barSpacing)
            let y = (size.height - height) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

            context.fill(path, with: .color(colorForBarResolved(at: index)))
        }
    }
    .frame(height: maxHeight)
}
```

### Pattern 4: Adaptive Accent Key Context Logic

**What:** Determine which character to show on the accent key based on what was just typed.

**When to use:** KBD-02 implementation.

**Example:**
```swift
// Extension to AccentedCharacters for adaptive key logic
extension AccentedCharacters {
    /// Returns the default accent for a vowel (most common in French)
    static let defaultAccents: [String: String] = [
        "e": "\u{00E9}",  // e -> e-acute (most common French accent)
        "a": "\u{00E0}",  // a -> a-grave
        "u": "\u{00F9}",  // u -> u-grave
        "i": "\u{00EE}",  // i -> i-circumflex (used in ile, etc.)
        "o": "\u{00F4}",  // o -> o-circumflex
    ]

    /// Given the last typed character, returns what the adaptive key should show
    static func adaptiveKeyLabel(afterTyping lastChar: String?) -> String {
        guard let lastChar = lastChar?.lowercased() else { return "'" }
        if let accent = defaultAccents[lastChar] {
            return accent
        }
        return "'"  // Default: apostrophe
    }
}
```

### Anti-Patterns to Avoid

- **Creating UIImpactFeedbackGenerator per call:** Current HapticFeedback.keyTapped() creates and discards a generator every tap. This adds ~2-5ms latency per haptic. Pre-allocate once.
- **Animating individual SwiftUI Views for waveform bars:** ForEach with 30 RoundedRectangle views creates 30 view diffing operations per frame. Canvas draws all bars in one pass.
- **Using Timer.scheduledTimer in keyboard extensions:** Timers are unreliable in extensions (RunLoop may not be active). Use Task.sleep pattern (already established in DeleteKey).
- **Fixed keyboard height for all devices:** The current 4x46 + spacing calculation is device-independent. iOS keyboards vary by device -- use UIScreen.main.bounds to scale.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Keyboard switching | Custom emoji picker view | advanceToNextInputMode() | Memory unsafe (emoji glyph cache), system handles it |
| Cursor movement | Custom text position tracking | textDocumentProxy.adjustTextPosition(byCharacterOffset:) | Only API that works across all host apps |
| Haptic feedback engine | Custom Core Haptics pattern | UIImpactFeedbackGenerator (pre-allocated) | Simpler API, lower overhead for keyboard use case |
| Glass effect | Custom blur/material | .dictusGlass() / GlassModifier | Already built, iOS 26 ready |

**Key insight:** Keyboard extensions have a very constrained environment (~50MB memory, no UIApplication.shared, limited RunLoop). Every custom solution adds memory and CPU overhead. Use system APIs wherever possible.

## Common Pitfalls

### Pitfall 1: Haptic Generator Lifecycle in Extensions
**What goes wrong:** Creating UIImpactFeedbackGenerator on every keyTapped() call adds 2-5ms latency because the Taptic Engine needs to "wake up" each time.
**Why it happens:** Apple docs suggest prepare() before impactOccurred(), but the current code creates + prepares + fires + discards in one call.
**How to avoid:** Pre-allocate static generator instances. Call prepare() after each impactOccurred() to keep the engine warm for the next tap.
**Warning signs:** Haptic feels "delayed" compared to Apple keyboard.

### Pitfall 2: Spacebar Trackpad Gesture Conflict
**What goes wrong:** DragGesture on spacebar may conflict with the parent ScrollView or other gesture recognizers in the keyboard hierarchy.
**Why it happens:** SwiftUI gesture system has precedence rules. A DragGesture(minimumDistance: 0) captures all touches.
**How to avoid:** The spacebar already has no competing gestures (it's a simple Button now). The refactor to DragGesture replaces the Button entirely, so no conflict. But ensure the trackpad drag doesn't propagate to parent views.
**Warning signs:** Spacebar becomes unresponsive, or keyboard scrolls instead of cursor moving.

### Pitfall 3: Key Popup Clipping -- iOS Limitation
**What goes wrong:** Top-row key popups are clipped by the keyboard container bounds. This is a known iOS keyboard extension limitation.
**Why it happens:** iOS constrains keyboard extension views within their inputView bounds. clipsToBounds is set to true by the system.
**How to avoid:** Two approaches to try: (1) Set inputView.clipsToBounds = false in viewDidLoad -- may work on some iOS versions. (2) Use UIKit overlay: add a separate UIView above the hosting controller that renders popups via a shared state. Neither approach is guaranteed -- Apple's own keyboard uses private APIs for this.
**Warning signs:** Setting clipsToBounds = false and seeing no change means iOS re-enforces it.

### Pitfall 4: Dynamic Keyboard Height Mismatch
**What goes wrong:** Height constraint on inputView doesn't match actual SwiftUI content height, causing system keyboard row (globe, mic) to show through or recording overlay to compress.
**Why it happens:** computeKeyboardHeight() is hard-coded and doesn't account for device variations.
**How to avoid:** Calculate height dynamically based on UIScreen.main.bounds.height. Keep computeKeyboardHeight() in sync with KeyboardView's actual frame height.
**Warning signs:** Gap between keyboard and system row, or system elements bleeding through.

### Pitfall 5: advanceToNextInputMode() Behavior
**What goes wrong:** advanceToNextInputMode() does not specifically go to emoji keyboard -- it cycles through ALL enabled keyboards in order.
**Why it happens:** This is the only public API for keyboard switching. There is no "go to emoji keyboard" API.
**How to avoid:** Accept this behavior. The emoji button will cycle to the next input mode (which may be emoji, or may be another keyboard). This matches how third-party keyboards handle it. Label the button with an emoji icon but understand it's "next keyboard" functionality.
**Warning signs:** User expects emoji picker but gets a different keyboard instead.

### Pitfall 6: Apple Dictation Mic Cannot Be Removed
**What goes wrong:** The system-provided dictation microphone icon below the keyboard cannot be removed by a third-party keyboard extension.
**Why it happens:** This is a system-level UI element controlled by iOS, not by the keyboard extension. There is no documented Info.plist key or API to suppress it.
**How to avoid:** Accept this limitation. The user can disable dictation system-wide in Settings > General > Keyboard > Enable Dictation. Document this as a known iOS limitation. Our own mic button in the toolbar serves as the Dictus dictation trigger.
**Warning signs:** Searching for undocumented APIs or private keys that could break in future iOS updates.

## Code Examples

### Dynamic Keyboard Height Calculation
```swift
// In KeyboardViewController
private func computeKeyboardHeight() -> CGFloat {
    let screenHeight = UIScreen.main.bounds.height
    let rows: CGFloat = 4

    // Scale key height based on device size
    // iPhone SE (667pt): ~42pt keys, Standard (844-852pt): ~46pt, Plus/Max (926-932pt): ~50pt
    let baseKeyHeight: CGFloat
    if screenHeight <= 667 {
        baseKeyHeight = 42  // SE / compact
    } else if screenHeight <= 852 {
        baseKeyHeight = 46  // Standard
    } else {
        baseKeyHeight = 50  // Plus / Max
    }

    let rowSpacing: CGFloat = KeyMetrics.rowSpacing
    let verticalPadding: CGFloat = 8
    let toolbarHeight: CGFloat = 44
    let bannerHeight: CGFloat = hasFullAccess ? 0 : 40

    return (rows * baseKeyHeight) + ((rows - 1) * rowSpacing) + verticalPadding + toolbarHeight + bannerHeight
}
```

### Trackpad Overlay (Greyed-out Keys)
```swift
// Overlay that fades key labels and shows grey rectangles
struct TrackpadOverlay: View {
    var body: some View {
        Color.clear
            .background(
                // Semi-transparent overlay dims the keyboard
                Color(.systemBackground).opacity(0.6)
            )
            .allowsHitTesting(false)  // Don't block trackpad drag
    }
}
```

### Pill Button for Recording Controls
```swift
// Reusable pill button with Liquid Glass style
struct PillButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 56, height: 36)
                .dictusGlass(in: Capsule())
        }
        .buttonStyle(GlassPressStyle())
    }
}
```

### Adaptive Accent Key View
```swift
struct AdaptiveAccentKey: View {
    let width: CGFloat
    let isShifted: Bool
    let lastTypedChar: String?
    let onTap: (String) -> Void

    // Long-press state (reuse KeyButton pattern)
    @State private var isPressed = false
    @State private var showingAccents = false
    @State private var longPressTimer: Task<Void, Never>?

    private var currentLabel: String {
        let label = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
        return isShifted ? label.uppercased() : label
    }

    var body: some View {
        Text(currentLabel)
            .font(.system(size: 22, weight: .regular))
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                    .fill(KeyMetrics.letterKeyColor)
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            )
            // DragGesture for tap + long-press (same pattern as KeyButton)
            .gesture(/* ... same as KeyButton pattern ... */)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Create UIImpactFeedbackGenerator per call | Pre-allocate + reuse | Best practice since iOS 10 | Eliminates 2-5ms haptic latency |
| ForEach + individual Views for animation | Canvas + TimelineView | iOS 15+ | Single draw call, 60fps capable |
| Fixed keyboard height (216pt) | Dynamic per device | iOS 8+ (always recommended) | Proper sizing on SE vs Max |
| playInputClick() only | UIImpactFeedbackGenerator.light | iOS 10+ | Consistent feel across all keys |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual UAT (keyboard extension) |
| Config file | none |
| Quick run command | Manual: install on device, type in Notes/Messages |
| Full suite command | Full UAT checklist across all test scenarios |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| KBD-01 | Spacebar trackpad: long-press, drag, cursor moves, haptics, overlay | manual | Install on device, long-press spacebar in Notes | N/A |
| KBD-02 | Accent key: shows apostrophe default, accent after vowel, long-press variants | manual | Type vowels on AZERTY, check key changes | N/A |
| KBD-03 | Haptic on all keys | manual | Tap every key type, feel haptic | N/A |
| KBD-04 | Emoji button cycles keyboard | manual | Tap emoji button, verify system emoji appears | N/A |
| KBD-05 | Apple mic removed | manual | Check bottom bar for system mic | N/A |
| KBD-06 | Performance: no perceptible input lag | manual | Side-by-side typing comparison with Apple keyboard | N/A |
| VIS-01 | Mic button pill shape | manual | Visual inspection in keyboard toolbar | N/A |
| VIS-02 | Recording pills | manual | Start recording, check cancel/validate buttons | N/A |
| VIS-03 | Waveform 60fps, still at zero | manual | Record silence (cover mic), observe waveform | N/A |

### Sampling Rate
- **Per task commit:** Build and run on device, verify changed feature
- **Per wave merge:** Full UAT of all keyboard interactions
- **Phase gate:** Complete UAT checklist before /gsd:verify-work

### Wave 0 Gaps
None -- keyboard extension testing is inherently manual (no XCTest for keyboard extensions). The existing build + install + manual test workflow is the standard approach.

## Open Questions

1. **Key Popup Clipping Fix**
   - What we know: iOS enforces clipping on keyboard extension inputView. clipsToBounds = false may or may not work.
   - What's unclear: Whether setting clipsToBounds on the UIHostingController's view or on the inputView itself works in current iOS versions. Apple uses private APIs for their own popups.
   - Recommendation: Try clipsToBounds = false on inputView in viewDidLoad. If it fails, accept the clipping for top-row keys as a known limitation (many third-party keyboards have this issue).

2. **Apple Dictation Mic Removal (KBD-05)**
   - What we know: No documented public API exists to remove the system dictation mic button from below the keyboard.
   - What's unclear: Whether future iOS versions will provide a key or whether there's an undocumented approach.
   - Recommendation: Mark KBD-05 as a known iOS limitation. Do not pursue undocumented APIs. The user can disable dictation in system Settings. Our mic button in toolbar is the Dictus-specific trigger.

3. **advanceToNextInputMode() vs Emoji Keyboard**
   - What we know: advanceToNextInputMode() cycles to the NEXT keyboard, not specifically to emoji.
   - What's unclear: Whether users will be confused when the button cycles to a non-emoji keyboard.
   - Recommendation: Keep the emoji icon on the button but accept it's a "next keyboard" button. This matches how Gboard, SwiftKey, and other third-party keyboards handle it.

## Sources

### Primary (HIGH confidence)
- UITextDocumentProxy.adjustTextPosition(byCharacterOffset:) -- [Apple Documentation](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)
- UIImpactFeedbackGenerator prepare/impactOccurred lifecycle -- [Apple Documentation](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator)
- Keyboard Extension Info.plist keys -- [Apple Archive](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html)
- Canvas + TimelineView animation pattern -- [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-custom-animated-drawings-with-timelineview-and-canvas)

### Secondary (MEDIUM confidence)
- iOS keyboard heights (~216pt standard) -- [Federica Benacquista](https://federicabenacquista.medium.com/list-of-the-official-ios-keyboards-heights-and-how-to-calculate-them-c2b844ef54b9)
- Haptic prepare() performance impact -- [Cocoacasts](https://cocoacasts.com/uikit-fundamentals-adding-haptic-feedback-with-feedback-generators-in-swift)
- Custom keyboard extension limitations -- [Shyngys Kassymov Guide](https://shyngys.com/ios-custom-keyboard-guide)

### Tertiary (LOW confidence)
- Key popup overflow workaround (clipsToBounds) -- Training data only, not verified against current iOS behavior
- Apple dictation mic removal impossibility -- Verified by absence of documentation (negative claim)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - pure SwiftUI/UIKit, no new dependencies, all APIs well-documented
- Architecture: HIGH - clean extension points already exist in codebase (KeyType enum, KeyboardLayout arrays, SpecialKeyButton views)
- Pitfalls: HIGH - haptic pre-allocation is well-documented; popup clipping is a known community issue; trackpad pattern follows established DragGesture code
- KBD-05 (dictation mic): LOW - no public API found, marked as limitation
- Performance (KBD-06): MEDIUM - pre-allocation is a known fix, but full optimization needs device profiling

**Research date:** 2026-03-08
**Valid until:** 2026-04-08 (stable iOS APIs, 30-day validity)
