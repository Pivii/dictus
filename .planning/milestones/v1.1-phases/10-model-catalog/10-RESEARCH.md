# Phase 10: Model Catalog - Research

**Researched:** 2026-03-10
**Domain:** On-device speech recognition models (WhisperKit + Parakeet/FluidAudio), model catalog UI
**Confidence:** MEDIUM

## Summary

Phase 10 involves three distinct work streams: (1) cleaning up the WhisperKit model catalog by removing underperforming tiny/base models and re-evaluating large-v3-turbo, (2) integrating NVIDIA Parakeet v3 as an alternative STT engine via FluidAudio SDK behind a SpeechModel protocol abstraction, and (3) redesigning the model selection UI with gauge-based metadata and engine badges.

The WhisperKit catalog cleanup is straightforward -- the codebase already has `ModelInfo.all` as a single source of truth. The Parakeet integration is the highest-risk item: FluidAudio (v0.12.3, March 2025) is a young SDK requiring iOS 17+, while Dictus targets iOS 16+. The FluidAudio API is clean (`AsrManager.transcribe()`) but French accuracy is unverified, and the 0.6B parameter model will be significantly larger than WhisperKit small (~250MB). The user explicitly accepted that Parakeet may need to be deferred if FluidAudio proves unstable.

**Primary recommendation:** Start with catalog cleanup + UI redesign (low risk, high value), then attempt Parakeet integration with a clear go/no-go gate after French accuracy testing. Keep the SpeechModel protocol only if Parakeet ships; otherwise remove the abstraction to avoid unnecessary complexity.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Remove Tiny and Base from catalog -- both confirmed bad for French dictation
- Keep Small and Medium as WhisperKit offerings
- Already-downloaded Tiny/Base keep working but can't be re-downloaded (soft deprecation)
- Re-test large-v3-turbo -- was removed early in project due to ANE compilation issue, but codebase is now stable; worth retrying
- Research newer WhisperKit model variants (distil, turbo fixes, etc.) during phase research
- Recommended default: deferred to after benchmarking all final models
- Full Parakeet integration attempted (SpeechModel protocol + FluidAudio runtime + downloadable in catalog)
- If FluidAudio SDK proves unstable or French accuracy is poor: defer to v1.2, don't block the phase
- Languages: fr/en only for all engines (no new languages in this phase)
- Layout: "Telecharges" / "Disponibles" sections (like Handy app reference)
- Engine badge on each model card (WK/PK) rather than engine-based sections
- Gauge bars for accuracy and speed replacing text labels
- Short description per model
- Taille en MB visible sur tous les modeles
- Engine description paragraphs

### Claude's Discretion
- SpeechModel protocol design (keep or remove if Parakeet fails -- evaluate based on added complexity)
- Exact section layout (Downloaded/Available vs Engine-first -- user said "fais au mieux")
- Gauge bar visual design (colors, scale, number of segments)
- Model description copywriting
- SmartModelRouter cleanup (currently bypassed -- decide whether to remove or update)

### Deferred Ideas (OUT OF SCOPE)
- Multi-language support beyond fr/en
- Device-adaptive model recommendation (WhisperKit.recommendedModels())
- Background download sessions (URLSession background)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MOD-01 | Model catalog cleaned -- remove underperforming models (tiny/base if confirmed unhelpful) | WhisperKit model variant research; soft deprecation pattern for already-downloaded models; new candidates (large-v3-turbo, distil-large-v3) |
| MOD-02 | Parakeet v3 integrated as alternative STT option (SpeechModel protocol + FluidAudio runtime) | FluidAudio SDK API research (AsrManager), iOS 17+ requirement risk, SpeechModel protocol design pattern |
| MOD-03 | Model selection UI updated to display both engines (WhisperKit + Parakeet) | Gauge bar UI patterns, Downloaded/Available section layout, engine badge design |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WhisperKit | 0.16.0+ (already in project) | On-device Whisper STT via CoreML | Already integrated, proven, actively maintained by Argmax |
| FluidAudio | 0.12.3 | On-device Parakeet STT via CoreML | Only Swift SDK for Parakeet CoreML models; actively maintained |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI (native) | iOS 16+ | Gauge bar UI, model cards | All UI work |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FluidAudio | Raw CoreML + custom pipeline | Much more work; FluidAudio handles model download, compilation, and inference |
| Gauge view (custom) | SwiftUI Gauge (iOS 16+) | Native Gauge is too limited for the Handy-style visual; custom view needed |

