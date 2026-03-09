# Phase 9: Keyboard Modes - Research

**Researched:** 2026-03-09
**Domain:** SwiftUI conditional rendering, App Group persistence, keyboard extension layout switching
**Confidence:** HIGH

## Summary

Phase 9 adds three switchable keyboard modes (Micro, Emoji+Micro, Clavier complet) with a settings UI, onboarding integration, and App Group persistence. The implementation is primarily a UI composition task -- all building blocks already exist in the codebase (AnimatedMicButton, EmojiPickerView, RecordingOverlay, ToolbarView, KeyboardView). The core technical challenge is restructuring `KeyboardRootView` to conditionally render one of three layouts based on an App Group preference, and creating a reusable `KeyboardModePicker` component with miniature previews for both Settings and onboarding.

The project already has established patterns for every integration point: `@AppStorage` with App Group store for cross-process preferences (used by language, keyboardLayout, hapticsEnabled, autocorrectEnabled), `SharedKeys` enum for centralized key management, switch/case onboarding with programmatic-only advancement, and conditional rendering in KeyboardRootView.

**Primary recommendation:** Define a `KeyboardMode` enum in DictusCore (like the existing `LayoutType`), add a `keyboardMode` SharedKey, then restructure `KeyboardRootView.body` to switch on the active mode. Build `KeyboardModePicker` as a reusable SwiftUI component for Settings and onboarding.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Micro mode: giant centered mic pill (~120pt, "Dicter" label) + globe in bottom-left, no other controls
- Emoji+Micro mode: full EmojiPickerView reused from Phase 7, mic pill in toolbar, no suggestion bar
- Clavier complet: current full AZERTY/QWERTY, no changes
- Settings: segmented picker ("Micro" | "Emoji+" | "Complet") with non-interactive miniature mockup below
- Mode picker absorbs AZERTY/QWERTY disposition picker (only visible for "Complet" mode)
- Conditional toggles: Micro hides correction+haptics, Emoji+ hides correction, Complet shows all
- Onboarding: new step between keyboard setup and model download, no default pre-selected, blocking step
- Reusable KeyboardModePicker component shared between Settings and onboarding
- Mode changed only from app Settings or onboarding -- no in-keyboard mode switching
- Globe = advanceToNextInputMode (switch iOS keyboards), not mode switch
- Mode persisted via App Group SharedKeys (new key: `dictus.keyboardMode`)
- Keyboard reads mode on each open (same pattern as AZERTY/QWERTY layout switch)
- Same keyboard height for all modes to prevent layout jump
- RecordingOverlay reused in all 3 modes

### Claude's Discretion
- Exact miniature mockup design and proportions for each mode preview
- Segmented picker styling (Liquid Glass or native iOS style)
- Animation when switching between mode previews in Settings
- Micro mode mic button Liquid Glass styling details (glow, gradient)
- Exact onboarding page layout and spacing

### Deferred Ideas (OUT OF SCOPE)
- In-keyboard mode switching (long-press gear to change mode)
- Mode-specific keyboard height (Micro could be shorter)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MODE-01 | Three keyboard modes available -- "Micro" (centered mic + globe), "Emoji + Micro" (emoji picker + mic in toolbar), "Clavier complet" (current full AZERTY) | KeyboardMode enum in DictusCore + conditional rendering in KeyboardRootView; all sub-views already exist |
| MODE-02 | User selects preferred keyboard mode in the app's Settings screen | SettingsView already uses @AppStorage pattern; add segmented picker + conditional toggle visibility |
| MODE-03 | Settings shows a non-interactive SwiftUI preview of each keyboard mode | Build MicroModePreview, EmojiModePreview, FullModePreview as simplified SwiftUI views inside KeyboardModePicker |
| MODE-04 | Keyboard extension reads selected mode from App Group and renders the correct layout | Same pattern as LayoutType.active -- read from AppGroup.defaults on each keyboard appearance |
</phase_requirements>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 16+ | All UI rendering | Project standard, already used everywhere |
| DictusCore (SPM) | local | Shared types + App Group | Existing shared framework between app and extension |

### No New Dependencies

This phase requires zero new libraries. All functionality is built with SwiftUI primitives and existing DictusCore infrastructure.

## Architecture Patterns

