# Stack Research

*Research date: 2026-03-04. Target: Dictus — iOS AZERTY keyboard with on-device French STT.*

---

## Recommended Stack

### Speech Recognition: WhisperKit (current release via SPM)

**Package**: `https://github.com/argmaxinc/whisperkit` via Swift Package Manager
**Model for keyboard extension**: `openai_whisper-tiny` or `openai_whisper-base` (multilingual)
**Model for main app download**: `openai_whisper-small` as the recommended default

WhisperKit is the correct choice for this project. It is a pure Swift library built by Argmax that runs Whisper models entirely through Core ML, distributing inference across ANE (Apple Neural Engine), GPU, and CPU depending on the device. It supports all 100 Whisper languages including French (`fr`), provides voice activity detection, word timestamps, and quantized model variants. It is actively maintained with production-level documentation and a TestFlight demo app.

**Model selection for the keyboard extension is the most critical architectural decision in this project.** The keyboard extension memory ceiling is approximately 40–60 MB (undocumented by Apple, empirically measured; varies by device and memory pressure). WhisperKit model sizes at runtime are approximately:

| Model | Disk size (CoreML quantized) | Approximate runtime RAM |
|---|---|---|
| tiny multilingual | ~75 MB disk | ~30 MB RAM |
| base multilingual | ~145 MB disk | ~55–65 MB RAM |
| small multilingual | ~480 MB disk | ~150–200 MB RAM |
| medium multilingual | ~1.5 GB disk | ~500 MB RAM |

The **tiny multilingual** model is the only one that reliably fits inside keyboard extension memory. The **base multilingual** sits at the edge and will cause jetsam kills on memory-pressured devices or older hardware. The **small model is definitively too large** for the extension process.

The recommended architecture: store downloaded models in the App Group shared container (`group.com.pivi.dictus`). The keyboard extension loads only `tiny` for inline use. The main app exposes `small` (or `medium` for users who want accuracy) via a model manager but runs transcription in the main app process, not the extension.

French WER with Whisper multilingual models: approximately 5–8% for `small`, 8–12% for `base`, 15–20% for `tiny` on clean speech. Tiny is acceptable for dictation where the user sees and corrects the result immediately; it is not acceptable for a silent background transcription. This matches Dictus's inline preview-and-correct workflow.

**Confidence: High** — WhisperKit is the only production-ready, actively maintained, pure-Swift, Core ML native Whisper implementation for iOS. The Argmax team benchmarks it continuously against Apple hardware. Argmax is also the partner Apple cited when introducing SpeechAnalyzer, indicating alignment with the Apple platform direction.

---

### Microphone / Audio Capture: AVAudioEngine in the Main App only

**Framework**: AVFoundation — `AVAudioEngine` with `AVAudioSession`
**Architecture decision**: Audio capture MUST happen in the main app process, not the keyboard extension.

This is the hardest constraint in the entire project. Apple's official documentation for custom keyboard extensions explicitly states:

> "Custom keyboards, like all app extensions in iOS 8.0, have no access to the device microphone, so dictation input is not possible."

Even with `RequestsOpenAccess = true`, which unlocks network access, shared containers, and audio playback (for key clicks), microphone recording via `AVAudioEngine` or `AVAudioRecorder` fails in the extension process. Developer reports from 2023–2024 on the Apple Developer Forums confirm that attempting to start an `AVAudioEngine` from a keyboard extension produces audio session errors even after Full Access is granted by the user.

**The workaround is a process-crossing architecture**:

1. The keyboard extension displays a record button.
2. Tapping the record button opens the main Dictus app (or uses a URL scheme / `openURL` via `UIApplication.shared` — which is NOT available in extensions). This means using `NSExtensionContext` to open the app URL, or passing a signal via an App Group flag that the main app monitors via a background task.
3. The main Dictus app wakes, records audio via `AVAudioEngine`, runs WhisperKit inference, writes the transcription string to the App Group `UserDefaults`, then returns focus to the previous app.
4. The keyboard extension reads the transcription from shared `UserDefaults` and inserts it via `textDocumentProxy.insertText()`.

