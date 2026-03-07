# Phase 2: Transcription Pipeline - Research

**Researched:** 2026-03-05
**Domain:** WhisperKit on-device speech recognition, AVAudioEngine audio capture, model management
**Confidence:** HIGH

## Summary

Phase 2 replaces the stub in `DictationCoordinator.startDictation()` with a real audio recording and transcription pipeline using WhisperKit (argmaxinc). WhisperKit v0.16.0 wraps OpenAI Whisper models as Core ML, providing a clean Swift API: `WhisperKit.init()` for setup, `transcribe(audioArray:decodeOptions:)` for inference, and static methods for model discovery/download. Audio capture uses `AVAudioEngine` with an input tap, and WhisperKit includes its own `AudioProcessor` that handles recording natively at 16 kHz mono Float32 -- the exact format Whisper expects.

The main challenge is model management: WhisperKit models live on HuggingFace (`argmaxinc/whisperkit-coreml`), range from ~40 MB (tiny) to ~1.5 GB (large-v3), and need background download support for large models. The filler word filter is a straightforward post-processing step (regex/string matching on transcription output). Smart model routing is a simple duration-based branch before calling transcribe.

**Primary recommendation:** Use WhisperKit's built-in `AudioProcessor` for recording (avoid building a separate AVAudioEngine pipeline), WhisperKit's `download()` static method with `progressCallback` for model downloads, and `prewarmModels()` after download for Core ML compilation. Transcription runs in the main app only -- the keyboard extension triggers it via URL scheme (already wired in Phase 1).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- User taps a stop button in the main app to end recording -- no auto-stop on silence
- No maximum recording duration -- user records as long as needed
- Recording screen shows a live audio waveform visualization + stop button + elapsed time counter
- After transcription completes, auto-return immediately to keyboard -- no result preview in the main app (brief "Done" checkmark, then user switches back)
- Recording starts automatically when app opens via `dictus://dictate` (carried forward from Phase 1)
- User chooses which model to download during initial setup (no pre-selected default)
- Smart model routing: audio under 5 seconds uses tiny/base (fast), audio over 5 seconds uses small (accurate)
- If only one model is downloaded, always use that model regardless of duration -- no error, no prompt
- Pre-compile (warm up) Core ML model after download for faster first transcription (~10-30 seconds, only once)
- `modelReady` flag written to App Group so keyboard extension knows transcription is available
- Each model displays: size (MB/GB), accuracy label (Good/Better/Best), speed indicator (Fast/Balanced/Slow), recommended badge for device
- Downloads run in background (URLSession background download) -- progress bar visible when returning to app
- Delete requires confirmation alert showing model name and size
- Cannot delete the last remaining model -- disable delete button with "At least one model required" message
- Available models: tiny, base, small, medium, large-v3-turbo (per roadmap)
- Standard fillers only: euh, hm, bah, ben, voila, um, uh, er -- no aggressive patterns
- No hallucination filtering (no "quoi", "en fait", "du coup") -- conservative approach
- After removing fillers, basic text cleanup: collapse double spaces, remove orphaned punctuation
- On by default, toggle available in Settings (Phase 4 delivers the toggle UI)

### Claude's Discretion
- AVAudioEngine + AVAudioSession configuration details
- WhisperKit API integration approach and model loading strategy
- Audio format and sample rate choices
- Exact waveform visualization implementation
- Model download URL management and storage location
- Filler word regex vs token-based approach
- Error handling and retry logic for failed transcriptions
- Smart model router implementation details (threshold tuning)