### New Files to Create

```
DictusCore/Sources/DictusCore/
├── KeyboardMode.swift          # KeyboardMode enum (like LayoutType)

DictusKeyboard/Views/
├── MicroModeView.swift         # Giant mic + globe layout for keyboard
├── EmojiMicroModeView.swift    # Emoji picker + mic toolbar layout

DictusApp/Views/
├── KeyboardModePicker.swift    # Reusable segmented picker + preview (Settings + onboarding)

DictusApp/Onboarding/
├── ModeSelectionPage.swift     # New onboarding step using KeyboardModePicker
```

### Files to Modify

```
DictusCore/Sources/DictusCore/SharedKeys.swift     # Add keyboardMode key
DictusKeyboard/KeyboardRootView.swift              # Switch on mode for conditional rendering
DictusApp/Views/SettingsView.swift                 # Replace "Clavier" section with mode picker
DictusApp/Onboarding/OnboardingView.swift          # Insert mode selection step (case 3)
```

### Pattern 1: KeyboardMode Enum in DictusCore

**What:** A String-backed enum with a static `active` property reading from App Group, mirroring the existing `LayoutType` pattern.
**When to use:** Everywhere that needs to know the current keyboard mode.

```swift
// DictusCore/Sources/DictusCore/KeyboardMode.swift
public enum KeyboardMode: String, CaseIterable, Codable {
    case micro       // Dictation-only: giant mic + globe
    case emojiMicro  // Emoji picker + mic in toolbar
    case full        // Current full AZERTY/QWERTY

    /// Reads the active mode from App Group, defaulting to .full
    /// (preserves existing behavior for users who haven't chosen yet).
    public static var active: KeyboardMode {
        guard let raw = AppGroup.defaults.string(forKey: SharedKeys.keyboardMode),
              let mode = KeyboardMode(rawValue: raw) else {
            return .full
        }
        return mode
    }

    /// French display name for UI labels
    public var displayName: String {
        switch self {
        case .micro: return "Micro"
        case .emojiMicro: return "Emoji+"
        case .full: return "Complet"
        }
    }
}
```

### Pattern 2: Conditional Rendering in KeyboardRootView

**What:** Read mode on appearance and switch between three layout branches.
**When to use:** Main keyboard view body.

```swift
// In KeyboardRootView.swift
@State private var currentMode: KeyboardMode = .full

var body: some View {
    VStack(spacing: 0) {
        if state.dictationStatus == .recording || state.dictationStatus == .transcribing {
            RecordingOverlay(/* ... */)
                .frame(height: totalContentHeight)
        } else {
            switch currentMode {
            case .micro:
                MicroModeView(
                    controller: controller,
                    dictationStatus: state.dictationStatus,
                    onMicTap: { state.startRecording() }
                )
            case .emojiMicro:
                EmojiMicroModeView(
                    controller: controller,
                    hasFullAccess: controller.hasFullAccess,
                    dictationStatus: state.dictationStatus,
                    onMicTap: { state.startRecording() }
                )
            case .full:
                // Existing toolbar + keyboard code (extract or keep inline)
                ToolbarView(/* ... */)
                KeyboardView(/* ... */)
                if !isEmojiMode { Spacer().frame(height: 8) }
            }
        }
    }
    .onAppear {
        currentMode = KeyboardMode.active
        // ... existing onAppear code
    }
}
```

### Pattern 3: MicroModeView Layout

**What:** Giant centered mic button with globe in bottom-left, filling the same height as other modes.
**When to use:** When `currentMode == .micro`.

```swift
// DictusKeyboard/Views/MicroModeView.swift
struct MicroModeView: View {
    let controller: UIInputViewController
    let dictationStatus: DictationStatus
    let onMicTap: () -> Void

    var body: some View {
        ZStack {
            // Centered: large mic pill with "Dicter" label
            VStack(spacing: 12) {
                AnimatedMicButton(status: dictationStatus, isPill: false, onTap: onMicTap)
                    .scaleEffect(1.6)  // Scale up from 72pt to ~115pt
                Text("Dicter")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Bottom-left: globe button
            VStack {
                Spacer()
                HStack {
                    Button(action: { controller.advanceToNextInputMode() }) {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}
```

