# Phase 15: Design Polish - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

All user-facing UI reaches beta quality with correct French localization, polished interaction details, and critical bugfixes. Scope includes DSGN-01 through DSGN-07 requirements plus GitHub issues #25, #26, #27, #28. Also includes diagnosing/fixing an intermittent waveform disappearance bug in the keyboard recording overlay.

</domain>

<decisions>
## Implementation Decisions

### Model card redesign
- **Active model highlight**: Subtle blue background tint (dictusAccent at ~0.08-0.12 opacity) on the active model card — no border, no "Actif" badge
- **Tap to select**: Tapping anywhere on a downloaded model card selects it as active. Remove "Choisir" button entirely
- **Tap to download**: Tapping anywhere on a non-downloaded model card starts the download. Remove download arrow icon button. User can cancel during download
- **Swipe to delete**: Remove visible trash button. Swipe left to reveal "Supprimer" action (like iOS Mail). Active model cannot be deleted
- **Gauge bar colors**: Change from blue/green to blue accent (#3D7EFF for Précision) + blue highlight (#6BA3FF for Vitesse). No more dictusSuccess green
- **Badges**: WK/PK engine badge and "Recommandé" badge stay as-is

### Recording overlay dismiss
- **X button hit area**: Keep visual size (56x36 PillButton) but add invisible `.contentShape(Rectangle())` to ensure 44pt minimum tap area
- **Haptic feedback**: Claude's discretion on impact style (light vs medium) for both X (cancel) and checkmark (validate)
- **Dismiss animation**: Smooth easeOut animation applied on both cancel AND transcription complete. Claude's discretion on slide-down+fade vs fade-only

### Mic button transcription feedback
- **Scope**: Both pill (keyboard toolbar) and circle (HomeView) — AnimatedMicButton in both modes
- **Approach**: Claude evaluates current opacity 0.5 + shimmer and adjusts if needed. Both contexts must be consistent

### French accent audit
- **Scope**: UI strings only (Text(), Label(), .navigationTitle(), alert messages) — not code comments
- **Method**: Systematic grep of all .swift files for French strings missing accents
- **Known issues**: "Recommande" → "Recommandé", "Demarrage..." → "Démarrage...", "Reessayer" → "Réessayer", "Precision" → "Précision"

### Onboarding success screen (#27)
- **Replace current**: After transcription test completes, replace the inline "Terminer" button with a full-screen success overlay
- **Transition**: Fade out test interface → fade in success screen (~0.6s total)
- **Checkmark animation**: Scale bounce (0 → 1.1 → 1.0) with green circle behind white checkmark — Apple Pay style
- **Text**: Title "C'est prêt !", subtitle "Dictus est configuré et prêt à l'emploi", button "Commencer"
- **Tap "Commencer"**: Navigate to home screen

### Settings visual feedback (#28)
- **Tap highlight**: Ensure all Settings options use Button inside List (not onTapGesture) for native iOS gray highlight on press. Fix any custom buttonStyle that masks the pressed state
- **Log export spinner**: Replace "Exporter" text with inline ProgressView() during log preparation. Share sheet appears when ready

### Bug: onboarding model not recognized (#25)
- Model downloaded during onboarding not showing as downloaded/active on Models page
- Root cause: likely SharedPreferences sync issue between onboarding flow and ModelManager
- Fix: ensure onboarding persists download state + active model to App Group, and ModelManager reads it on appear

### Bug: crash on return from keyboard settings (#26)
- Intermittent crash (~1 in 2-3) when returning from iOS Settings after enabling keyboard + Full Access during onboarding
- Likely race condition in scenePhase / didBecomeActive during keyboard status check
- Need crash log analysis + logging around the onboarding keyboard detection flow

### Bug: intermittent waveform disappearance in keyboard
- Recording overlay sometimes shows buttons + text but no waveform animation
- Random, hard to reproduce. Removing/re-adding keyboard doesn't reliably fix it
- Approach: Add detailed logging in RecordingOverlay (waveformEnergy count, BrandWaveform render state), diagnose root cause, fix if possible

### Claude's Discretion
- Dismiss animation style (slide-down+fade vs fade-only)
- Haptic feedback style for overlay buttons (light vs medium impact)
- Mic button transcription opacity adjustment (current 0.5 may be sufficient)
- Exact blue background opacity for active model card (0.08-0.12 range)
- Success screen checkmark animation timing and spring parameters

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AnimatedMicButton`: Already has transcribing state with shimmer — may only need opacity tweak
- `PillButton` (in RecordingOverlay): Reusable for X/checkmark with added hit area
- `dictusGlass()`: Glass modifier used on all cards — active card needs overlay on top
- `GaugeBarView`: Takes color parameter — just change the color constants
- `GlassPressStyle`: Existing button style with press scale animation
- `BrandWaveform`: The waveform component used in recording overlay

### Established Patterns
- `@ScaledMetric` for Dynamic Type support in keyboard extension views
- `PersistentLog.log()` for all state transitions and diagnostics
- `withAnimation(.easeOut)` for state-driven animations (Phase 12 pattern)
- Pre-allocated haptic generators (static instances for zero-latency feedback)
- `SharedPreferences` via App Group for cross-process state

### Integration Points
- `ModelCardView` → `ModelManagerView` (card layout changes)
- `RecordingOverlay` → `KeyboardRootView` (dismiss animation)
- `AnimatedMicButton` → `ToolbarView` (pill mode) + `HomeView` (circle mode)
- `SettingsView` → various settings sections (button/list style)
- `OnboardingView` → `TestDictationPage` (success screen transition)
- `ModelManager` → `ModelDownloadPage` (onboarding sync bug #25)
- `KeyboardSetupPage` → `scenePhase` handling (crash bug #26)

</code_context>

<specifics>
## Specific Ideas

- "Je suis pas hyper fan du vert" — Pierre wants gauge bars to stay within the blue brand palette, no green
- Active model card visual should be obvious without reading text — background tint is the primary indicator
- Model cards should feel like radio buttons: tap to select, no extra "Choisir" button needed
- Same for download: tap the card = start download, keep it simple
- Success screen inspired by Apple Pay checkmark and AirPods setup completion screen
- Waveform bug needs diagnostic logging before attempting fix — the issue is intermittent and hard to reproduce

</specifics>

<deferred>
## Deferred Ideas

- **#24: Sound feedback for recording start/stop** — Full feature with SoundFeedbackService, settings page, WAV files. Separate phase (post-beta or v1.3)
- **Confetti/particle animation** for success screen — considered but scale bounce is more appropriate for a utility app

</deferred>

---

*Phase: 15-design-polish*
*Context gathered: 2026-03-13*
