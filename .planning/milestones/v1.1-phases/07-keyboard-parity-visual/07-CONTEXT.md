# Phase 7: Keyboard Parity & Visual - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Users perceive the Dictus keyboard as equal to or better than Apple's native keyboard in core interactions, with a polished mic button and recording experience. Covers spacebar trackpad, adaptive accent key, haptics on all keys, bottom row cleanup (emoji button, remove Apple mic), mic/recording pill redesign, waveform rework, and performance optimization.

Requirements: KBD-01, KBD-02, KBD-03, KBD-04, KBD-05, KBD-06, VIS-01, VIS-02, VIS-03

</domain>

<decisions>
## Implementation Decisions

### Spacebar Trackpad (KBD-01)
- Long-press spacebar activates trackpad mode
- Visual overlay: greyed-out keys (labels fade out, key shapes remain as grey rectangles) — matches Apple's native behavior
- Free movement in all directions (left, right, up, down) — full Apple parity, not horizontal-only
- 1:1 cursor-to-finger sensitivity mapping (~8-10pt per character)
- Haptic pattern matches Apple exactly: (1) haptic on initial spacebar tap, (2) different haptic when trackpad mode activates, (3) no haptics during drag movement
- Cursor movement via textDocumentProxy.adjustTextPosition(byCharacterOffset:)

