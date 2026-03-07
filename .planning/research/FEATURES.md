# Feature Landscape: v1.1 Keyboard Parity & UX

**Domain:** iOS keyboard extension -- French speech-to-text
**Researched:** 2026-03-07
**Focus:** Apple keyboard parity features, UX improvements for existing v1.0 keyboard

---

## Table Stakes

Features users expect from any iOS keyboard that claims to replace Apple's native keyboard. Missing any of these makes the keyboard feel "off" and pushes users back to Apple's default.

### 1. Spacebar Trackpad / Cursor Movement

| Aspect | Detail |
|--------|--------|
| **Why Expected** | Apple introduced this in iOS 12 (2018). Every iPhone user who edits text uses it daily. Third-party keyboards (Gboard, SwiftKey) also implement it. A keyboard without trackpad feels broken. |
| **Complexity** | Medium |
| **Can Reuse Existing Code** | Partially -- SpaceKey already exists, needs long-press gesture added |

**How Apple Does It:**
- Long-press spacebar (~350-400ms) activates trackpad mode
- All key labels fade out, entire keyboard turns light grey/transparent
- Finger movement on the greyed-out area maps to cursor movement via `textDocumentProxy.adjustTextPosition(byCharacterOffset:)`
- Horizontal movement = character-by-character cursor repositioning
- Vertical movement has no effect on iPhone (iPad supports vertical for line movement)
- Release finger = exit trackpad mode, keys reappear
- Subtle haptic tick on each cursor position change (UIImpactFeedbackGenerator, light)
- No text selection on iPhone via spacebar alone (iPad uses two-finger gesture for selection)

**How Gboard/SwiftKey Do It:**
- SwiftKey: slide thumb along spacebar (no long-press delay, immediate cursor drag). More responsive but sometimes triggers accidentally.
- Gboard: long-press spacebar, similar to Apple but with slightly different visual treatment.
- Both: horizontal movement only for cursor on iPhone.

**Implementation in Dictus:**
- Add DragGesture with long-press timer (400ms) to SpaceKey, same pattern already used in KeyButton for accent popups
- On activation: set a `@State var trackpadActive = true` in KeyboardView, conditionally render greyed-out overlay
- During drag: call `controller.textDocumentProxy.adjustTextPosition(byCharacterOffset:)` with +1 or -1 based on horizontal delta
- Map pixel movement to character offset: ~15-20pt per character step works well
- Add haptic feedback per cursor step: `UIImpactFeedbackGenerator(style: .light).impactOccurred()`
- On release: restore normal keyboard view

**Key API:** `UITextDocumentProxy.adjustTextPosition(byCharacterOffset:)` -- moves insertion point forward (positive) or backward (negative). Available since iOS 11. Uses UTF-16 character offsets internally, so emoji/special chars may need `.utf16.count` handling.

**Confidence:** HIGH -- well-documented Apple API, straightforward gesture implementation.

### 2. Haptic Feedback on All Keys

| Aspect | Detail |
|--------|--------|
| **Why Expected** | Apple's native keyboard provides haptic feedback on every key press (iOS 16+). Users notice immediately when a third-party keyboard lacks it. |
| **Complexity** | Low |
| **Can Reuse Existing Code** | Yes -- HapticFeedback utility exists, KeyButton already calls it on accent selection |

**How Apple Does It:**
- Light impact haptic on every key press (not just special keys)
- Enabled via Settings > Sounds & Haptics > Keyboard Feedback > Haptic
- Uses UIImpactFeedbackGenerator(style: .light) or equivalent system API

**Current State in Dictus:**
- `HapticFeedback.keyTapped()` already exists and is called in KeyButton.onEnded
- `UIDevice.current.playInputClick()` is called for audio feedback when hasFullAccess
- Haptic calls appear to be in place for character keys and accent selection
- Special keys (shift, delete, globe, layer switch) may be missing haptics

**What Needs to Change:**
- Audit all special key views (ShiftKey, DeleteKey, GlobeKey, LayerSwitchKey, ReturnKey) for haptic feedback
- Ensure delete-on-hold also fires haptics on each repeat deletion
- Verify HapticFeedback.keyTapped() uses the right intensity (should be light, not medium)

**Confidence:** HIGH -- minimal new code, mostly verification and consistency.

### 3. Adaptive Accent/Apostrophe Key (Context-Sensitive)

