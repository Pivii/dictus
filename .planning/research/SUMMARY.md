# Project Research Summary

**Project:** Dictus v1.1 -- UX & Keyboard Parity
**Domain:** iOS keyboard extension -- French speech-to-text with offline dictation
**Researched:** 2026-03-07
**Confidence:** MEDIUM-HIGH

## Executive Summary

Dictus v1.1 is a UX and keyboard parity milestone for an existing iOS custom keyboard with offline French speech-to-text (WhisperKit). The v1.0 MVP ships a functional AZERTY keyboard with recording overlay and two-process architecture (keyboard extension + main app via Darwin notifications). Research reveals that the biggest gaps are missing Apple keyboard parity features -- spacebar trackpad, adaptive apostrophe key, and haptic feedback on all keys -- that make users perceive the keyboard as incomplete. These are well-understood, low-risk features using documented Apple APIs (`adjustTextPosition`, `UITextChecker`, `textDocumentProxy`). They should ship first because they have the highest user impact per engineering hour.

The recommended approach is to prioritize keyboard-only changes (no IPC modifications) before touching the transcription pipeline or app-side logic. The existing two-process architecture is sound and does not need modification for most v1.1 features. Text prediction runs entirely in the keyboard extension using Apple's zero-memory-cost `UITextChecker`, and the spacebar trackpad uses the official `adjustTextPosition(byCharacterOffset:)` API. The only new external dependency is a French n-gram SQLite database (~10-15MB) for word prediction re-ranking, and optionally FluidAudio SDK for Parakeet v3 model support. A prerequisite infrastructure task -- consolidating 6+ duplicated design files into a shared `DictusUI` package -- should precede all feature work to prevent compounding tech debt.

The two highest-risk items are cold start auto-return (no public API exists; competitors use unknown techniques) and Parakeet v3 model integration (entirely different STT pipeline from WhisperKit). Research strongly recommends deferring Parakeet integration to v1.2 and limiting model work to curating the existing WhisperKit catalog. For cold start, the pragmatic path is minimizing cold start frequency (keep-alive via background audio) and optimizing cold start speed, rather than chasing an auto-return solution that may require private APIs.

## Key Findings

### Recommended Stack

No major new dependencies are needed. The existing stack (Swift 5.9+, SwiftUI, WhisperKit, App Group) is unchanged. All keyboard parity features use built-in iOS APIs.

**Core technologies (new for v1.1):**
- **UITextChecker** (system): French spell-check and word completion -- zero memory cost, available in keyboard extensions
- **UILexicon** (system): Supplementary user vocabulary from contacts and shortcuts -- free data source via `requestSupplementaryLexicon()`
- **French n-gram SQLite DB** (custom-built, ~10-15MB): Word prediction frequency re-ranking -- queried via SQLite, not loaded into memory to respect 50MB extension limit
- **TimelineView + Canvas** (SwiftUI, iOS 15+): Waveform animation rewrite for smooth 60fps interpolation between 5Hz data updates

**Explicitly not adding:** KeyboardKit Pro (commercial, contradicts MIT), Presage (GPL, unmaintained), any server-based autocorrect (contradicts offline-first), Apple Foundation Models (requires iPhone 15 Pro+, iOS 26.1+).

**Optional (defer to v1.2):** FluidAudio SDK for Parakeet v3 CoreML inference. Requires iOS 17+, 2.5GB model, entirely different STT pipeline. Not ready for v1.1.

### Expected Features

**Must have (table stakes):**
- **Spacebar trackpad** -- every iOS user expects long-press spacebar for cursor movement (since iOS 12)
- **Adaptive apostrophe key** -- French users type apostrophes 5-10 times per paragraph; currently requires 3 taps via layer switch
- **Haptic feedback on all keys** -- Apple's keyboard has this since iOS 16; absence feels broken
- **Bottom row reorganization** -- replace filtered mic slot with emoji button, match Apple's layout

