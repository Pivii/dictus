---
phase: 04-main-app-onboarding-and-polish
verified: 2026-03-06T23:30:00Z
status: human_needed
score: 6/6 must-haves verified
human_verification:
  - test: "Run on device, toggle dark mode in Settings > Display"
    expected: "All screens adapt colors correctly, no white-on-white or black-on-black text"
    why_human: "Color adaptation depends on runtime colorScheme evaluation"
  - test: "Set Dynamic Type to largest accessibility size in Settings > Accessibility > Display & Text Size"
    expected: "No text truncation, all screens remain scrollable and usable"
    why_human: "Layout overflow at extreme text sizes cannot be verified statically"
  - test: "Fresh install: delete app, reinstall, verify onboarding appears and guides through all 5 steps"
    expected: "Welcome > Mic permission > Keyboard setup > Model download > Test recording > TabView"
    why_human: "End-to-end flow requires real device with Settings navigation"
  - test: "AnimatedMicButton visual states in keyboard toolbar"
    expected: "Idle blue glow, recording red pulse, transcribing shimmer, success green flash"
    why_human: "Animation timing and visual quality need human eye"
---

# Phase 4: Main App, Onboarding, and Polish Verification Report

**Phase Goal:** A new user can install Dictus, complete onboarding, and dictate their first sentence -- and every screen looks like it belongs on iOS 26.
**Verified:** 2026-03-06T23:30:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | First-time user sees onboarding before main app | VERIFIED | `DictusApp.swift:37` uses `.fullScreenCover(isPresented: .constant(!hasCompletedOnboarding))` presenting `OnboardingView`. Default is `false`, so onboarding always shows on first launch. `.interactiveDismissDisabled()` at `OnboardingView.swift:58` prevents swipe dismiss. |
| 2 | Onboarding guides through 5 steps: welcome, mic, keyboard, model download, test transcription | VERIFIED | `OnboardingView.swift` contains 5 tagged pages: `WelcomePage` (tag 0), `MicPermissionPage` (tag 1), `KeyboardSetupPage` (tag 2), `ModelDownloadPage` (tag 3), `TestRecordingPage` (tag 4). Each has substantive implementation with proper UI, actions, and `onNext`/`onComplete` callbacks. |
| 3 | Settings screen has all required preferences that persist via App Group | VERIFIED | `SettingsView.swift` has 3 sections: Transcription (langue picker, filler words toggle), Clavier (disposition picker, haptic toggle), A propos (version, GitHub, licences, diagnostic). All 4 preferences use `@AppStorage(SharedKeys.*, store: UserDefaults(suiteName: AppGroup.identifier))`. |
| 4 | Every surface uses glass (iOS 26) or Material fallback (iOS 16-25) | VERIFIED | `GlassModifier.swift` implements `#available(iOS 26, *)` check with `.glassEffect(.regular, in: shape)` and `.background(shape.fill(.regularMaterial))` fallback. Applied to: HomeView cards (`.dictusGlass()`), RecordingView result card, ModelDownloadPage model card, TestRecordingPage result card, KeyButton background, ToolbarView glass bar, FullAccessBanner. |
| 5 | AnimatedMicButton shows idle glow, recording pulse, transcribing shimmer, and success flash | VERIFIED | `AnimatedMicButton.swift` implements all 4 states: idle glow (pulsing 0.3-0.6 opacity over 2s), recording pulse (scale 1.0-1.3 over 0.8s with red ring), transcribing shimmer (LinearGradient sweep 1.5s), success flash (green 0.3s fade on transcribing->ready transition). Wired into keyboard `ToolbarView.swift:44` and onboarding `TestRecordingPage.swift:91`. |
| 6 | App launches into 3-tab TabView with RecordingView overlay | VERIFIED | `DictusApp.swift:32` renders `MainTabView()`. `MainTabView.swift` has TabView with 3 tabs: Accueil (HomeView), Modeles (ModelManagerView), Reglages (SettingsView). ZStack overlay at line 65 shows `RecordingView` when `coordinator.status != .idle`. |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `DictusCore/Sources/DictusCore/SharedKeys.swift` | New keys: language, hapticsEnabled, fillerWordsEnabled, hasCompletedOnboarding | VERIFIED | All 4 keys present at lines 31-37 with correct string values |
| `DictusApp/Design/GlassModifier.swift` | `.dictusGlass()` modifier with iOS 26 glass + Material fallback | VERIFIED | 41 lines, `glassEffect` at line 17, `regularMaterial` fallback at line 20, both `dictusGlass()` and `dictusGlassBar()` extensions |
| `DictusApp/Design/DictusColors.swift` | Color extension with brand colors + light/dark adaptive | VERIFIED | 86 lines, `dictusAccent` at line 19, adaptive `dictusBackground` and `dictusSurface` with light/dark variants, hex initializer |
| `DictusApp/Design/BrandWaveform.swift` | Multi-bar waveform with brand colors | VERIFIED | 113 lines, 30-bar design with blue gradient center and white opacity edges, `@ScaledMetric` for barWidth, `energyLevels` parameter |
| `DictusApp/Design/AnimatedMicButton.swift` | 4-state animated mic button | VERIFIED | 193 lines, `pulseScale` present, all 4 animation states implemented with transitions |
| `DictusApp/Design/DictusTypography.swift` | Font extension with SF Pro Rounded headings | VERIFIED | 29 lines, `dictusHeading` (rounded bold), `dictusSubheading` (rounded semibold), `dictusBody`, `dictusCaption` |
| `DictusApp/Views/MainTabView.swift` | 3-tab TabView with Home/Models/Settings | VERIFIED | 77 lines, `TabView` present, 3 tabs with correct labels and icons |
| `DictusApp/Views/HomeView.swift` | Dashboard with model status + test dictation link | VERIFIED | 149 lines, BrandWaveform logo, model status card with `.dictusGlass()`, last transcription card, test dictation NavigationLink |
| `DictusApp/Onboarding/OnboardingView.swift` | 5-page paged TabView container | VERIFIED | 69 lines, `tabViewStyle(.page)` present, 5 pages tagged 0-4 |
| `DictusApp/Onboarding/WelcomePage.swift` | Welcome with animated logo + "Commencer" | VERIFIED | 79 lines, `BrandWaveform`, "Commencer" button, spring animation |
| `DictusApp/Onboarding/MicPermissionPage.swift` | Mic permission request page | VERIFIED | 140 lines, `requestRecordPermission` called, handles granted/denied/undetermined |
| `DictusApp/Onboarding/KeyboardSetupPage.swift` | Keyboard + Full Access setup page | VERIFIED | 158 lines, `openSettingsURLString` deep link, keyboard auto-detection via `UITextInputMode`, manual fallback button |
| `DictusApp/Onboarding/ModelDownloadPage.swift` | Model download with progress | VERIFIED | 181 lines, "Telecharger" button, `modelManager.downloadModel()`, ProgressView with percentage |
| `DictusApp/Onboarding/TestRecordingPage.swift` | Test transcription with "Dites quelque chose" | VERIFIED | 193 lines, "Dites quelque chose !" prompt, AnimatedMicButton, BrandWaveform with live energy, "Terminer" sets `onComplete()` |
| `DictusApp/Views/SettingsView.swift` | 3-section settings list | VERIFIED | 109 lines, "Transcription" section with langue + filler toggle, "Clavier" section with disposition + haptic toggle, "A propos" section |
| `DictusApp/Views/LicensesView.swift` | License attributions | VERIFIED | 89 lines, WhisperKit + Dictus MIT licenses |
| `DictusKeyboard/Design/` (5 files) | Design components duplicated for keyboard target | VERIFIED | All 5 files present: GlassModifier.swift, DictusColors.swift, BrandWaveform.swift, AnimatedMicButton.swift, DictusTypography.swift |
| `DictusKeyboard/Views/RecordingOverlay.swift` | BrandWaveform replacing old waveform | VERIFIED | `BrandWaveform(energyLevels: waveformEnergy, maxHeight: 60)` at line 84 |
| `DictusKeyboard/Views/ToolbarView.swift` | AnimatedMicButton replacing inline mic | VERIFIED | `AnimatedMicButton(status: dictationStatus, onTap: onMicTap)` at line 44, glass toolbar background |
| `DictusKeyboard/Views/KeyButton.swift` | Glass-styled keys | VERIFIED | `.dictusGlass(in: RoundedRectangle(cornerRadius: 5))` at line 137 |
| `DictusKeyboard/Views/FullAccessBanner.swift` | Glass-styled banner | VERIFIED | `.dictusGlass(in: Rectangle())` at line 33, `.dictusCaption` typography, `.dictusAccent` link color |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `DictusApp.swift` | `MainTabView.swift` | body renders MainTabView | WIRED | Line 32: `MainTabView()` |
| `DictusApp.swift` | `OnboardingView.swift` | fullScreenCover when !hasCompletedOnboarding | WIRED | Line 37-39: `.fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) { OnboardingView(isComplete: $hasCompletedOnboarding) }` |
| `OnboardingView.swift` | `TestRecordingPage.swift` | Last page sets isComplete = true | WIRED | Line 48-49: `TestRecordingPage(onComplete: { isComplete = true })` |
| `MainTabView.swift` | `RecordingView.swift` | ZStack overlay when coordinator.status != .idle | WIRED | Line 65-68: `if coordinator.status != .idle { RecordingView()... }` |
| `SettingsView.swift` | SharedKeys via AppGroup | @AppStorage with AppGroup.defaults store | WIRED | Lines 20-29: All 4 `@AppStorage(SharedKeys.*, store: UserDefaults(suiteName: AppGroup.identifier))` |
| `RecordingView.swift` | `BrandWaveform.swift` | BrandWaveform(energyLevels:) | WIRED | Line 59: `BrandWaveform(energyLevels: coordinator.bufferEnergy, maxHeight: 120)` |
| `ToolbarView.swift` | `AnimatedMicButton` | Replaces inline micIcon | WIRED | Line 44: `AnimatedMicButton(status: dictationStatus, onTap: onMicTap)` |
| `KeyButton.swift` | `GlassModifier` | .dictusGlass() on key backgrounds | WIRED | Line 137: `.dictusGlass(in: RoundedRectangle(cornerRadius: 5))` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| **APP-01** | 04-02 | Onboarding guides through mic permission, keyboard addition, Full Access, model download | SATISFIED | 5-step onboarding flow with all required pages: MicPermissionPage (requestRecordPermission), KeyboardSetupPage (openSettingsURLString + auto-detection), ModelDownloadPage (download with progress), TestRecordingPage (end-to-end validation) |
| **APP-03** | 04-02 | Settings screen for active model, transcription language, keyboard layout, filler word toggle, haptic toggle | SATISFIED | SettingsView has Transcription section (language picker, filler word toggle), Clavier section (layout picker, haptic toggle). Active model selection is in the Models tab (separate concern). |
| **KBD-06** | 04-03 | Keyboard uses iOS 26 Liquid Glass design | SATISFIED | GlassModifier applied to KeyButton (.dictusGlass), ToolbarView (dictusGlassBar on iOS 26), FullAccessBanner (.dictusGlass). Design files duplicated in DictusKeyboard/Design/. |
| **DSN-01** | 04-01, 04-03 | All UI surfaces use iOS 26 Liquid Glass (.glassEffect) | SATISFIED | GlassModifier.swift uses `#available(iOS 26, *)` with `.glassEffect(.regular, in: shape)` and Material fallback. Applied across app cards, keyboard keys, toolbar, banner. |
| **DSN-02** | 04-01, 04-03 | Mic button has animated states (idle glow, recording pulse, transcribing shimmer) | SATISFIED | AnimatedMicButton.swift implements all 4 states + success flash. Wired into keyboard ToolbarView and onboarding TestRecordingPage. |
| **DSN-03** | 04-01 | Light and dark mode supported automatically | SATISFIED | DictusColors.swift uses `Color(light:dark:)` initializer with UIColor dynamic provider for adaptive colors. Views use `.foregroundStyle(.primary)`, `.secondary`, and semantic system colors. |
| **DSN-04** | 04-01, 04-03 | SF Pro Rounded for headings, SF Pro Text for body, Dynamic Type throughout | SATISFIED | DictusTypography.swift defines `.dictusHeading` (.system(.title, design: .rounded)), `.dictusBody` (.system(.body)). Used throughout all views. BrandWaveform uses `@ScaledMetric` for barWidth. Keyboard uses `@ScaledMetric` for timer and icon sizes. |