### Deferred Ideas (OUT OF SCOPE)
- Wide mic button above keyboard (Phase 3 scope)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STT-01 | User can dictate text and receive accurate French transcription via on-device WhisperKit | WhisperKit `transcribe(audioArray:decodeOptions:)` with `language: "fr"` in DecodingOptions; AudioProcessor for recording |
| STT-02 | Filler words (euh, hm, voila, um, uh) are automatically removed from transcription | Post-processing `FillerWordFilter` on transcription text output; regex-based approach on the locked word list |
| STT-03 | Transcription includes automatic punctuation (provided natively by Whisper) | Whisper models produce punctuated output by default; no additional processing needed, just pass-through validation |
| STT-04 | Smart Model Routing switches between fast model (tiny/base) and accurate model (small) based on audio duration | `SmartModelRouter` checks audio duration vs 5-second threshold; selects from downloaded models |
| STT-05 | Transcription completes in under 3 seconds for 10 seconds of audio | WhisperKit tiny/small models on iPhone 12+ (A14) meet this; requires physical device benchmarking |
| APP-02 | Model Manager allows downloading, selecting, and deleting Whisper models | WhisperKit `fetchAvailableModels()`, `download(variant:progressCallback:)`, local storage in App Group container |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WhisperKit | 0.16.0 | On-device speech recognition (Whisper via Core ML) | Official argmaxinc library; Apple-optimized; includes audio processor, model download, prewarming |
| AVFoundation | System | `AVAudioSession` configuration for microphone access | System framework; required for audio category/mode setup |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI | System | Model Manager screen, recording waveform UI | All new UI in this phase |
| Combine | System | `@Published` properties for download progress, model state | Already used in DictationCoordinator pattern |

### Not Needed (WhisperKit handles these)
| Instead of | WhisperKit provides | Why |
|------------|---------------------|-----|
| Custom AVAudioEngine setup | `whisperKit.audioProcessor.startRecordingLive()` | Handles 16 kHz mono Float32 conversion, buffer management, energy levels |
| Custom model downloader | `WhisperKit.download(variant:progressCallback:)` | HuggingFace integration, progress callbacks, background session support |
| Manual Core ML compilation | `whisperKit.prewarmModels()` | Specializes models for device hardware |

**SPM Dependency (add to DictusApp target only):**
```swift
// In Xcode: File > Add Package Dependencies
// URL: https://github.com/argmaxinc/WhisperKit.git
// Version: from "0.16.0"
// Product: WhisperKit (NOT TTSKit)
```

**Important:** WhisperKit must NOT be added to DictusKeyboard target. Keyboard extensions have ~50 MB memory limit -- even the tiny model exceeds this at runtime. Transcription runs exclusively in DictusApp.

## Architecture Patterns

### Recommended Project Structure
```
DictusApp/
├── DictationCoordinator.swift       # MODIFY: replace stub with real pipeline
├── Audio/
│   ├── AudioRecorder.swift          # Wraps WhisperKit's AudioProcessor
│   └── TranscriptionService.swift   # WhisperKit transcribe + post-processing
├── Models/
│   ├── ModelManager.swift           # Download, select, delete, state tracking
│   ├── SmartModelRouter.swift       # Duration-based model selection
│   └── ModelInfo.swift              # Model metadata (size, labels, recommended)
├── PostProcessing/
│   └── FillerWordFilter.swift       # Regex-based filler removal + cleanup
└── Views/
    ├── RecordingView.swift          # Waveform + stop button + timer
    └── ModelManagerView.swift       # Model list + download/delete UI

DictusCore/Sources/DictusCore/
├── SharedKeys.swift                 # ADD: modelReady, activeModel keys
└── (existing files unchanged)
```

### Pattern 1: WhisperKit Recording via AudioProcessor
**What:** Use WhisperKit's built-in `AudioProcessor` instead of building custom AVAudioEngine pipeline
**When to use:** Always -- WhisperKit's AudioProcessor handles format conversion, energy levels, and sample accumulation
**Example:**
```swift
// Source: WhisperKit example app (WhisperAX)
import WhisperKit

@MainActor
class AudioRecorder: ObservableObject {
    private var whisperKit: WhisperKit?
    @Published var isRecording = false
    @Published var bufferEnergy: [Float] = []  // For waveform visualization
    @Published var bufferSeconds: Double = 0

    func startRecording() throws {
        guard let whisperKit else { return }
        try whisperKit.audioProcessor.startRecordingLive { [weak self] _ in
            DispatchQueue.main.async {
                self?.bufferEnergy = whisperKit.audioProcessor.relativeEnergy
                self?.bufferSeconds = Double(whisperKit.audioProcessor.audioSamples.count)
                    / Double(WhisperKit.sampleRate)
            }
        }
        isRecording = true
    }

    func stopRecording() -> [Float] {
        whisperKit?.audioProcessor.stopRecording()
        isRecording = false
        return whisperKit?.audioProcessor.audioSamples ?? []
    }
}
```