This is the architecture used by Super Whisper and similar apps. It is the only viable approach on iOS. There is no API available to grant microphone access directly to a keyboard extension process, and there is no evidence that Apple will change this in iOS 26.

**Alternative pattern worth investigating**: `SpeechAnalyzer` (iOS 26 only) runs out-of-process, meaning its inference does not count against the extension's memory budget. If Apple permits keyboard extensions to open a SpeechAnalyzer session (which feeds from an audio file or stream, not from a live microphone directly in the extension), this could simplify the architecture for iOS 26+ users. This is unconfirmed and should be treated as a research spike for v2, not a v1 dependency.

**Required entitlements for the main app**:
- `NSMicrophoneUsageDescription` in Info.plist
- `RequestsOpenAccess = true` in the keyboard extension's Info.plist (for shared container access)
- App Group entitlement on both targets: `group.com.pivi.dictus`

**Confidence: High** — The microphone restriction is a hard platform constraint, not a configuration issue.

---

### Keyboard Extension UI: UIInputViewController + SwiftUI via UIHostingController

**Architecture**: `UIInputViewController` subclass (required by iOS) hosting a SwiftUI root view via `UIHostingController`

UIKit is mandatory for keyboard extensions — the entry point is always `UIInputViewController`, which is a UIKit class. There is no SwiftUI-native path to a custom keyboard extension. However, you are not forced to write the entire keyboard UI in UIKit. The standard and well-supported pattern is:

```swift
class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let hostingController = UIHostingController(
            rootView: KeyboardView(textProxy: textDocumentProxy)
        )
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([...fill superview...])
        hostingController.didMove(toParent: self)
    }
}
```

The SwiftUI view inside the `UIHostingController` can use the full SwiftUI view hierarchy, animations, state management, and as of iOS 26, the `glassEffect` modifier. The `UIInputViewController.textDocumentProxy` must be passed down as an observable object or environment value for text insertion.

**SwiftUI-only limitation**: You cannot use `@FocusState` or `TextField` inside a keyboard extension in a way that steals first responder. All text output goes through `textDocumentProxy.insertText()`, not through SwiftUI text fields.

**What does NOT work in keyboard extensions**:
- `UIApplication.shared` (unavailable — crashes at runtime)
- `UIScene` or multi-window APIs
- Direct microphone recording (see above)
- Secure text entry fields (extension is deactivated automatically)
- Key press artwork displayed above the primary view (system limitation)

**KeyboardKit consideration**: KeyboardKit (v10.3.0, open source base tier) provides AZERTY layout definitions, key rendering, and input handling boilerplate. For a learning project, using it reduces time-to-working-keyboard but makes the codebase less educational and adds a dependency. For Dictus specifically, given the learning goal stated in PROJECT.md, build the keyboard layout manually in SwiftUI. The AZERTY layout is not complex (roughly 50 keys, 3 rows), and building it manually teaches the fundamental SwiftUI layout skills needed for the rest of the app. KeyboardKit Pro's French dictation feature is paid and cloud-dependent, which conflicts with Dictus's design.

**Confidence: High** — UIInputViewController + UIHostingController is the only supported pattern, well-documented, and proven in production keyboards.

---

### Data Sharing: App Group with UserDefaults + FileManager

**App Group ID**: `group.com.pivi.dictus`

Two sharing mechanisms are needed:

**1. Settings and state** — `UserDefaults(suiteName: "group.com.pivi.dictus")`

Use for: selected model name, language preference, filler word toggle, keyboard layout preference. Always call `.synchronize()` after writes in the extension (iOS does not guarantee flush timing for extensions). Use `@AppStorage(wrappedValue:store:)` in SwiftUI views in the main app; access via the named suite directly in the extension.

**2. Model files and transcription results** — `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pivi.dictus")`

Use for: downloaded Whisper model files (CoreML bundles can be 75 MB – 480 MB, too large for UserDefaults). Store models at `<group-container>/Models/<model-name>/`. The main app downloads models here; WhisperKit in the extension loads from this path.

Use also for: transcription result passing. Write the transcription string to a small JSON file in the shared container rather than UserDefaults if the string is long (UserDefaults is not designed for large values).

