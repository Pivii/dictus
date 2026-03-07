# Domain Pitfalls

**Domain:** iOS keyboard extension — v1.1 feature additions (text prediction, spacebar trackpad, cold start auto-return, emoji picker, model catalog update)
**Researched:** 2026-03-07
**Context:** Existing v1.0 shipped with AZERTY/QWERTY layouts, long-press accent popup, recording overlay, two-process architecture (keyboard + app via Darwin notifications), WhisperKit STT in app process. 50MB extension memory limit. 6 design files duplicated between DictusApp and DictusKeyboard.

---

## Critical Pitfalls

Mistakes that cause rewrites, App Review rejections, or ship-blocking issues.

---

### Pitfall 1: Spacebar Trackpad Gesture Conflicts with Existing Long-Press Accent System

**What goes wrong:** The spacebar trackpad (long-press spacebar to enter cursor movement mode) uses the same gesture primitive as the existing accent popup system: `DragGesture(minimumDistance: 0)` with a timer-based long-press detection. Both features rely on detecting a hold gesture followed by horizontal drag. When both are active, SwiftUI's gesture resolution becomes unpredictable. Specifically:

- The spacebar's long-press must transition the entire keyboard into "trackpad mode" (all keys become a touch surface for cursor movement, letters disappear)
- But the accent popup system expects per-key DragGesture ownership to track which accent the finger hovers over
- If the user long-presses the spacebar and then drags upward into the letter rows, the system cannot determine if the user wants trackpad cursor movement or accidentally triggered an accent popup on a letter key above

The current `KeyButton.swift` uses a `DragGesture(minimumDistance: 0)` per key with a 400ms timer. The spacebar trackpad needs a single DragGesture across the entire keyboard area after spacebar long-press. These two gesture systems will fight each other.

**Why it happens:** Apple's stock keyboard handles this at the UIKit level with gesture recognizer priority and exclusive touch handling. SwiftUI does not expose gesture recognizer priority or `require(toFail:)` relationships between gestures on different views. The two gesture systems are architecturally incompatible as currently designed.

**Consequences:** Trackpad mode activates when user wants accents, or accents appear when user wants trackpad. Both features feel broken. Users lose trust in the keyboard.