### Installation

FluidAudio SPM (add to Xcode project, NOT DictusCore Package.swift since it depends on CoreML/AVFoundation):
```swift
// In Xcode: File > Add Package Dependencies
// URL: https://github.com/FluidInference/FluidAudio.git
// Version: from "0.12.3"
```

## Architecture Patterns

### Recommended Project Structure
```
DictusCore/Sources/DictusCore/
├── ModelInfo.swift          # Extended with engine type, gauge values, descriptions
├── SpeechEngine.swift       # NEW: Engine enum (.whisperKit, .parakeet)
├── SharedKeys.swift         # Add activeEngine key

DictusApp/
├── Audio/
│   ├── TranscriptionService.swift    # Refactored to use SpeechModel protocol
│   ├── WhisperKitEngine.swift        # NEW: WhisperKit conformance to SpeechModel
│   └── ParakeetEngine.swift          # NEW: FluidAudio conformance to SpeechModel
├── Models/
│   ├── ModelManager.swift            # Extended for multi-engine download/select
│   └── ModelCatalog.swift            # NEW: Static catalog with all available models
├── Views/
│   ├── ModelManagerView.swift        # Redesigned with gauges + sections
│   ├── ModelCardView.swift           # NEW: Individual model card with gauge bars
│   └── GaugeBarView.swift            # NEW: Reusable gauge component
```

### Pattern 1: SpeechModel Protocol
**What:** Protocol abstraction allowing multiple STT engines behind a common interface
**When to use:** Only if Parakeet integration succeeds; otherwise keep direct WhisperKit usage
**Example:**
```swift
// DictusApp/Audio/SpeechModel.swift
protocol SpeechModel {
    /// Human-readable engine name for UI
    var engineName: String { get }

    /// Prepare the engine with a specific model
    func prepare(modelIdentifier: String) async throws

    /// Transcribe audio samples to text
    func transcribe(audioSamples: [Float], language: String) async throws -> String

    /// Whether the engine is ready for transcription
    var isReady: Bool { get }
}
```

### Pattern 2: Soft Deprecation for Downloaded Models
**What:** Models removed from catalog but still functional if already downloaded
**When to use:** For tiny/base models that users may have downloaded
**Example:**
```swift
// In ModelInfo
public enum CatalogVisibility {
    case available      // Shown in catalog, can download
    case deprecated     // Not shown in catalog, but works if already downloaded
}

public let visibility: CatalogVisibility

// ModelInfo.all returns only .available models
// ModelInfo.allIncludingDeprecated returns everything (for downloaded model display)
```

### Pattern 3: Engine-Aware ModelInfo
**What:** Extend ModelInfo with engine type and numeric gauge values
**Example:**
```swift
public struct ModelInfo: Identifiable {
    public var id: String { identifier }

    public let identifier: String
    public let displayName: String
    public let engine: SpeechEngine        // NEW
    public let sizeBytes: Int64
    public let accuracyScore: Double       // NEW: 0.0-1.0 for gauge
    public let speedScore: Double          // NEW: 0.0-1.0 for gauge
    public let description: String         // NEW: short French description
    public let visibility: CatalogVisibility // NEW
}

public enum SpeechEngine: String, Codable {
    case whisperKit = "WK"
    case parakeet = "PK"
}
```

### Anti-Patterns to Avoid
- **Engine-specific UI branches everywhere:** Use the SpeechEngine enum on ModelInfo, not if/else chains in views
- **Breaking DictationCoordinator for multi-engine:** Keep DictationCoordinator engine-agnostic; it already uses TranscriptionService which is the right abstraction point
- **Storing engine selection separately from model:** The model identifier already implies the engine; don't create a separate "activeEngine" setting that can desync

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Parakeet model download + CoreML compilation | Custom HuggingFace downloader + CoreML pipeline | FluidAudio `AsrModels.downloadAndLoad()` | Handles caching, recompilation, error recovery |
| WhisperKit model download | Custom downloader | `WhisperKit.download(variant:from:progressCallback:)` | Already working in codebase |
| Model compatibility checking | Device capability detection | WhisperKit.recommendedModels() for WK; test-and-fallback for Parakeet | Deferred per user decision, but don't build custom detection |

