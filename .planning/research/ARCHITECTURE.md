# Architecture Research: v1.1 Feature Integration

**Domain:** iOS keyboard extension with on-device speech-to-text
**Researched:** 2026-03-07
**Focus:** How v1.1 features integrate with the existing two-process architecture

---

## Existing Architecture (v1.0 Recap)

```
┌──────────────────────────────────────┐     ┌──────────────────────────────────┐
│  DictusApp (Main Process)            │     │  DictusKeyboard (Extension)      │
│                                      │     │  Memory ceiling: ~50MB           │
│  DictationCoordinator (singleton)    │     │                                  │
│  ├── AudioRecorder (WhisperKit live) │     │  KeyboardViewController          │
│  ├── TranscriptionService            │     │  ├── KeyboardRootView            │
│  └── ModelManager                    │     │  │   ├── ToolbarView (mic btn)   │
│                                      │     │  │   ├── KeyboardView (4 rows)   │
│  WhisperKit loaded here (~50-200MB)  │     │  │   └── RecordingOverlay        │
│  AVAudioEngine kept warm             │     │  └── KeyboardState (observer)    │
│                                      │     │                                  │
└──────────┬───────────────────────────┘     └──────────┬───────────────────────┘
           │                                            │
           │  Darwin Notifications (ping-only)          │
           │  App Group UserDefaults (data payload)     │
           ◄────────────────────────────────────────────►
```

**IPC Pattern:** Keyboard writes flags to App Group, posts Darwin notification. App reads flags, acts, writes results back. Keyboard reads results on status change notification.

**Key Existing Components:**
- `KeyDefinition` / `KeyboardLayout` — data model for key rendering
- `KeyButton` with `DragGesture` — handles tap + long-press + accent popup
- `BrandWaveform` — 30-bar energy visualization (duplicated in both targets)
- `AccentedCharacters` — static mappings for French AZERTY long-press accents
- `DictusCore` — shared SPM package (App Group, Darwin notifications, models, preferences)

---

## Feature 1: Text Prediction Engine

### Decision: Runs in the keyboard extension

**Rationale:** Text prediction must respond in <50ms to feel native. Round-tripping through Darwin notifications + App Group adds 100-200ms latency minimum (write + synchronize + notify + read). This latency is unacceptable for real-time typing suggestions.

**Confidence:** HIGH (based on how UITextChecker works and extension architecture constraints)

### Implementation: UITextChecker (built-in, zero memory cost)

Use Apple's `UITextChecker` which is available in keyboard extensions and supports French (`"fr"` language code). This is the same engine backing iOS autocorrect.

**Capabilities:**
- `completions(forPartialWordRange:in:language:)` — word completions for partially-typed words
- `rangeOfMisspelledWord(in:range:startingAt:wrap:language:)` — spell checking
- `guesses(forWordRange:in:language:)` — correction suggestions for misspelled words

**Supplementary:** `UIInputViewController.requestSupplementaryLexicon()` provides device-level shortcuts and contacts, which should be merged with UITextChecker results.

**Memory impact:** Near-zero. UITextChecker uses the system dictionary already loaded by iOS. No additional model files needed. This is critical given the ~50MB constraint.

### Architecture