**Should have (differentiators):**
- **Text prediction / suggestion bar** -- bridges gap between "dictation keyboard" and "full replacement keyboard"
- **Pill-shaped mic button** -- modern iOS design language, larger tap target
- **Waveform animation rework** -- smoother, premium feel via TimelineView + Canvas
- **Cold start UX improvement** -- minimize cold starts, faster warm-up, clear "tap Back" guidance

**Defer (v1.2+):**
- Built-in emoji picker (use `advanceToNextInputMode()` to cycle to system emoji keyboard)
- Next-word prediction (requires custom ML model beyond UITextChecker capabilities)
- Swipe typing (years of engineering from Gboard/SwiftKey, not in scope)
- Keyboard themes / custom colors
- Parakeet v3 model integration (different pipeline, needs its own research spike)
- Auto-capitalize after punctuation (needs French-specific rules)

### Architecture Approach

The two-process architecture (keyboard extension + main app via Darwin notifications + App Group) remains unchanged. All keyboard parity features run entirely in the extension with zero IPC overhead. Text prediction must run locally in the extension (<50ms response) using UITextChecker. The key architectural addition is a `SpeechModel` protocol abstraction over the transcription pipeline, designed now but only fully used when Parakeet is added in v1.2.

**Major new components:**
1. **TextPredictionService** (DictusKeyboard) -- wraps UITextChecker + UILexicon, computes suggestions on each keystroke via `textDidChange()`
2. **SuggestionBarView** (DictusKeyboard) -- 3-slot horizontal bar above keyboard rows
3. **SpacebarTrackpadModifier** (DictusKeyboard) -- ViewModifier handling long-press + drag gesture on spacebar
4. **AdaptiveAccentKeyResolver** (DictusCore) -- stateless context function: preceding text in, key config out
5. **ColdStartView** (DictusApp) -- minimal overlay for cold-start dictation launch
6. **SpeechModel protocol** (DictusCore) -- abstraction for future multi-engine support
7. **WaveformInterpolator** (both targets) -- smooth interpolation between 5Hz energy data

### Critical Pitfalls

1. **Spacebar trackpad gesture conflicts with accent popup system** -- Both use `DragGesture(minimumDistance: 0)` with timer-based detection. Trackpad mode must be a keyboard-level state that overlays a transparent gesture capture and disables all per-key gestures. Must be implemented FIRST because it changes the gesture architecture.

2. **Text prediction blows 50MB memory budget** -- n-gram dictionaries expand 3-5x from disk to memory. Start with UITextChecker only (zero memory cost). Hard budget: prediction system must use <5MB resident memory. Profile on iPhone 12 before adding any dictionary data.

3. **Emoji glyph cache is unrecoverable** -- iOS caches emoji bitmaps permanently for the process lifetime. Never show more than 50-80 unique emoji in the extension. Use a recent-emoji row (8-12 items), not a full category picker.

4. **Cold start auto-return has no public API** -- Apple intentionally restricts programmatic app switching. Wispr Flow's technique is undocumented. Best strategy: minimize cold starts via background audio keep-alive, optimize cold start to <2s, show clear "tap Back" guidance.

5. **Design file duplication compounds with every feature** -- 6 files already duplicated between DictusApp and DictusKeyboard. Create a shared `DictusUI` Swift Package BEFORE starting feature work, or use `#if canImport(SwiftUI)` in DictusCore.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 0: Infrastructure -- Design File Consolidation
**Rationale:** 6+ duplicated design files will grow to 9+ with v1.1 features. Every feature that touches design must be implemented twice without consolidation. This is a force-multiplier that prevents compounding tech debt.
**Delivers:** Shared `DictusUI` Swift Package (or DictusCore with SwiftUI views) imported by both targets
**Addresses:** Pitfall 7 (design file duplication)
**Avoids:** Visual inconsistencies between app and keyboard, doubled implementation time for design changes