**Note on mic button sizing:** Rather than `scaleEffect` (which also scales glow/ring), consider adding a new size parameter to AnimatedMicButton (e.g., `isPill: false, size: .large`) that uses ~120pt width. This avoids blurry scaling artifacts. Claude's discretion on exact approach.

### Pattern 4: Reusable KeyboardModePicker

**What:** Segmented picker with miniature preview, used in both Settings and onboarding.
**When to use:** SettingsView and ModeSelectionPage.

```swift
// DictusApp/Views/KeyboardModePicker.swift
struct KeyboardModePicker: View {
    @Binding var selectedMode: String  // Raw value of KeyboardMode

    var body: some View {
        VStack(spacing: 16) {
            // Segmented picker
            Picker("Mode", selection: $selectedMode) {
                Text("Micro").tag(KeyboardMode.micro.rawValue)
                Text("Emoji+").tag(KeyboardMode.emojiMicro.rawValue)
                Text("Complet").tag(KeyboardMode.full.rawValue)
            }
            .pickerStyle(.segmented)

            // Non-interactive miniature preview
            Group {
                switch KeyboardMode(rawValue: selectedMode) ?? .full {
                case .micro:
                    MicroModePreview()
                case .emojiMicro:
                    EmojiModePreview()
                case .full:
                    FullModePreview()
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)  // Non-interactive
        }
    }
}
```

### Pattern 5: Onboarding Integration

**What:** Insert new step at index 3 (after keyboard setup, before model download).
**When to use:** OnboardingView switch/case.

Current flow: 0=Welcome, 1=MicPermission, 2=KeyboardSetup, 3=ModelDownload, 4=TestRecording
New flow: 0=Welcome, 1=MicPermission, 2=KeyboardSetup, **3=ModeSelection**, 4=ModelDownload, 5=TestRecording

```swift
// Changes in OnboardingView.swift:
// 1. Update totalSteps from 5 to 6
// 2. Insert case 3: ModeSelectionPage
// 3. Shift ModelDownloadPage to case 4
// 4. Shift TestRecordingPage to case 5
```

### Pattern 6: Conditional Settings Toggles

**What:** Show/hide settings rows based on selected mode.
**When to use:** SettingsView "Clavier" section.

```swift
// In SettingsView.swift, replace Section("Clavier") with:
Section("Clavier") {
    KeyboardModePicker(selectedMode: $keyboardMode)

    // Only show layout picker for full keyboard mode
    if keyboardMode == KeyboardMode.full.rawValue {
        Picker("Disposition", selection: $keyboardLayout) {
            Text("AZERTY").tag("azerty")
            Text("QWERTY").tag("qwerty")
        }
    }

    // Haptics: show for Emoji+ and Full (not Micro -- no tapping)
    if keyboardMode != KeyboardMode.micro.rawValue {
        Toggle("Retour haptique", isOn: $hapticsEnabled)
    }

    // Autocorrect: only for Full keyboard
    if keyboardMode == KeyboardMode.full.rawValue {
        Toggle("Correction automatique", isOn: $autocorrectEnabled)
    }
}
```

### Anti-Patterns to Avoid
- **Separate UserDefaults stores per mode:** Use a single `keyboardMode` key, not separate booleans for each mode. The existing SharedKeys pattern is one key = one value.
- **Reading mode in init():** Read mode in `.onAppear` so it picks up changes made while the keyboard was closed. Same pattern as `KeyboardLayout.currentLettersRows()`.
- **Modifying AnimatedMicButton heavily for Micro mode:** Better to create a dedicated large mic view that wraps or extends AnimatedMicButton than to add conditional complexity inside it.
- **Using NavigationLink for mode previews:** Previews are non-interactive inline views, not navigation destinations. Use `allowsHitTesting(false)`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Segmented control | Custom tab bar | SwiftUI `Picker(.segmented)` | Native iOS look, automatic accessibility, keyboard navigation |
| Cross-process persistence | Custom file sync | `@AppStorage` with App Group store | Already used for 5+ preferences in this project |
| Globe button behavior | Custom keyboard switching | `controller.advanceToNextInputMode()` | Only Apple API for keyboard switching, already used |
| Emoji picker for Emoji+Micro | New emoji view | Existing `EmojiPickerView` | Phase 7 built the complete picker, reuse as-is |

