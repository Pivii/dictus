# Phase 4: Main App, Onboarding, and Polish - Research

**Researched:** 2026-03-06
**Domain:** SwiftUI app architecture, onboarding flows, iOS 26 Liquid Glass design system, animations
**Confidence:** HIGH

## Summary

Phase 4 is primarily a design and UX overhaul. The existing codebase has all functional pieces (recording, transcription, model management, keyboard) working end-to-end. This phase restructures the main app into TabView navigation, adds a guided onboarding flow, creates a Settings screen, applies iOS 26 Liquid Glass styling throughout, and redesigns the recording waveform and mic button animations to match brand identity.

iOS 26 introduces `.glassEffect()` as the core Liquid Glass API. TabView gets automatic Liquid Glass styling on iOS 26. For iOS 16-25 fallback, a custom view modifier wraps `#available(iOS 26, *)` with `Material.regularMaterial` or `.ultraThinMaterial` as the fallback. The onboarding flow uses `TabView` with `.tabViewStyle(.page)` for swipeable pages with programmatic navigation control. Keyboard detection on return from Settings uses `UITextInputMode.activeInputModes` polling.

**Primary recommendation:** Build a reusable `GlassModifier` view modifier once (glass on iOS 26, Material fallback on older), then apply consistently across all surfaces. Structure onboarding as a non-dismissible fullscreen cover gated on `@AppStorage("hasCompletedOnboarding")`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- 5-step fullscreen onboarding: Welcome -> Microphone -> Keyboard+FullAccess -> Download Model -> Test Transcription
- TabBar with 3 tabs: Home, Models, Settings
- Home tab: Dashboard with logo mark, active model status, last transcription preview, test dictation quick action
- Models tab: Existing ModelManagerView as-is
- Settings: 3 sections (Transcription, Clavier, A propos) -- NO model selector in Settings
- Diagnostic view moved from Home to Settings > A propos > Diagnostic
- Recording waveform redesign: 3-bar logo-inspired waveform (heights respond to audio energy, center bar accent gradient, side bars white opacity)
- Mic button animations: idle glow (blue), recording pulse (red), transcribing shimmer (blue), success flash (green)
- `.glassEffect()` on iOS 26 with `Material.regularMaterial` fallback on iOS 16-25
- Glass on: TabBar, navigation bars, cards/sections, onboarding pages, keyboard container
- SF Pro Rounded for headings, SF Pro Text for body, Dynamic Type throughout
- Light and dark mode automatic -- no hardcoded colors
- Languages limited to French + English for v1
- Onboarding non-dismissible on first launch
- RecordingView hides TabBar -- fullscreen overlay

### Claude's Discretion
- Exact onboarding page transitions and animation timing
- Screenshot asset creation for keyboard setup step
- Auto-detection mechanism for keyboard installation
- TabBar icon choices (SF Symbols)
- Settings row styling details
- Glass effect intensity and blur radius
- Exact spring animation parameters for waveform
- How to handle onboarding "skip" if user has already set up keyboard from a previous install