| Aspect | Detail |
|--------|--------|
| **Why Expected** | Apple's native iOS French AZERTY has a key in the bottom letter row (row 3, between N and delete) that shows either an apostrophe (') or an accent grave/cedilla based on typing context. This is a distinctive French AZERTY feature. |
| **Complexity** | Medium |
| **Can Reuse Existing Code** | Partially -- KeyDefinition supports character keys, but needs context-awareness logic |

**How Apple Does It (French AZERTY, iOS):**
- Row 3 on Apple's iOS AZERTY: `shift W X C V B N ['/accent] delete`
- The key between N and delete is context-adaptive:
  - Default state: shows apostrophe (') -- the most common punctuation in French
  - After certain letters where accent is likely (e.g., after space before a vowel): shows accent grave or other contextual character
- The key adapts based on `documentContextBeforeInput` -- what the user just typed
- Most common behavior: apostrophe by default, because French uses contractions constantly (l'homme, j'ai, d'accord, c'est, n'est, qu'il)

**Dictus Current State:**
- Row 3 is: `shift W X C V B N delete` -- missing this key entirely
- Apostrophe is only accessible via long-press or switching to the numbers layer (row 3 of numbers layout has `'`)
- This is a significant gap -- French users type apostrophes constantly

**Implementation Approach:**
- Add a new KeyType: `.adaptive` or modify `.character` to support context-sensitivity
- Add a `KeyDefinition` between N and delete in the AZERTY layout: `KeyDefinition("'", output: "'", type: .adaptive, width: 1.0)`
- Context logic reads `controller.textDocumentProxy.documentContextBeforeInput` to decide what to show
- Simple heuristic for French:
  - Default: apostrophe `'` (covers 90%+ of use cases)
  - After specific letter combinations: could show accent but this is complex and low-ROI
- Start with a static apostrophe key -- it solves the biggest pain point. Make it adaptive later.