**Signal mechanism**: To notify the keyboard extension that a new transcription is ready, write a `transcription_ready` boolean flag to shared UserDefaults. The extension polls this flag on `viewWillAppear` or via a short `Timer` while the recording button is in a "processing" state. Darwin notifications (`CFNotificationCenterGetDarwinNotifyCenter`) can also be used for immediate cross-process signaling without polling.

**Confidence: High** — App Group is the only supported cross-process data sharing mechanism for extensions. The patterns above are stable and unchanged since iOS 8.

---

### iOS 26 Liquid Glass Design

**APIs**: `.glassEffect()` modifier, `GlassEffectContainer`, `.glassEffectID()` for morphing
**Minimum deployment target impact**: iOS 26 for Liquid Glass; use `#available(iOS 26, *)` guards throughout

The `.glassEffect()` modifier is a SwiftUI-only API. Since the keyboard UI runs inside a `UIHostingController`, the entire SwiftUI layer inside it gets access to `glassEffect`. This is the correct approach for Dictus — the keyboard key backgrounds, the dictation bar, and the transcription preview zone can all use `glassEffect`.

Key rules for correct Liquid Glass usage:

- Wrap adjacent glass elements in a `GlassEffectContainer` to share the sampling region. This is mandatory when glass elements are close to each other, or rendering artifacts appear.
- Use `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))` for key backgrounds.
- Use `.glassEffect(.clear)` for the transcription preview zone that sits over keyboard content.
- Never apply `glassEffect` to list or table content — only navigation-layer UI.
- The system automatically handles Reduce Transparency (increases frost), Increase Contrast (adds stark borders), and Reduce Motion. No manual fallback needed.
- For iOS 16–25 fallback: replace `glassEffect` with a simple `Material.regularMaterial` background.

**UIKit interop for Liquid Glass**: If any part of the keyboard UI needs UIKit-level control (e.g., custom gesture recognizers on key cells), wrap the UIKit view in `UIViewRepresentable` and apply `glassEffect` on the SwiftUI side. Do not try to bridge Liquid Glass to UIKit layers — the API is SwiftUI-only with no UIKit equivalent currently documented.

**Confidence: Medium** — The API surface is well-defined from WWDC 2025 sessions and community documentation. The uncertainty is whether `glassEffect` renders correctly within `UIHostingController` inside a keyboard extension (the background content being "sampled" by the glass is the host app's content, not the keyboard's own background — this may require testing to confirm the visual result is as expected). If glass sampling does not work correctly in the extension context, fall back to `Material.regularMaterial` for the keyboard surface and reserve full glass effects for the main app UI.

---

## Alternatives Considered

### Apple SpeechAnalyzer (iOS 26+)

Introduced at WWDC 2025. Supports French (`fr_FR`, `fr_CA`, `fr_CH`, `fr_BE`). Runs out-of-process so model inference does not count against the app's memory budget. All language models are system-managed (zero app bundle impact). Word error rate on English benchmarks: ~14% (WhisperKit small: ~12.8%, WhisperKit base: ~15.2%). Supports DictationTranscriber (punctuation-aware) and SpeechTranscriber (command-style) modes.

**Why not chosen for v1**: iOS 26 is in beta as of research date (2026-03-04). Targeting iOS 26 as the minimum excludes the entire installed base on iOS 16–25. The Dictus requirement is iOS 16.0 minimum. SpeechAnalyzer should be adopted as an additive enhancement for iOS 26+ users in v2 — it solves the extension memory problem and has excellent French support. It does not solve the microphone restriction in keyboard extensions.

### whisper.cpp via SwiftWhisper or whisper.spm