### Deferred Ideas (OUT OF SCOPE)
- Step-by-step onboarding animations (Remotion/Lottie)
- Smart mode mic button state (purple #8B5CF6)
- All WhisperKit languages beyond French + English
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-01 | Onboarding guides user through mic permission, keyboard addition, Full Access, model download | Onboarding architecture with TabView page style, permission APIs, keyboard detection, Settings deep-link |
| APP-03 | Settings screen for transcription language, keyboard layout, filler word toggle, haptic toggle | iOS-style grouped List with picker/toggle patterns, App Group UserDefaults persistence via SharedKeys |
| KBD-06 | Keyboard uses iOS 26 Liquid Glass design | GlassModifier with #available fallback, keyboard container glass styling |
| DSN-01 | All UI surfaces use iOS 26 Liquid Glass material | GlassModifier, GlassEffectContainer, TabView automatic glass, navigation bar glass |
| DSN-02 | Mic button animated states (idle glow, recording pulse, transcribing shimmer) | SwiftUI animation patterns, spring animations, overlay pulse rings |
| DSN-03 | Light and dark mode supported automatically | Color asset catalogs, semantic colors, no hardcoded Color literals |
| DSN-04 | SF Pro Rounded headings, SF Pro Text body, Dynamic Type | `.font(.system(.title, design: .rounded))`, Dynamic Type text styles, @ScaledMetric |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 16+ | All UI rendering | Project standard, already used throughout |
| UIKit (bridged) | iOS 16+ | Permission APIs, keyboard detection | Required for AVAudioSession, UITextInputMode |
| DictusCore | local SPM | SharedKeys, shared types | Existing shared framework |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AVFoundation | iOS 16+ | Microphone permission request | Onboarding step 2 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| TabView(.page) for onboarding | ScrollView + ScrollPosition (iOS 18+) | TabView(.page) works on iOS 16+, ScrollPosition requires iOS 18 minimum -- TabView is correct for this project |
| Custom glass modifier | Raw .background(Material) everywhere | Custom modifier centralizes the iOS 26 availability check -- always use the modifier |

**No new dependencies required.** This phase uses only SwiftUI, UIKit bridging, and existing DictusCore.

## Architecture Patterns

### Recommended Project Structure
```
DictusApp/
├── DictusApp.swift              # App entry, TabView or Onboarding gate
├── ContentView.swift            # REPLACED: becomes TabView with 3 tabs
├── Onboarding/
│   ├── OnboardingView.swift     # Page container with TabView(.page)
│   ├── WelcomePage.swift        # Step 1: animated logo
│   ├── MicPermissionPage.swift  # Step 2: microphone permission
│   ├── KeyboardSetupPage.swift  # Step 3: keyboard + full access
│   ├── ModelDownloadPage.swift  # Step 4: model download
│   └── TestRecordingPage.swift  # Step 5: test transcription
├── Views/
│   ├── HomeView.swift           # Tab 1: dashboard
│   ├── SettingsView.swift       # Tab 3: grouped list
│   ├── RecordingView.swift      # MODIFIED: 3-bar waveform
│   ├── ModelManagerView.swift   # Tab 2: unchanged
│   └── TestDictationView.swift  # Moved into Home tab action
├── Design/
│   ├── GlassModifier.swift      # .glassEffect / Material fallback
│   ├── BrandWaveform.swift      # 3-bar logo-inspired waveform
│   ├── MicButtonAnimated.swift  # Animated mic button states
│   └── DictusColors.swift       # Color assets, no hardcoded values
├── Audio/
│   ├── AudioRecorder.swift      # Unchanged
│   └── TranscriptionService.swift # Unchanged
├── Models/
│   └── ModelManager.swift       # Unchanged
└── DictationCoordinator.swift   # Unchanged

DictusKeyboard/Views/
├── RecordingOverlay.swift       # MODIFIED: 3-bar waveform
├── ToolbarView.swift            # MODIFIED: animated mic button
├── KeyboardView.swift           # MODIFIED: glass styling
├── KeyButton.swift              # MODIFIED: glass key backgrounds
└── FullAccessBanner.swift       # MODIFIED: glass styling

DictusCore/Sources/DictusCore/
└── SharedKeys.swift             # EXTENDED: language, haptics, hasCompletedOnboarding
```

### Pattern 1: Glass Effect Fallback Modifier
**What:** Single reusable modifier that applies iOS 26 glassEffect with Material fallback
**When to use:** Every surface that needs glass styling
**Example:**
```swift
// Source: https://livsycode.com/swiftui/implementing-the-glasseffect-in-swiftui/
extension View {
    @ViewBuilder
    func dictusGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 16)) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(
                shape
                    .fill(.regularMaterial)
            )
        }
    }
}
```

### Pattern 2: Onboarding Gate at App Entry
**What:** Fullscreen cover that blocks app access until onboarding is complete
**When to use:** DictusApp.swift body
**Example:**
```swift
@main
struct DictusApp: App {
    @AppStorage("hasCompletedOnboarding",
                store: UserDefaults(suiteName: "group.com.pivi.dictus"))
    private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
                        .interactiveDismissDisabled() // non-dismissible
                }
        }
    }
}
```

### Pattern 3: TabView with Programmatic Page Control
**What:** Onboarding pages with forward-only navigation
**When to use:** OnboardingView
**Example:**
```swift
struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage(onNext: { currentPage = 1 })
                .tag(0)
            MicPermissionPage(onNext: { currentPage = 2 })
                .tag(1)
            KeyboardSetupPage(onNext: { currentPage = 3 })
                .tag(2)
            ModelDownloadPage(onNext: { currentPage = 4 })
                .tag(3)
            TestRecordingPage(onComplete: { isComplete = true })
                .tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}
```

### Pattern 4: Semantic Color System (No Hardcoded Colors)
**What:** All colors from Color assets or semantic system colors
**When to use:** Every color reference in the app
**Example:**
```swift
// Define in DictusColors.swift using Color extension
extension Color {
    static let dictusBackground = Color("DictusBackground")  // from Assets.xcassets
    static let dictusAccent = Color("DictusAccent")
    static let dictusSurface = Color("DictusSurface")
    static let dictusRecording = Color("DictusRecording")
    static let dictusSuccess = Color("DictusSuccess")
}
// These automatically adapt to light/dark mode via asset catalog variants
```

### Pattern 5: 3-Bar Brand Waveform
**What:** Logo-inspired waveform that responds to audio energy
**When to use:** RecordingView (main app) and RecordingOverlay (keyboard)
**Example:**
```swift
struct BrandWaveform: View {
    let energy: Float  // 0.0 - 1.0 from audio engine

    // Logo bar proportions (18pt / 42pt / 27pt normalized)
    private let baseHeights: [CGFloat] = [0.43, 1.0, 0.64]
    private let barWidth: CGFloat = 12
    private let barSpacing: CGFloat = 8
    private let cornerRadius: CGFloat = 4.5

    var body: some View {
        HStack(spacing: barSpacing) {
            // Left bar: white 45% opacity
            bar(index: 0, color: .white.opacity(0.45))
            // Center bar: accent gradient
            bar(index: 1, gradient: LinearGradient(
                colors: [Color(hex: "6BA3FF"), Color(hex: "2563EB")],
                startPoint: .top, endPoint: .bottom
            ))
            // Right bar: white 65% opacity
            bar(index: 2, color: .white.opacity(0.65))
        }
    }

    private func bar(index: Int, color: Color) -> some View {
        let height = baseHeights[index] * (0.3 + CGFloat(energy) * 0.7) * maxHeight
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(color)
            .frame(width: barWidth, height: height)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: energy)
    }
}
```

### Pattern 6: Dynamic Type Typography
**What:** System fonts with rounded design for headings, respecting Dynamic Type
**When to use:** All text in the app
**Example:**
```swift
// Headings: SF Pro Rounded via .rounded design
Text("Dictus")
    .font(.system(.largeTitle, design: .rounded, weight: .bold))

// Body: SF Pro Text (default system design)
Text("Description text")
    .font(.body)

// Metrics that scale with Dynamic Type
@ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24
```

### Anti-Patterns to Avoid
- **Hardcoded Color literals:** Never use `Color(red:green:blue:)` or hex directly in views. Always go through Color assets or the DictusColors extension for dark mode support.
- **Nested #available checks:** Don't scatter `#available(iOS 26, *)` everywhere. Use the `dictusGlass()` modifier once and apply it. Same for any other iOS 26-specific API.
- **Glass on content views:** Glass is for the navigation layer (toolbars, tab bars, cards, controls). Never apply glass to list content, text bodies, or media.
- **Blocking onboarding steps:** Don't force the user to wait on permission dialogs. If they deny microphone, show a message but let them proceed -- they can grant it later from Settings.
- **Force-unwrapping UITextInputMode:** The `activeInputModes` array may not contain your keyboard's language identifier in a predictable way. Always handle the "not detected" case gracefully.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Glass effect with fallback | Per-view `#available` checks | Single `dictusGlass()` ViewModifier | Consistency, single point of change |
| Dynamic Type support | Manual font size calculations | `.font(.system(.body))` text styles | System handles all 11 size categories automatically |
| Color scheme adaptation | Manual `colorScheme` checks for every color | Color asset catalog with light/dark variants | System handles adaptation automatically |
| Microphone permission | Custom permission manager | `AVAudioSession.sharedInstance().requestRecordPermission` | One-liner, system handles the dialog |
| Settings deep link | Custom URL schemes | `UIApplication.openSettingsURLString` | Official API, App Store safe |
| Keyboard installed detection | File system checks | `UITextInputMode.activeInputModes` polling | Official API for detecting active keyboards |
| Tab bar glass styling | Custom glass tab bar | Native `TabView` on iOS 26 (automatic glass) | iOS 26 TabView gets glass automatically |

**Key insight:** iOS 26 applies Liquid Glass to standard UIKit/SwiftUI navigation elements (TabBar, NavigationBar) automatically. Custom glass is only needed for custom surfaces like cards and onboarding pages.

## Common Pitfalls

### Pitfall 1: Glass-on-Glass Artifacts
**What goes wrong:** Applying `.glassEffect()` to views that are children of other glass views creates visual artifacts (double sampling)
**Why it happens:** Glass samples the content behind it. Glass sampling glass creates recursive blur.
**How to avoid:** Use `GlassEffectContainer` to group multiple glass elements. On iOS 16-25 with Material fallback, avoid stacking multiple Material backgrounds.
**Warning signs:** Overly bright or washed-out glass areas, visual "halos" around glass elements.

### Pitfall 2: Onboarding Page Swiping Past Incomplete Steps
**What goes wrong:** User swipes forward past the microphone permission or keyboard setup step without completing it.
**Why it happens:** TabView with `.page` style allows free swiping by default.
**How to avoid:** Disable forward swiping until the current step is complete. Use programmatic `currentPage` control. On the button action, validate step completion before incrementing. Consider disabling swipe gesture entirely and using only buttons for navigation.
**Warning signs:** Users reaching the test recording step without microphone permission granted.

### Pitfall 3: Keyboard Detection Returning False Negative
**What goes wrong:** App thinks keyboard is not installed even though user just added it in Settings.
**Why it happens:** `UITextInputMode.activeInputModes` is cached and may not update immediately when the user returns from Settings. The keyboard must have been selected at least once to appear.
**How to avoid:** Poll `activeInputModes` on `scenePhase` change (when app returns to foreground). Add a manual "I've added it" button as fallback. Don't block onboarding completion entirely on keyboard detection.
**Warning signs:** User is stuck on keyboard setup step despite having added the keyboard.

### Pitfall 4: TabView Interfering with RecordingView Overlay
**What goes wrong:** TabBar remains visible during the fullscreen recording overlay.
**Why it happens:** SwiftUI TabView doesn't natively hide for overlays.
**How to avoid:** Use `.toolbar(.hidden, for: .tabBar)` on RecordingView, or present RecordingView as a `.fullScreenCover`. Alternatively, use a ZStack at the app level where RecordingView covers everything including the TabBar.
**Warning signs:** Tab bar visible at the bottom during recording, user accidentally taps tabs during dictation.

### Pitfall 5: Dynamic Type Causing Layout Overflow
**What goes wrong:** At the largest accessibility text sizes (AX1-AX5), text overflows its container or gets truncated.
**Why it happens:** Fixed frame sizes don't scale with Dynamic Type.
**How to avoid:** Never use fixed `frame(height:)` for text containers. Use `@ScaledMetric` for spacing and sizing. Test in Accessibility Inspector at all Dynamic Type sizes. Use `.minimumScaleFactor(0.7)` as a last resort on constrained labels.
**Warning signs:** Truncated text with "..." at large accessibility sizes, overlapping UI elements.

### Pitfall 6: App Group UserDefaults Not Syncing for New Settings
**What goes wrong:** Settings changes in the main app are not reflected in the keyboard extension.
**Why it happens:** Standard `UserDefaults.standard` doesn't share with extensions. Must use `UserDefaults(suiteName: "group.com.pivi.dictus")`.
**How to avoid:** All new SharedKeys (language, hapticsEnabled, hasCompletedOnboarding) must use `AppGroup.defaults` -- the pattern already established in DictusCore.
**Warning signs:** Keyboard still using old settings after user changes preferences.

## Code Examples

### Microphone Permission Request (Onboarding Step 2)
```swift
// Source: Apple AVAudioSession documentation
import AVFoundation

func requestMicrophonePermission() async -> Bool {
    let session = AVAudioSession.sharedInstance()
    let status = session.recordPermission

    switch status {
    case .granted:
        return true
    case .denied:
        return false
    case .undetermined:
        return await withCheckedContinuation { continuation in
            session.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    @unknown default:
        return false
    }
}
```

### Keyboard Detection (Onboarding Step 3)
```swift
// Check if Dictus keyboard is in the active input modes
func isDictusKeyboardInstalled() -> Bool {
    // UITextInputMode.activeInputModes lists all enabled keyboards
    // Check for our keyboard's bundle identifier in the list
    let activeInputModes = UITextInputMode.activeInputModes
    // Dictus keyboard has primaryLanguage "fr-FR" and belongs to our bundle
    // Note: This is imperfect -- multiple keyboards may share a language.
    // Best approach: combine with checking the bundle identifier pattern.
    return activeInputModes.contains { mode in
        guard let identifier = mode.value(forKey: "identifier") as? String else {
            return false
        }
        return identifier.contains("com.pivi.dictus")
    }
}

// Alternatively, a simpler approach: just guide the user and provide
// a manual confirmation button since detection is unreliable.
```

### Settings Deep Link (Onboarding Step 3)
```swift
// Source: Apple Technical Q&A QA1924
// Official API for opening app settings
if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
    await UIApplication.shared.open(settingsURL)
}

// Note: Cannot deep-link directly to Keyboards settings page.
// UIApplication.openSettingsURLString opens the app's own settings page.
// User must navigate: Settings > Dictus > Keyboards manually.
// The onboarding UI should include a screenshot showing the path.
```

### iOS-Style Settings List (APP-03)
```swift
struct SettingsView: View {
    @AppStorage("dictus.language", store: AppGroup.defaults)
    private var language = "fr"

    @AppStorage("dictus.fillerWordsEnabled", store: AppGroup.defaults)
    private var fillerWordsEnabled = true

    @AppStorage("dictus.keyboardLayout", store: AppGroup.defaults)
    private var keyboardLayout = "azerty"

    @AppStorage("dictus.hapticsEnabled", store: AppGroup.defaults)
    private var hapticsEnabled = true

    var body: some View {
        List {
            Section("Transcription") {
                Picker("Langue", selection: $language) {
                    Text("Francais").tag("fr")
                    Text("English").tag("en")
                }
                Toggle("Mots de remplissage", isOn: $fillerWordsEnabled)
            }

            Section("Clavier") {
                Picker("Disposition", selection: $keyboardLayout) {
                    Text("AZERTY").tag("azerty")
                    Text("QWERTY").tag("qwerty")
                }
                Toggle("Retour haptique", isOn: $hapticsEnabled)
            }

            Section("A propos") {
                LabeledContent("Version", value: Bundle.main.appVersion)
                Link("GitHub", destination: URL(string: "https://github.com/Pivii/dictus")!)
                NavigationLink("Licences") { LicensesView() }
                NavigationLink("Diagnostic") { DiagnosticDetailView() }
            }
        }
        .navigationTitle("Reglages")
    }
}
```

### Animated Mic Button (DSN-02)
```swift
struct AnimatedMicButton: View {
    let status: DictationStatus
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -100

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Glow ring (idle state)
                if status == .idle || status == .ready {
                    Circle()
                        .stroke(Color(hex: "3D7EFF").opacity(glowOpacity), lineWidth: 2)
                        .frame(width: 40, height: 40)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                glowOpacity = 0.6
                            }
                        }
                }

                // Pulse ring (recording state)
                if status == .recording {
                    Circle()
                        .stroke(Color(hex: "EF4444").opacity(0.5), lineWidth: 3)
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulseScale)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulseScale = 1.3
                            }
                        }
                }

                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(micColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(micBackground))
            }
        }
        .disabled(status == .recording || status == .transcribing)
    }

    private var micColor: Color {
        switch status {
        case .recording: return Color(hex: "EF4444")
        case .transcribing: return Color(hex: "3D7EFF")
        default: return Color(.systemGray)
        }
    }
}
```

### TabView with 3 Tabs
```swift
struct MainTabView: View {
    @EnvironmentObject var coordinator: DictationCoordinator

    var body: some View {
        ZStack {
            TabView {
                Tab("Accueil", systemImage: "house.fill") {
                    NavigationStack { HomeView() }
                }
                Tab("Modeles", systemImage: "cpu") {
                    NavigationStack { ModelManagerView(modelManager: ModelManager()) }
                }
                Tab("Reglages", systemImage: "gearshape.fill") {
                    NavigationStack { SettingsView() }
                }
            }

            // Recording overlay covers everything including TabBar
            if coordinator.status != .idle {
                RecordingView()
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
        }
    }
}
```

**Note on TabView API:** iOS 18+ uses `Tab("label", systemImage:)` syntax. For iOS 16-17 compatibility, use the older `TabView { view.tabItem { Label("label", systemImage: "icon") }.tag(0) }` pattern. Since the project targets iOS 16.0, the older syntax is required unless minimum deployment target is raised.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.background(Material.regularMaterial)` | `.glassEffect(.regular)` | iOS 26 (WWDC 2025) | Native Liquid Glass with blur, refraction, morphing |
| TabView `tabItem` modifier | `Tab("label", systemImage:)` initializer | iOS 18 | Cleaner API but requires iOS 18 minimum |
| Manual glass-on-glass handling | `GlassEffectContainer` | iOS 26 | Automatic shared sampling, morphing support |
| `tabBarMinimizeBehavior` | New in iOS 26 | iOS 26 | Tab bar auto-minimizes on scroll |
| ScrollView onboarding (iOS 18) | ScrollPosition + containerRelativeFrame | iOS 18 | Better snap behavior, programmatic control |

**Important for this project:** Since minimum target is iOS 16.0, the older TabView API (`tabItem` + `tag`) must be used. The `Tab()` initializer requires iOS 18. Wrap iOS 26 glass in `#available` guards.

**Deprecated/outdated:**
- TabView `PageTabViewStyle()`: Still works on iOS 16+ but renamed to `.tabViewStyle(.page)` in recent APIs. Both work.
- `UIApplication.shared.open(URL)` from extensions: Not available in keyboard extensions. Use SwiftUI's `@Environment(\.openURL)` instead.

## Open Questions

1. **Keyboard detection reliability**
   - What we know: `UITextInputMode.activeInputModes` can detect keyboards, but using KVC (`value(forKey: "identifier")`) is fragile and potentially private API.
   - What's unclear: Whether Apple would reject this approach in App Store review.
   - Recommendation: Implement both automated detection and a manual "I've added the keyboard" button. If automated detection works, great. If not, the manual button is the fallback. Don't block onboarding on detection.

2. **iOS 16 TabView `.page` back-swipe prevention**
   - What we know: TabView with page style allows free bidirectional swiping by default.
   - What's unclear: Whether `.gesture(DragGesture())` can reliably block backward swiping on iOS 16.
   - Recommendation: Allow free swiping between completed steps, but only enable the "Next" button when the current step is complete. Keep the page dots visible so users know their progress.

3. **Keyboard extension glass styling on iOS 26**
   - What we know: The keyboard container already has a native blurred background from iOS. Adding `.glassEffect()` on top may create glass-on-glass artifacts.
   - What's unclear: Whether the native keyboard chrome on iOS 26 is already Liquid Glass, making custom glass unnecessary.
   - Recommendation: Test on iOS 26 simulator/device. If native keyboard chrome is already glass, only apply glass to custom elements (key buttons, toolbar). Do not add glass to the overall keyboard container background.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (via Swift Package Manager) |
| Config file | `DictusCore/Package.swift` |
| Quick run command | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test` |
| Full suite command | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| APP-01 | Onboarding flow completion sets hasCompletedOnboarding | unit (SharedKeys) | `cd DictusCore && swift test --filter SharedKeys` | Partial (SharedKeys exists) |
| APP-03 | Settings preferences persist via App Group | unit (SharedKeys) | `cd DictusCore && swift test` | Partial (SharedKeys exists) |
| KBD-06 | Keyboard glass styling | manual-only | N/A (requires iOS 26 device/sim) | N/A |
| DSN-01 | Glass effect on all surfaces | manual-only | N/A (visual verification) | N/A |
| DSN-02 | Mic button animation states | manual-only | N/A (visual verification) | N/A |
| DSN-03 | Light/dark mode | manual-only | N/A (visual verification) | N/A |
| DSN-04 | Dynamic Type support | manual-only | N/A (Accessibility Inspector) | N/A |

### Sampling Rate
- **Per task commit:** `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test`
- **Per wave merge:** Full test suite + Xcode build verification for both targets
- **Phase gate:** Full suite green + manual visual verification on device

### Wave 0 Gaps
- [ ] `DictusCore/Tests/DictusCoreTests/SharedKeysExtensionTests.swift` -- covers new keys (language, hapticsEnabled, hasCompletedOnboarding)
- [ ] Xcode build verification for DictusApp + DictusKeyboard targets after glass modifier changes

*(Most Phase 4 requirements are UI/visual and require manual verification on device. Automated testing is limited to data layer changes in SharedKeys.)*

## Sources

### Primary (HIGH confidence)
- [Apple glassEffect documentation](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) - iOS 26 glass API reference
- [Apple WWDC25 Session 323](https://developer.apple.com/videos/play/wwdc2025/323/) - Build a SwiftUI app with the new design
- [Apple Applying Liquid Glass docs](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) - Official glass tutorial
- [Apple AVAudioSession.RecordPermission](https://developer.apple.com/documentation/avfaudio/avaudiosession/recordpermission-swift.enum) - Microphone permission API
- [Apple Technical Q&A QA1924](https://developer.apple.com/library/archive/qa/qa1924/_index.html) - Opening Settings from keyboard extension
- [Apple UITextInputMode.activeInputModes](https://developer.apple.com/documentation/uikit/uitextinputmode/activeinputmodes) - Keyboard detection API

### Secondary (MEDIUM confidence)
- [LiquidGlassReference GitHub](https://github.com/conorluddy/LiquidGlassReference) - Community-compiled iOS 26 glass reference with code examples
- [Donny Wals: Tab bars on iOS 26](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/) - TabView glass patterns and new APIs
- [Livsy Code: glassEffect implementation](https://livsycode.com/swiftui/implementing-the-glasseffect-in-swiftui/) - Fallback modifier pattern
- [River Labs: SwiftUI Onboarding](https://www.riveralabs.com/blog/swiftui-onboarding/) - Modern onboarding patterns

### Tertiary (LOW confidence)
- Keyboard detection via KVC `value(forKey: "identifier")` on UITextInputMode -- may be private API, needs App Store review validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftUI + UIKit, no new dependencies, all patterns verified against official docs
- Architecture: HIGH - Patterns well-established in existing codebase, glassEffect API documented by Apple
- Pitfalls: MEDIUM - Glass-on-glass in keyboard context needs on-device testing, keyboard detection reliability unverified
- Onboarding: HIGH - TabView page style is standard iOS pattern, permission APIs well documented
- Design system: HIGH - SF Pro Rounded via `.rounded` design is official Apple API, Dynamic Type is built-in

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable -- iOS 26 APIs are finalized post-WWDC)