### Adaptive Accent Key (KBD-02)
- New key inserted between N and delete on AZERTY row 3: `shift | W X C V B N ['/accent] | delete`
- AZERTY only — QWERTY layout does not get this key (Apple convention)
- Context logic matches Apple French AZERTY: default shows apostrophe ('), after typing a vowel that can take an accent (e, a, u, etc.) the key shows the most common accent for that vowel (e.g., é after e, à after a)
- Long-press on the accent key shows all accent variants for the relevant vowel (consistent with existing letter key long-press behavior)

### Haptic Feedback on All Keys (KBD-03)
- Uniform HapticFeedback.keyTapped() on every key tap: letters, space, return, delete, symbols, emoji, 123, shift
- Currently only letter keys have haptic — space/return/delete use UIDevice.playInputClick() only
- playInputClick() kept as addition for click sound where already present

### Bottom Row & Emoji (KBD-04)
- Globe key in our row 4 replaced with emoji button (😊 icon)
- Tap emoji = advanceToNextInputMode() which cycles to system emoji keyboard
- No long-press behavior on emoji button
- Globe functionality (keyboard switching) handled by the iOS system globe key that appears below the keyboard automatically
- Bottom row becomes: `emoji | 123 | space | return`

### Remove Apple Dictation Mic (KBD-05)
- Remove the system-provided Apple dictation mic icon that appears at bottom-right below the keyboard
- Research required: Info.plist key or other approach to suppress it

### Performance Optimization (KBD-06)
- Two confirmed issues from user testing:
  1. Input lag — typing feels slower than Apple keyboard, characters appear with delay
  2. Haptic latency — haptic feedback triggers noticeably later than on Apple keyboard
- Likely cause: HapticFeedback.keyTapped() creates a new UIImpactFeedbackGenerator on every call instead of pre-allocating + calling .prepare() ahead of time
- Likely cause: SwiftUI rendering overhead from overlays, popup previews, re-renders
- Needs profiling on real device to identify and fix bottlenecks

### Mic Button Pill Redesign (VIS-01)
- Mic button in toolbar becomes pill-shaped (icon only, no text label)
- Design inspired by existing AnimatedMicButton style (Liquid Glass, glow, state animations) — adapted from circle to pill shape
- Keeps the 4 visual states (idle glow, recording pulse, transcribing shimmer, success flash)

### Recording Buttons Pill Redesign (VIS-02)
- Cancel (X) and validate (✓) buttons in RecordingOverlay become pill-shaped
- Icon only, no text labels
- Same Liquid Glass pill style as the mic button for consistency
- Colors: Claude's Discretion (may adapt from current foreground/secondary colors)

### Waveform Rework (VIS-03)
- Waveform perfectly still when no sound input (currently has micro-movements at zero energy) — Super Whisper reference from Phase 6
- Sinusoidal processing animation already implemented in BrandWaveform(isProcessing: true) — reuse and adapt for keyboard RecordingOverlay
- Target 60fps via TimelineView + Canvas (current BrandWaveform already uses TimelineView for processing mode, needs Canvas for smoother bar rendering)

### Key Popup Clipping Fix
- Key press popups on top row are clipped/cut off by the keyboard container bounds
- Apple's popups extend above the keyboard area without clipping
- Fix needed: either clipsToBounds = false on the UIHostingController container, or render popups at a higher z-level that can extend beyond keyboard bounds

### Keyboard Height & Sizing
- Match Apple's native keyboard height per device (currently fixed at 4×46pt + spacing ≈ 210pt for all devices)
- Apple's keyboard height varies: ~216pt on iPhone SE, ~226pt on standard iPhones, ~271pt on Plus/Max
- Dynamic height calculation based on screen size

### Full Access Banner "Activer" Button Fix
- The "Activer" button in FullAccessBanner currently opens `app-settings:` URL which doesn't work reliably in keyboard extensions
- Should open Dictus app via `dictus://` URL scheme, which can then guide the user to enable Full Access
- This is the most reliable approach from a keyboard extension

### Claude's Discretion
- Recording pill button colors (may differ from mic pill to indicate different functions)
- Exact trackpad overlay animation (fade transition timing)
- Waveform Canvas rendering approach details
- Performance profiling strategy and specific optimizations found
- Key popup overflow rendering technique

</decisions>

<specifics>
## Specific Ideas

- Apple French AZERTY keyboard is the gold standard reference — match its layout, behavior, and feel exactly
- Haptic pattern on spacebar trackpad tested by user on Apple keyboard: tap → different haptic on mode activation → no haptics during drag
- Mic pill should carry the Liquid Glass aesthetic from AnimatedMicButton (existing circle design adapted to pill shape)
- BrandWaveform sinusoidal processing animation (Phase 6) is "really not bad" — reuse it for keyboard overlay
- User confirmed: typing on Dictus keyboard feels noticeably slower than Apple keyboard — priority performance issue
- User confirmed: haptic feedback triggers later than Apple — likely UIImpactFeedbackGenerator instantiation overhead

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictusCore/HapticFeedback.swift`: Already has keyTapped() (light impact) — needs to be called on ALL keys, not just letters. Generator pre-allocation needed for performance.
- `DictusCore/Design/AnimatedMicButton.swift`: 72pt circle with 4 states (idle/recording/transcribing/success) + Liquid Glass ring — adapt to pill shape for VIS-01
- `DictusCore/Design/BrandWaveform.swift`: 30-bar waveform with TimelineView for processing sinusoidal animation — upgrade to Canvas for 60fps, fix zero-energy stillness
- `DictusCore/AccentedCharacters.swift`: Accent lookup table already exists — extend for adaptive key context logic
- `DictusCore/Design/GlassModifier.swift`: .dictusGlass() modifier available for pill buttons

### Established Patterns
- KeyDefinition model with KeyType enum — add new .emoji type for the emoji button
- DragGesture(minimumDistance: 0) pattern used on KeyButton and DeleteKey — reuse for spacebar trackpad
- SpaceKey is currently a simple Button — needs DragGesture refactor for long-press → trackpad
- Task.sleep for long-press detection (400ms) — same pattern usable for spacebar trackpad activation

### Integration Points
- `KeyboardLayout.swift` — AZERTY lettersRows row 3: add adaptive accent key between N and delete
- `KeyboardLayout.swift` — row 4: replace globe with emoji key type
- `KeyboardView.swift` — add trackpad mode state, overlay rendering, cursor movement logic
- `SpecialKeyButton.swift` — add EmojiKey view, modify SpaceKey for trackpad behavior
- `ToolbarView.swift` — replace AnimatedMicButton circle with pill variant
- `RecordingOverlay.swift` — replace SF Symbol buttons with Liquid Glass pills
- `KeyboardRootView.swift` — fix FullAccessBanner URL from `app-settings:` to `dictus://`
- `KeyboardViewController.swift` — may need clipsToBounds override for popup overflow fix

</code_context>

<deferred>
## Deferred Ideas

- **Mic start/stop sound effect** — Audio feedback when activating/deactivating microphone. Requires sound design work. Future milestone (noted Phase 6).
- **Accuracy/speed gauges in model catalog** — Handy-style gauge bars per model. Scope: Phase 10 (MOD-03).
- **"FR EN" language indicator on spacebar** — Apple shows "FR EN" on spacebar. Could add this but it's cosmetic polish, not core parity.

</deferred>

---

*Phase: 07-keyboard-parity-visual*
*Context gathered: 2026-03-08*