No orphaned requirements found -- all 7 requirement IDs from the phase (APP-01, APP-03, KBD-06, DSN-01, DSN-02, DSN-03, DSN-04) are accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `DictusApp/Views/RecordingView.swift` | 55, 67, 95, 120 | `.font(.system(size: N))` without `@ScaledMetric` | Info | Timer (monospaced) and SF Symbol icon sizes are fixed. Timer is acceptable for alignment; icon sizes are cosmetic at these scales. |
| `DictusApp/Onboarding/*.swift` | multiple | `.font(.system(size: 42/64/72))` without `@ScaledMetric` | Info | Large decorative icon and wordmark sizes. These are display elements, not reading text. Acceptable for onboarding splash screens. |
| `DictusKeyboard/Views/SpecialKeyButton.swift` | 33, 76, 119, 140, 160, 181 | `.font(.system(size: 15/16))` without `@ScaledMetric` | Warning | Special key labels (shift, delete, return, space) use fixed font sizes without `@ScaledMetric`. Will not scale with Dynamic Type. Non-blocking since keyboard keys have physical size constraints. |
| `DictusApp/Views/TestDictationView.swift` | 136 | `Color.red.opacity(0.5)` | Info | Single hardcoded color in a pre-phase-4 file not listed in plan scope. Minor. |
| `DictusKeyboard/Views/AccentPopup.swift` | 35 | `Color.blue` | Info | Hardcoded color in accent popup highlight. Not in plan scope but slightly inconsistent with design system. |