**User Behavior Reference:**
- French users type apostrophes ~5-10 times per paragraph (l', d', n', s', c', j', qu')
- Without a visible apostrophe key, users must: switch to numbers layer, type apostrophe, switch back -- 3 taps instead of 1
- This alone is enough to make users abandon a French keyboard

**Confidence:** MEDIUM -- Apple's exact context-switching logic is not documented. Starting with a static apostrophe key is safe and solves the core problem.

### 4. Remove Duplicate Globe Key / Reorganize Bottom Row

| Aspect | Detail |
|--------|--------|
| **Why Expected** | Apple's iOS keyboard has one globe key in the bottom-left. Having duplicates or wrong placement confuses muscle memory. |
| **Complexity** | Low |
| **Can Reuse Existing Code** | Yes -- layout changes only in KeyboardLayout.swift |

**Current Dictus Bottom Row (AZERTY):** `globe 123 [mic filtered] space return`
**Apple's Bottom Row (AZERTY):** `globe 123 emoji space return`

**What Needs to Change:**
- The mic key is already filtered from the bottom row (moved to toolbar in v1.0)
- Replace the mic key slot with an emoji button
- Ensure globe key uses `advanceToNextInputMode()` (already does)

**Confidence:** HIGH -- layout restructuring only.

---

## Differentiators

Features that set Dictus apart. Not expected by default but valued by users who discover them.

### 1. Text Prediction / Autocorrect Suggestion Bar

| Aspect | Detail |
|--------|--------|
| **Value Proposition** | Bridges the gap between "dictation keyboard" and "full replacement keyboard." Users who switch to Dictus for dictation but have to switch back for typing (because no autocorrect) will eventually stop switching. |
| **Complexity** | High |
| **New Subsystem Required** | Yes -- prediction engine, suggestion bar UI, word replacement logic |

**How Apple Does It:**
- Three-slot suggestion bar above the keyboard
- Center slot: autocorrect (bold, auto-applied on space)
- Left/right slots: alternative predictions
- Tap a suggestion to insert it (replaces current partial word)
- Powered by on-device ML model trained per language
- Learns from user typing patterns over time

**How Gboard/SwiftKey Do It:**
- SwiftKey: three-slot bar, learns writing style, predicts next word (not just completion)
- Gboard: similar three-slot bar, powered by Google's prediction engine
- Both use proprietary ML models far beyond what public APIs offer

**Available iOS APIs for Dictus:**
- `UITextChecker` -- built-in iOS spell checker with French support
  - `rangeOfMisspelledWord(in:range:startingAt:wrap:language:)` -- finds misspelled words
  - `guesses(forWordRange:in:language:)` -- returns correction suggestions
  - `completions(forPartialWordRange:in:language:)` -- word completions from partial input
  - Language parameter: `"fr"` or `"fr_FR"` for French
  - Limitations: completions sort alphabetically (not by probability), no next-word prediction, context-independent
- `UILexicon` (via `requestSupplementaryLexicon`) -- user's contact names and text shortcuts
  - Supplements UITextChecker with user-specific vocabulary
- `UITextDocumentProxy.documentContextBeforeInput` -- recent text for context

**Realistic Scope for Dictus:**
- **Spell-check + autocorrect**: Use UITextChecker with `"fr"` language. Trigger on space/punctuation. Show top 3 guesses in suggestion bar. Auto-apply top guess if confidence is high (single guess returned).
- **Word completion**: Use `completions(forPartialWordRange:)` as user types. Show in suggestion bar.
- **Next-word prediction**: NOT possible with public iOS APIs. Would require a custom n-gram model or on-device LLM. Defer.
- **User learning**: UITextChecker.learnWord() lets Dictus remember user vocabulary. Learned words persist device-wide.

**Suggestion Bar UI:**
- Horizontal bar above the keyboard, height ~36-40pt
- Three slots separated by thin dividers
- Center slot = autocorrect (bold text), auto-inserted on space
- Left/right slots = completions or alternatives, tap to insert
- Integrates between ToolbarView (mic button) and KeyboardView
- Consider: merge suggestion bar INTO the toolbar row to save vertical space

**Accented Character Suggestions in Bar:**
- For French, when user types "e", show e/e/e/e as quick-access accented variants
- This supplements the existing long-press accent popup with a faster one-tap method
- Read `documentContextBeforeInput` to determine if accented suggestion is relevant

**Memory Considerations:**
- UITextChecker is lightweight, system-provided -- no extra memory
- Suggestion bar UI is minimal SwiftUI
- No ML model loading required for basic spell-check
- Stays well within 50MB keyboard extension limit

**Confidence:** MEDIUM -- UITextChecker French support works but quality of suggestions is unknown. Alphabetical sorting (not probability) may produce poor UX. Needs prototyping to evaluate.

### 2. Emoji Picker Integration

| Aspect | Detail |
|--------|--------|
| **Value Proposition** | Users switch keyboards frequently for emoji. If Dictus has a basic emoji picker, they stay in Dictus longer. |
| **Complexity** | Medium-High |
| **New Subsystem Required** | Yes -- emoji data source, grid view, category tabs, search |

**How Apple Does It:**
- Emoji button in bottom row opens full emoji keyboard
- Category tabs at bottom (Smileys, Animals, Food, etc.)
- Recently used section at top
- Search bar
- Skin tone variants on long-press

**Options for Dictus:**
1. **Globe key fallback** (simplest): tapping an emoji button calls `advanceToNextInputMode()` which cycles to Apple's emoji keyboard. Zero implementation but requires a keyboard switch round-trip.
2. **Basic built-in picker** (medium): grid of common emoji organized by category. Use Unicode emoji data. No search, no skin tones. Covers 80% of use cases.
3. **Third-party library** (ISEmojiView, MCEmojiPicker): pre-built emoji grids with categories and search. SPM-compatible. Adds dependency but saves significant development time.
4. **KeyboardKit Pro** ($): includes emoji keyboard. But adds a paid dependency to an open-source project -- philosophically misaligned.

**Recommendation:** Start with option 1 (globe/emoji button that switches to system emoji keyboard). This is what Wispr Flow does. A built-in emoji picker is a v1.2+ feature -- it's a lot of UI work for a feature that Apple already provides well.

**Bottom Row Change:**
- Replace the filtered mic key position with an emoji/smiley button
- Button shows `face.smiling` SF Symbol
- Tap action: `advanceToNextInputMode()` -- cycles to next keyboard (usually emoji)
- This is functionally identical to a second globe key but with emoji iconography, signaling to the user "tap here for emoji"

**Confidence:** HIGH for the globe-based approach. LOW for building a custom emoji picker (complex, memory-heavy, version compatibility issues with new emoji).

### 3. Pill-Shaped Button Design (Mic + Recording Controls)

| Aspect | Detail |
|--------|--------|
| **Value Proposition** | Modern, premium feel. Pill/capsule shapes are the dominant iOS design pattern for action buttons (App Store download, Messages send, Spotlight search). Makes the mic button more tappable. |
| **Complexity** | Low |
| **Can Reuse Existing Code** | Yes -- AnimatedMicButton exists, just needs shape change |

**How to Implement:**
- SwiftUI `Capsule()` shape or `.clipShape(Capsule())` modifier
- `.buttonBorderShape(.capsule)` for system-styled buttons
- Replace circular mic button with horizontal pill: icon + "Dicter" label
- Recording overlay buttons (Stop, Cancel) also become pills
- Minimum tap target: 44x44pt (Apple HIG), pill allows wider touch area

**Design Pattern:**
```
[mic icon] Dicter     -- idle state, pill button in toolbar
[stop icon] Arreter   -- recording state, red pill
[x] Annuler           -- cancel, secondary pill
```

**Confidence:** HIGH -- pure UI change, well-supported by SwiftUI.

### 4. Cold Start Auto-Return to Keyboard

| Aspect | Detail |
|--------|--------|
| **Value Proposition** | When iOS kills the main app (common after 2-3 app switches), tapping mic opens the app but doesn't auto-return to the keyboard. User must manually navigate back. Competitors (Wispr Flow, Super Whisper) handle this seamlessly. |
| **Complexity** | High |
| **New Subsystem Required** | Partially -- needs investigation of competitor approaches |

**This is documented as the top priority in PROJECT.md and MEMORY.md.** Research on implementation approaches is a separate concern from feature landscape -- flagged for deeper investigation in PITFALLS.md.

**Confidence:** LOW -- how competitors achieve auto-return is unknown. Public APIs don't support programmatic app switching. May require private API usage or creative workarounds.

### 5. Waveform Animation Rework

| Aspect | Detail |
|--------|--------|
| **Value Proposition** | Current waveform works but could be smoother/more fluid. Premium animation quality signals app quality. |
| **Complexity** | Medium |
| **Can Reuse Existing Code** | Yes -- BrandWaveform.swift exists, needs animation tuning |

**Confidence:** HIGH -- pure visual polish, no API dependencies.

### 6. Model Catalog Update

| Aspect | Detail |
|--------|--------|
| **Value Proposition** | Remove underperforming models, add newer models (Parakeet v3) for better French accuracy. |
| **Complexity** | Medium |
| **New Subsystem Required** | No -- model manager already exists, needs catalog data update |

**Confidence:** MEDIUM -- depends on what models WhisperKit supports and Parakeet v3 compatibility.

---

## Anti-Features

Features to explicitly NOT build in v1.1.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Custom emoji picker (built-in) | 500+ lines of UI code, memory pressure in extension, Apple already provides emoji keyboard | Use `advanceToNextInputMode()` to cycle to system emoji keyboard |
| Next-word prediction | Requires custom ML model or n-gram database. UITextChecker cannot do this. Would need KeyboardKit Pro ($) or custom training. | Stick with word completion and spell-check via UITextChecker |
| Swipe typing (gesture typing) | Extremely complex gesture recognition + dictionary lookup. Gboard/SwiftKey spent years perfecting this. | Not in scope -- users who need swipe typing use Apple/Gboard |
| Text selection via trackpad | Apple does this on iPad (two-finger gesture), not on iPhone. Implementing it on iPhone would confuse users. | Only implement cursor movement (single-finger horizontal) |
| Auto-capitalize after punctuation | UITextChecker doesn't handle this. Would need custom logic for French rules (capitalize after `.`, `!`, `?` but NOT after `:` in French). | Defer to v1.2 -- could be a quick add but needs French-specific rules |
| Keyboard themes / custom colors | Nice-to-have, large surface area, distracts from core UX improvements. | Keep Liquid Glass as the single theme. Themes are a v2+ feature. |
| Clipboard history | Requires Full Access (already have it), but adds privacy concerns and UI complexity. | Defer indefinitely -- not aligned with privacy-first positioning |

---

## Feature Dependencies

```
Existing v1.0 infrastructure (keyboard, layout, gesture system)
  |
  +-- Spacebar Trackpad (builds on SpaceKey + DragGesture pattern from KeyButton)
  |     Requires: adjustTextPosition API, greyed-out overlay state
  |     No dependency on other v1.1 features
  |
  +-- Haptic Feedback on All Keys (builds on existing HapticFeedback utility)
  |     Requires: audit of all key views
  |     No dependency on other v1.1 features
  |
  +-- Adaptive Apostrophe Key (builds on KeyDefinition + KeyboardLayout)
  |     Requires: new key in AZERTY row 3, documentContextBeforeInput reading
  |     No dependency on other v1.1 features
  |
  +-- Bottom Row Reorganization (builds on KeyboardLayout)
  |     Requires: emoji/globe button replacing mic slot
  |     Blocks: emoji picker (needs button to exist first)
  |
  +-- Pill-Shaped Buttons (builds on AnimatedMicButton + RecordingOverlay)
  |     Requires: Capsule() shape, label text
  |     No dependency on other v1.1 features
  |
  +-- Text Prediction / Suggestion Bar [HIGH EFFORT]
  |     Requires: UITextChecker integration, suggestion bar UI, word replacement logic
  |     Depends on: bottom row reorganization (suggestion bar placement)
  |     Should be built AFTER simpler keyboard parity features
  |
  +-- Cold Start Auto-Return [HIGH RISK]
  |     Requires: deep research into competitor approaches
  |     No dependency on other v1.1 features
  |     Can be worked on in parallel
  |
  +-- Waveform Animation Rework (builds on BrandWaveform)
  |     No dependency on other v1.1 features
  |
  +-- Model Catalog Update (builds on model manager)
        No dependency on other v1.1 features
```

---

## MVP Recommendation for v1.1

### Phase 1 -- Keyboard Parity (ship first, highest user impact)

Prioritize these -- they are fast to implement and close the biggest gaps:

1. **Adaptive apostrophe key** -- French users need this immediately. Static apostrophe between N and delete. Low-medium effort, huge impact.
2. **Spacebar trackpad** -- Every iOS user expects this. Medium effort, clear implementation path via `adjustTextPosition`.
3. **Haptic feedback on all keys** -- Audit and fix. Low effort, noticeable quality improvement.
4. **Bottom row reorganization** -- Replace mic slot with emoji button, clean up layout. Low effort.
5. **Pill-shaped buttons** -- Pure visual upgrade. Low effort, premium feel.

### Phase 2 -- UX Polish (ship second)

6. **Waveform animation rework** -- Visual polish, medium effort.
7. **Recording screen redesign** -- Visual polish, medium effort.

### Phase 3 -- Complex Features (ship third, needs prototyping)

8. **Text prediction / suggestion bar** -- High effort, uncertain quality with UITextChecker for French. Prototype first, validate quality before committing.
9. **Model catalog update** -- Research Parakeet v3 compatibility, medium effort.

### Separate Track (parallel investigation)

10. **Cold start auto-return** -- High risk, needs dedicated research. Work on this in parallel with Phase 1-2, don't block other features on it.

**Defer to v1.2+:**
- Built-in emoji picker (use system keyboard cycling for now)
- Next-word prediction (needs custom ML, beyond UITextChecker)
- Swipe typing
- Keyboard themes

---

## Sources

- [Apple UITextDocumentProxy Documentation](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)
- [adjustTextPosition(byCharacterOffset:) API](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/1618194-adjusttextposition)
- [UITextChecker Documentation](https://developer.apple.com/documentation/uikit/uitextchecker)
- [UITextChecker - NSHipster](https://nshipster.com/uitextchecker/) -- detailed analysis of UITextChecker capabilities and limitations
- [ios-uitextchecker-autocorrect GitHub](https://github.com/ansonl/ios-uitextchecker-autocorrect) -- reference autocorrect implementation
- [KeyboardKit Features](https://keyboardkit.com/features) -- commercial framework feature comparison
- [SwiftKey Cursor Control](https://support.microsoft.com/en-us/topic/how-do-i-use-cursor-control-on-my-microsoft-swiftkey-keyboard-748643ba-8485-43ad-9729-8e5c908603e3)
- [Apple Capsule Shape Documentation](https://developer.apple.com/documentation/swiftui/capsule)
- [ISEmojiView GitHub](https://github.com/isaced/ISEmojiView) -- open-source emoji picker for iOS
- [MCEmojiPicker GitHub](https://github.com/izyumkin/MCEmojiPicker) -- SwiftUI emoji picker
- [Macworld: iPhone Keyboard Trackpad](https://www.macworld.com/article/558720/how-to-iphone-keyboard-trackpad.html)
- [9to5Mac: Keyboard Trackpad Mode](https://9to5mac.com/2018/09/17/how-to-use-keyboard-trackpad-mode-on-every-iphone-and-ipad-with-ios-12/)
- [Handling text interactions in custom keyboards - Apple](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)