```
┌─ DictusKeyboard ──────────────────────────────────────────────┐
│                                                               │
│  KeyboardRootView                                             │
│  ├── SuggestionBarView  [NEW]                                 │
│  │   └── displays 3 suggestions: [left] [center/bold] [right]│
│  ├── ToolbarView (existing, moves below suggestion bar)       │
│  ├── KeyboardView (existing)                                  │
│  └── RecordingOverlay (existing)                              │
│                                                               │
│  TextPredictionService  [NEW - in DictusKeyboard target]      │
│  ├── UITextChecker (French + English)                         │
│  ├── UILexicon (device shortcuts/contacts)                    │
│  ├── context: reads textDocumentProxy.documentContextBeforeInput │
│  └── outputs: [AutocompleteSuggestion] (max 3)               │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### New Components

| Component | Target | Responsibility |
|-----------|--------|---------------|
| `TextPredictionService` | DictusKeyboard | Computes suggestions from UITextChecker + UILexicon |
| `SuggestionBarView` | DictusKeyboard | Renders 3-slot suggestion bar above keyboard |
| `AutocompleteSuggestion` | DictusCore | Data model (word, isAutocorrect, isFromLexicon) |

### Data Flow

```
User types character
  → KeyboardView calls insertCharacter()
  → textDocumentProxy.insertText(char)
  → textDidChange fires on KeyboardViewController
  → TextPredictionService.updateContext(proxy.documentContextBeforeInput)
  → UITextChecker.completions() + guesses()
  → SuggestionBarView updates with 3 suggestions
  → User taps suggestion
  → Delete partial word + insert complete word
```

### Integration Points (Modified Existing Code)

1. **KeyboardViewController.textDidChange()** — Currently empty (`// Future: react to cursor position changes`). Add call to prediction service.
2. **KeyboardRootView** — Insert `SuggestionBarView` above `ToolbarView`.
3. **KeyboardViewController.computeKeyboardHeight()** — Add suggestion bar height (~36pt).

### Anti-Pattern: Do NOT Use LLM/ML-Based Prediction

KeyboardKit 10.3 added next-word prediction via Apple Foundation Models (iOS 26.1+, iPhone 15 Pro+). This is too restrictive for Dictus (minimum target iOS 16.0, iPhone 12). Also, Foundation Models runs in a separate process with unpredictable latency.

UITextChecker is the correct choice: universal availability, zero memory cost, French support built-in.

---

## Feature 2: Spacebar Trackpad

### API: `textDocumentProxy.adjustTextPosition(byCharacterOffset:)`

This is the official Apple API for cursor movement from keyboard extensions. It accepts positive (forward) or negative (backward) integer offsets.

**Confidence:** HIGH (official Apple API, documented, used by all major third-party keyboards)

### Architecture: Gesture on SpecialKeyButton for Space

The spacebar trackpad requires converting the existing space key from a simple tap handler to a dual-mode gesture recognizer:

```
Spacebar interaction states:
  IDLE → tap (< 400ms, no significant horizontal movement) → insert space
  IDLE → long-press (>= 400ms) → TRACKPAD MODE
  TRACKPAD MODE → horizontal drag → adjustTextPosition(byCharacterOffset:)
  TRACKPAD MODE → release → return to IDLE
```

### New Components

| Component | Target | Responsibility |
|-----------|--------|---------------|
| `SpacebarTrackpadModifier` | DictusKeyboard | ViewModifier handling long-press + drag gesture on spacebar |

### Integration Points (Modified Existing Code)

1. **KeyboardView.onSpace closure** — Replace simple `insertText(" ")` with stateful gesture. The spacebar is rendered via `KeyRow` which calls `onSpace`. Need to intercept the space key in `KeyRow` and apply the trackpad gesture modifier.
2. **KeyRow** — Detect `.space` key type and use `SpacebarTrackpadModifier` instead of the standard tap handler.

### Implementation Detail

The DragGesture pattern already exists in `KeyButton` for accent popup detection. Reuse the same approach:

```swift
// Pseudo-code for SpacebarTrackpadModifier
DragGesture(minimumDistance: 0)
    .onChanged { value in
        if !isActive {
            isActive = true
            startTimer() // 400ms threshold
        }
        if isTrackpadMode {
            // Calculate character offset from horizontal delta
            let dx = value.translation.width
            let charOffset = Int(dx / sensitivityFactor) - lastReportedOffset
            if charOffset != 0 {
                proxy.adjustTextPosition(byCharacterOffset: charOffset)
                lastReportedOffset += charOffset
                HapticFeedback.cursorMoved() // light tick per character
            }
        }
    }
    .onEnded { _ in
        if !isTrackpadMode {
            proxy.insertText(" ") // Normal space tap
        }
        reset()
    }
```