### Pattern 2: Transcription with French Language
**What:** Call `transcribe(audioArray:decodeOptions:)` with French language code
**When to use:** After recording stops, pass accumulated audio samples
**Example:**
```swift
// Source: WhisperKit API + WhisperAX example
func transcribe(audioSamples: [Float]) async throws -> String {
    guard let whisperKit else { throw TranscriptionError.notReady }

    let options = DecodingOptions(
        task: .transcribe,
        language: "fr",            // Force French
        temperature: 0.0,          // Greedy decoding (fastest)
        usePrefillPrompt: true,
        usePrefillCache: true,
        skipSpecialTokens: true,
        withoutTimestamps: false   // Keep timestamps for segment info
    )

    let results = try await whisperKit.transcribe(
        audioArray: audioSamples,
        decodeOptions: options
    )

    let rawText = results.map { $0.text }.joined(separator: " ")
    return FillerWordFilter.clean(rawText)
}
```

### Pattern 3: Model Download with Progress
**What:** Use WhisperKit's static `download()` with progress callback
**When to use:** When user selects a model to download in Model Manager
**Example:**
```swift
// Source: WhisperKit API
func downloadModel(_ variant: String) async throws -> URL {
    modelState = .downloading

    let folder = try await WhisperKit.download(
        variant: variant,
        from: "argmaxinc/whisperkit-coreml",
        useBackgroundSession: true,
        progressCallback: { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress = Float(progress.fractionCompleted)
            }
        }
    )

    // Pre-compile for device after download
    modelState = .prewarming
    let config = WhisperKitConfig(
        model: variant,
        modelFolder: folder.path,
        prewarm: true,
        load: true,
        download: false
    )
    let kit = try await WhisperKit(config)
    try await kit.prewarmModels()

    modelState = .ready
    return folder
}
```

### Pattern 4: Smart Model Router
**What:** Select model based on audio duration and available downloaded models
**When to use:** Before transcription, after recording stops
**Example:**
```swift
struct SmartModelRouter {
    static let durationThreshold: TimeInterval = 5.0 // seconds

    static func selectModel(
        audioDuration: TimeInterval,
        downloadedModels: [String]
    ) -> String {
        // If only one model, use it regardless
        guard downloadedModels.count > 1 else {
            return downloadedModels.first ?? "openai_whisper-tiny"
        }

        let fastModels = ["openai_whisper-tiny", "openai_whisper-base"]
        let accurateModels = ["openai_whisper-small", "openai_whisper-medium",
                              "openai_whisper-large-v3_turbo"]

        if audioDuration < durationThreshold {
            // Prefer fast model for short audio
            return downloadedModels.first { fastModels.contains($0) }
                ?? downloadedModels.first!
        } else {
            // Prefer accurate model for longer audio
            return downloadedModels.first { accurateModels.contains($0) }
                ?? downloadedModels.first!
        }
    }
}
```