## Common Pitfalls

### Pitfall 1: Onboarding Step Index Shift
**What goes wrong:** Inserting a new step at index 3 shifts ModelDownload to 4 and TestRecording to 5, but forgetting to update `totalSteps` from 5 to 6 causes the step indicator dots to be wrong.
**Why it happens:** The step indicator uses `ForEach(0..<totalSteps)`.
**How to avoid:** Update `totalSteps` to 6 and verify all `advanceToPage()` calls reference the correct indices.
**Warning signs:** Step indicator shows 5 dots instead of 6, or last step is unreachable.

### Pitfall 2: Default Mode for Existing Users
**What goes wrong:** Existing users who completed onboarding never chose a mode. If default is nil/empty, the keyboard could show nothing.
**Why it happens:** New `keyboardMode` key doesn't exist in App Group for users who onboarded before this update.
**How to avoid:** Default to `.full` when the key is absent (preserves existing behavior). The `KeyboardMode.active` computed property handles this with a nil-coalescing fallback.
**Warning signs:** Keyboard shows blank after app update.

### Pitfall 3: @SceneStorage Page Index Mismatch
**What goes wrong:** OnboardingView uses `@SceneStorage("onboarding_currentPage")` which persists across app launches. After adding the new step, an existing user mid-onboarding could land on the wrong page.
**Why it happens:** The persisted page index maps to a different step after the case shift.
**How to avoid:** This only affects users who are literally mid-onboarding when the update lands -- extremely rare. The switch/case `default` branch already falls back to WelcomePage. No action needed unless we want to be extra cautious (could reset the stored page index on first launch of new version).

### Pitfall 4: Keyboard Height Mismatch Between Modes
**What goes wrong:** MicroModeView or EmojiMicroModeView renders at a different height than full keyboard, causing a visible "jump" when user switches modes between uses.
**Why it happens:** Each mode view has different content, so intrinsic height varies.
**How to avoid:** Use the same `totalContentHeight` (toolbar + keyboard rows) as a fixed frame height for all modes. Wrap each mode view in `.frame(height: totalContentHeight)`.

### Pitfall 5: EmojiPickerView Globe Button Conflict
**What goes wrong:** In Emoji+Micro mode, the emoji category bar already contains navigation. Adding a globe button could conflict with the layout or be hard to discover.
**Why it happens:** The CONTEXT.md says "Globe in category bar or standard iOS position."
**How to avoid:** Place globe as the first item in the EmojiCategoryBar (leftmost position, before Recents), or place it in the toolbar next to the mic pill. The toolbar approach is cleaner since it keeps the category bar purely for emoji navigation.

## Code Examples

### Reading Mode in Keyboard Extension
```swift
// Same pattern as LayoutType.active, already proven in this codebase
// Source: DictusCore/Sources/DictusCore/KeyboardLayoutData.swift lines 17-24
let mode = KeyboardMode.active  // Reads from AppGroup.defaults
```

### @AppStorage for Mode in Settings
```swift
// Same pattern used 4 times in SettingsView.swift already
// Source: DictusApp/Views/SettingsView.swift lines 20-33
@AppStorage(SharedKeys.keyboardMode, store: UserDefaults(suiteName: AppGroup.identifier))
private var keyboardMode = KeyboardMode.full.rawValue
```