## Common Pitfalls

### Pitfall 1: FluidAudio iOS 17+ vs Dictus iOS 16 Target
**What goes wrong:** FluidAudio requires iOS 17+. Dictus targets iOS 16.
**Why it happens:** FluidAudio uses CoreML APIs only available on iOS 17+.
**How to avoid:** Use `@available(iOS 17.0, *)` guards around ALL FluidAudio code. Parakeet models should only appear in the catalog on iOS 17+ devices. On iOS 16, only WhisperKit models are shown.
**Warning signs:** Build errors or runtime crashes on iOS 16 devices.

### Pitfall 2: ANE Compilation Conflicts Between Engines
**What goes wrong:** WhisperKit and FluidAudio both compile CoreML models on the Neural Engine. Simultaneous compilation crashes ANE.
**Why it happens:** The project already has a serial prewarm lock for WhisperKit models, but FluidAudio has its own compilation path.
**How to avoid:** Never run WhisperKit prewarm and FluidAudio model load simultaneously. Serialize all ANE compilation. Consider a shared lock or sequential initialization.
**Warning signs:** "E5 bundle" ANE errors during model switching.

### Pitfall 3: Parakeet Model Size Unknown
**What goes wrong:** The Parakeet 0.6B parameter model could be 600MB-1.2GB on device, much larger than expected.
**Why it happens:** CoreML model sizes depend on quantization; FluidAudio docs don't publish explicit sizes.
**How to avoid:** Test actual download size on first integration attempt. If > 1GB, this may be impractical for many users. Document size in the model card honestly.
**Warning signs:** User runs out of storage; download takes too long.