### Anti-Patterns to Avoid
- **Building custom AVAudioEngine pipeline:** WhisperKit's AudioProcessor already handles 16 kHz mono Float32 conversion. Building your own duplicates work and risks format mismatches.
- **Loading WhisperKit in keyboard extension:** Memory limit (~50 MB) will crash the extension. All transcription MUST stay in DictusApp.
- **Downloading models without prewarming:** First transcription will be extremely slow if Core ML models are not pre-compiled. Always call `prewarmModels()` after download.
- **Using multilingual model names without prefix:** WhisperKit model identifiers use `openai_whisper-` prefix (e.g., `openai_whisper-tiny`, not `tiny`). Using wrong identifiers will fail silently.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audio recording at 16 kHz | Custom AVAudioEngine + format converter | `whisperKit.audioProcessor.startRecordingLive()` | Handles sample rate, channels, format; exposes energy levels for waveform |
| Model discovery | Manual HuggingFace API calls | `WhisperKit.fetchAvailableModels()` | Handles repo access, filtering, versioning |
| Model download | Custom URLSession download manager | `WhisperKit.download(variant:progressCallback:)` | Handles chunked download, progress, background session option |
| Core ML compilation | Manual `MLModel.compileModel()` | `whisperKit.prewarmModels()` | Knows exact model architecture, handles device-specific optimization |
| Audio format conversion | Manual PCM conversion / resampling | WhisperKit AudioProcessor | Proven pipeline matching Whisper's expected input format |

**Key insight:** WhisperKit is not just a transcription API -- it's a complete pipeline including audio capture, model management, and inference. Using its built-in components avoids format mismatches and edge cases.

## Common Pitfalls

### Pitfall 1: AVAudioSession Category Conflicts
**What goes wrong:** Audio session not configured before recording starts, or conflicts with other audio sources
**Why it happens:** iOS requires explicit session configuration; keyboard extension may have set a category
**How to avoid:** Set `.record` category with `.measurement` mode before starting recording; handle interruptions
**Warning signs:** Silent recording, zero-length audio buffers, permission dialogs not appearing
```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.record, mode: .measurement, options: .duckOthers)
try session.setActive(true)
```

### Pitfall 2: Model Identifier Mismatch
**What goes wrong:** Model download or loading fails silently
**Why it happens:** Using "tiny" instead of "openai_whisper-tiny" (the HuggingFace repo convention)
**How to avoid:** Use `WhisperKit.fetchAvailableModels()` to get exact identifiers; store the identifier string, not a display name
**Warning signs:** Download completes but model folder is empty; `modelState` stays at `.loading`

### Pitfall 3: Memory Pressure During Prewarming
**What goes wrong:** App crashes during `prewarmModels()` for larger models (medium, large-v3-turbo)
**Why it happens:** Core ML compilation is memory-intensive; iPhone 12 has 4 GB RAM
**How to avoid:** Warn user that prewarming takes 10-30 seconds; show progress indicator; consider limiting to small model on older devices
**Warning signs:** `didReceiveMemoryWarning`, jetsam logs in Console

### Pitfall 4: Background Download Session Lifecycle
**What goes wrong:** Download progress lost when app is suspended
**Why it happens:** `useBackgroundSession: true` in WhisperKit.download() requires proper `URLSession` background handling
**How to avoid:** WhisperKit handles this internally when `useBackgroundSession: true`; ensure the app delegate handles `handleEventsForBackgroundURLSession`
**Warning signs:** Downloads restart from 0% when returning to app

### Pitfall 5: Microphone Permission Not Requested
**What goes wrong:** Recording starts but captures silence
**Why it happens:** `NSMicrophoneUsageDescription` missing from Info.plist, or permission not requested before first recording
**How to avoid:** DictusApp Info.plist already has it (Phase 1). Always check `AVAudioSession.sharedInstance().recordPermission` before starting; request if `.undetermined`
**Warning signs:** `audioSamples` array is empty after recording

### Pitfall 6: Filler Word Filter Removing Valid Words
**What goes wrong:** French words containing filler substrings get corrupted (e.g., "voila" inside "devoiler")
**How to avoid:** Match whole words only using `\b` word boundaries in regex; test with French sentences containing these substrings
**Warning signs:** Words like "humain", "bénévole", "errer" get partial deletions

## Code Examples