### Blocking Onboarding Step (no default pre-selected)
```swift
// ModeSelectionPage.swift
struct ModeSelectionPage: View {
    let onNext: () -> Void
    @AppStorage(SharedKeys.keyboardMode, store: UserDefaults(suiteName: AppGroup.identifier))
    private var keyboardMode = ""  // Empty string = no selection yet

    var body: some View {
        VStack(spacing: 24) {
            Text("Choisissez votre clavier")
                .font(.title2.bold())
                .foregroundColor(.white)

            KeyboardModePicker(selectedMode: $keyboardMode)

            Button("Continuer", action: onNext)
                .disabled(keyboardMode.isEmpty)  // Blocked until selection
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

## State of the Art

No external library changes or API evolution relevant to this phase. All patterns used are stable SwiftUI features available since iOS 16 (project minimum).

| Pattern | Status | Notes |
|---------|--------|-------|
| `Picker(.segmented)` | Stable since iOS 13 | No known issues |
| `@AppStorage` with suite | Stable since iOS 14 | Already used 5+ times in project |
| `allowsHitTesting(false)` | Stable since iOS 13 | Correct way to make non-interactive previews |
| `advanceToNextInputMode()` | Stable UIKit API | Only way to switch iOS keyboards |

## Open Questions

1. **Micro mode mic button sizing approach**
   - What we know: AnimatedMicButton currently supports circle (72pt) and pill (56x36) modes. Micro mode needs ~120pt.
   - What's unclear: Whether to add a third size mode to AnimatedMicButton or create a wrapper/scaled version.
   - Recommendation: Add a `.large` size parameter to AnimatedMicButton to avoid scaleEffect blur. Claude's discretion per CONTEXT.md.

2. **Globe button placement in Emoji+Micro mode**
   - What we know: CONTEXT.md says "Globe in category bar or standard iOS position."
   - What's unclear: Exact position -- leftmost in category bar vs. in toolbar.
   - Recommendation: Place in toolbar (next to mic pill, left side) for consistency with how globe appears in full keyboard mode. Keeps category bar purely for emoji categories.

3. **Miniature preview fidelity**
   - What we know: Previews should "feel like looking at the actual keyboard from a distance."
   - What's unclear: How detailed to make them (simplified rectangles vs. actual key labels at tiny size).
   - Recommendation: Use simplified geometric representations -- rectangles for keys, a circle for mic, colored blocks for emoji grid. Key labels at preview scale would be illegible and wasteful. Claude's discretion per CONTEXT.md.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing / XCTest via SPM |
| Config file | DictusCore/Package.swift (test target exists) |
| Quick run command | `swift test --package-path DictusCore` |
| Full suite command | `swift test --package-path DictusCore` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MODE-01 | Three keyboard modes available | unit | `swift test --package-path DictusCore --filter KeyboardModeTests` | No -- Wave 0 |
| MODE-02 | User selects mode in Settings | manual-only | Xcode simulator | N/A (SwiftUI view) |
| MODE-03 | Settings shows non-interactive preview | manual-only | Xcode simulator | N/A (SwiftUI view) |
| MODE-04 | Extension reads mode from App Group | unit | `swift test --package-path DictusCore --filter KeyboardModeTests` | No -- Wave 0 |

**Manual-only justification for MODE-02, MODE-03:** These are pure SwiftUI view composition tasks. The underlying persistence is testable (MODE-04), but the visual layout requires Xcode simulator verification. The project does not have UI testing infrastructure (no XCUITest target).

### Sampling Rate
- **Per task commit:** `swift test --package-path DictusCore`
- **Per wave merge:** `swift test --package-path DictusCore`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `DictusCore/Tests/DictusCoreTests/KeyboardModeTests.swift` -- covers MODE-01 (enum cases, displayName, rawValue) and MODE-04 (reading from UserDefaults)

## Sources

### Primary (HIGH confidence)
- Project codebase analysis -- all files read directly:
  - `DictusKeyboard/KeyboardRootView.swift` -- current conditional rendering pattern
  - `DictusApp/Views/SettingsView.swift` -- @AppStorage pattern with App Group
  - `DictusCore/Sources/DictusCore/SharedKeys.swift` -- centralized key management
  - `DictusCore/Sources/DictusCore/KeyboardLayoutData.swift` -- LayoutType.active pattern (model for KeyboardMode)
  - `DictusApp/Onboarding/OnboardingView.swift` -- switch/case step flow
  - `DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift` -- mic button sizing
  - `DictusKeyboard/Views/ToolbarView.swift` -- toolbar composition
  - `DictusKeyboard/Views/EmojiPickerView.swift` -- emoji picker structure
  - `DictusCore/Sources/DictusCore/AppGroup.swift` -- App Group access

### Secondary (MEDIUM confidence)
- None needed -- all patterns are already established in the codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all existing project patterns
- Architecture: HIGH -- direct extension of existing conditional rendering and App Group persistence patterns already used 5+ times
- Pitfalls: HIGH -- identified from reading actual codebase (onboarding step indices, default mode for existing users, height consistency)

**Research date:** 2026-03-09
**Valid until:** No expiration -- all patterns are internal to this codebase, no external dependency risk