### Phase 1: Keyboard Parity -- Core UX Gaps
**Rationale:** These are the highest-impact, lowest-risk features. All use documented Apple APIs, run entirely in the keyboard extension, require no IPC changes. Spacebar trackpad must come first because it changes the gesture architecture for all keys.
**Delivers:** Keyboard that matches Apple's native AZERTY in core interactions
**Addresses:** Spacebar trackpad, adaptive apostrophe key, haptic feedback on all keys, bottom row reorganization
**Avoids:** Pitfall 1 (gesture conflicts -- solve by implementing trackpad as keyboard-level state first), Pitfall 10 (haptic battery drain -- use single prepared generator with `.light` style)

### Phase 2: Visual Polish -- Buttons and Waveform
**Rationale:** Pure visual improvements with no architectural risk. Can be tested independently. Waveform rewrite uses TimelineView + Canvas (available since iOS 15).
**Delivers:** Premium visual feel -- pill-shaped mic button, smooth waveform animation
**Addresses:** Pill-shaped button design, waveform animation rework
**Avoids:** Pitfall 9 (suggestion bar height) -- design decision about toolbar integration should be resolved here before Phase 3

### Phase 3: Text Prediction -- Suggestion Bar
**Rationale:** Highest-complexity keyboard feature. Depends on Phase 1 (bottom row must be finalized) and Phase 2 (toolbar/suggestion bar height decision). Memory-sensitive -- must be profiled on real devices.
**Delivers:** 3-slot suggestion bar with French spell-check and word completion
**Uses:** UITextChecker (system), UILexicon, optional French n-gram SQLite DB
**Implements:** TextPredictionService, SuggestionBarView, AutocompleteSuggestion model
**Avoids:** Pitfall 2 (memory budget -- start with UITextChecker only), Pitfall 5 (poor French suggestions -- supplement with frequency re-ranking), Pitfall 13 (keystroke logging -- in-memory only, audit before submission)

### Phase 4: Cold Start UX
**Rationale:** App-side changes, user-facing UX improvement. Independent of keyboard features. Research spike at start to determine if auto-return is achievable; if not, optimize cold start speed and add clear user guidance.
**Delivers:** Faster cold start (<2s), minimal ColdStartView overlay, extended background keep-alive
**Addresses:** Cold start auto-return (best-effort), background session keep-alive
**Avoids:** Pitfall 4 (no public API -- accept limitation, optimize speed instead)

### Phase 5: Model Catalog Curation
**Rationale:** Riskiest phase -- touches the transcription pipeline. Should come last after all simpler features are stable. Limit scope to curating WhisperKit models (remove English-only models) and designing the SpeechModel protocol for future Parakeet integration.
**Delivers:** Cleaned model catalog, SpeechModel protocol abstraction (no behavior change), WhisperKitModel wrapper
**Uses:** Existing WhisperKit, no new dependencies
**Implements:** SpeechModel protocol, WhisperKitModel, ModelCatalog registry
**Avoids:** Pitfall 6 (Parakeet scope bloat -- defer actual integration to v1.2)

### Phase Ordering Rationale

- **Phase 0 before everything** because every subsequent phase creates design components that would be duplicated without consolidation
- **Phase 1 before Phase 3** because the suggestion bar depends on finalized keyboard layout and the trackpad gesture changes the architecture for all keys
- **Phase 2 before Phase 3** because the toolbar/suggestion bar height trade-off must be resolved before building the suggestion bar UI
- **Phase 4 is independent** and can run in parallel with Phases 2-3 if resources allow, since it only touches app-side code
- **Phase 5 last** because it refactors the transcription pipeline (AudioRecorder, DictationCoordinator, TranscriptionService) which is the riskiest change

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Text Prediction):** UITextChecker French quality is unknown in production. Needs prototyping to evaluate whether suggestions are usable or need heavy supplementation. Memory profiling on iPhone 12 is mandatory.
- **Phase 4 (Cold Start UX):** 1-2 day research spike needed at phase start. Reverse-engineer Wispr Flow's cold start behavior using Console.app. Investigate PiP as potential workaround.
- **Phase 5 (Model Catalog):** If Parakeet v3 integration is pulled into scope, needs dedicated research on FluidAudio SDK iOS compatibility, Core ML conversion quality, and French accuracy benchmarks.