**Sensitivity factor:** ~12pt per character is a good starting point (Apple's trackpad mode uses approximately this density). Fine-tune during implementation.

### textDocumentProxy Quirk

`adjustTextPosition(byCharacterOffset:)` does NOT trigger `textDidChange`. The `documentContextBeforeInput` and `documentContextAfterInput` properties update lazily. After cursor movement, you may need to call `adjustTextPosition(byCharacterOffset: 0)` or read the context to force a refresh if prediction needs to update. Test this during implementation.

---

## Feature 3: Adaptive Accent Key

### Design: Context-Aware Key Next to N

The key should display either apostrophe (') or the most likely accented character based on the preceding text context. This is a keyboard extension-only feature, no IPC needed.

### State Machine

```
┌──────────────────────────────────────────────────────────────┐
│  AdaptiveAccentKeyResolver                                   │
│                                                              │
│  Input: documentContextBeforeInput (last 1-3 chars)          │
│  Output: (primaryLabel: String, primaryOutput: String)       │
│                                                              │
│  Rules (evaluated in order):                                 │
│  1. After "l'"/"d'"/"j'"/"n'"/"s'"/"c'" → show apostrophe   │
│  2. After consonant at word boundary   → show apostrophe     │
│  3. After vowel "e"                    → show "e" (accent)   │
│  4. After vowel "a"                    → show "a" (accent)   │
│  5. Default (empty/start of sentence)  → show apostrophe     │
│                                                              │
│  Long-press: always shows full accent popup for the          │
│  displayed character (reuses AccentedCharacters mappings)     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### New Components

| Component | Target | Responsibility |
|-----------|--------|---------------|
| `AdaptiveAccentKeyResolver` | DictusCore | Stateless function: context string in, key config out |
| New `KeyType.adaptiveAccent` | DictusKeyboard | New key type in KeyDefinition |

### Integration Points (Modified Existing Code)

1. **KeyDefinition.KeyType** — Add `.adaptiveAccent` case.
2. **KeyboardLayoutData** — Replace the key next to N in AZERTY layout with the adaptive accent key.
3. **KeyRow** — Handle `.adaptiveAccent` type: query resolver on each render, display dynamic label, long-press shows accent popup.
4. **KeyboardView** — Pass `documentContextBeforeInput` or trigger resolver update on `textDidChange`.

### Complexity Assessment

LOW. This is a pure function (string in, key config out) with simple French grammar rules. No ML, no IPC, no memory concerns. The most complex part is determining the correct rule set through user testing.

---

## Feature 4: Cold Start Auto-Return

### Verdict: NO reliable public API exists

**Confidence:** HIGH (verified across Apple Developer Forums, Swift Forums, and competitor analysis)

### What Happens on Cold Start

```
User taps mic in keyboard
  → App not running (killed by iOS)
  → Keyboard opens dictus://dictate URL via extensionContext.open()
  → iOS launches DictusApp in foreground
  → DictusApp: configureAudioSession() + ensureWhisperKitReady() + startRecording()
  → User sees DictusApp briefly
  → USER MUST MANUALLY TAP "< Back" in status bar to return to keyboard
  → Recording continues in background (audio background mode)
```

The problem: step 6 requires manual user action. Competitors like Wispr Flow handle this automatically for most apps.

### What Wispr Flow Does (Reverse-Engineered)

Based on research, Wispr Flow uses a **"Flow Session" model**: user explicitly starts a session in the app first, then returns to their work. The keyboard mic button works seamlessly only AFTER the initial session start. On true cold start, Wispr Flow also opens its main app -- but it auto-returns. Their FAQ states "Not all apps allow the app to reopen," suggesting they use a technique that is app-dependent.

Likely mechanism: **private API or undocumented behavior** that Apple tolerates for well-known apps. The Swift Forums thread confirms no public API exists.

### Possible Approaches (Ranked by Feasibility)

| Approach | Feasibility | Risk |
|----------|------------|------|
| 1. Minimize cold start time (pre-warm faster) | HIGH | None |
| 2. Keep app alive longer (background audio + silent buffer) | HIGH | Battery |
| 3. Local notification with deeplink back | MEDIUM | UX friction |
| 4. Clipboard + pasteboard URL trick | LOW | Unreliable, bad UX |
| 5. Private API (_hostBundleID + openURL) | LOW | App Store rejection |

### Recommended Strategy: Reduce Cold Starts, Minimize Warm-Up

Instead of solving auto-return (unsolvable with public APIs), make cold starts:
1. **Rare:** Keep the audio engine alive as long as possible. The current `UIBackgroundModes:audio` with a warm engine already does this. Consider adding a silent audio buffer playback to extend background lifetime.
2. **Fast:** Current cold start takes 4-5s (WhisperKit init). Pre-download and cache the compiled Core ML model to reduce init to <2s.
3. **Graceful:** When the app opens for cold start, show a minimal "Starting..." overlay and auto-start recording immediately. The status bar "< Back to [App]" is visible -- guide users with a brief animation pointing to it.

### New Components

| Component | Target | Responsibility |
|-----------|--------|---------------|
| `ColdStartView` | DictusApp | Minimal overlay shown during cold-start dictation launch |
| Background keepalive logic | DictusApp | Silent audio playback to prevent iOS from killing the app |

### Integration Points (Modified Existing Code)

1. **DictationCoordinator.init()** — Add background keepalive after warm-up completes.
2. **DictusApp** — Route `dictus://dictate` URL to show `ColdStartView` instead of full app UI.
3. **ContentView** — Conditional rendering based on launch context.

---

## Feature 5: Model Catalog with Non-Whisper Models (Parakeet)

### Key Finding: Parakeet v3 Supports French via Core ML

**Parakeet-TDT-0.6B-v3** (not v2 -- v2 is English-only) supports 25 European languages including French. Core ML conversions exist:
- `FluidInference/parakeet-tdt-0.6b-v3-coreml` — Requires iOS 17+
- `NexaAI/parakeet-tdt-0.6b-v3-ane` — Apple Neural Engine optimized

**Confidence:** MEDIUM. Core ML conversions exist on HuggingFace but are third-party, not official NVIDIA. Runtime behavior on iPhone (memory, latency) is undocumented for mobile.

### Critical Constraint: Parakeet Uses a Different Pipeline

WhisperKit provides a complete, opinionated pipeline: audio capture, VAD, inference, decoding. Parakeet uses NeMo's FastConformer encoder + Token-and-Duration Transducer (TDT) decoder -- an entirely different architecture from Whisper's encoder-decoder.

**This means Parakeet CANNOT use WhisperKit's pipeline.** It needs its own inference wrapper.

### Architecture: Model Protocol Abstraction

```
┌─ DictusApp ──────────────────────────────────────────────────┐
│                                                              │
│  TranscriptionService (existing)                             │
│  └── SpeechModel protocol  [NEW]                             │
│      ├── WhisperKitModel (existing behavior, wraps WhisperKit)│
│      └── ParakeetModel  [NEW] (wraps Core ML directly)       │
│                                                              │
│  protocol SpeechModel {                                      │
│      var id: String { get }                                  │
│      var displayName: String { get }                         │
│      var memoryFootprint: Int { get } // MB                  │
│      func load() async throws                                │
│      func transcribe(_ samples: [Float]) async throws -> String │
│      func unload()                                           │
│  }                                                           │
│                                                              │
│  ModelManager (existing)                                     │
│  ├── Downloads/manages models from catalog                   │
│  └── ModelCatalog  [NEW]                                     │
│      ├── WhisperKit models (existing HuggingFace source)     │
│      └── Parakeet models (new HuggingFace source)            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### New Components

| Component | Target | Responsibility |
|-----------|--------|---------------|
| `SpeechModel` protocol | DictusCore | Abstraction over different STT engines |
| `WhisperKitModel` | DictusApp | Wraps existing WhisperKit usage behind protocol |
| `ParakeetModel` | DictusApp | Loads Core ML Parakeet model, runs inference |
| `ModelCatalog` | DictusCore | Registry of available models with metadata |
| `ParakeetInferenceEngine` | DictusApp | Core ML inference for Parakeet's FastConformer + TDT |

### Integration Points (Modified Existing Code)

1. **TranscriptionService** — Replace direct WhisperKit dependency with `SpeechModel` protocol.
2. **DictationCoordinator** — Replace `whisperKit: WhisperKit?` with `activeModel: SpeechModel?`.
3. **AudioRecorder** — Currently tightly coupled to WhisperKit (`prepare(whisperKit:)`). Need to decouple: AudioRecorder handles raw audio capture, model handles transcription.
4. **ModelManager** — Extend to support downloading from multiple sources (WhisperKit HuggingFace repo + Parakeet Core ML repos).
5. **ModelManagerView** — UI updates to show model type (Whisper vs Parakeet), size, language support.

### Memory Consideration

Parakeet-TDT-0.6B has 600M parameters. Even with quantization, the Core ML model will likely be 300-600MB on disk and require significant RAM. This is comparable to Whisper medium/large models. It runs in DictusApp (not the extension), so the 50MB keyboard limit is not a concern. However, older iPhones (A14/A15) may struggle with a 600M parameter model.

### Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Core ML conversion quality unknown | HIGH | Test accuracy before integrating |
| Parakeet requires iOS 17+ | MEDIUM | Keep WhisperKit as default, Parakeet as optional |
| Different audio preprocessing | MEDIUM | Parakeet expects 16kHz mono Float32 -- same as WhisperKit |
| No streaming support | LOW | Dictus uses batch mode anyway |

### Recommendation

Phase this carefully:
1. **First:** Abstract the existing WhisperKit code behind `SpeechModel` protocol (no behavior change).
2. **Second:** Build `ParakeetModel` wrapper + test accuracy on French audio.
3. **Third:** If accuracy is competitive, add to model catalog UI.

Do NOT remove WhisperKit models. Keep them as the default, battle-tested option. Parakeet is an experimental addition.

---

## Feature 6: Waveform Animation Rework

### Current Implementation

`BrandWaveform` uses:
- `GeometryReader` for adaptive bar width
- `ForEach` over 30 bars with `RoundedRectangle`
- `.animation(.easeOut(duration: 0.08))` implicit animation
- Data updates at ~5Hz from App Group (throttled by DictationCoordinator)

**Problem:** The 5Hz update rate + 0.08s ease-out creates choppy, discontinuous movement. The bars "jump" between positions rather than flowing smoothly.

### Recommended Approach: TimelineView + Canvas

**Why not Metal/CADisplayLink:**
- Metal shaders via `.drawingGroup()` are overkill for 30 rectangles
- CADisplayLink requires UIKit bridging, breaks pure SwiftUI
- TimelineView + Canvas is the SwiftUI-native solution for frame-synchronized animations

**Why TimelineView + Canvas:**
- Canvas uses immediate-mode drawing (no view diffing overhead per bar)
- TimelineView with `.animation` schedule drives 60fps updates
- Interpolation between 5Hz data points happens client-side for smooth motion
- Available since iOS 15 (within our iOS 16 target)

**Confidence:** HIGH (well-documented SwiftUI pattern, multiple production examples)

### Architecture

```
┌─ BrandWaveform (reworked) ────────────────────────────────────┐
│                                                               │
│  TimelineView(.animation) { timeline in                       │
│      Canvas { context, size in                                │
│          // Interpolate between lastEnergy and currentEnergy  │
│          // based on timeline.date                            │
│          for i in 0..<barCount {                              │
│              let interpolated = lerp(prev[i], curr[i], t)     │
│              context.fill(barPath(i, interpolated), with: ...) │
│          }                                                    │
│      }                                                        │
│  }                                                            │
│                                                               │
│  WaveformInterpolator  [NEW]                                  │
│  ├── Stores last 2 energy snapshots with timestamps           │
│  ├── lerp(prev, curr, fraction) → smoothed energy per bar     │
│  └── Applies spring/ease curve for organic feel               │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### New Components

| Component | Target | Responsibility |
|-----------|--------|---------------|
| `WaveformInterpolator` | DictusCore (or duplicated) | Smooth interpolation between 5Hz data snapshots |

### Integration Points (Modified Existing Code)

1. **BrandWaveform** — Complete rewrite using TimelineView + Canvas. Both copies (DictusApp + DictusKeyboard) must be updated.
2. **No IPC changes needed** — The 5Hz App Group update rate stays the same. Smoothing happens client-side.

### Design Consideration: Move BrandWaveform to DictusCore?

Currently BrandWaveform is duplicated (DictusApp/Design/ and DictusKeyboard/Design/) because keyboard extensions cannot import the app target. However, DictusCore is a shared SPM package that both targets import.

**Problem:** DictusCore currently has no SwiftUI views -- it's pure Foundation/data models. Adding SwiftUI views would require adding SwiftUI as a dependency and broadening its scope.

**Recommendation:** Keep the duplication for now. The waveform is a single file. Moving it to DictusCore to save one file of duplication isn't worth the architectural precedent of mixing UI into the data layer. If more design files accumulate, consider a `DictusUI` shared SPM package in the future.

---

## Component Summary: New vs Modified

### New Files to Create

| File | Target | Purpose |
|------|--------|---------|
| `TextPredictionService.swift` | DictusKeyboard | UITextChecker + UILexicon wrapper |
| `SuggestionBarView.swift` | DictusKeyboard | 3-slot suggestion bar UI |
| `AutocompleteSuggestion.swift` | DictusCore | Suggestion data model |
| `SpacebarTrackpadModifier.swift` | DictusKeyboard | Long-press trackpad gesture |
| `AdaptiveAccentKeyResolver.swift` | DictusCore | Context-based accent key logic |
| `ColdStartView.swift` | DictusApp | Minimal cold-start dictation UI |
| `SpeechModel.swift` (protocol) | DictusCore | Model abstraction protocol |
| `WhisperKitModel.swift` | DictusApp | WhisperKit behind SpeechModel |
| `ParakeetModel.swift` | DictusApp | Parakeet Core ML inference |
| `ParakeetInferenceEngine.swift` | DictusApp | Core ML loading + inference for Parakeet |
| `ModelCatalog.swift` | DictusCore | Available models registry |
| `WaveformInterpolator.swift` | Both targets (or DictusCore) | Smooth energy interpolation |

### Existing Files to Modify

| File | Change |
|------|--------|
| `KeyboardViewController.swift` | Add textDidChange() prediction trigger, update height |
| `KeyboardRootView.swift` | Insert SuggestionBarView, update totalContentHeight |
| `KeyDefinition.swift` | Add `.adaptiveAccent` KeyType case |
| `KeyboardLayoutData.swift` | Replace key next to N with adaptive accent |
| `KeyRow.swift` | Handle `.adaptiveAccent` and spacebar trackpad |
| `KeyboardView.swift` | Pass context to adaptive key resolver |
| `BrandWaveform.swift` (both copies) | Rewrite with TimelineView + Canvas |
| `TranscriptionService.swift` | Use SpeechModel protocol |
| `DictationCoordinator.swift` | Use SpeechModel protocol, add cold start logic |
| `AudioRecorder.swift` | Decouple from WhisperKit direct dependency |
| `ModelManager.swift` | Support multiple model sources |
| `ModelManagerView.swift` | Show model type, Parakeet option |
| `DictusApp.swift` | Cold start URL handling |

---

## Suggested Build Order

Based on dependency analysis and risk:

```
Phase 1: Keyboard Polish (no IPC changes, low risk)
  1. Spacebar trackpad — self-contained gesture modifier
  2. Adaptive accent key — pure function, simple integration
  3. Haptic feedback on all keys — trivial addition
  4. Remove duplicate globe, add emoji button — layout change only

Phase 2: Suggestion Bar (moderate complexity, extension-only)
  5. TextPredictionService + SuggestionBarView
  6. Wire textDidChange → prediction → UI update

Phase 3: Waveform Rework (both targets, visual-only)
  7. WaveformInterpolator + BrandWaveform rewrite

Phase 4: Cold Start UX (app-side, user-facing)
  8. ColdStartView + background keepalive
  9. Faster WhisperKit init (pre-compiled model caching)

Phase 5: Model Abstraction (high risk, foundational refactor)
  10. SpeechModel protocol + WhisperKitModel wrapper (no behavior change)
  11. AudioRecorder decoupling from WhisperKit
  12. ParakeetModel + ParakeetInferenceEngine
  13. ModelCatalog + UI updates
```

**Rationale:**
- Phases 1-2 are keyboard-only, no IPC changes, lowest risk of regression.
- Phase 3 is visual-only, can be tested independently.
- Phase 4 improves UX without changing core pipeline.
- Phase 5 is the riskiest (refactoring the transcription pipeline) and should come last, after all simpler features are stable.

---

## Scalability Considerations

| Concern | Current (v1.0) | v1.1 Impact | Future (v2+) |
|---------|----------------|-------------|---------------|
| Extension memory | ~15MB baseline | +2-3MB for prediction service | Stay under 30MB to leave headroom |
| IPC latency | 100-200ms | No change (prediction is local) | Consider XPC for streaming |
| Model loading | 4-5s cold start | Target <2s with caching | Lazy model segments |
| Keyboard height | 4 rows + toolbar | +36pt suggestion bar | Configurable height |
| Code duplication | 6 files shared | +1 (WaveformInterpolator) | Consider DictusUI package |

---

## Sources

- [UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) — Apple Developer Documentation
- [adjustTextPosition(byCharacterOffset:)](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/1618194-adjusttextposition) — Apple Developer Documentation
- [UITextChecker](https://developer.apple.com/documentation/uikit/uitextchecker) — Apple Developer Documentation
- [Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards) — Apple Developer Documentation
- [Custom Keyboard Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) — Apple Archive
- [TimelineView and Canvas](https://commitstudiogs.medium.com/advanced-animations-in-swiftui-using-timelineview-and-canvas-cf71fbcb2f11) — Commit Studio
- [Swift Forums: Auto-return from keyboard extension](https://forums.swift.org/t/how-do-voice-dictation-keyboard-apps-like-wispr-flow-return-users-to-the-previous-app-automatically/83988) — No public API exists
- [Wispr Flow Setup](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) — Flow Session model
- [Parakeet-TDT-0.6B-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — Multilingual, includes French
- [Parakeet-TDT-0.6B-v3 Core ML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) — iOS 17+ Core ML conversion
- [Parakeet-TDT-0.6B-v3 ANE](https://huggingface.co/NexaAI/parakeet-tdt-0.6b-v3-ane) — Apple Neural Engine optimized
- [Parakeet v2 is English-only](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) — v3 needed for French
- [KeyboardKit Autocomplete](https://keyboardkit.com/features/autocomplete) — Reference implementation
- [UITextChecker French support](https://nshipster.com/uitextchecker/) — NSHipster
- [ios-uitextchecker-autocorrect](https://github.com/ansonl/ios-uitextchecker-autocorrect) — Open source implementation
