# Phase 6: Infrastructure & App Polish - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Consolidate duplicated design files into a shared package importable by both DictusApp and DictusKeyboard. Generate app icon from brand kit. Fix all app-side visual bugs: HomeView stale state, duplicate title, onboarding flow blocking, and test recording screen redesign. Every subsequent phase builds on this clean, consolidated codebase.

Requirements: INFRA-01, INFRA-02, VIS-04, VIS-05, VIS-06, VIS-07, VIS-08

</domain>

<decisions>
## Implementation Decisions

### Test Recording & Stop Screens (VIS-04, VIS-05)
- Single shared screen reused in both onboarding (step 5) and HomeView ("Tester la dictee" button)
- Immersive centered design: large mic button centered on screen, waveform as ambient background behind it (like Voice Memos)
- Transcription result replaces the waveform area: waveform fades out, text fades in at the same position — no card, simple transition
- Haptic feedback on mic button tap (start recording) and stop button tap (stop recording)

### Onboarding Flow (VIS-08)
- Model download step: auto-download default model (small) — no user choice during onboarding
- Reword download step with clear explanation: "Pour la transcription, on a besoin de telecharger un modele vocal" + confirm button + auto-download
- Pre-load model (WhisperKit warmUp/loadModel) immediately after download completes, while user is still on the download completion screen — so mic tap on test recording step starts instantly with no 2-3s delay
- Keyboard added detection: auto-detect via UITextInputMode.activeInputModes when app returns to foreground (no manual confirm button)
- Progression blocking and visual indication of incomplete steps: Claude's Discretion

### HomeView (VIS-06, VIS-07)
- Remove `.navigationTitle("Dictus")` — the logo section with blue "Dictus" text already serves as the page title, the white navigation title is a doublon
- Fix post-onboarding bug: ensure modelManager.isModelReady correctly reflects downloaded model state so "Telecharger un modele" card doesn't show when a model exists
- Model card: display user-friendly name ("Whisper Small" instead of "openai_whisper-small") + model size in MB

### App Icon (INFRA-02)
- Generate from brand kit SVG (assets/brand/dictus-brand-kit.html)
- Adjust for readability at small sizes (38pt home screen icon)
- Variants and approach: Claude's Discretion (Light + Dark + Tinted if standard practice)

### Design Consolidation (INFRA-01)
- 6 files currently duplicated between DictusApp/Design/ and DictusKeyboard/Design/: AnimatedMicButton, BrandWaveform, DictusColors, DictusTypography, GlassModifier, ProcessingAnimation
- DictusLogo exists only in DictusApp/Design/ (not duplicated)
- Consolidate into a shared package importable by both targets — approach is Claude's Discretion

### Claude's Discretion
- Onboarding blocking UX: how strictly to block (disable swipe vs button-only), visual indication of incomplete steps
- App icon variant strategy (Light/Dark/Tinted)
- Design consolidation approach (DictusCore extension, new DictusUI SPM package, or other)
- Test recording screen layout details (exact spacing, animation timing)

</decisions>

<specifics>
## Specific Ideas

- Test recording screen should feel immersive and centered, like Voice Memos — big mic, ambient waveform
- Super Whisper reference: waveform is perfectly still when no sound, only reacts to actual audio input (noted for Phase 7 VIS-03)
- Super Whisper reference: processing state = waveform switches to sinusoidal animation instead of a spinner (noted for Phase 7 VIS-03)
- Handy app reference: model cards with accuracy/speed gauges — clean way to show model comparison (noted for Phase 10 MOD-03)
- Model name on HomeView should be human-readable, not the technical identifier

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictusApp/Design/DictusColors.swift`: Color definitions used throughout (`.dictusBackground`, `.dictusAccent`, `.dictusSuccess`, `.dictusRecording`)
- `DictusApp/Design/GlassModifier.swift`: `.dictusGlass()` modifier for Liquid Glass effect
- `DictusApp/Design/DictusTypography.swift`: Font definitions (`.dictusHeading`, `.dictusBody`, `.dictusCaption`, `.dictusSubheading`)
- `DictusApp/Design/AnimatedMicButton.swift`: Mic button component (exists in both targets)
- `DictusApp/Design/BrandWaveform.swift`: Waveform visualization (exists in both targets)
- `DictusApp/Design/DictusLogo.swift`: Brand logo component (DictusApp only)
- `DictusApp/Design/ProcessingAnimation.swift`: Processing state animation (exists in both targets)

### Established Patterns
- Liquid Glass theme via `.dictusGlass()` modifier — all cards use this
- Brand colors via `Color.dictus*` extensions
- `@EnvironmentObject var coordinator: DictationCoordinator` for dictation state
- `@ObservedObject var modelManager: ModelManager` for model state
- App Group shared via `AppGroup.defaults` and `SharedKeys`
- `@SceneStorage` for persisting onboarding page across scene phase changes

### Integration Points
- `DictusApp/Views/HomeView.swift:42` — `.navigationTitle("Dictus")` to remove (VIS-06)
- `DictusApp/Views/HomeView.swift:69-101` — model status card logic to fix (VIS-07)
- `DictusApp/Onboarding/OnboardingView.swift` — TabView paging to add blocking gates (VIS-08)
- `DictusApp/Onboarding/TestRecordingPage.swift` — redesign target (VIS-04/VIS-05)
- `DictusApp/Onboarding/ModelDownloadPage.swift` — add warmUp after download + reword UX
- `DictusCore/Sources/` — potential home for shared design package (INFRA-01)

</code_context>

<deferred>
## Deferred Ideas

- **Mic start/stop sound effect** — Audio feedback when activating/deactivating microphone. Requires sound design work (asset creation, tool research). Future milestone.
- **Waveform at rest = perfectly still** — Currently has micro-movements even without sound input. Super Whisper does this well. Scope: Phase 7 (VIS-03 waveform rework).
- **Sinusoidal processing animation** — Replace spinner with waveform switching to sinusoidal motion during transcription. Super Whisper reference. Scope: Phase 7 (VIS-03).
- **Accuracy/speed gauges in model catalog** — Handy-style gauge bars showing accuracy and speed per model. Scope: Phase 10 (MOD-03 model selection UI update).

</deferred>

---

*Phase: 06-infrastructure-app-polish*
*Context gathered: 2026-03-07*
