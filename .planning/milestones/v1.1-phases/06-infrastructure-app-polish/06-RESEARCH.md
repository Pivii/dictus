# Phase 6: Infrastructure & App Polish - Research

**Researched:** 2026-03-07
**Domain:** Swift/SwiftUI design system consolidation, app icon generation, onboarding UX, visual bug fixes
**Confidence:** HIGH

## Summary

Phase 6 covers seven requirements across two domains: infrastructure (design file consolidation + app icon) and visual polish (HomeView bugs, onboarding blocking, test recording redesign). The codebase already has a working DictusCore local SPM package imported by both targets -- this is the natural home for shared design files. Six files are duplicated between DictusApp/Design/ and DictusKeyboard/Design/ with identical or near-identical content (minor comment differences only).

The onboarding flow currently uses TabView with .page style which allows free swiping between steps. Blocking progression requires disabling swipe gestures and controlling advancement programmatically. The HomeView bug (VIS-07) traces to `ModelManager.isModelReady` which depends on both `downloadedModels` being non-empty AND `activeModel` being non-nil -- the fix involves ensuring `loadState()` is called at the right time and the state is consistent after onboarding download.

**Primary recommendation:** Add design files to DictusCore as a `Design/` subdirectory (no new SPM package needed -- DictusCore already ships to both targets). Fix onboarding by replacing TabView paging with manual state machine. Redesign TestRecordingPage with immersive centered layout per user's Voice Memos reference.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Test recording & stop screens: Single shared screen for both onboarding (step 5) and HomeView. Immersive centered design with large mic button, waveform as ambient background. Transcription replaces waveform area with fade transition. Haptic feedback on mic tap.
- Onboarding model download: Auto-download "small" model, no user choice. Reword with clear French explanation + confirm button. Pre-load model (warmUp/loadModel) immediately after download so test recording step starts instantly.
- Keyboard added detection: Auto-detect via UITextInputMode.activeInputModes on foreground return.
- HomeView: Remove `.navigationTitle("Dictus")`. Fix modelManager.isModelReady bug. Display user-friendly model name ("Whisper Small") + size in MB.
- App icon: Generate from brand kit SVG. Adjust for 38pt readability.
- Design consolidation: 6 duplicated files to consolidate into shared package importable by both targets.

### Claude's Discretion
- Onboarding blocking UX: how strictly to block (disable swipe vs button-only), visual indication of incomplete steps
- App icon variant strategy (Light/Dark/Tinted)
- Design consolidation approach (DictusCore extension, new DictusUI SPM package, or other)
- Test recording screen layout details (exact spacing, animation timing)

### Deferred Ideas (OUT OF SCOPE)
- Mic start/stop sound effect -- future milestone
- Waveform at rest = perfectly still -- Phase 7 (VIS-03)
- Sinusoidal processing animation -- Phase 7 (VIS-03)
- Accuracy/speed gauges in model catalog -- Phase 10 (MOD-03)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-01 | Design files consolidated into shared DictusUI package | Move 6 duplicated design files + DictusLogo into DictusCore/Sources/DictusCore/Design/. Both targets already import DictusCore. |
| INFRA-02 | App icon generated from brand kit (SVG to PNG, adaptive light/dark) | Extract SVG from brand kit HTML, generate 1024x1024 PNG, create Contents.json with light/dark/tinted variants in xcassets |
| VIS-04 | Test recording screen in app redesigned | Redesign TestRecordingPage and TestDictationView as single shared immersive screen with centered mic + ambient waveform |
| VIS-05 | Recording stop screen redesigned | Same screen as VIS-04 -- transcription result replaces waveform with fade transition, matching Liquid Glass theme |
| VIS-06 | Duplicate "Dictus" navigation title removed | Remove `.navigationTitle("Dictus")` at HomeView.swift:42 -- logo section already serves as title |
| VIS-07 | Post-onboarding bug fixed -- HomeView shows correct state | Fix ModelManager state consistency: ensure isModelReady reflects reality after onboarding download completes |
| VIS-08 | Onboarding flow improved -- progression blocked until step completed | Replace TabView swipe paging with programmatic-only advancement, add visual step completion indicators |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 16+ | All UI views and design system | Already used throughout project |
| DictusCore | local SPM | Shared framework between App and Keyboard | Already imported by both targets -- natural home for shared design |
| WhisperKit | 0.16.0+ | Model download/warmUp/loadModel | Already integrated, needed for onboarding pre-load |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UIKit (UIImpactFeedbackGenerator) | iOS 16+ | Haptic feedback on mic tap | Test recording screen mic/stop button taps |
| AVFoundation | iOS 16+ | Audio session for recording | Existing -- used in test recording flow |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| DictusCore for design files | New DictusUI SPM package | Adds package management complexity with no benefit -- DictusCore already ships to both targets |
| Manual PNG generation | Xcode asset catalog SVG import | SVGs in asset catalogs work for simple shapes but the Dictus logo uses gradients and opacity that need explicit PNG rendering for pixel-perfect control at small sizes |

