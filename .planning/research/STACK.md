# Technology Stack — v1.1 Additions

**Project:** Dictus v1.1 UX & Keyboard
**Researched:** 2026-03-07
**Scope:** Stack additions for new features only. Existing stack (WhisperKit, Swift 5.9+, SwiftUI, App Group, DictusCore) is validated and unchanged.

---

## 1. Text Prediction / Autocorrect (French)

### Recommendation: Build custom using UITextChecker + n-gram model

**Confidence:** MEDIUM

There is no production-ready, open-source, French text prediction library for iOS. The options are:

| Option | Verdict | Why |
|--------|---------|-----|
| **UITextChecker (Apple)** | USE for spell-check | Built-in, supports `fr_FR`, no dependency. `rangeOfMisspelledWord()` + `guesses(forWordRange:in:language:)` work for French out of the box |
| **UILexicon (Apple)** | USE as supplement | Available in keyboard extensions via `requestSupplementaryLexicon()`. Contains contact names + user shortcuts. Free data source |
| **Custom n-gram model** | BUILD for word prediction | Train trigram model on French corpus (Wikipedia FR dump). Ship as SQLite DB in App Group. ~5-15MB compressed |
| **KeyboardKit Pro** | DO NOT USE | Commercial license ($$$), closed-source Pro for autocorrect/prediction. Contradicts MIT open-source positioning |
| **Presage** | DO NOT USE | C++ library, no iOS/Swift bindings, GPL license (incompatible with MIT), unmaintained |
| **Predict4All** | DO NOT USE | Java-based, no iOS port, research project |
| **Apple Foundation Models (iOS 26.1+)** | DEFER to v1.2+ | On-device next word prediction via Apple Intelligence, but requires iPhone 15 Pro+ and iOS 26.1+. Too restrictive for iOS 16+ target |

### Implementation approach

```
Autocorrect pipeline:
1. UITextChecker.rangeOfMisspelledWord() -> detect typos
2. UITextChecker.guesses(forWordRange:in:language:"fr") -> get corrections
3. Custom n-gram DB -> rank corrections by context probability
4. Display top 3 in suggestion bar

Word prediction pipeline:
1. Track last 2 words typed (trigram context)
2. Query n-gram SQLite DB for most probable next words
3. Display top 3 predictions in suggestion bar
4. Tap suggestion -> insert word + space
```

### Dependencies needed

| Technology | Purpose | Size Impact | Notes |
|------------|---------|-------------|-------|
| UITextChecker | Spell-check + corrections | 0 (system) | Already available, language param `"fr"` |
| UILexicon | Contact names supplement | 0 (system) | `requestSupplementaryLexicon()` in UIInputViewController |
| SQLite (via Foundation) | n-gram storage | 0 (system) | No third-party SQLite wrapper needed, use Foundation's built-in |
| French n-gram DB | Word prediction data | ~10-15MB | Generate offline from French Wikipedia corpus using text2ngram or custom Python script, ship via App Group |

### Key constraints

