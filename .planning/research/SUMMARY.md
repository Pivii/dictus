# Research Summary

*Synthesized: 2026-03-04 — based on STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md*

---

## Key Findings

1. **Microphone access is architecturally blocked in keyboard extensions.** This is not a configuration issue or a permissions gap — it is an OS-level sandbox enforcement that has existed since iOS 8 and is not expected to change. Attempting to record audio inside the keyboard extension process will fail at runtime on physical devices, even with Full Access granted. All dictation audio must be captured in the main app process.

2. **WhisperKit is the correct and only production-ready choice for on-device French STT.** It is a native Swift library, Core ML native (routing inference to the Apple Neural Engine), actively maintained by Argmax (Apple's WWDC 2025 SpeechAnalyzer partner), and the only implementation with documented benchmarks across Apple hardware. Alternatives (whisper.cpp, SFSpeechRecognizer, KeyboardKit Pro) are either unmaintained, less accurate, cloud-dependent, or deprecated in spirit.

3. **The keyboard extension memory ceiling is approximately 30 MB resident — not 50 MB.** Even the smallest WhisperKit model (whisper-tiny) consumes 40–60 MB at runtime once Core ML expands it for inference. Loading WhisperKit inside the keyboard extension process will cause silent jetsam termination on most devices, especially during the Core ML compilation spike on first launch. WhisperKit must run in the main app process only.

4. **No competitor ships an AZERTY keyboard with on-device French dictation.** Super Whisper, Wispr Flow, and Willow are all QWERTY-only on iOS. This is the primary untapped differentiator and directly addresses the pain point stated in PROJECT.md. Dictus has genuine category-level whitespace to occupy.

5. **The two-process architecture is the only viable approach.** The keyboard extension handles layout, text insertion, and UI state. The main app handles audio recording, WhisperKit inference, and model management. Data moves between processes via an App Group shared container (`group.com.pivi.dictus`). This is how Super Whisper and similar production apps work.

6. **App Group misconfiguration is the most common silent failure mode.** Both the main app and extension targets must have identical App Group identifiers in their entitlements and matching provisioning profiles. Failure returns `nil` with no error — the keyboard appears to work but data never crosses the process boundary.

7. **iOS 26 Liquid Glass is accessible from within a UIHostingController inside the keyboard extension**, but whether the glass sampling source (the host app's content behind the keyboard) produces the expected visual result needs device validation. The API itself is well-defined; the rendering in the extension context is an open unknown.

---

## Recommended Stack

| Component | Choice | Confidence |
|-----------|--------|------------|
| Speech-to-text | WhisperKit via SPM (`argmaxinc/WhisperKit`) | High |
| STT model (keyboard, in-extension) | None — inference in main app only | High |
| STT model (main app, default) | `openai_whisper-small` (multilingual) | High |
| STT model (main app, fast mode) | `openai_whisper-tiny` (multilingual) | High |
| Audio capture | `AVAudioEngine` + `AVAudioSession` — main app target only | High |
| Keyboard entry point | `UIInputViewController` subclass | High |
| Keyboard UI | SwiftUI via `UIHostingController` inside `UIInputViewController` | High |
| Cross-process data | App Group `UserDefaults` + `FileManager` (`group.com.pivi.dictus`) | High |
| Cross-process signaling | Custom URL scheme (`dictus://dictate`, `dictus://return`) | Medium |
| Design system | iOS 26 SwiftUI Liquid Glass (`.glassEffect()`) with `Material.regularMaterial` fallback for iOS 16–25 | Medium |
| Shared code | Local SPM package (`DictusCore`) — no UIKit, no WhisperKit dependency | High |
| Keyboard layout library | None — build AZERTY manually in SwiftUI (learning goal, 50 keys) | High |

**Deferred to v2:**
- Apple SpeechAnalyzer (iOS 26+, out-of-process, zero bundle cost — revisit once stable)
- Darwin notifications for low-latency cross-process signaling (use polling for v1)
- Streaming real-time transcription (WhisperKit supports it, complexity deferred)

---

## Table Stakes Features

Features that must ship in v1. Absence of any of these is a reason for users to not adopt or abandon Dictus.

1. **Universal dictation — works in any app.** The keyboard extension must function as a system keyboard with Full Access.
2. **French transcription accuracy that beats Apple's built-in dictation.** Whisper small multilingual achieves ~5–8% WER on clean French speech. Apple's dictation has regressed in iOS 18 — this bar is clearable.
3. **Low-latency transcription** — perceptually 1–3 seconds for a short utterance. Achievable with whisper-small on A14+ via Core ML.
4. **AZERTY keyboard layout** — the French character set (é, è, à, ç, etc.) and standard punctuation, functional for everyday typing without dictation.
5. **Transcription preview before insertion** — the user must see and approve the result before it lands in the target text field.
6. **Filler word removal** — French filler words ("euh", "bah", "voilà", "hm") and English equivalents. Rule-based word list is sufficient for v1.
7. **Automatic punctuation** — Whisper produces this natively; it must not be stripped.
8. **Microphone visual feedback** — a clear recording state indicator during capture. Without it users do not know if recording started.
9. **Onboarding flow** — keyboard installation is multi-step and non-obvious on iOS. Guided setup with screenshots is required for any user beyond the developer.
10. **Model download and management** — WhisperKit models are not bundled. Users must download at least one model and understand the size/accuracy tradeoffs.
11. **Undo inserted text** — deleting a wrong transcription block via `textDocumentProxy.deleteBackward() × N`, tracked via local state (not read back from the proxy).
12. **Basic typing works without Full Access** — required by App Store Guideline 4.5.1. AZERTY layout, delete, space, and return must be functional when Full Access is off.

---

## Differentiators

What makes Dictus genuinely different from every competitor on the iOS App Store today.

1. **AZERTY keyboard layout** — no competitor offers this with on-device French dictation on iOS. This is the single clearest gap in the market and the reason this project exists.
2. **Fully on-device, no account, no subscription** — Wispr Flow ($15/mo, cloud-required), Super Whisper ($8.49/mo). Dictus is free, open source, and offline-only. This is a principled position that resonates with privacy-conscious users and French users frustrated by English-centric SaaS pricing.
3. **Inline correction without context switching** — the dictation, preview, and correction all happen in the same keyboard view. The user never needs to switch input methods. This is the primary UX failure mode of Super Whisper that PROJECT.md describes as the core pain point.
4. **French-first tuning** — French filler words, French punctuation conventions (space before `:`), accent handling on proper nouns. Competitors support French but are tuned for English. A curated French experience at the detail level matters to native speakers.
5. **iOS 26 Liquid Glass design from day one** — no incumbent will ship a Liquid Glass-native keyboard at launch. Dictus is purpose-built for iOS 26 and can own the visual benchmark for this category.
6. **Open source / MIT licensed** — enables community-driven contributions (Belgian AZERTY, Swiss French, Canadian French variants), public privacy audit, and developer trust.

---

## Critical Architecture Decision

**The two-process architecture is the foundational constraint that shapes every other decision in this project.**

iOS keyboard extensions cannot access the microphone. This is a hard, undocumented OS-level sandbox enforcement — not a configuration flag, not a permissions issue, not a bug Apple will fix. `AVAudioEngine.start()` fails in the extension process even when `RequestsOpenAccess = true` and the user has explicitly granted microphone permission. The error is `com.apple.coreaudio.avfaudio Code=561145187` (`kAudioSessionIncompatibleCategory`). Simulator testing hides this failure; it surfaces only on physical devices.

Compounding this, the keyboard extension memory ceiling (~30 MB resident) makes loading any WhisperKit model inside the extension process infeasible. Even the tiny model spikes to 40–60 MB during Core ML compilation and inference.

**The mandated architecture:**

```
[Keyboard Extension]
  User taps mic button
    → Write DictationStatus.requested to App Group UserDefaults
    → openURL("dictus://dictate") via UIInputViewController.openURL
      → iOS brings Dictus.app to foreground

[Main App]
  DictationCoordinator handles "dictus://dictate"
    → AVAudioEngine records audio (microphone permission on main app)
    → WhisperKit transcribes [Float] audio at 16 kHz
    → FillerWordFilter cleans output
    → Write transcription result to App Group UserDefaults
    → openURL("dictus://return") returns focus to previous context

[Keyboard Extension]
  viewDidAppear / App Group observer fires
    → Read dictation result from App Group
    → TranscriptionPreviewBar shows text
    → User confirms → textDocumentProxy.insertText(result)
```

All model downloading and Core ML compilation must occur in the main app target. The extension is a pure UI and signaling layer with no ML dependency.

This architecture imposes a UX cost: the user briefly sees the Dictus app during the dictation flow before returning to their original context. Whether this context switch is acceptable is the primary unknown that Sprint 1 must validate with a functional prototype.

---

## Watch Out For

The top 5 pitfalls to actively manage throughout development.

1. **Testing on Simulator hides microphone and memory failures.** Microphone access failures and jetsam kills only manifest on physical devices. Every audio and memory validation must happen on a real device — minimum iPhone 12 (A14, 4 GB RAM) — from Sprint 1 onward. Never ship a build that has only been tested in Simulator.

2. **App Group misconfiguration returns nil silently.** If either target's provisioning profile is missing the `group.com.pivi.dictus` capability, `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` and `UserDefaults(suiteName:)` writes into a local sandbox with no error. Write a `AppGroupDiagnostic` check that logs container access on launch of both targets in Sprint 1, before any feature code is written.

3. **`UIApplication.shared` crashes the extension process.** It is unavailable in all extension targets. Setting `EXTENSION_SAFE_API_ONLY = YES` in the extension target's build settings makes Xcode emit a compile-time error for forbidden APIs. Enable this in Sprint 1 before writing any extension code. Audit all SPM dependencies for extension safety before linking them to the extension target.

4. **Users will not grant Full Access without clear in-app guidance.** Full Access requires a separate manual step in iOS Settings that most users will miss. Without it, the App Group shared container is inaccessible and dictation silently fails. The dictation button must be visually disabled (not silently non-functional) when Full Access is off. A non-dismissible banner with a Settings deep link is required. Basic typing must work without Full Access (App Store Guideline 4.5.1).

5. **WhisperKit cold start and Core ML compilation happen at first launch.** On older A-series chips this takes 10–60 seconds and temporarily doubles memory consumption. All model downloading and pre-compilation must happen in the main app, writing a `modelReady` flag to the App Group when complete. The extension must check this flag before any transcription is attempted. Validate model file integrity after download (check `.mlmodelc` directory contents) — corrupted partial downloads affect roughly 20% of users per WhisperKit Issue #171.

---

## Impact on PROJECT.md

The following items require revision in the project definition based on research findings.

**Architecture corrections:**
- The stated "~50 MB" memory limit for the keyboard extension should be revised to "~30 MB empirical resident limit." Planning at 50 MB will cause jetsam failures on production devices.
- The project must explicitly adopt the two-process architecture from Sprint 0. Any project plan that assumes in-extension recording or inference should be revised — these paths are not viable.

**Model strategy revision:**
- The tiny model cannot run inference inside the extension. If PROJECT.md implies an "in-extension WhisperKit" design, this must be removed. All inference runs in the main app.
- Small multilingual (`openai_whisper-small`) should be the recommended default model in the main app, not tiny. Tiny's French WER of 15–20% is marginal and only acceptable as a "fast mode" option.

**Feature additions to consider:**
- A `SFSpeechRecognizer` fallback during the period before a Whisper model is downloaded. This is a graceful degradation path not currently in PROJECT.md that would improve first-run experience.
- An explicit "Full Access off" graceful degradation state for the keyboard — required for App Store approval under Guideline 4.5.1 and currently not called out.

**Feature deferral confirmations — research validates these are correct:**
- Real-time streaming transcription: defer to v2 (implementation complexity is real, marginal UX benefit over 1-2 second batch transcription).
- LLM post-processing: defer to v2 (on-device LLM story on iOS is immature, adds complexity before core pipeline is proven).
- iCloud sync and dictation history: defer to v2+ (extension limitations make this an unnecessary complication for v1).
- Apple SpeechAnalyzer: defer to v2 (iOS 26 beta, microphone restriction still applies, track as a research spike).

**iOS version target:**
- Liquid Glass (`.glassEffect()`) requires iOS 26. If the project targets iOS 26 minimum, the installed base is near zero today (iOS 26 is in beta). If the project targets iOS 16.0 minimum as stated, Liquid Glass should be behind `#available(iOS 26, *)` guards with `Material.regularMaterial` fallbacks. PROJECT.md should be explicit about which it is.

**Build order implication:**
- Sprint 1 must validate the cross-process dictation flow on a physical device (URL scheme trigger → main app audio → App Group result → extension display) before any other feature work begins. This is the highest-risk assumption in the project and must be proven early, not after the keyboard UI is built.