## Architecture Patterns

### Recommended Project Structure
```
DictusCore/
  Sources/DictusCore/
    Design/                  # NEW: shared design system
      DictusColors.swift
      DictusTypography.swift
      GlassModifier.swift
      AnimatedMicButton.swift
      BrandWaveform.swift
      ProcessingAnimation.swift
      DictusLogo.swift       # moved from DictusApp-only
    AppGroup.swift
    SharedKeys.swift
    ...existing files...

DictusApp/
  Design/                    # DELETED after consolidation
  Views/
    HomeView.swift           # VIS-06, VIS-07 fixes
    TestDictationView.swift  # REPLACED by shared RecordingView
  Onboarding/
    OnboardingView.swift     # VIS-08 blocking logic
    ModelDownloadPage.swift  # Pre-load after download
    TestRecordingPage.swift  # REPLACED by shared RecordingView

DictusKeyboard/
  Design/                    # DELETED after consolidation
```

### Pattern 1: Design System in Shared Framework
**What:** Move all design files (colors, typography, modifiers, components) into DictusCore so both targets import them from one source.
**When to use:** When both DictusApp and DictusKeyboard need the same UI components.
**Key consideration:** DictusCore currently has no SwiftUI import. Adding design files means DictusCore gains a SwiftUI dependency. This is fine -- keyboard extensions can use SwiftUI.

```swift
// DictusCore/Sources/DictusCore/Design/DictusColors.swift
// Same content as current file, just moved to DictusCore
import SwiftUI

extension Color {
    public static let dictusAccent = Color(hex: 0x3D7EFF)
    // ... all existing color definitions
    // IMPORTANT: must be `public` since they're now in a framework
}
```

### Pattern 2: Onboarding State Machine (replacing TabView paging)
**What:** Replace TabView(.page) with a custom step controller that only advances programmatically.
**When to use:** When steps have prerequisites that must be completed before advancing.

```swift
// Replace TabView with manual page switching
struct OnboardingView: View {
    @Binding var isComplete: Bool
    @SceneStorage("onboarding_currentPage") private var currentPage: Int = 0
    @State private var completedSteps: Set<Int> = []

    var body: some View {
        ZStack {
            Color.dictusBackground.ignoresSafeArea()

            // Show only the current page -- no TabView swiping
            Group {
                switch currentPage {
                case 0: WelcomePage(onNext: { advanceToPage(1) })
                case 1: MicPermissionPage(onNext: { advanceToPage(2) })
                case 2: KeyboardSetupPage(onNext: { advanceToPage(3) })
                case 3: ModelDownloadPage(onNext: { advanceToPage(4) })
                case 4: TestRecordingPage(onComplete: { isComplete = true })
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))

            // Step indicator dots at bottom
            stepIndicator
        }
    }
}
```