**Prevention:**
1. Trackpad mode must be a **keyboard-level state**, not a per-key gesture. When spacebar long-press is detected, set `KeyboardState.isTrackpadMode = true` and overlay a transparent gesture capture view on top of all keys
2. While in trackpad mode, all per-key DragGestures are disabled (don't render KeyButton gesture at all when `isTrackpadMode`)
3. Use `adjustTextPosition(byCharacterOffset:)` on `textDocumentProxy` for cursor movement — this is the official API. Map horizontal drag delta to character offset: ~10pt per character works well
4. Exit trackpad mode on finger lift (DragGesture.onEnded)
5. Add haptic feedback (light impact) per cursor step to match Apple's stock behavior
6. Test the transition: long-press spacebar -> drag up into letter area -> release. This must NOT trigger any letter key or accent popup

**Detection:** User reports of "wrong letter inserted when trying to move cursor" or "cursor moves when trying to type accents on E"

**Phase:** Must be the FIRST keyboard feature implemented in v1.1 — it changes the gesture architecture for all keys.

---

### Pitfall 2: Text Prediction Blows the 50MB Memory Budget

**What goes wrong:** A French text prediction system (autocorrect + suggestion bar) requires at minimum:
- A French dictionary/word frequency model: 5-15MB depending on coverage
- N-gram or trie data structure for prefix matching: 8-20MB resident
- UITextChecker (Apple's built-in) is essentially free on memory but has poor French support and no word frequency ranking
- Any ML-based prediction model (even a small one): 15-50MB

The keyboard extension is already consuming memory for: SwiftUI view hierarchy (~8-10MB), DictusCore framework, Darwin notification observers, keyboard layout data, and the accent character mapping. Realistic baseline is ~15-20MB before any prediction engine loads. Adding even a modest prediction system pushes total memory toward or past the ~30-40MB jetsam kill threshold.

**Why it happens:** Developers underestimate the resident memory of dictionary/trie structures because they see small on-disk sizes. A compressed dictionary might be 3MB on disk but expand to 15MB when loaded into a trie for fast prefix lookup. Additionally, the suggestion bar itself (3 UILabel/Text views that update on every keystroke) triggers frequent SwiftUI re-renders that add to heap pressure.

**Consequences:** Extension gets killed by jetsam mid-typing. iOS replaces Dictus with the stock keyboard without warning. User loses their current text input context. This happens more on older devices (iPhone 12, 4GB RAM) where the threshold is lower.

**Prevention:**
1. Start with `UITextChecker` only — it is built into iOS, costs zero additional memory, supports French (`"fr"` language code), and provides spelling corrections via `guesses(forWordRange:in:language:)` and completions via `completions(forPartialWordRange:in:language:)`
2. UITextChecker limitations for French: no word frequency ranking (suggestions are alphabetical), no contextual prediction (doesn't know "je" should be followed by "suis"), no accented character suggestions based on context
3. If UITextChecker is insufficient, use a **compact frequency-based approach**: ship a pre-sorted top-10K French words file (~200KB), load it lazily, and do prefix matching in a sorted array with binary search. This adds <1MB resident memory
4. Do NOT ship a full French dictionary (300K+ words) in the extension. If needed, keep it in the app and query via App Group file reads
5. Profile memory after adding prediction: `Instruments > Allocations > mark generation before/after prediction init`
6. Set a hard budget: prediction system must use <5MB resident memory total

**Detection:** Extension crashes increase on iPhone 12/13 mini. Jetsam events in device logs. Users report "keyboard disappears randomly while typing."

**Phase:** Text prediction should be implemented AFTER trackpad and emoji, once the memory baseline is known. It has the highest memory risk.

---

### Pitfall 3: Emoji Picker Memory Is Unrecoverable

**What goes wrong:** iOS renders emoji as bitmap glyphs, and these bitmaps are cached in memory by the system font rendering pipeline. The critical issue: **after destroying a view that displays emoji, the emoji glyph cache is NOT released**. iOS keeps this cache for the lifetime of the process. In a normal app this is fine (plenty of memory), but in a keyboard extension with a ~40MB budget, rendering even 100-200 emoji can consume 5-15MB of cache that never comes back.

A full emoji picker showing all Unicode 15.1 emoji (~3,700+ emoji) will consume far more memory than the extension can afford. The picker will work the first time, but each category switch loads more emoji bitmaps into the permanent cache. After browsing 3-4 categories, the extension hits jetsam and dies.

**Why it happens:** The emoji glyph cache is managed by CoreText/CoreGraphics at the system level, not by the app. There is no API to flush this cache. Setting the view to `nil`, removing it from the hierarchy, or calling `removeFromSuperview()` does not release the cached glyphs.

**Consequences:** First use of emoji picker works. After browsing several categories, the keyboard crashes and iOS replaces it with the stock keyboard. This is not reproducible in the Simulator (which has much higher memory limits).

**Prevention:**
1. Do NOT build a full-category emoji picker inside the extension. Instead, show only a **single row of recent/frequent emoji** (8-12 emoji max) directly in the keyboard toolbar
2. For the full picker, open it as a **scrolling grid that renders only visible cells** — use SwiftUI `LazyVGrid` so off-screen emoji views are destroyed. However, note that the glyph cache still accumulates
3. Hard limit: never render more than ~50-80 unique emoji glyphs in a single session. After that threshold, the extension is at risk
4. Consider a "search-first" emoji design: user types emoji name, show 5-8 matching results. This avoids rendering hundreds of glyphs
5. Pre-populate the "recent emoji" row from the main app (store in App Group UserDefaults) so the extension never needs to show the full picker
6. Profile with `Instruments > VM Tracker` on an iPhone 12 — track dirty memory specifically, as the emoji cache shows up there

**Detection:** Memory grows monotonically during emoji browsing and never decreases. Extension crashes after extended emoji picker use.

**Phase:** Emoji button should replace the duplicate globe key with a simple recent-emoji row, NOT a full category picker. Full picker is out of scope for v1.1 given memory constraints.

---

### Pitfall 4: Cold Start Auto-Return Has No Public API Solution

**What goes wrong:** When the app is not running (cold start), the keyboard must open the app via URL scheme to start recording. The app launches, records, transcribes — but there is NO public iOS API to programmatically return the user to the previous app. The user is stranded in the Dictus app and must manually swipe back or tap the status bar "< Back" arrow.

Competitors like Wispr Flow handle this, but the technique is not publicly documented. Research into the Swift Forums and Apple Developer Forums reveals:
- `suspend()` on UIApplication goes to home screen, not the previous app
- `x-callback-url` requires cooperation from the host app (Messages, WhatsApp, etc. don't support it)
- Private APIs like `_hostBundleID` and `LSApplicationWorkspace` are blocked in iOS 18+
- Wispr Flow's approach appears to involve "Flow Sessions" where the app opens and immediately returns, but the exact mechanism is unclear

**Why it happens:** Apple intentionally restricts apps from controlling navigation flow between apps. This is a security/UX design decision. The "< Back to [previous app]" arrow in the status bar is an iOS system feature that apps cannot programmatically trigger.

**Consequences:** Cold start requires 2 taps (1st opens app, 2nd starts recording from keyboard after manually returning). This is the worst UX issue in v1.0 and the top priority for v1.1, but it may not be fully solvable without reverse-engineering competitor approaches.

**Prevention:**
1. **Minimize cold starts**: Keep the app alive as long as possible using `UIBackgroundModes: audio` (already implemented). Configure the audio session to maintain background execution even when not recording — play a silent audio loop if needed
2. **Speed up the cold start flow**: If the app must open, make it transcription-ready in <1 second. Pre-load WhisperKit at app launch, pre-warm the audio engine. The faster the round-trip, the less painful the UX
3. **Auto-start recording on URL scheme launch**: When opened via `dictus://dictate`, skip any UI and immediately start recording + show a minimal overlay with "Recording... Tap to stop". Auto-stop after silence detection
4. **Research Wispr Flow's exact technique**: Install Wispr Flow, use `Console.app` to monitor its system calls during cold start. Check if it uses `NSUserActivity` continuation, Handoff, or another system API
5. **Consider PiP (Picture-in-Picture) as a workaround**: A small floating recording indicator via PiP might keep the app "present" while the user returns to their previous app. This is a stretch but worth investigating
6. **Accept the limitation for v1.1**: Document the cold start behavior clearly in onboarding ("First tap opens Dictus, then tap the mic again"). Focus engineering effort on preventing cold starts rather than solving the auto-return

**Detection:** Users complain about "needing to tap twice" or "being stuck in the Dictus app after recording."

**Phase:** Research spike at the START of v1.1 (1-2 days max). Either find a working technique or accept the limitation and optimize the cold start speed instead.

---

## Moderate Pitfalls

Issues that cause significant rework or degraded UX.

---

### Pitfall 5: UITextChecker French Suggestions Are Poor Quality

**What goes wrong:** UITextChecker uses Apple's built-in dictionary infrastructure. While it supports French (`"fr"` language parameter), the quality of suggestions is significantly worse than Apple's stock keyboard prediction because:
- UITextChecker only does spell-checking (is this word misspelled?) and basic completions (prefix matching). It does NOT do contextual prediction ("after 'je', suggest 'suis', 'vais', 'peux'")
- Suggestions are alphabetically ordered, not frequency-ordered. For the prefix "con", it returns "conaissance" before "contacter" even though "contacter" is far more common
- French accentuation errors are handled inconsistently: "ecole" might not suggest "ecole" (missing accent) depending on the iOS version
- No n-gram or language model — each word is evaluated independently

Developers who prototype with UITextChecker and show it to testers get feedback like "the suggestions are useless" because users compare it to Apple's built-in keyboard which has a full neural language model.

**Prevention:**
1. Set expectations: UITextChecker is a v1.1 starting point, not the final solution. It is "free" in terms of memory and implementation time
2. Supplement with a hand-curated top-1000 French words list sorted by frequency. When UITextChecker returns suggestions, re-rank them against this frequency list
3. For accented character suggestions specifically (the v1.1 feature "accented character suggestions in suggestion bar"): build a simple rule-based system. After typing "e", show "e", "e", "e", "e" in the suggestion bar based on the preceding consonant pattern. This does not require UITextChecker at all
4. Do NOT build a custom language model for v1.1. Defer ML-based prediction to v1.2 when it can be researched properly
5. Label the feature as "Spelling suggestions" not "Predictive text" to set correct user expectations

**Phase:** Implement after spacebar trackpad and emoji row. Use UITextChecker as the base, add frequency re-ranking and accent rules on top.

---

### Pitfall 6: Adding Non-Whisper STT Models Breaks the Two-Process Architecture

**What goes wrong:** The v1.1 scope includes "Model catalog update (remove weak models, research Parakeet v3+)." Adding NVIDIA Parakeet alongside WhisperKit introduces several integration risks:

- **Different APIs**: WhisperKit has a specific Swift API (`WhisperKit.transcribe()`). Parakeet models via FluidAudio/CoreML have a completely different interface. The `TranscriptionService` and `AudioRecorder` would need an abstraction layer
- **Different model formats**: WhisperKit uses its own `.mlmodelc` packaging with specific encoder/decoder structure. Parakeet CoreML models from HuggingFace (FluidInference/parakeet-tdt-0.6b-v2-coreml) use a different architecture (TDT = Token-and-Duration Transducer, not encoder-decoder)
- **Different audio preprocessing**: Whisper expects 16kHz 80-channel mel spectrogram. Parakeet expects 16kHz 80-channel mel spectrogram but with different normalization. Sending Whisper-preprocessed audio to Parakeet produces garbage output
- **Memory**: Parakeet 0.6B is 600M parameters — far too large for the current architecture. Even quantized to INT4, it would be ~300MB resident

**Why it happens:** "Add Parakeet" sounds simple because both are "speech-to-text CoreML models." But the preprocessing, inference pipeline, and output format are completely different. This is not a model swap — it is a second complete STT pipeline.

**Prevention:**
1. For v1.1, limit scope to **curating the WhisperKit model catalog**: remove models with poor French accuracy (tiny.en, base.en), add better French-specific Whisper variants if available on the WhisperKit model hub
2. Do NOT add Parakeet in v1.1. It requires: a new model loader, new audio preprocessor, new output parser, abstraction layer over TranscriptionService, and memory profiling of a much larger model
3. If Parakeet is desired for v1.2+: design the `TranscriptionService` protocol NOW (in v1.1) with `protocol STTEngine { func transcribe(audioURL: URL) async throws -> String }` so WhisperKit and future engines conform to the same interface
4. Research Parakeet v3 CoreML availability: as of March 2026, FluidInference has published `parakeet-tdt-0.6b-v2-coreml` on HuggingFace but it requires FluidAudio SDK — check licensing and iOS compatibility

**Phase:** Model catalog curation (removing weak models) is safe for v1.1. Parakeet integration is a v1.2 feature that needs its own research spike.

---

### Pitfall 7: Design File Duplication Worsens with Every v1.1 Feature

**What goes wrong:** Six design files are currently duplicated between DictusApp and DictusKeyboard:
- `GlassModifier.swift`
- `DictusColors.swift`
- `AnimatedMicButton.swift`
- `DictusTypography.swift`
- `ProcessingAnimation.swift`
- `BrandWaveform.swift`

Every v1.1 feature that touches design (suggestion bar styling, emoji button, mic button redesign, waveform animation rework, recording overlay redesign) must be implemented in BOTH copies. Forgetting to sync one copy creates visual inconsistencies between the keyboard and the app.

The v1.1 scope adds at least 3 new shared design components (suggestion bar, emoji row, new mic button shape). This will grow the duplicated file count from 6 to potentially 9.

**Why it happens:** DictusKeyboard cannot import DictusApp code (they are separate targets). DictusCore is a Swift Package that cannot contain UIKit/SwiftUI views (it is a pure data/logic layer).

**Prevention:**
1. **Before starting v1.1 features**: Create a `DictusUI` Swift Package (or framework target) that contains all shared design files. Both DictusApp and DictusKeyboard import DictusUI
2. DictusUI should contain: colors, typography, glass modifiers, animations, shared button styles, suggestion bar view
3. DictusUI CAN use SwiftUI — Swift Packages support platform-specific code with `#if canImport(SwiftUI)`
4. Move existing duplicated files into DictusUI first, verify both targets still build, THEN start implementing v1.1 features
5. If creating a new target feels too heavy: at minimum, move shared design into DictusCore with `#if canImport(SwiftUI)` guards. DictusCore already compiles into both targets

**Detection:** Visual differences between app and keyboard (different button radius, wrong color, missing animation). Bug reports like "the mic button looks different in the app vs the keyboard."

**Phase:** Must be done BEFORE any v1.1 design work. It is infrastructure that prevents compounding tech debt.

---

### Pitfall 8: adjustTextPosition(byCharacterOffset:) Behaves Inconsistently Across Apps

**What goes wrong:** The spacebar trackpad uses `textDocumentProxy.adjustTextPosition(byCharacterOffset:)` to move the cursor. This API works reliably in UITextField and UITextView but has inconsistent behavior in:
- **WKWebView** text fields (Safari, web-based apps): cursor may not move, or moves by wrong amount
- **Messages app**: works for single-line messages, behaves erratically in multi-line
- **Some third-party apps** (Slack, Discord): may not respond to cursor adjustment at all
- **Emoji characters**: adjusting by 1 character offset may skip emoji that use multiple Unicode code points (emoji with skin tones, flags, ZWJ sequences are 2-7 code points)

**Prevention:**
1. Map drag distance to character offset conservatively: ~15pt per character (not 10pt). Overshooting is worse than undershooting for UX
2. Add a small delay (50ms) between consecutive `adjustTextPosition` calls — calling it too rapidly causes iOS to batch/drop adjustments
3. Test in: Messages, Notes, Safari, WhatsApp, Slack, Gmail. Each has different UITextInput behavior
4. For emoji-aware movement: read `documentContextBeforeInput` after each adjustment to detect if the cursor actually moved. If it didn't, increase the offset
5. Provide haptic feedback (light impact) per successful cursor step so the user knows the cursor is moving even if they can't see it clearly

**Phase:** Implement during spacebar trackpad feature. Test across at least 5 different host apps before marking complete.

---

## Minor Pitfalls

Issues that cause friction or polish problems.

---

### Pitfall 9: Suggestion Bar Steals Vertical Space from Keys

**What goes wrong:** Adding a suggestion/prediction bar above the keyboard rows reduces the available height for keys. The current keyboard height is precisely calculated in `computeKeyboardHeight()` (4 rows * 46pt + spacing + toolbar + banner). Adding a suggestion bar (~36-44pt) without adjusting the total height compresses the key rows, making them harder to tap accurately. Alternatively, increasing total height makes the keyboard feel oversized and leaves less screen space for the host app content.

**Prevention:**
1. The suggestion bar should be integrated INTO the existing toolbar area (44pt), not added as a separate row. When prediction is active, the toolbar switches from showing globe/mic/layout buttons to showing 3 suggestion pills
2. Alternatively, add the suggestion bar and reduce key height from 46pt to 42pt (still within Apple's recommended minimum of 40pt). Update `KeyMetrics.keyHeight` and `computeKeyboardHeight()` together
3. Update `heightConstraint?.constant` in `viewWillAppear` to include the new height
4. Test on iPhone 12 mini (smallest screen) — the keyboard must not consume more than ~40% of screen height

**Phase:** Design decision needed before implementing text prediction UI.

---

### Pitfall 10: Haptic Feedback on Every Key Press Drains Battery

**What goes wrong:** The v1.1 scope includes "Haptic feedback on all keyboard keys." The Taptic Engine consumes measurable power per actuation. At 60 WPM (average typing speed), that is ~300 key presses per minute, each triggering `UIImpactFeedbackGenerator`. On devices with smaller batteries (iPhone 12 mini, iPhone SE), this can noticeably impact battery life during extended typing sessions.

Additionally, preparing the haptic engine (`prepare()`) before each tap adds ~2ms of latency. If `prepare()` is not called, the first tap of a burst has a noticeable delay (~50ms).

**Prevention:**
1. Use `UIImpactFeedbackGenerator(style: .light)` for key taps — lightest haptic, lowest power
2. Keep one `UIImpactFeedbackGenerator` instance alive and call `prepare()` once when the keyboard appears, not per-tap
3. Make haptics a user-toggleable setting (already exists in v1.0 Settings) — default ON but clearly visible
4. Consider haptics only on special keys (space, return, delete, shift) not every letter — this is what many third-party keyboards do
5. Test battery impact: use Xcode Energy Diagnostics over a 10-minute typing session and compare with/without haptics

**Phase:** Implement alongside the spacebar trackpad (which already needs haptics for cursor steps).

---

### Pitfall 11: Removing Apple Dictation Mic May Confuse Users

**What goes wrong:** The v1.1 scope includes "Remove Apple dictation mic from keyboard." The globe key and Apple dictation mic are system elements that users expect. Removing the dictation mic (if it is a system-provided button) is not directly controllable by the custom keyboard — iOS may still show it in the bottom bar. If Dictus replaces it with its own mic button, users who expect Apple's dictation to work will be confused when it doesn't.

**Prevention:**
1. The Apple dictation mic in the keyboard toolbar is a system element. Custom keyboards can choose NOT to show it by not including `needsInputModeSwitchKey`-related system elements, but iOS may still show its own toolbar below the custom keyboard
2. Focus on making Dictus's mic button prominent and clearly different from Apple's (the pill shape redesign helps)
3. Do not claim to "replace" Apple dictation — position Dictus as an alternative
4. Test: does removing/hiding the system dictation button trigger any App Review concern? Apple allows custom keyboards to have their own mic buttons as long as Full Access is properly handled

**Phase:** UI redesign phase. Test on device to understand what the custom keyboard actually controls vs what iOS shows.

---

## App Review Pitfalls (Keyboard-Specific for v1.1)

---

### Pitfall 12: Full Emoji Picker May Require Justifying Full Access Scope

**Risk:** If the emoji picker sends any data through the App Group (e.g., syncing recent emoji between app and extension), App Review may question whether this data sharing is necessary. Keyboard extensions that share more data than strictly needed through App Groups face scrutiny under Guideline 5.1.1.

**Prevention:** Only share the `recentEmoji: [String]` array via App Group UserDefaults. Do not share emoji usage analytics, frequency data, or typing patterns. Document this in App Review notes.

---

### Pitfall 13: Text Prediction Must Not Log Keystrokes

**Risk:** Implementing text prediction requires reading `documentContextBeforeInput` on every keystroke to generate relevant suggestions. If ANY of this text is logged (even in debug builds), persisted to disk, or sent over the network, Apple will reject under Guideline 5.1.1 (Data Collection). Even storing word frequency data locally could be flagged if the privacy policy does not disclose it.

**Prevention:**
1. Text prediction must be purely in-memory. No keystroke logging, no word frequency persistence, no disk writes of user input
2. If word frequency data is desired (to improve predictions), store it as anonymized frequency counts in App Group, never raw text. Disclose this in the privacy policy
3. In App Review notes, explicitly state: "The keyboard does not log, store, or transmit any keystrokes. Text prediction operates entirely in-memory using the iOS built-in UITextChecker API."
4. Remove ALL `print()` and `DictusLogger` calls that output `documentContextBeforeInput` content before submitting to App Review

**Phase:** Pre-submission checklist item. Audit all logging before every App Store submission.

---

### Pitfall 14: Keyboard Must Still Function Without Full Access for v1.1 Features

**Risk:** With v1.1 adding text prediction, emoji, and trackpad — all of these features must work without Full Access. Only dictation requires Full Access. If the keyboard becomes non-functional or severely degraded without Full Access (e.g., no prediction, no emoji, no trackpad), Apple may reject under Guideline 4.5.1.

**Prevention:**
1. Text prediction via UITextChecker works WITHOUT Full Access (it is a local API)
2. Emoji row works WITHOUT Full Access (emoji are Unicode characters, inserted via `insertText`)
3. Spacebar trackpad works WITHOUT Full Access (`adjustTextPosition` is a local API)
4. Only dictation (mic button) requires Full Access — this is already correctly gated in v1.0
5. Test all v1.1 features with Full Access DISABLED before submission

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Design file consolidation | Breaking existing keyboard/app builds when moving files to shared package | Move one file at a time, build both targets after each move |
| Spacebar trackpad | Gesture conflicts with accent long-press on letter keys | Implement trackpad as keyboard-level state that disables per-key gestures |
| Text prediction | Memory budget exceeded with dictionary data | Start with zero-memory UITextChecker, add frequency list only if needed |
| Emoji button | Emoji glyph cache never released, cumulative memory growth | Limit to recent-emoji row (8-12), never show full picker in extension |
| Cold start auto-return | No public API exists, competitors use undocumented techniques | Research spike first (1-2 days), then decide: solve or optimize cold start speed |
| Model catalog update | Accidentally adding Parakeet scope bloats v1.1 | Limit to curating WhisperKit models; design STT protocol for future engines |
| Mic button redesign | Pill shape increases touch target overlap with adjacent keys | Ensure mic button touch area does not overlap with space or return key |
| Waveform animation rework | Animation frame rate causes memory/CPU pressure in extension | Use `CADisplayLink` or SwiftUI `TimelineView` with 30fps cap, not 60fps |
| Haptics on all keys | Battery drain at high typing speed, latency on first tap | Single prepared `UIImpactFeedbackGenerator`, `.light` style |
| Suggestion bar height | Keyboard becomes too tall, steals screen space from host app | Integrate into existing toolbar row, or reduce key height by 4pt |
| App Review submission | Keystroke logging in debug code left in release build | Pre-submission audit: search for `documentContextBeforeInput` in log statements |

---

## Sources

- [Apple App Extension Programming Guide: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) — HIGH confidence
- [UITextChecker Apple Documentation](https://developer.apple.com/documentation/uikit/uitextchecker) — HIGH confidence
- [adjustTextPosition(byCharacterOffset:) Apple Documentation](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/1618194-adjusttextposition) — HIGH confidence
- [Swift Forums: How do voice dictation keyboard apps return users to previous app?](https://forums.swift.org/t/how-do-voice-dictation-keyboard-apps-like-wispr-flow-return-users-to-the-previous-app-automatically/83988) — MEDIUM confidence
- [High memory usage of Emojis on iOS](https://vinceyuan.github.io/high-memory-usage-of-emojis-on-ios/) — MEDIUM confidence
- [React Native iOS Custom Keyboard memory crashes (GitHub #31910)](https://github.com/facebook/react-native/issues/31910) — MEDIUM confidence
- [Apple Developer Forums: Keyboard Extension Memory Issue](https://developer.apple.com/forums/thread/85478) — MEDIUM confidence
- [FluidInference/parakeet-tdt-0.6b-v2-coreml on HuggingFace](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml) — MEDIUM confidence
- [iOS UITextChecker Autocorrect GitHub implementation](https://github.com/ansonl/ios-uitextchecker-autocorrect) — LOW confidence
- [Wispr Flow Setup Documentation](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) — MEDIUM confidence
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — HIGH confidence
- [Limitations of custom iOS keyboards (Medium)](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694) — LOW confidence