### WhisperKit Initialization
```swift
// Source: WhisperKit v0.16.0 API
let config = WhisperKitConfig(
    model: "openai_whisper-small",
    modelRepo: "argmaxinc/whisperkit-coreml",
    modelFolder: modelStoragePath,  // App Group container path
    prewarm: true,
    load: true,
    download: false  // Already downloaded
)
let whisperKit = try await WhisperKit(config)
```

### Fetching Available Models
```swift
// Source: WhisperKit API
let allModels = try await WhisperKit.fetchAvailableModels(
    from: "argmaxinc/whisperkit-coreml"
)
// Filter to the 5 models we support
let supportedPrefixes = [
    "openai_whisper-tiny",
    "openai_whisper-base",
    "openai_whisper-small",
    "openai_whisper-medium",
    "openai_whisper-large-v3_turbo"
]
```

### Device-Recommended Models
```swift
// Source: WhisperKit API
let recommended = WhisperKit.recommendedModels()
// recommended.default — best model for this device
// Use to show "Recommended" badge in Model Manager
```

### Filler Word Filter
```swift
struct FillerWordFilter {
    // Locked word list from CONTEXT.md
    private static let fillers = [
        "euh", "hm", "bah", "ben", "voila",  // French
        "um", "uh", "er"                       // English
    ]

    // Build regex matching whole words only (case-insensitive)
    private static let pattern: String = {
        let escaped = fillers.map { NSRegularExpression.escapedPattern(for: $0) }
        return "\\b(" + escaped.joined(separator: "|") + ")\\b"
    }()

    static func clean(_ text: String) -> String {
        var result = text
        // Remove filler words (whole word match, case-insensitive)
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        // Collapse multiple spaces
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        // Remove orphaned punctuation (punctuation preceded only by whitespace)
        result = result.replacingOccurrences(of: "\\s+([,.])", with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }
}
```