`whisper.cpp` by ggerganov is the original C++ Whisper implementation. Swift wrappers exist: `SwiftWhisper` (exPHAT/SwiftWhisper, last meaningfully updated 2023) and `whisper.spm` (ggerganov's own SPM wrapper). Both use Metal for GPU inference rather than Core ML/ANE.

**Why not chosen**: WhisperKit uses Core ML, which routes inference to the Apple Neural Engine on A14+. ANE inference is significantly more power-efficient than Metal GPU inference, which matters for battery life during dictation. WhisperKit is a native Swift codebase with no C++ bridge, simpler to debug and integrate. SwiftWhisper is essentially unmaintained. The whisper.spm package is cross-platform C++ wrapped in Swift — not idiomatic and harder to maintain. Argmax's own benchmarks show WhisperKit outperforming whisper.cpp on Apple Silicon in both speed and energy consumption.

### Apple SFSpeechRecognizer (legacy)

Available since iOS 10. On-device mode added in iOS 13. Supports French on-device (available in iOS 13+, but with fewer training data and lower accuracy than Whisper).

**Why not chosen**: On-device accuracy is notably lower than WhisperKit/Whisper for French. Audio duration limit of ~60 seconds for buffer-based requests. The API is deprecated in spirit — Apple's WWDC 2025 introduced SpeechAnalyzer as its replacement. No control over model quality or updates. SFSpeechRecognizer does offer one advantage: it does not require a separate model download step. For a v1 fallback while the Whisper model downloads, SFSpeechRecognizer could be used transiently — this is worth implementing as a graceful degradation path.

### KeyboardKit (open source, v10.3.0)

A full keyboard SDK with AZERTY layout definitions, key cap rendering, autocomplete scaffolding, and a dictation module (KeyboardKit Pro, paid).

**Why not chosen for the core keyboard layout**: This is a learning project. Building the AZERTY layout in SwiftUI is achievable in one sprint and is more educational. The free tier of KeyboardKit does not include French dictation or autocomplete. The Pro tier is commercial and cloud-dependent for dictation, which directly conflicts with Dictus's offline-first design. Adding KeyboardKit as a dependency for layout alone adds significant surface area with little benefit given the targeted key count.

### Combine for cross-process communication

`NotificationCenter` or `Combine` publishers do not cross process boundaries between the extension and the main app. Darwin notifications (`CFNotificationCenterGetDarwinNotifyCenter`) do.

**Darwin notifications** are available to both the extension and main app and can trigger immediate signaling without file polling. They are the recommended low-latency cross-process signal mechanism. Used in combination with App Group UserDefaults for the actual data payload.

---

## What NOT to Use

**AVAudioEngine or AVAudioRecorder directly in the keyboard extension process** — These will fail at runtime. Microphone access is architecturally blocked for all iOS keyboard extensions regardless of entitlements. There is no workaround. Do not attempt this; it will waste sprint time.

**`UIApplication.shared` in the extension** — This property is unavailable in extension targets and will crash. Use `NSExtensionContext` for app opening and URL handling.

**WhisperKit `small` or larger models loaded in the keyboard extension process** — The small model requires approximately 150–200 MB at runtime. The keyboard extension will be killed by jetsam before inference begins. Only `tiny` (multilingual) is safe to load inside the extension. If the user needs `small` quality, transcription must occur in the main app process.

**Synchronous WhisperKit inference on the main thread** — WhisperKit inference blocks the thread it runs on. Always dispatch to a background actor or `Task { }` with `await`. Blocking the keyboard extension's main thread will trigger system-level unresponsiveness warnings and potential termination.

**`UserDefaults.standard` in either target for cross-process data** — Standard UserDefaults is process-scoped. Data written by the main app is not visible to the extension. Always use `UserDefaults(suiteName: "group.com.pivi.dictus")`.

**SwiftUI `TextField` or `TextEditor` for keyboard output** — These steal first responder. Text output must go through `textDocumentProxy.insertText()` exclusively.

**KeyboardKit Pro for dictation** — The dictation feature in KeyboardKit Pro routes audio to cloud services, which is incompatible with Dictus's core value of no-cloud, no-subscription offline operation.

**Liquid Glass `glassEffect` on list or table content** — Apple explicitly designates Liquid Glass for navigation-layer UI (bars, sheets, overlays). Applying it to content layers (key rows, lists) creates visual noise. Use it for the key cap surfaces and the floating dictation UI, not for list-style settings views inside the keyboard.

**iOS 16 `UIInputViewController` without `UIHostingController`** — Building the full keyboard in UIKit directly (no SwiftUI) is unnecessary extra work and forfeits access to SwiftUI animation, Liquid Glass, and the modern layout system. The `UIHostingController` bridge is stable and well-understood.

**Streaming real-time transcription in v1** — WhisperKit supports streaming (chunked inference), but it adds significant complexity to the architecture (partial result display, chunking heuristics, cancellation). PROJECT.md correctly defers this to v2. Use a push-to-talk / tap-to-dictate model for v1 where the user records a complete utterance and then sees the result.

---

## Confidence Levels

| Component | Confidence | Rationale |
|---|---|---|
| WhisperKit via SPM | High | Production-proven, actively maintained, Core ML native, used in production apps |
| UIInputViewController + UIHostingController | High | Standard pattern, documented, used in every modern custom keyboard |
| Microphone block in extension process | High | Hard platform constraint, Apple documentation + developer reports agree |
| App Group shared container pattern | High | Stable API since iOS 8, extensively documented |
| Tiny model as extension default | High | Memory math is clear; alternatives will be killed by jetsam |
| App URL scheme for recording handoff | Medium | The UX is clunky (app switches); unclear if there is a smoother API path that avoids it. Needs prototyping in Sprint 1. |
| Liquid Glass in UIHostingController | Medium | API is well-defined, but rendering behavior inside extension UIHostingController needs device validation; the "sampling" source may not behave as expected |
| SpeechAnalyzer in extension (iOS 26+) | Low | Out-of-process design is promising but extension microphone entitlement is still a barrier; needs testing on iOS 26 beta |
| Darwin notifications for cross-process signals | Medium | Well-known pattern, but brittle in low-memory scenarios where extension is suspended |
| French accuracy with tiny model | Medium | Whisper tiny multilingual is acceptable for conversational French but noticeably worse than small; user correction workflow mitigates this, but needs user testing to confirm acceptability |

---

## Key Architectural Constraint Summary

The central constraint that shapes the entire architecture is this: **iOS keyboard extensions cannot access the microphone**. All other decisions flow from this.

The consequence is a two-process architecture where:
- The **keyboard extension** handles UI, text insertion via proxy, model display, and signals the main app.
- The **main app** handles audio recording, WhisperKit inference (for quality above tiny), model downloading, and writes results to the shared App Group container.
- **Shared state** (transcription results, settings, model selection) lives in `group.com.pivi.dictus` via `UserDefaults` and `FileManager`.

For in-extension transcription using only the `tiny` model: audio must still be recorded in the main app, written to a temp file in the shared container, then loaded by WhisperKit running in the extension. Whether this roundtrip is fast enough for good UX is the primary unknown that Sprint 1 must validate.

---

*Sources consulted:*
- *[WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)*
- *[WhisperKit vs whisper.cpp discussion](https://github.com/argmaxinc/WhisperKit/discussions/250)*
- *[WhisperKit arXiv paper (2507.10860)](https://arxiv.org/html/2507.10860v1)*
- *[Apple SpeechAnalyzer and Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax)*
- *[Apple Custom Keyboard Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)*
- *[iOS 26 Liquid Glass Reference](https://github.com/conorluddy/LiquidGlassReference)*
- *[iOS 26 Liquid Glass in UIKit+SwiftUI hybrid](https://fatbobman.com/en/posts/grow-ios26/)*
- *[SpeechAnalyzer iOS 26 Guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)*
- *[SpeechAnalyzer WWDC25 Session 277](https://developer.apple.com/videos/play/wwdc2025/277/)*
- *[Building iOS AI Keyboard with SwiftUI](https://medium.com/@jonathanaraney/building-an-ios-ai-keyboard-with-swiftui-my-experience-so-far-308a67e536a7)*
- *[KeyboardKit](https://github.com/KeyboardKit/KeyboardKit)*
- *[App Group data sharing patterns](https://rderik.com/blog/sharing-information-between-ios-app-and-an-extension/)*
- *[Keyboard extension memory issue — Apple Developer Forums](https://developer.apple.com/forums/thread/85478)*
- *[Recording audio in keyboard extension — Apple Developer Forums](https://developer.apple.com/forums/thread/742601)*
