# Phase 9: Keyboard Modes - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Users choose the keyboard layout that fits their usage — dictation-focused (mic only), emoji+mic, or full AZERTY — with a live preview in settings and mode selection during onboarding. Covers three switchable modes, settings UI with segmented picker and miniature previews, onboarding integration, and App Group persistence.

Requirements: MODE-01, MODE-02, MODE-03, MODE-04

</domain>

<decisions>
## Implementation Decisions

### Micro mode layout
- Giant centered mic pill button (~120pt wide, pill shape with "Dicter" label) — Voice Memos style
- Globe button in bottom-left corner for switching to other iOS keyboards
- No other controls (no backspace, no space bar, no suggestions)
- Dictation-only mode — to correct text, user switches keyboard via globe or changes mode in Settings
- Recording uses same RecordingOverlay as full keyboard (waveform + timer + cancel/validate pills)
- Same keyboard height as other modes to prevent layout jump when switching

### Emoji + Micro mode layout
- Full EmojiPickerView reused from Phase 7 (horizontal LazyHGrid, 4 rows, category bar)
- Emoji search bar (mini keyboard) available — same as Phase 7 implementation
- Mic pill in toolbar above emoji picker (same toolbar as full keyboard)
- No suggestion bar — toolbar shows mic pill only (no gear, no predictions)
- Globe in category bar or standard iOS position for keyboard switching
- Recording overlay replaces entire view (emoji grid disappears) — same RecordingOverlay

### Clavier complet mode
- Current full AZERTY/QWERTY keyboard — no changes
- All existing features active: suggestions, trackpad, adaptive accent, haptics, autocorrect

### Settings UI — mode picker
- Segmented picker (SegmentedControl) with 3 segments: "Micro" | "Emoji+" | "Complet"
- Below the picker: non-interactive miniature keyboard mockup of the selected mode
- Mockups are simplified SwiftUI views (not screenshots) — mini representations of each mode's layout
- Mode picker absorbs the AZERTY/QWERTY disposition picker:
  - AZERTY/QWERTY picker only visible when "Complet" mode is selected
  - Hidden for Micro and Emoji+ modes (layout irrelevant)
- Conditional toggles based on selected mode:
  - Micro: hide "Correction automatique" and "Retour haptique" (no typing)
  - Emoji+: hide "Correction automatique" (no typing), keep haptics (emoji taps)
  - Complet: show all toggles
- Reusable component: KeyboardModePicker (segmented + preview) shared between Settings and onboarding

### Onboarding integration
- New page added after keyboard setup, before model download:
  1. Micro permission
  2. Add keyboard
  3. **Choose mode** (new)
  4. Download model
  5. Done
- Uses same KeyboardModePicker component as Settings (segmented picker + preview)
- Title: "Choisissez votre clavier"
- No default pre-selected — user must tap one to proceed (blocking step like other onboarding steps)
- "Continuer" button enabled only after selection

### Mode switching behavior
- Mode changed only from app Settings (or during onboarding) — no in-keyboard mode switching
- Globe button in keyboard = advanceToNextInputMode (switch iOS keyboards), not mode switch
- Mode persisted via App Group SharedKeys (new key: `dictus.keyboardMode`)
- Keyboard reads mode on each open (same pattern as AZERTY/QWERTY layout switch) — no restart needed
- Immediate effect: next keyboard appearance uses new mode

### Claude's Discretion
- Exact miniature mockup design and proportions for each mode preview
- Segmented picker styling (Liquid Glass or native iOS style)
- Animation when switching between mode previews in Settings
- Micro mode mic button Liquid Glass styling details (glow, gradient)
- Exact onboarding page layout and spacing

</decisions>

<specifics>
## Specific Ideas

- User concern: "J'ai peur que l'utilisateur ne decouvre jamais ce parametre" — solved by adding mode choice to onboarding flow
- Reuse strategy: same KeyboardModePicker component in both Settings and onboarding, one codebase to maintain
- Mini keyboard mockups should feel like looking at the actual keyboard from a distance — recognizable at a glance
- Micro mode is the "Dictus differentiator" — the unique selling point for dictation-first users

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictusKeyboard/Views/EmojiPickerView.swift`: Full emoji picker with LazyHGrid, category bar, search — reuse as-is for Emoji+Micro mode
- `DictusKeyboard/Views/ToolbarView.swift`: Toolbar with gear + suggestions + mic pill — reuse for Emoji+Micro (mic only, no suggestions)
- `DictusKeyboard/Views/RecordingOverlay.swift`: Recording UI with waveform + timer + cancel/validate — reuse in all 3 modes
- `DictusCore/Design/AnimatedMicButton.swift`: Mic pill with 4 states + Liquid Glass — scale up for Micro mode's giant mic button
- `DictusCore/Sources/DictusCore/SharedKeys.swift`: Centralized App Group keys — add `keyboardMode` key
- `DictusApp/Views/SettingsView.swift`: Settings with @AppStorage + App Group — add mode picker section

### Established Patterns
- `@AppStorage(SharedKeys.X, store: UserDefaults(suiteName: AppGroup.identifier))` for cross-process preferences
- `KeyboardLayout.currentLettersRows()` reads layout from App Group on each call — same pattern for mode
- Onboarding uses switch/case (not TabView) to block step swiping — add new case for mode selection
- `KeyboardRootView` conditionally renders toolbar + keyboard or recording overlay — extend with mode-based rendering

### Integration Points
- `KeyboardRootView.swift` — Read mode from App Group, render Micro/Emoji+Micro/Full based on mode
- `SettingsView.swift` — Replace "Disposition" section with mode picker + conditional layout picker
- `OnboardingView.swift` — Insert mode selection page between keyboard setup and model download
- `SharedKeys.swift` — Add `keyboardMode` static key
- `KeyboardLayout.swift` — No changes needed (layout data stays, rendering changes in KeyboardRootView)

</code_context>

<deferred>
## Deferred Ideas

- **In-keyboard mode switching** (long-press gear to change mode) — could be added later if Settings-only proves too inconvenient
- **Mode-specific keyboard height** — Micro could be shorter since it only has mic + globe. Deferred to avoid layout jump complexity.

</deferred>

---

*Phase: 09-keyboard-modes*
*Context gathered: 2026-03-09*