Phases with standard patterns (skip research-phase):
- **Phase 0 (Infrastructure):** Well-documented Swift Package creation pattern
- **Phase 1 (Keyboard Parity):** All APIs are official Apple documentation with multiple reference implementations
- **Phase 2 (Visual Polish):** Standard SwiftUI animation patterns (TimelineView + Canvas, Capsule shape)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Almost no new dependencies. All core APIs are system-provided (UITextChecker, adjustTextPosition, textDocumentProxy). Only new dep is self-built n-gram DB |
| Features | HIGH | Table stakes features clearly identified from Apple keyboard analysis. Differentiators have clear scope boundaries. Anti-features well-reasoned |
| Architecture | HIGH | Existing two-process architecture validated. New components fit cleanly into existing targets. Integration points are specific and well-mapped |
| Pitfalls | MEDIUM-HIGH | Critical pitfalls (gesture conflicts, memory budget, emoji cache) are well-sourced. Cold start auto-return is the one area with genuine uncertainty |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **UITextChecker French quality**: No production data on how good French suggestions actually are. Must prototype and user-test before committing to the full suggestion bar feature. If quality is poor, fall back to spell-check only with accent shortcuts.
- **Cold start auto-return mechanism**: How Wispr Flow returns to the previous app remains unknown. A 1-2 day research spike (Console.app monitoring, network inspection) during Phase 4 planning is needed. May ultimately be unsolvable with public APIs.
- **Parakeet v3 French accuracy on iPhone**: CoreML conversions exist on HuggingFace but are third-party. No published benchmarks for French accuracy on mobile. Must be validated before any integration work begins (v1.2 scope).
- **Emoji glyph memory threshold**: The "50-80 unique emoji" limit cited in pitfall research is approximate. Actual jetsam threshold varies by device and iOS version. Must be profiled on iPhone 12 (lowest target) during implementation.
- **Suggestion bar vs toolbar height trade-off**: Two approaches (integrate into toolbar vs add separate row) have different UX implications. Needs design decision before Phase 3 implementation.

## Sources

### Primary (HIGH confidence)
- [Apple UITextDocumentProxy Documentation](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) -- cursor movement, text context APIs
- [Apple UITextChecker Documentation](https://developer.apple.com/documentation/uikit/uitextchecker) -- spell-check, completions for French
- [Apple Custom Keyboard Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) -- extension constraints, memory limits
- [Apple App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) -- keyboard privacy requirements
- [adjustTextPosition(byCharacterOffset:)](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/1618194-adjusttextposition) -- spacebar trackpad API

### Secondary (MEDIUM confidence)
- [NSHipster UITextChecker](https://nshipster.com/uitextchecker/) -- French support analysis, limitations
- [Swift Forums: Auto-return from keyboard extension](https://forums.swift.org/t/how-do-voice-dictation-keyboard-apps-like-wispr-flow-return-users-to-the-previous-app-automatically/83988) -- confirms no public API
- [Wispr Flow FAQ](https://docs.wisprflow.ai/iphone/faq) -- competitor analysis, session model
- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio) -- Parakeet CoreML wrapper
- [Parakeet-TDT-0.6B-v3 CoreML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) -- model availability
- [High memory usage of emojis on iOS](https://vinceyuan.github.io/high-memory-usage-of-emojis-on-ios/) -- emoji glyph cache behavior

### Tertiary (LOW confidence)
- [ios-uitextchecker-autocorrect GitHub](https://github.com/ansonl/ios-uitextchecker-autocorrect) -- reference implementation, unmaintained
- [Limitations of custom iOS keyboards (Medium)](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694) -- general constraints overview

---
*Research completed: 2026-03-07*
*Ready for roadmap: yes*
