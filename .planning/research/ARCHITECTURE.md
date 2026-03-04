# Architecture Research

*Research date: 2026-03-04 — targeting iOS 16.0+, iPhone 12+ (A14 Bionic)*

---

## Component Architecture

### The Fundamental Constraint: Memory

The single most important architectural fact for Dictus is the **keyboard extension memory ceiling**. iOS enforces a hard memory limit on keyboard extensions — empirically around 48–70 MB depending on device generation. Even `whisper-tiny` (the smallest WhisperKit model) requires approximately 30 MB of RAM on disk, and actual runtime allocation during inference is substantially higher once Core ML buffers, audio buffers, and model activations are factored in.

**Conclusion: WhisperKit cannot be loaded inside the keyboard extension process.** The extension must delegate all transcription work to the main app process.

This single constraint drives the entire two-process architecture described below.

---

### Process Boundaries

```
┌──────────────────────────────────────────────────────────────┐
│  Main App Process (Dictus.app)                               │
│                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌─────────────────┐  │
│  │ ModelManager │   │ AudioEngine  │   │ TranscriptionSvc│  │
│  │              │──▶│              │──▶│ (WhisperKit)    │  │
│  │ Download     │   │ AVAudioEngine│   │                 │  │
│  │ Select       │   │ VAD          │   │ DecodingOptions │  │
│  │ Unload/Reload│   │              │   │ lang: "fr"      │  │
│  └──────────────┘   └──────────────┘   └────────┬────────┘  │
│                                                  │           │
│  ┌──────────────────────────────────────────────▼────────┐  │
│  │ DictationCoordinator                                   │  │
│  │  - Triggered by URL scheme from keyboard extension     │  │
│  │  - Runs recording + transcription                      │  │
│  │  - Writes result to App Group shared container         │  │
│  │  - Returns to hosting app via openURL                  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ Settings / Onboarding / Model Manager UI (SwiftUI)   │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
                         App Group Container
                    group.com.pivi.dictus
                    ┌─────────────────────┐
                    │ UserDefaults suite  │
                    │ - selected model    │
                    │ - dictation result  │
                    │ - state flags       │
                    │                     │
                    │ FileManager shared  │
                    │ - downloaded models │
                    │   (whisper-small,   │
                    │    whisper-tiny...) │
                    └─────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Keyboard Extension Process (DictusKeyboard)                 │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ KeyboardViewController : UIInputViewController       │    │
│  │                                                      │    │
│  │  ┌───────────────────────────────────────────────┐   │    │
│  │  │ KeyboardRootView (SwiftUI via UIHostingCtrl)  │   │    │
│  │  │                                               │   │    │
│  │  │  ┌─────────────────┐  ┌────────────────────┐ │   │    │
│  │  │  │  AZERTYLayout   │  │  DictationButton   │ │   │    │
│  │  │  │  (key grid)     │  │  (mic icon + state)│ │   │    │
│  │  │  └─────────────────┘  └────────────────────┘ │   │    │
│  │  │                                               │   │    │
│  │  │  ┌─────────────────────────────────────────┐ │   │    │
│  │  │  │  TranscriptionPreviewBar                │ │   │    │
│  │  │  │  (shows pending result, undo button)    │ │   │    │
│  │  │  └─────────────────────────────────────────┘ │   │    │
│  │  └───────────────────────────────────────────────┘   │    │
│  │                                                      │    │
│  │  AppGroupStore (read-only for results)               │    │
│  │  DictationTrigger (writes URL scheme call)           │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### Major Components

#### Main App

| Component | Responsibility |
|-----------|----------------|
| `ModelManager` | Download, select, delete WhisperKit models into the App Group shared container. Exposes available models and currently active model. |
| `AudioEngine` | Wraps `AVAudioEngine` for microphone capture. Applies energy-based VAD to detect speech boundaries. Outputs `[Float]` audio arrays at 16 kHz (WhisperKit's required format). |
| `TranscriptionService` | Holds the live `WhisperKit` instance. Receives audio arrays, calls `pipe.transcribe(audioArray:decodeOptions:)`, returns cleaned text. Responsible for filler word removal post-transcription. |
| `DictationCoordinator` | Orchestrates the dictation flow when the app is opened via URL scheme from the keyboard. Controls audio capture lifecycle, drives TranscriptionService, writes result to App Group, navigates back. |
| `AppGroupStore` | Single source of truth for inter-process shared state: selected model path, dictation results, status flags. Backed by `UserDefaults(suiteName: "group.com.pivi.dictus")`. |
| `Settings / Onboarding UI` | SwiftUI views for model management, keyboard setup instructions, permissions, language selection. |

#### Keyboard Extension

| Component | Responsibility |
|-----------|----------------|
| `KeyboardViewController` | Subclasses `UIInputViewController`. Hosts SwiftUI view via `UIHostingController`. Bridges SwiftUI callbacks to `textDocumentProxy`. |
| `KeyboardRootView` | Top-level SwiftUI view. Composes layout rows, dictation controls, preview bar. |
| `AZERTYLayout` | Renders the full AZERTY key grid. Emits key tap events as `String` actions. |
| `DictationButton` | Mic button with visual + haptic states: idle, recording-requested, result-pending, error. Triggers the URL scheme when tapped. |
| `TranscriptionPreviewBar` | Displays the pending transcription result from App Group. Contains Confirm and Undo actions. Inserts or removes text via `textDocumentProxy`. |
| `AppGroupStore` (read) | Polls or observes shared UserDefaults for dictation results written by the main app. |
| `DictationTrigger` | Constructs and fires the custom URL scheme (`dictus://dictate`) using `self.openURL(url)` — the only allowed way to open URLs from a keyboard extension (via `UIInputViewController`'s `openURL` method, not `UIApplication.shared`). |