### Waveform from Energy Levels
```swift
// Source: WhisperKit AudioProcessor exposes relativeEnergy: [Float]
// Values are 0.0-1.0, updated in real-time during recording
struct WaveformView: View {
    let energyLevels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(energyLevels.suffix(50), id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: CGFloat(level) * 40 + 2)
            }
        }
        .frame(height: 44)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SFSpeechRecognizer (Apple) | WhisperKit (on-device Whisper) | 2024 | Much better accuracy for French; no network requirement; model selection flexibility |
| Manual AVAudioEngine + converter | WhisperKit AudioProcessor | WhisperKit 0.9+ | Built-in 16 kHz recording, energy levels, VAD |
| Manual HuggingFace download | WhisperKit.download() static | WhisperKit 0.9+ | Integrated progress, background session, model verification |
| Core ML manual compilation | prewarmModels() | WhisperKit 0.6+ | Device-optimized compilation handled internally |

**WhisperKit version note:** v0.16.0 (March 2025) is current stable. Includes TTSKit (not needed), bug fixes for Bluetooth audio, enhanced input suppression. Use `from: "0.16.0"` in SPM.

## Model Reference

| Model Identifier | Display Name | Approx Size | Speed | Accuracy | Language |
|------------------|-------------|-------------|-------|----------|----------|
| `openai_whisper-tiny` | Tiny | ~40 MB | Fast | Good | Multilingual |
| `openai_whisper-base` | Base | ~75 MB | Fast | Good+ | Multilingual |
| `openai_whisper-small` | Small | ~250 MB | Balanced | Better | Multilingual |
| `openai_whisper-medium` | Medium | ~750 MB | Slow | Best | Multilingual |
| `openai_whisper-large-v3_turbo` | Large v3 Turbo | ~950 MB | Balanced | Best | Multilingual |

**Note:** Use multilingual variants (not `.en` suffixed) since the target language is French.

## Open Questions

1. **WhisperKit `useBackgroundSession` reliability**
   - What we know: WhisperKit supports `useBackgroundSession: true` in `download()`
   - What's unclear: Whether WhisperKit handles `application(_:handleEventsForBackgroundURLSession:)` automatically or if DictusApp needs AppDelegate integration
   - Recommendation: Test with default foreground download first; add background session in Plan 2.3 if needed

2. **Model storage location**
   - What we know: WhisperKit downloads to a default cache directory; App Group container is at `AppGroup.containerURL`
   - What's unclear: Whether WhisperKit can be configured to download directly into App Group container, or if files need manual relocation
   - Recommendation: Use WhisperKit's `modelFolder` config parameter pointing to App Group container subdirectory

3. **Prewarming duration on older devices**
   - What we know: 10-30 seconds claimed; memory-intensive for larger models
   - What's unclear: Exact duration on iPhone 12 (A14) for each model size
   - Recommendation: Show indeterminate progress during prewarm; benchmark on device during Plan 2.1

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in, already in use) |
| Config file | DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift (existing) |
| Quick run command | `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing DictusCoreTests` |
| Full suite command | `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STT-01 | French transcription produces text | integration (device) | Manual: requires microphone + WhisperKit model on device | No - Wave 0 |
| STT-02 | Filler words removed from output | unit | `xcodebuild test ... -only-testing DictusCoreTests/FillerWordFilterTests` | No - Wave 0 |
| STT-03 | Punctuation preserved | unit | `xcodebuild test ... -only-testing DictusCoreTests/FillerWordFilterTests` (verify filter preserves punctuation) | No - Wave 0 |
| STT-04 | Smart routing selects model by duration | unit | `xcodebuild test ... -only-testing DictusCoreTests/SmartModelRouterTests` | No - Wave 0 |
| STT-05 | Transcription under 3s for 10s audio | manual-only | Physical device benchmark (simulator has no Neural Engine) | N/A |
| APP-02 | Model manager download/select/delete | integration (device) | Manual: requires network + HuggingFace access | No - Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing DictusCoreTests`
- **Per wave merge:** Full test suite
- **Phase gate:** Full suite green + manual device test of recording + transcription

### Wave 0 Gaps
- [ ] `DictusCore/Tests/DictusCoreTests/FillerWordFilterTests.swift` -- covers STT-02, STT-03
- [ ] `DictusCore/Tests/DictusCoreTests/SmartModelRouterTests.swift` -- covers STT-04
- [ ] `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` -- covers APP-02 (model metadata)

Note: `FillerWordFilter` and `SmartModelRouter` should live in DictusCore (pure logic, no WhisperKit dependency) so they are unit-testable in the existing test target. WhisperKit integration itself requires device testing.

## Sources

### Primary (HIGH confidence)
- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit) - API methods, configuration, example app patterns
- [WhisperKit Configurations.swift](https://github.com/argmaxinc/whisperkit/blob/main/Sources/WhisperKit/Core/Configurations.swift) - WhisperKitConfig and DecodingOptions full property list
- [WhisperKit Releases](https://github.com/argmaxinc/WhisperKit/releases) - v0.16.0 is current stable (March 2025)
- [WhisperKit CoreML Models](https://huggingface.co/argmaxinc/whisperkit-coreml) - Complete model variant list with exact identifiers

### Secondary (MEDIUM confidence)
- [WhisperAX Example App](https://github.com/argmaxinc/WhisperKit/tree/main/Examples/WhisperAX) - Recording, model download, transcription patterns
- [WhisperKit Blog](https://www.argmaxinc.com/blog/whisperkit) - Architecture overview, Apple partnership context

### Tertiary (LOW confidence)
- AVAudioEngine 16 kHz conversion approach (from web articles) -- mitigated by using WhisperKit's AudioProcessor instead
- Model memory sizes (approximate, from various sources) -- recommend validating on device

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - WhisperKit API verified from source code and releases
- Architecture: HIGH - Patterns extracted from official WhisperAX example app
- Pitfalls: MEDIUM - Some pitfalls from community issues, some from API analysis
- Model sizes: MEDIUM - Approximate values, need device validation

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (WhisperKit stable, slow release cadence)