### Pattern 3: Immersive Recording Screen (Voice Memos-style)
**What:** Centered mic button with ambient waveform behind it, transcription fades in replacing waveform.
**When to use:** Both onboarding test recording (step 5) and HomeView "Tester la dictee" button.

```swift
// Single shared view used from both contexts
struct RecordingView: View {
    let mode: RecordingMode // .onboarding or .standalone
    let onComplete: (() -> Void)?

    @EnvironmentObject var coordinator: DictationCoordinator

    var body: some View {
        ZStack {
            // Ambient waveform as full background
            if coordinator.status == .recording {
                BrandWaveform(energyLevels: coordinator.bufferEnergy, maxHeight: 200)
                    .opacity(0.3) // ambient, not dominant
            }

            VStack {
                Spacer()

                // Transcription result (fades in, replacing waveform)
                if let result = transcriptionResult {
                    Text(result)
                        .transition(.opacity)
                }

                Spacer()

                // Large centered mic button
                micButton
                    .padding(.bottom, 60)
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Separate DictusUI package:** Creating a third SPM package adds dependency management overhead. DictusCore is already shared -- use it.
- **Keeping design file copies "for safety":** Delete the duplicates in DictusApp/Design/ and DictusKeyboard/Design/ completely. Any remaining reference will fail to compile, making leftover references immediately visible.
- **Using TabView with disabled gestures:** TabView's gesture disabling is unreliable across iOS versions. A manual switch/case approach is simpler and fully controllable.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Haptic feedback | Custom AudioServicesPlaySystemSound | UIImpactFeedbackGenerator (.medium) | Already used in project via DictusCore/HapticFeedback.swift |
| App icon sizes | Manual scaling/exporting | Script that generates all sizes from 1024x1024 source | Apple requires specific sizes; manual resizing is error-prone |
| Step indicator dots | Custom dot view from scratch | Simple HStack of Circle views with opacity | 5-10 lines of SwiftUI, no need for a library |
| Model display name | String parsing of identifier | ModelInfo.forIdentifier()?.displayName | Already exists in DictusCore/ModelInfo.swift |

**Key insight:** ModelInfo already has `displayName` ("Small", "Base", etc.) and `sizeLabel` ("~250 MB"). The HomeView model card just needs to use `ModelInfo.forIdentifier(activeModelName)` instead of displaying the raw identifier string.

## Common Pitfalls

### Pitfall 1: Access Control After Moving to Framework
**What goes wrong:** Moving files from app target to DictusCore framework but forgetting to add `public` access modifiers. Everything compiles in the framework but callers get "inaccessible due to internal protection level" errors.
**Why it happens:** Swift defaults to `internal` access. Files in the app target don't need `public` because everything is in the same module. Framework code must be `public` to be visible to importers.
**How to avoid:** After moving each file, add `public` to: all Color extensions, all Font extensions, all View extensions (dictusGlass), all struct declarations (AnimatedMicButton, BrandWaveform, etc.), all init methods.
**Warning signs:** Build errors mentioning "internal protection level" after the move.

### Pitfall 2: ModelManager State After Onboarding Download
**What goes wrong:** User completes onboarding, model downloads successfully, but HomeView still shows "Telecharger un modele" card because `ModelManager.isModelReady` returns false.
**Why it happens:** The onboarding `ModelDownloadPage` creates its own `@StateObject private var modelManager = ModelManager()` -- a separate instance from the one `HomeView` uses. The download completes in the onboarding instance, but the HomeView instance still has stale state.
**How to avoid:** Either (a) share a single ModelManager instance via @EnvironmentObject throughout the app, or (b) ensure HomeView's ModelManager calls `loadState()` on appear. Option (a) is cleaner.
**Warning signs:** `isModelReady` returns false despite model files existing on disk.

### Pitfall 3: DictusCore SwiftUI Import Breaking Keyboard Extension
**What goes wrong:** Adding `import SwiftUI` to DictusCore files could theoretically cause issues in keyboard extension context.
**Why it happens:** Keyboard extensions have restricted APIs (no UIApplication.shared). SwiftUI itself is allowed, but some UIKit bridging code might not work.
**How to avoid:** The existing design files already use `import SwiftUI` and `import UIKit` (for UIColor bridging in DictusColors.swift). They already work in the keyboard extension target. No issue here -- the keyboard already has copies of these files.
**Warning signs:** None expected -- this is a non-issue based on the existing working copies.

### Pitfall 4: Onboarding @SceneStorage Persistence After Refactor
**What goes wrong:** Replacing TabView with switch/case could break @SceneStorage("onboarding_currentPage") persistence.
**Why it happens:** @SceneStorage works at the view identity level. If the view hierarchy changes significantly, stored values might not restore correctly.
**How to avoid:** Keep the same @SceneStorage key and ensure the OnboardingView struct identity is stable (same type, same position in hierarchy).
**Warning signs:** User returns from Settings and gets sent back to step 1.

### Pitfall 5: App Icon Rendering at Small Sizes
**What goes wrong:** The 3-bar Dictus logo is designed at 42pt+ heights. At 38pt (home screen icon size on smaller iPhones), the bars become indistinct.
**Why it happens:** The logo has thin bars (variable widths) with subtle opacity differences that blur at low resolution.
**How to avoid:** Generate the icon at 1024x1024 with slightly thicker bars and higher opacity for the side bars. Test at 60x60pt (smallest rendered size @3x = 180px) to verify readability.
**Warning signs:** Bars merge visually or side bars become invisible on the home screen.

## Code Examples

### Moving Design Files: Access Control Fix
```swift
// BEFORE (in DictusApp target -- internal access is fine):
extension Color {
    static let dictusAccent = Color(hex: 0x3D7EFF)
}