---

## Data Flow

### Key Tap (normal typing)

```
User taps key
  → AZERTYLayout emits character String
    → KeyboardRootView closure calls insertText callback
      → KeyboardViewController.textDocumentProxy.insertText(char)
        → Host app text field updated
```

### Dictation Flow (the critical path)

The dictation flow crosses two processes because the keyboard extension cannot load WhisperKit.

```
1. USER TAPS MIC BUTTON (keyboard extension process)
   DictationButton tapped
     → Write DictationStatus.requested to App Group UserDefaults
     → DictationTrigger.openURL("dictus://dictate")
       → iOS suspends keyboard, brings Dictus.app to foreground

2. MAIN APP ACTIVATED (main app process)
   AppDelegate / SceneDelegate handles "dictus://dictate" URL
     → DictationCoordinator.startDictation()
       → AudioEngine.startRecording()
         → AVAudioSession category: .record
         → AVAudioEngine input tap installed on inputNode
         → Audio buffers accumulate as [Float] at 16 kHz

3. USER STOPS RECORDING (main app process)
   User taps "Done" / VAD detects silence / max duration reached
     → AudioEngine.stopRecording() → returns [Float] audioArray
       → TranscriptionService.transcribe(audioArray: audioArray)
         → WhisperKit.pipe.transcribe(
               audioArray: audioArray,
               decodeOptions: DecodingOptions(
                 language: "fr",
                 temperature: 0.0,
                 skipSpecialTokens: true,
                 noSpeechThreshold: 0.6
               )
             )
           → Returns TranscriptionResult
             → FillerWordFilter.clean(result.text)
               → AppGroupStore.write(dictationResult: cleanedText)
                 → AppGroupStore.write(status: .completed)
                   → DictationCoordinator.openURL("dictus://return")
                     → iOS returns focus to originating app + keyboard

4. KEYBOARD RECEIVES RESULT (keyboard extension process)
   KeyboardViewController viewDidAppear / sceneWillEnterForeground
     → AppGroupStore.read(dictationResult)
       → TranscriptionPreviewBar shows text
         → User taps "Insert"
           → textDocumentProxy.insertText(result)
         → User taps "Undo"
           → textDocumentProxy.deleteBackward() × result.count
```

### App Group Shared State Schema

```swift
// Key names in UserDefaults(suiteName: "group.com.pivi.dictus")
enum AppGroupKeys {
    static let selectedModelId    = "selectedModelId"    // String: e.g. "whisper-small"
    static let dictationStatus    = "dictationStatus"    // String: "idle"|"requested"|"recording"|"completed"|"error"
    static let dictationResult    = "dictationResult"    // String: transcribed text
    static let dictationTimestamp = "dictationTimestamp" // Double: unix timestamp for staleness check
}

// Models directory lives in shared FileManager container:
// FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pivi.dictus")
//   └── Models/
//       ├── whisper-tiny/
//       └── whisper-small/
```

---

## Suggested Build Order

Building bottom-up respects dependencies and allows each layer to be tested before the next is added.

### Phase 1 — Foundation (no UI, no audio)