### Pitfall 4: Breaking Onboarding Model Download
**What goes wrong:** `ModelDownloadPage` hardcodes `"openai_whisper-small"` and `ModelInfo.all`. Changing the catalog breaks onboarding.
**Why it happens:** Onboarding references `ModelInfo.all` indirectly through `ModelManager`.
**How to avoid:** Ensure `ModelInfo.all` still contains `openai_whisper-small` (it will -- we're keeping Small). Verify onboarding flow after catalog changes.
**Warning signs:** New users can't complete onboarding.

### Pitfall 5: SmartModelRouter References Removed Models
**What goes wrong:** SmartModelRouter.fastModels references tiny/base, which will be removed from the catalog.
**Why it happens:** SmartModelRouter is already bypassed but still compiled.
**How to avoid:** Remove SmartModelRouter entirely (it's bypassed per project decision) or update its model lists. Recommendation: **remove it** -- it was causing bugs (see MEMORY.md) and is marked as out of scope in REQUIREMENTS.md.

### Pitfall 6: Already-Downloaded Deprecated Models Display
**What goes wrong:** Users who have tiny/base downloaded see them in the model list but can't re-download after deletion.
**Why it happens:** Soft deprecation requires showing downloaded models even if not in the catalog.
**How to avoid:** Display logic must check both `ModelInfo.allIncludingDeprecated` (for downloaded models) and `ModelInfo.all` (for available downloads). Use the CatalogVisibility enum pattern above.

## Code Examples

### FluidAudio Transcription (from official docs)
```swift
// Source: https://github.com/FluidInference/FluidAudio
import FluidAudio

// Download and load Parakeet v3 models
let models = try await AsrModels.downloadAndLoad(version: .v3)

// Initialize ASR manager
let asrManager = AsrManager(config: .default)
try await asrManager.initialize(models: models)

// Transcribe audio samples (same [Float] format as WhisperKit)
let result = try await asrManager.transcribe(audioSamples)
let text = result.text
```

### Gauge Bar View Pattern
```swift
// Custom gauge bar inspired by Handy app
struct GaugeBarView: View {
    let value: Double  // 0.0 to 1.0
    let label: String
    let color: Color
    let segments: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Double(index) / Double(segments) < value
                              ? color
                              : color.opacity(0.15))
                        .frame(height: 6)
                }
            }
        }
    }
}
```

### Soft Deprecation Filter
```swift
// In ModelManagerView, show downloaded models even if deprecated
let downloadedModels = ModelInfo.allIncludingDeprecated
    .filter { modelManager.downloadedModels.contains($0.identifier) }

let availableModels = ModelInfo.all
    .filter { !modelManager.downloadedModels.contains($0.identifier) }
```

## State of the Art

### WhisperKit Available Models (as of March 2026)
| Model | Identifier | Size | Notes |
|-------|-----------|------|-------|
| ~~Tiny~~ | openai_whisper-tiny | ~40 MB | REMOVE from catalog (bad French) |
| ~~Base~~ | openai_whisper-base | ~75 MB | REMOVE from catalog (bad French) |
| Small | openai_whisper-small | ~250 MB | KEEP - good balance |
| Small (quantized) | openai_whisper-small_216MB | ~216 MB | NEW candidate - smaller, worth testing |
| Medium | openai_whisper-medium | ~750 MB | KEEP - best WhisperKit accuracy |
| Large-v3-turbo | openai_whisper-large-v3-turbo | ~954 MB | RE-TEST - ANE issue may be resolved |
| Large-v3 (Sept 2024) | openai_whisper-large-v3-v20240930 | varies | NEW candidate - newer Whisper release |
| Large-v3 (Sept, quantized) | openai_whisper-large-v3-v20240930_547MB | ~547 MB | NEW candidate - compact large model |
| Distil-large-v3 | distil-whisper_distil-large-v3 | varies | NEW candidate - distilled, faster |
| Distil-large-v3 turbo | distil-whisper_distil-large-v3_turbo | ~600 MB | NEW candidate - distilled + turbo |

**Key insight:** The `openai_whisper-large-v3-v20240930` variant is a newer Whisper checkpoint (September 2024) that was not available when Dictus started. The 547MB quantized version could be an excellent addition -- large model accuracy at medium model size. The distil variants are also worth testing as they trade minimal accuracy for significant speed gains.

### FluidAudio / Parakeet Status
| Property | Value |
|----------|-------|
| SDK Version | 0.12.3 (March 8, 2025) |
| Model | Parakeet TDT 0.6B v3 |
| Parameters | 600M |
| Languages | 25 European (incl. French) |
| iOS Minimum | 17.0 |
| Performance | ~0.02x RTF (50x faster than real-time) |
| French WER | Unknown -- not published, needs testing |
| Model size on disk | Unknown -- needs testing (estimate: 600MB-1.2GB based on 0.6B params) |

**Risk assessment:** FluidAudio is actively maintained (latest release 8 days ago) but is a v0.x SDK. French accuracy is completely unverified. The iOS 17+ requirement means iOS 16 users cannot use Parakeet. The model download size is unknown and could be prohibitively large.

### Recommendation: SmartModelRouter Cleanup
SmartModelRouter should be **removed entirely**:
1. It was causing bugs that broke background recording (per MEMORY.md)
2. It references tiny/base models being removed
3. It's explicitly listed as out of scope in REQUIREMENTS.md ("Smart Model Routing at runtime")
4. It's currently bypassed in DictationCoordinator (user selects model once)

Remove `SmartModelRouter.swift` and `SmartModelRouterTests.swift` from DictusCore.

## Open Questions

1. **Parakeet model download size on iOS**
   - What we know: 0.6B parameter model, CoreML format
   - What's unclear: Actual file size after CoreML compilation; whether it fits comfortably alongside WhisperKit models
   - Recommendation: Test during implementation; if > 1GB, flag to user clearly

2. **Parakeet French accuracy**
   - What we know: Supports 25 European languages including French
   - What's unclear: WER for French dictation compared to WhisperKit small/medium
   - Recommendation: First implementation task should be a comparison test; if WER is significantly worse, defer per user decision

3. **large-v3-turbo ANE status**
   - What we know: ANE compilation was failing early in the project; WhisperKit has since shipped optimizations (45% latency reduction per ICML 2025 paper)
   - What's unclear: Whether the specific E5 bundle crash is fixed on target iPhone models
   - Recommendation: Re-test on physical device early in the phase; if it works, add to catalog as premium option

4. **FluidAudio iOS 16 compatibility**
   - What we know: FluidAudio requires iOS 17+; Dictus targets iOS 16
   - What's unclear: Whether importing FluidAudio via SPM breaks compilation for iOS 16 target
   - Recommendation: Use `#if canImport(FluidAudio)` or conditional SPM dependency. May need to make FluidAudio an optional import that only compiles on iOS 17+. Alternatively, wrap all Parakeet code in availability checks.

5. **Gauge values for models**
   - What we know: User wants gauge bars for accuracy and speed
   - What's unclear: Exact numeric values to assign (no official WER benchmarks per model for French)
   - Recommendation: Use relative scores based on model architecture knowledge: tiny 0.3/1.0, base 0.4/0.9, small 0.6/0.7, medium 0.8/0.4, large-v3-turbo 0.9/0.6. Refine after benchmarking.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (already configured in DictusCore) |
| Config file | DictusCore/Package.swift (test target exists) |
| Quick run command | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test --filter ModelInfoTests` |
| Full suite command | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MOD-01 | Catalog contains only performant models | unit | `swift test --filter ModelInfoTests` | Exists but needs update (currently asserts 4 models) |
| MOD-01 | Deprecated models still resolve by identifier | unit | `swift test --filter ModelInfoTests` | Wave 0 |
| MOD-02 | SpeechEngine enum has whisperKit and parakeet cases | unit | `swift test --filter SpeechEngineTests` | Wave 0 |
| MOD-02 | Parakeet transcription produces text (integration) | manual-only | Manual: requires FluidAudio model download + audio input | N/A |
| MOD-03 | All visible models have gauge values in valid range | unit | `swift test --filter ModelInfoTests` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test --filter ModelInfoTests`
- **Per wave merge:** `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Update `ModelInfoTests.swift` -- currently asserts 4 models, needs update for new catalog
- [ ] `SpeechEngineTests.swift` -- covers SpeechEngine enum if created
- [ ] No new framework install needed -- XCTest already configured

## Sources

### Primary (HIGH confidence)
- WhisperKit CoreML model list: [HuggingFace argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main) -- all available model variants
- FluidAudio GitHub: [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) -- SDK API, installation, version
- FluidAudio releases: [GitHub Releases](https://github.com/FluidInference/FluidAudio/releases) -- v0.12.3 March 8, 2025
- Parakeet v3 CoreML: [HuggingFace FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- Existing codebase: ModelInfo.swift, ModelManager.swift, TranscriptionService.swift, DictationCoordinator.swift

### Secondary (MEDIUM confidence)
- WhisperKit ICML 2025 paper: [arxiv](https://arxiv.org/html/2507.10860v1) -- large-v3-turbo ANE optimizations
- FluidAudio DeepWiki: [DeepWiki](https://deepwiki.com/FluidInference/FluidAudio) -- API details, model download flow
- FluidAudio Swift Package Index: [SPI](https://swiftpackageindex.com/FluidInference/FluidAudio) -- iOS 17+ requirement

### Tertiary (LOW confidence)
- Parakeet French accuracy -- no published WER benchmarks found; needs real-device testing
- Parakeet model size on iOS -- estimated 600MB-1.2GB based on parameter count; needs verification
- large-v3-turbo ANE fix status -- inferred from paper optimizations; needs device testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- WhisperKit proven, FluidAudio API verified via official docs
- Architecture: MEDIUM -- SpeechModel protocol is standard pattern, but multi-engine complexity untested in this codebase
- Pitfalls: HIGH -- identified from existing codebase analysis and known iOS constraints
- Parakeet feasibility: LOW -- French accuracy and model size are unknown; iOS 17 requirement is a real constraint

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (30 days -- FluidAudio is actively releasing; check for new versions)