// AFTER (in DictusCore framework -- must be public):
extension Color {
    public static let dictusAccent = Color(hex: 0x3D7EFF)

    public init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    public init(light: Color, dark: Color) {
        // ... same implementation, just public
    }
}
```

### HomeView Model Name Fix (VIS-07)
```swift
// Use ModelInfo.forIdentifier to get human-readable name
private var modelStatusCard: some View {
    if modelManager.isModelReady, let modelName = activeModelName {
        let info = ModelInfo.forIdentifier(modelName)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Modele actif")
                    .font(.dictusCaption)
                    .foregroundColor(.secondary)
                // Display "Whisper Small" instead of "openai_whisper-small"
                Text("Whisper \(info?.displayName ?? modelName)")
                    .font(.dictusSubheading)
                if let size = info?.sizeLabel {
                    Text(size)
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.dictusSuccess)
        }
        .padding()
        .dictusGlass()
    }
}
```

### Onboarding Model Pre-Load After Download
```swift
// In ModelDownloadPage -- after download, immediately warmUp/loadModel
private func startDownload() {
    isDownloading = true
    Task {
        do {
            try await modelManager.downloadModel(recommendedModel)
            downloadComplete = true
            isDownloading = false
            // Model is already prewarmed by downloadModel() -- it calls WhisperKit(config)
            // with prewarm: true, load: true. No additional warmUp call needed.
            // DO NOT auto-advance -- let user see completion, then tap "Continuer"
        } catch {
            errorMessage = error.localizedDescription
            isDownloading = false
        }
    }
}
```

### App Icon Contents.json Structure
```json
{
  "images": [
    {
      "filename": "AppIcon-1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    },
    {
      "appearances": [
        { "appearance": "luminosity", "value": "dark" }
      ],
      "filename": "AppIcon-1024-dark.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    },
    {
      "appearances": [
        { "appearance": "luminosity", "value": "tinted" }
      ],
      "filename": "AppIcon-1024-tinted.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Copy design files per target | Shared framework/package | Swift Package Manager standard | Single source of truth for UI components |
| TabView(.page) for onboarding | Custom step navigation | Common iOS pattern | Full control over step progression |
| Multiple icon sizes in asset catalog | Single 1024x1024 source | iOS 12+ (single size) | Xcode auto-generates all needed sizes |
| Light-only app icon | Light + Dark + Tinted variants | iOS 18+ | Matches system appearance automatically |

**iOS 18 app icon variants:** Since iOS 18, Xcode supports light/dark/tinted icon variants in the asset catalog. The `Contents.json` format uses `appearances` array with `luminosity` values. On older iOS, only the default (light) variant is shown. This is current best practice.

## Open Questions

1. **WhisperKit pre-load timing during onboarding**
   - What we know: `downloadModel()` already calls `WhisperKit(config)` with `prewarm: true, load: true` -- the model IS loaded after download completes
   - What's unclear: Whether DictationCoordinator (which also initializes WhisperKit) will pick up this pre-loaded instance or create a new one
   - Recommendation: Verify DictationCoordinator reads the active model from App Group defaults and initializes with the same model. If it creates a new WhisperKit instance, the pre-load benefit is limited to CoreML compilation cache (still valuable -- eliminates the 10-30s first-use delay).

2. **Asset catalog creation**
   - What we know: No .xcassets directory exists yet for DictusApp (confirmed by search)
   - What's unclear: Where the Xcode project expects assets -- there may be an xcassets referenced in the project file that was deleted
   - Recommendation: Create `DictusApp/Assets.xcassets/AppIcon.appiconset/` and add to the Xcode project. Verify the Xcode project's ASSETCATALOG_COMPILER_APPICON_NAME build setting.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual validation (no automated test framework configured) |
| Config file | none |
| Quick run command | `xcodebuild build -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet` |
| Full suite command | Same as quick run (no tests exist) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | Design files compile from DictusCore, no duplicates remain | build | `xcodebuild build -scheme DictusApp -quiet && xcodebuild build -scheme DictusKeyboard -quiet` | N/A -- build verification |
| INFRA-02 | App icon renders in simulator | manual | Launch in simulator, check home screen | N/A -- visual check |
| VIS-04 | Test recording screen matches design spec | manual | Navigate to test recording, verify layout | N/A -- visual check |
| VIS-05 | Recording stop shows transcription with fade | manual | Record, stop, verify transition | N/A -- visual check |
| VIS-06 | No duplicate "Dictus" title | manual | Open app, verify single title | N/A -- visual check |
| VIS-07 | Model card shows correct state post-onboarding | manual | Complete onboarding, verify HomeView | N/A -- state check |
| VIS-08 | Cannot skip onboarding steps | manual | Try swiping past incomplete step | N/A -- UX check |

### Sampling Rate
- **Per task commit:** `xcodebuild build -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
- **Per wave merge:** Build both schemes + manual visual check
- **Phase gate:** Both targets build clean, all visual requirements verified manually

### Wave 0 Gaps
- None -- this phase is UI-focused with no unit-testable logic. Build verification and manual visual checks are the appropriate validation method.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: All 6 duplicated design files verified identical (diff confirmed)
- DictusCore/Package.swift: Confirmed local SPM package structure already importable by both targets
- ModelManager.swift: Confirmed `downloadModel()` already prewarms with `WhisperKit(config)` where `prewarm: true, load: true`
- ModelInfo.swift: Confirmed `displayName` and `sizeLabel` already exist for human-readable model names
- Xcode project file: Confirmed DictusCore is a dependency of both DictusApp and DictusKeyboard targets

### Secondary (MEDIUM confidence)
- iOS 18 app icon variants: Based on Apple documentation for Xcode 15+/iOS 18+ asset catalog format with light/dark/tinted appearances

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries already in use, no new dependencies
- Architecture: HIGH - consolidation approach validated by existing DictusCore integration pattern
- Pitfalls: HIGH - identified from direct codebase analysis (access control, ModelManager instances, state persistence)

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- no external dependencies changing)