1. **App Group infrastructure** — Create the Xcode project with both targets. Configure `group.com.pivi.dictus` entitlement on both. Implement `AppGroupStore` (read/write helpers). Verify data round-trips between targets in a unit test.

2. **WhisperKit model pipeline** — In the main app, wire up `ModelManager`: download a `whisper-tiny` model to the App Group container, initialize `WhisperKit(config:)` pointing at that folder, call `pipe.transcribe(audioPath:)` on a test WAV file. Confirm French transcription works. This validates the entire ML pipeline before any UI exists.

3. **Audio capture** — Implement `AudioEngine` using `AVAudioEngine`. Install a tap on the input node, accumulate PCM buffers, convert to `[Float]` at 16 kHz (WhisperKit's required sample rate). Validate output with the WhisperKit transcription from step 2.

### Phase 2 — Keyboard Extension Shell

4. **`KeyboardViewController` scaffold** — Basic `UIInputViewController` subclass hosting a `UIHostingController<KeyboardRootView>`. Confirm it loads as the system keyboard in the simulator.

5. **AZERTY key layout** — Implement key rows with proper French characters (é, è, à, ç, etc.) and standard punctuation. Wire taps to `textDocumentProxy.insertText()` and `deleteBackward()`. No dictation yet — just a working keyboard.

6. **URL scheme trigger (extension → main app)** — Implement `DictationTrigger` using `UIInputViewController.openURL`. Confirm the main app opens. Implement the reverse journey (`dictus://return`) from the main app back to the previous app.

### Phase 3 — Dictation Integration

7. **`DictationCoordinator`** — Connects AudioEngine + TranscriptionService, driven by the URL scheme. Writes result to App Group on completion. Handles errors and timeouts.

8. **Main app dictation UI** — Minimal recording screen shown when opened via `dictus://dictate`. Displays recording state, stop button, and visual feedback. Navigates back automatically after transcription.

9. **`TranscriptionPreviewBar`** — Keyboard reads result from App Group on return. Shows preview with Insert / Undo controls. Inserts via `textDocumentProxy`.

### Phase 4 — Productization

10. **Filler word filter** — Post-processing pass on transcription result (euh, hm, voilà, etc.) before writing to App Group.

11. **Model Manager UI** — Download, select, delete models from the main app settings. Progress tracking via `WhisperKit.download` progress callback.

12. **Onboarding flow** — Permission requests (microphone, Full Access keyboard), keyboard setup instructions with deep link to iOS Settings.

13. **Settings screen** — Model picker, language selector, filler word toggle, keyboard layout toggle (AZERTY/QWERTY).

14. **iOS 26 Liquid Glass styling** — Apply design system throughout once all functionality is proven.

---

## Key Interfaces

### 1. URL Scheme Contract (Extension → Main App)

The keyboard extension cannot use `UIApplication.shared.open()`. It must use the `openURL(_:)` method inherited by `UIInputViewController`.

```
dictus://dictate
  → Opens main app, starts DictationCoordinator

dictus://return
  → Main app opens originating app (using openURL from DictationCoordinator)
  → Keyboard extension observes App Group for result
```

The main app registers this URL scheme in `Info.plist` under `CFBundleURLTypes`. The extension uses `self.openURL(URL(string: "dictus://dictate")!)`.

### 2. AppGroupStore Interface

```swift
// Shared module (DictusCore SPM package)
struct AppGroupStore {
    static let suiteName = "group.com.pivi.dictus"
    private let defaults = UserDefaults(suiteName: suiteName)!

    // Written by extension, read by main app
    func requestDictation()

    // Written by main app, read by extension
    func writeDictationResult(_ text: String)
    func readDictationResult() -> String?
    func clearDictationResult()

    // Written and read by both
    var dictationStatus: DictationStatus { get set }

    // Written by main app settings, read by extension (for display)
    var selectedModelId: String { get set }

    // Shared model container
    static var modelsDirectoryURL: URL
}

enum DictationStatus: String {
    case idle, requested, recording, completed, error
}
```

### 3. TranscriptionService Interface

```swift
// Main app only — never imported by extension
actor TranscriptionService {
    func loadModel(at folderURL: URL) async throws
    func transcribe(_ audioArray: [Float]) async throws -> String
    func unload() async
}
```

### 4. KeyboardViewController → SwiftUI Bridge

```swift
// Pattern: UIInputViewController owns UIHostingController
// SwiftUI views receive closures — no direct UIKit dependency

struct KeyboardRootView: View {
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onStartDictation: () -> Void
    let onInsertDictationResult: (String) -> Void
    let onUndoDictation: (String) -> Void
    // ...
}

// KeyboardViewController.swift
let rootView = KeyboardRootView(
    onInsertText: { [weak self] text in
        self?.textDocumentProxy.insertText(text)
    },
    onDeleteBackward: { [weak self] in
        self?.textDocumentProxy.deleteBackward()
    },
    onStartDictation: { [weak self] in
        self?.openURL(URL(string: "dictus://dictate")!)
    },
    // ...
)
```

### 5. Shared Code Structure (SPM Local Package)

WhisperKit is a binary SPM package and **must only be linked to the main app target**, not to the keyboard extension. The extension gets access via the app's frameworks folder at runtime (Runpath Search Paths: `@executable_path/../../Frameworks`).

Shared pure-Swift code (no UIKit, no WhisperKit dependency) lives in a local SPM package:

```
Dictus/                          ← Xcode workspace root
├── Dictus.xcodeproj
├── Dictus/                      ← Main app target sources
├── DictusKeyboard/              ← Keyboard extension target sources
└── Packages/
    └── DictusCore/              ← Local SPM package (no binary deps)
        ├── Package.swift
        └── Sources/
            └── DictusCore/
                ├── AppGroupStore.swift
                ├── DictationStatus.swift
                ├── FillerWordFilter.swift
                └── SharedConstants.swift
```

`DictusCore` is linked to both targets as a static library. It contains no UIKit, no WhisperKit — only shared data models and App Group access. WhisperKit is added exclusively to the main app target.

---

## Critical Risks and Open Questions

| Risk | Severity | Notes |
|------|----------|-------|
| Microphone access in keyboard extension | HIGH | Apple documentation is contradictory. Multiple developer reports say microphone recording fails in the keyboard process even with Full Access. The two-process architecture (keyboard → main app for audio) is the proven workaround used by SwiftKey and WeChat Input. |
| WhisperKit tiny/small model RAM in main app | MEDIUM | The main app process has no hard memory cap like extensions, but model loading time (cold start) may be noticeable. `prewarm: true` in `WhisperKitConfig` helps. `unloadModels()` / `loadModels()` can manage this. |
| Return-to-previous-app after dictation | MEDIUM | After dictation, the main app must use `openURL` to return the user to the previous context. The host app's URL scheme is not known. Common pattern: use `dictus://return` as the main app's own URL scheme, then iOS automatically returns focus to the app that opened dictus:// — this needs to be validated. |
| `UIInputViewController.openURL` availability | LOW | This method is available on `UIInputViewController` specifically for this pattern. It is not deprecated. Confirmed in Apple's Custom Keyboard docs. |
| App Group container for model files | LOW | Models can be large (whisper-small ~466 MB on disk). The App Group container has no enforced storage quota but users must be informed during download. |

---

*Sources consulted:*
- [Apple Developer: App Extension Programming Guide – Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Apple Developer: UIInputViewController](https://developer.apple.com/documentation/uikit/uiinputviewcontroller)
- [Apple Developer: Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [WhisperKit GitHub – argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [WhisperKit Context7 documentation](https://context7.com/argmaxinc/whisperkit/llms.txt)
- [KeyboardKit: A brand new keyboard dictation experience](https://keyboardkit.com/blog/2026/01/03/a-brand-new-keyboard-dictation-experience)
- [KeyboardKit: Issue #903 – dictation from extension](https://github.com/KeyboardKit/KeyboardKit/issues/903)
- [Dealing with memory limits in iOS app extensions – Igor Kulman](https://blog.kulman.sk/dealing-with-memory-limits-in-app-extensions/)
- [iOS App Extensions: Data Sharing – dmtopolog](https://dmtopolog.com/ios-app-extensions-data-sharing/)
- [Apple Developer Forums: Recording audio in keyboard extension](https://developer.apple.com/forums/thread/742601)
- [Apple Developer Forums: iOS keyboard app extension crashes](https://developer.apple.com/forums/thread/105815)
- [Modularizing iOS Applications with SwiftUI and SPM – Nimble](https://nimblehq.co/blog/modern-approach-modularize-ios-swiftui-spm)
- [SwiftUI: Create Systemwide Custom Keyboard – Level Up Coding](https://levelup.gitconnected.com/swiftui-create-systemwide-custom-keyboard-ef4c79ecb89a)