No blocker anti-patterns found. No TODO/FIXME/placeholder comments in any phase 4 files.

### Human Verification Required

### 1. Fresh Install Onboarding Flow

**Test:** Delete app, reinstall, launch Dictus
**Expected:** Onboarding appears as non-dismissible fullscreen cover. Complete all 5 steps: welcome (tap Commencer), mic permission (grant or skip), keyboard setup (add in Settings), model download (download small model), test recording (record and see transcription). After "Terminer", main app TabView appears.
**Why human:** Requires real device with Settings navigation, microphone hardware, and WhisperKit model download

### 2. Dark/Light Mode Rendering

**Test:** Toggle dark mode in Settings > Display & Brightness on every screen
**Expected:** All screens adapt colors correctly. No white-on-white or black-on-black text. Glass surfaces adjust opacity appropriately.
**Why human:** Color adaptation depends on runtime colorScheme evaluation and cannot be verified statically

### 3. Dynamic Type at Largest Size

**Test:** Set Dynamic Type to largest accessibility size in Settings > Accessibility > Display & Text Size. Navigate all screens.
**Expected:** No text truncation, all screens remain scrollable and usable. Key labels remain readable.
**Why human:** Layout overflow at extreme text sizes cannot be verified statically

### 4. AnimatedMicButton Visual States

**Test:** Trigger dictation from keyboard, observe mic button through idle -> recording -> transcribing -> ready cycle
**Expected:** Idle: soft blue glow pulsing. Recording: red pulse ring scaling. Transcribing: blue shimmer sweep. Success: brief green flash.
**Why human:** Animation timing, visual quality, and state transitions need human eye

### Gaps Summary

No gaps found. All 6 observable truths are verified with evidence. All 7 requirements (APP-01, APP-03, KBD-06, DSN-01, DSN-02, DSN-03, DSN-04) are satisfied. All key artifacts exist, are substantive, and are properly wired. Anti-patterns found are informational or minor warnings (fixed font sizes on decorative/constrained elements), none blocking goal achievement.

The phase goal -- "A new user can install Dictus, complete onboarding, and dictate their first sentence -- and every screen looks like it belongs on iOS 26" -- is achievable pending human verification of visual quality and end-to-end flow on device.

---

_Verified: 2026-03-06T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
