# Phase 4: Main App, Onboarding, and Polish - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

A new user installs Dictus, completes onboarding (permissions, keyboard setup, model download, test transcription), and dictates their first sentence. The main app is restructured with TabBar navigation. A Settings screen delivers all user preferences. Every screen in the app and keyboard extension uses iOS 26 Liquid Glass design with Material fallback on iOS 16-25. Mic button animations and recording waveform are redesigned to match the brand identity. No new transcription features, no new keyboard capabilities, no text prediction.

</domain>

<decisions>
## Implementation Decisions

### Onboarding flow
- 5-step fullscreen page sequence (swipeable), dark background (#0A1628), accent blue highlights
- Step 1: Welcome page — animated logo (3 bars appearing), "dictus" wordmark, tagline "Dictation vocale, 100% offline", [Commencer] button
- Step 2: Microphone permission — explain why, trigger system permission dialog
- Step 3: Add keyboard + Full Access — annotated screenshot of iOS Settings path with deep-link button to Settings. Auto-detect when user returns if keyboard was added. Show both keyboard addition and Full Access enablement on this step
- Step 4: Download model — "small" model pre-selected as recommended (~500MB), [Telecharger] button with progress, "Voir tous les modeles" link to full ModelManager
- Step 5: Test transcription — mandatory test recording to validate setup, pre-load/initialize the model, and demonstrate value to user. "Dites quelque chose !" prompt
- Screenshot + deep link for keyboard setup in v1; step-by-step animations deferred to future improvement (Remotion/Lottie)
- Onboarding is non-dismissible on first launch — user must complete all steps before reaching the main app

### App navigation
- TabBar with 3 tabs: Home, Models, Settings
- Tab 1 (Home): Dashboard with logo mark, active model status, last transcription preview, [Tester la dictee] quick action button
- Tab 2 (Models): Existing ModelManagerView (download, select, delete models)
- Tab 3 (Settings): All user preferences (see Settings section below)
- TabBar uses iOS 26 Liquid Glass styling with standard glass transitions between tabs
- RecordingView (dictus://dictate) hides TabBar — fullscreen overlay, immersive recording experience
- No model selector in Settings — the Models tab is the single source of truth for model management
- Diagnostic view moved from Home to Settings > A propos > Diagnostic

### Settings screen
- iOS-style grouped list with 3 sections:
  - **Transcription**: Langue (French/English picker, French default), Mots de remplissage toggle (on by default)
  - **Clavier**: Disposition (AZERTY/QWERTY picker, AZERTY default), Retour haptique toggle (on by default)
  - **A propos**: Version number, lien GitHub, Licences, Diagnostic (detail view)
- No model setting in Settings — handled by Models tab
- All preferences persisted via App Group UserDefaults (SharedKeys)
- Languages limited to French + English for v1

### Liquid Glass design system
- Apply `.glassEffect()` on ALL surfaces behind `#available(iOS 26, *)` with `Material.regularMaterial` fallback on iOS 16-25
- Glass on: TabBar, navigation bars, cards/sections, onboarding pages, keyboard container
- Keyboard (KBD-06): match native iOS 26 keyboard glass styling exactly — research iOS 26 beta keyboard appearance during planning
- SF Pro Rounded for headings, SF Pro Text for body, Dynamic Type throughout (DSN-04)
- Light and dark mode supported automatically — no hardcoded colors (DSN-03)

### Recording waveform redesign
- Replace current 30-bar waveform with 3-bar logo-inspired waveform
- Same 3 asymmetric bars as the logo (short left, tall center, medium right)
- Heights respond to audio energy in real-time with smooth spring animations
- Center bar uses accent gradient (#6BA3FF -> #2563EB), side bars white at 45%/65% opacity
- The logo "comes alive" during recording — brand identity reinforced in the core interaction
- Applies to both: RecordingOverlay in keyboard AND RecordingView in main app

### Mic button animations (DSN-02)
- Subtle + branded approach — premium but not distracting
- Idle: soft glow ring (accent blue #3D7EFF, low opacity)
- Recording: red pulsing ring (#EF4444), gentle scale breathing animation
- Transcribing: blue shimmer sweep across button
- Success: brief green flash (#22C55E) + checkmark
- All animations smooth, 0.3-0.8s duration
- Smart mode state (#8B5CF6) defined in brand kit but not implemented in v1 (deferred to v2 smart modes)

### Claude's Discretion
- Exact onboarding page transitions and animation timing
- Screenshot asset creation for keyboard setup step
- Auto-detection mechanism for keyboard installation
- TabBar icon choices (SF Symbols)
- Settings row styling details
- Glass effect intensity and blur radius
- Exact spring animation parameters for waveform
- How to handle onboarding "skip" if user has already set up keyboard from a previous install

</decisions>

<specifics>
## Specific Ideas

- "Je voudrais qu'on balaye tout le cote design de l'application" — this phase is a major design overhaul, not just adding features
- Recording waveform must be inspired by the logo's 3 asymmetric bars — the logo becomes alive during recording
- TabBar must use Liquid Glass with transitions matching modern iOS 26 apps (GitHub, Slack reference)
- Onboarding test transcription step is critical: validates setup + shows value + pre-loads model — three birds with one stone
- Brand kit at `assets/brand/dictus-brand-kit.html` is the design source of truth for all colors, gradients, and visual tokens
- Wordmark: "dictus" lowercase, weight 200, tracking -0.03em (DM Sans for brand, SF Pro Rounded for iOS UI)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ContentView.swift`: Current app entry point — will be completely restructured into TabBar + Home tab
- `ModelManagerView.swift` + `ModelManager.swift`: Complete model management UI — becomes Tab 2 content as-is
- `TestDictationView.swift`: Test dictation screen — moves into Home tab as quick action
- `RecordingView.swift`: Main app recording UI — stays as fullscreen overlay, waveform needs redesign
- `RecordingOverlay.swift`: Keyboard recording UI — waveform needs same redesign
- `ToolbarView.swift`: Keyboard toolbar with mic button — mic button gets animation polish
- `SharedKeys.swift`: Already has keys for model, layout, filler preferences — extend with language + haptic keys
- `DiagnosticView` in ContentView.swift: Moves to Settings > A propos
- `FullAccessBanner.swift`: Only file currently using Material — pattern exists for glass fallback

### Established Patterns
- `@StateObject` / `@EnvironmentObject` for state management
- App Group UserDefaults for cross-process persistence
- Darwin notifications for keyboard-app communication
- `#available(iOS 14.0, *)` guards for API availability — same pattern for `#available(iOS 26, *)`
- NavigationStack for in-tab navigation

### Integration Points
- `DictusApp.swift`: Add TabView wrapping, keep `.onOpenURL` for dictus://dictate
- `ContentView.swift`: Replace with TabView containing Home/Models/Settings tabs
- `SharedKeys`: Add `language`, `hapticsEnabled`, `fillerWordsEnabled`, `hasCompletedOnboarding` keys
- `KeyboardView.swift` + `KeyButton.swift`: Glass styling pass
- `RecordingView.swift` + `RecordingOverlay.swift`: New 3-bar waveform component
- `ToolbarView.swift`: Mic button animation states

</code_context>

<deferred>
## Deferred Ideas

- **Step-by-step onboarding animations** — Remotion/Lottie animated walkthrough for keyboard setup. Upgrade from screenshot approach in future version.
- **Smart mode mic button state** — Brand kit defines purple (#8B5CF6) smart mode state. Implemented when v2 smart modes (MODE-01 to MODE-05) are built.
- **All WhisperKit languages** — v1 limited to French + English. Expand language picker when more languages are tested.

</deferred>

---

*Phase: 04-main-app-onboarding-and-polish*
*Context gathered: 2026-03-06*