- Keyboard extension 50MB memory limit applies -- n-gram DB must be queried via SQLite (not loaded into memory)
- UITextChecker guesses on iOS are alphabetically ordered, not probability-ranked -- need n-gram model to re-rank
- Must handle French-specific challenges: accented characters (e/e/e/e), elision (l'homme), compound words

### Sources

- [UITextChecker Apple Docs](https://developer.apple.com/documentation/uikit/uitextchecker)
- [UITextChecker guesses method](https://developer.apple.com/documentation/uikit/uitextchecker/guesses(forwordrange:in:language:))
- [NSHipster UITextChecker](https://nshipster.com/uitextchecker/)
- [ios-uitextchecker-autocorrect](https://github.com/ansonl/ios-uitextchecker-autocorrect) -- reference implementation (unmaintained but useful pattern)

---

## 2. Spacebar Trackpad Cursor Movement

### Recommendation: Custom gesture recognizer on space bar key (no library needed)

**Confidence:** HIGH

This is a pure UIKit gesture implementation. No third-party library exists or is needed. Apple's own keyboard does this with a UILongPressGestureRecognizer transitioning to UIPanGestureRecognizer.

### Implementation approach

| Component | Technology | Notes |
|-----------|------------|-------|
| Long-press detection | UILongPressGestureRecognizer | 0.3s threshold on spacebar |
| Pan tracking | UIPanGestureRecognizer | Track X/Y translation after long-press activates |
| Cursor movement | `textDocumentProxy.adjustTextPosition(byCharacterOffset:)` | UIInputViewController API -- moves cursor left/right |
| Visual feedback | SwiftUI animation | Fade keyboard labels, show trackpad indicator |
| Haptic feedback | UIImpactFeedbackGenerator(.light) | Tick on each character position change |

### Key detail: `adjustTextPosition(byCharacterOffset:)`

This is the official UITextDocumentProxy method for moving the cursor. Takes a positive (right) or negative (left) integer offset. Call it based on pan gesture translation divided by a sensitivity threshold (~8-10pt per character step).

### Vertical movement

Vertical cursor movement (line up/down) is NOT supported by `adjustTextPosition()` -- it only moves horizontally by character count. This matches Apple's keyboard behavior on non-3D-Touch devices. Do not attempt vertical movement.

### Dependencies needed

None. All APIs are built into UIKit.

### Sources

- [UITextDocumentProxy adjustTextPosition](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/1618198-adjusttextposition)

---

## 3. Adaptive Accent Key

### Recommendation: Context-aware key using textDocumentProxy + frequency table

**Confidence:** HIGH

No library needed. Build a simple state machine that checks the previous character(s) via `textDocumentProxy.documentContextBeforeInput` and shows the most likely accent/punctuation.

### Implementation approach

```
Context rules (French-specific):
- After vowel -> show accent acute (e)
- After consonant at word end -> show apostrophe (')
- After "c" -> show cedilla (c)
- After space/start -> show apostrophe (for l', d', s', n', j', qu')
- Default -> show apostrophe (most common in French)
```

| Input context | Key shows | Rationale |
|---------------|-----------|-----------|
| After a vowel | acute accent (e) | Most common French accent |
| After "c" | cedilla (c) | Cedilla after c |
| After space or start | apostrophe (') | Elision is very frequent |
| Default | apostrophe (') | Highest-frequency French punctuation |

### Dependencies needed

None. Uses `textDocumentProxy.documentContextBeforeInput` (already available in keyboard extension).

---

## 4. Cold Start Auto-Return to Keyboard

### Recommendation: Wispr Flow "session" model -- minimize cold starts, don't solve auto-return

**Confidence:** LOW -- This is the hardest unsolved problem in the milestone

### The problem

When DictusApp is not running (cold start), the keyboard extension opens DictusApp via URL scheme. After DictusApp starts recording, the user needs to return to the host app. There is NO public API to programmatically return to the previous app.

### What competitors do

**Wispr Flow's approach** (reverse-engineered from behavior, not documented):
1. Opens main app from keyboard for "Flow Session" activation
2. Claims to auto-return to previous app
3. FAQ admits "Not all apps allow the app to reopen" -- meaning it is selective/imperfect
4. Session stays active for 5 minutes of idle, so cold start only happens once per session

**Technical options investigated:**

| Technique | Status | Risk |
|-----------|--------|------|
| `_hostBundleID` private API | Blocked in iOS 18+ | App Store rejection |
| `UIApplication.suspend()` | Goes to home screen, not previous app | Wrong behavior |
| x-callback-url | Requires host app cooperation | Only works with specific apps |
| NSUserActivity / Handoff | Not applicable to keyboard extensions | Wrong use case |
| Clipboard-based bundle ID stash | Store host bundle ID before opening app, use URL scheme to return | Only works for apps with known URL schemes |
| Background URL scheme timer | Open dictus://, do work, then open host app URL scheme | Requires knowing host app's URL scheme |
| "Session" model (Wispr Flow pattern) | Keep app alive with audio background mode, only cold start once | Best practical approach |

### Recommended approach: Wispr Flow session model

1. **First cold start:** User taps mic in keyboard -> opens DictusApp -> user manually returns (swipe/tap status bar "< Back")
2. **DictusApp stays alive** via `UIBackgroundModes:audio` (already implemented)
3. **Subsequent taps:** Darwin notification works instantly, no app switch needed
4. **Session timeout:** After 5 min idle, audio session ends, next tap = cold start again (rare)

This is what Wispr Flow does. The "auto-return" is not truly automatic -- they minimize cold starts. The key improvement for Dictus is to **extend the audio session keep-alive duration** and **show a clear "tap Back to return" instruction** on first cold start.

### Dependencies needed

None new. Existing Darwin notification + URL scheme + audio background mode.

### Open research question

How exactly does Wispr Flow return to the previous app on cold start? The Swift Forums thread (Jan 2026) found no public API. Either they use a private API (risky for App Store) or they have a clever workaround not yet discovered. Flag this for deeper reverse-engineering research during implementation.

### Sources

- [Swift Forums discussion -- auto-return](https://forums.swift.org/t/how-do-voice-dictation-keyboard-apps-like-wispr-flow-return-users-to-the-previous-app-automatically/83988)
- [Wispr Flow FAQ](https://docs.wisprflow.ai/iphone/faq)

---

## 5. Removing Apple Dictation Mic Button

### Recommendation: Already handled by custom keyboard -- non-issue

**Confidence:** HIGH

Custom keyboard extensions (UIInputViewController) do NOT show the Apple dictation mic button. That button only appears on the system keyboard. Since Dictus IS a custom keyboard, the Apple mic is not present when Dictus keyboard is active.

### What you actually need to address

The real issue may be the **system keyboard bottom bar** (globe button area) that iOS shows beneath custom keyboards on certain devices. This is controlled by iOS, not by the extension.

| Concern | Solution |
|---------|----------|
| Globe button shows at bottom | Check `needsInputModeSwitchKey` -- if true, show your own globe key. System globe appears in bottom bar on iPhone X+ regardless |
| Dictation mic in system bar | Cannot be removed programmatically. Users disable via Settings > General > Keyboard > Enable Dictation |
| System keyboard bleeding through | Ensure `inputView` height constraint is properly set (already done in KeyboardViewController) |

### Dependencies needed

None. This is a design/layout concern, not a technology concern.

### Sources

- [Apple Custom Keyboard Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)

---

## 6. Parakeet v3 / Alternative STT Models

### Recommendation: FluidAudio SDK with Parakeet TDT v3 CoreML -- as optional ALTERNATIVE to WhisperKit

**Confidence:** MEDIUM

### FluidAudio + Parakeet TDT v3

| Attribute | Value |
|-----------|-------|
| **Library** | [FluidAudio](https://github.com/FluidInference/FluidAudio) |
| **Model** | Parakeet TDT 0.6B v3 (CoreML) |
| **Languages** | 25 European languages including French |
| **iOS minimum** | iOS 17.0+ (higher than Dictus's iOS 16.0 target) |
| **Model size on disk** | ~2.5GB (significantly larger than WhisperKit small ~460MB) |
| **RAM usage** | ~1.2GB (vs WhisperKit small ~150-200MB) |
| **Performance** | ~110x RTF on M4 Pro (batch mode). Much faster than Whisper |
| **Accuracy** | Beats Whisper Large v3 on benchmarks |
| **License** | MIT/Apache 2.0 (models permissive) |
| **Integration** | Swift native, SPM, CoreML on Neural Engine |

### Critical constraints for Dictus

| Constraint | Impact |
|------------|--------|
| iOS 17.0+ minimum | Raises Dictus minimum from iOS 16.0 to 17.0 if adopted. Acceptable -- iOS 17 adoption >95% |
| 2.5GB model size | Cannot coexist easily with WhisperKit models. Must be an either/or choice for users |
| 1.2GB RAM | Cannot run in keyboard extension (50MB limit). Must run in DictusApp process (same as current WhisperKit architecture) |
| Batch-only transcription | No streaming/real-time mode documented. Compatible with current batch approach |

### Recommendation

Add Parakeet v3 as an **optional model** in the model manager alongside existing WhisperKit models. Users choose one engine. Do NOT replace WhisperKit -- it remains the default for users with storage constraints.

### Integration plan

```
Model Manager UI:
+-- WhisperKit Models (default)
|   +-- tiny (~40MB) -- fast, lower accuracy
|   +-- base (~140MB) -- balanced
|   +-- small (~460MB) -- best WhisperKit accuracy
+-- Parakeet v3 (alternative)
    +-- parakeet-tdt-0.6b-v3 (~2.5GB) -- highest accuracy, needs more storage
```

### Dependencies needed

| Technology | Version | Purpose |
|------------|---------|---------|
| FluidAudio | latest (SPM) | Parakeet CoreML inference engine |

### Installation

```swift
// Xcode SPM: File > Add Package Dependencies
// URL: https://github.com/FluidInference/FluidAudio.git
```

### Sources

- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio)
- [Parakeet TDT v3 CoreML on HuggingFace](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- [sherpa-onnx RAM issue #2626](https://github.com/k2-fsa/sherpa-onnx/issues/2626) -- confirms 1.2GB RAM for Parakeet 0.6B

---

## 7. Emoji Picker in Keyboard Extension

### Recommendation: Build custom emoji grid in SwiftUI (no library needed)

**Confidence:** HIGH

### Options evaluated

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Custom SwiftUI grid** | Full Liquid Glass design control, zero dependencies | More work (~2-3 days), must handle categories/skin tones | RECOMMENDED |
| **ISEmojiView** | Battle-tested, SPM support, ~0.3.0 | UIKit-based (needs bridging in SwiftUI keyboard), may not match Liquid Glass | ACCEPTABLE for faster delivery |
| **MCEmojiPicker** | SwiftUI native, small (795KB), updated Feb 2026 | Popover-style (macOS-like), not keyboard-style grid | NOT IDEAL for keyboard context |
| **KeyboardKit emoji module** | Professional, categorized | Commercial Pro required for full features | DO NOT USE (license conflict) |

### Recommended approach: Custom SwiftUI grid

Emojis are Unicode strings. No library needed to render them.

```swift
// Emojis are just strings -- insert via textDocumentProxy
textDocumentProxy.insertText("emoji-character")

// Use LazyVGrid for scrollable grid
// Categories: Smileys, People, Animals, Food, Travel, Activities, Objects, Symbols, Flags
// Skin tone: long-press popup (same pattern as existing AccentPopup)
// Recents: store in UserDefaults via App Group
```

### Dependencies needed

None for recommended approach. ISEmojiView (~0.3.0 via SPM) as fallback option.

### Sources

- [ISEmojiView GitHub](https://github.com/isaced/ISEmojiView)
- [MCEmojiPicker GitHub](https://github.com/izyumkin/MCEmojiPicker)

---

## Summary: New Dependencies for v1.1

### Required additions

| Dependency | Version | Purpose | Feature | Size Impact |
|------------|---------|---------|---------|-------------|
| French n-gram SQLite DB | Custom-built | Word prediction | Text prediction | ~10-15MB in App Group |

### Optional additions

| Dependency | Version | Purpose | Feature | Size Impact |
|------------|---------|---------|---------|-------------|
| FluidAudio | latest via SPM | Parakeet v3 STT engine | Model catalog | SDK ~5MB, model ~2.5GB user-downloaded |
| ISEmojiView | ~0.3.0 via SPM | Emoji picker grid (if not building custom) | Emoji keyboard | ~100KB |

### Explicitly NOT adding

| Technology | Why Not |
|------------|---------|
| KeyboardKit / KeyboardKit Pro | Commercial, closed-source, contradicts MIT open-source project |
| Presage | C++ only, GPL license, unmaintained |
| LanguageTool | Server-based, contradicts offline-first |
| Any autocorrect API service | Contradicts privacy/offline identity |
| Apple Foundation Models | Requires iPhone 15 Pro+ and iOS 26.1+ -- too restrictive for current target |
| sherpa-onnx for Parakeet | ONNX Runtime on iOS has CoreML instability; FluidAudio's native CoreML conversion is superior |

### Unchanged from v1.0

| Technology | Version | Status |
|------------|---------|--------|
| WhisperKit | 0.16.0+ | Stays as default STT engine |
| Swift | 5.9+ | Unchanged |
| SwiftUI | - | Unchanged |
| App Group | group.com.pivi.dictus | Unchanged |
| Minimum iOS | 16.0 (or 17.0 if Parakeet added) | Potentially raised |

---

## Installation (new dependencies only)

```bash
# If adding FluidAudio for Parakeet v3:
# Xcode: File > Add Package Dependencies
# URL: https://github.com/FluidInference/FluidAudio.git

# If using ISEmojiView for emoji picker:
# URL: https://github.com/isaced/ISEmojiView.git
# Version: Up to Next Minor from 0.3.0

# French n-gram database:
# Generated offline with Python script (not an SPM dependency)
# Placed in App Group container at build time or first launch
```

---

## Confidence Assessment

| Feature Area | Confidence | Reason |
|--------------|------------|--------|
| Text prediction/autocorrect | MEDIUM | UITextChecker for French is documented but under-tested in production keyboards. N-gram approach is proven but requires building from scratch |
| Spacebar trackpad | HIGH | `adjustTextPosition(byCharacterOffset:)` is well-documented Apple API, widely implemented |
| Adaptive accent key | HIGH | Simple context logic using existing `textDocumentProxy` API |
| Cold start auto-return | LOW | No public API exists. Wispr Flow's technique is unknown. Best approach is minimizing cold starts |
| Remove Apple mic | HIGH | Non-issue for custom keyboards -- mic is system keyboard only |
| Parakeet v3 models | MEDIUM | FluidAudio is young (2025), CoreML conversion works, but production iOS stories are limited |
| Emoji picker | HIGH | Well-understood problem, multiple proven approaches, existing AccentPopup pattern to follow |
