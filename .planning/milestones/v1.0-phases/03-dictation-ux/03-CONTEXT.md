# Phase 3: Dictation UX - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

The full dictation loop works fluidly from the keyboard: tap mic, record (with visual feedback in the keyboard itself), stop, transcribe, auto-insert text. Includes QWERTY layout alternative, accented characters on AZERTY, haptic feedback, and in-app test dictation screen. No onboarding, no settings screen, no design system pass (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Dictation flow (Wispr Flow-inspired)
- Tap mic in keyboard toolbar -> DictusApp opens briefly (for microphone activation) -> auto-return to the app the user was in
- Recording continues while user is back in their app — keyboard shows recording UI
- Keyboard letters are entirely replaced by recording UI during active recording
- Recording UI: waveform animation (center), timer (below waveform), X cancel (top-left), checkmark stop (top-right)
- After stop: keyboard stays in recording UI mode showing "processing" state until transcription completes
- Text auto-inserts via `textDocumentProxy.insertText()` — no preview bar, no confirmation step
- After insertion: keyboard snaps back to normal letter layout immediately — no confirmation message
- **Architecture change from Phase 1:** Recording/stop now controlled from the keyboard UI, not from DictusApp. Researcher must investigate feasibility (recording in keyboard extension vs background audio in main app with real-time signaling)

### Undo behavior
- No dedicated undo button — DUX-02 dropped by user decision
- If user doesn't like transcription, they select and delete manually
- Simplest possible flow: dictate -> text appears -> done

### Mic button design (Wispr Flow reference)
- Toolbar row above keyboard letters: app/settings shortcut (left), mic button (right)
- Mic button: round, top-right of toolbar, similar to Wispr Flow but slightly larger
- Mic button states: subtle/muted when idle, animated when recording (keyboard transforms), shimmer/spinner when transcribing
- Let animations carry the state distinction, not bold color changes
- During recording mode: X (cancel, top-left) discards recording and returns to keyboard; checkmark (stop, top-right) sends audio to transcription
- Timer visible below waveform during recording
- Reference: Wispr Flow iOS keyboard screenshots provided by user (idle state + recording state)

### Text insertion
- Auto-insert directly into active text field — no preview bar (ROADMAP success criterion #1 overridden by user)
- No confirm/dismiss buttons (ROADMAP success criterion #2 overridden by user)
- No post-insertion confirmation message — text appearing in the field IS the feedback

### Haptic feedback
- DUX-03 still applies: haptics on recording start, recording stop, and text insertion
- Implementation details at Claude's discretion (UIImpactFeedbackGenerator)

### Layout switching
- AZERTY (default) + QWERTY available, switchable from Settings screen only (no in-keyboard toggle)
- Layout preference persisted in App Group UserDefaults
- QWERTY layout: no accented characters (English typing only)
- AZERTY layout: add long-press accented character popups (e, e, e, e, a, a, a, u, u, c, etc.) — matching standard iOS French keyboard behavior
- Accented characters were deferred from Phase 1 — delivered now

### In-app test dictation screen
- APP-04: Test screen for end-to-end transcription testing without leaving Dictus
- Placement in app navigation: Claude's discretion (simple approach, full navigation redesign deferred to Phase 4)

### Claude's Discretion
- Exact toolbar dimensions and mic button sizing
- Waveform animation style during recording (bar count, colors, animation speed)
- Processing/transcribing state animation in keyboard
- Haptic feedback intensity and generator types
- Test dictation screen layout and integration point
- Accented character popup positioning and available characters per key
- How the toolbar left button (app/settings shortcut) works technically from a keyboard extension

</decisions>

<specifics>
## Specific Ideas

- "Je veux reproduire l'UX de Wispr Flow" — the gold standard reference for the keyboard recording experience
- Wispr Flow screenshots provided: (1) idle state with mic button top-right, "Flow" button, standard keyboard; (2) recording state with X/checkmark, centered waveform, "Listening" label, keyboard fully replaced
- The mic button should be the obvious main feature — the keyboard exists for typing AND dictation equally
- "Quitte a y passer du temps" — Pierre wants premium recording UX, willing to invest effort here
- During recording, keyboard should feel immersive — letters disappear, it's all about the voice input
- After transcription, snap back to keyboard instantly — no delay, no message, text just appears

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TranscriptionStub` (KeyboardRootView.swift:68-87): Phase 1 placeholder — to be removed and replaced by auto-insert logic
- `StatusBar` (KeyboardRootView.swift:46-64): Reusable for toolbar-style bar above keyboard, may evolve into the mic toolbar
- `KeyboardState` (KeyboardState.swift): Already tracks dictationStatus and lastTranscription via Darwin notifications — extend for new recording-in-keyboard flow
- `WaveformView` (RecordingView.swift:152-180): Existing waveform component in main app — pattern reusable for keyboard waveform (may need adaptation for extension constraints)
- `KeyboardLayout` (Models/): Data-driven layout system — extend with QWERTY layout data
- `MicKey` (KeyboardView.swift:115-146): Current mic button using `Link(destination:)` — will be redesigned as toolbar mic button
- `KeyboardRootView` (KeyboardRootView.swift): Composition root — needs restructuring to support recording mode that replaces keyboard

### Established Patterns
- `Link(destination:)` for URL scheme opening from keyboard extension (no UIApplication.shared)
- Darwin notifications + UserDefaults for cross-process communication
- `@StateObject` ownership of `KeyboardState` in root view
- `Task.sleep` for async operations in keyboard extensions (not Timer)
- `GeometryReader` for responsive keyboard layout

### Integration Points
- `KeyboardRootView`: Needs conditional rendering — normal keyboard vs recording UI
- `KeyboardState`: Needs new states/properties for recording-in-keyboard mode
- `DictationCoordinator` in DictusApp: May need changes if recording architecture shifts
- `SharedKeys` in DictusCore: May need new keys for real-time waveform data or recording control
- `KeyboardLayout`: Add QWERTY layout data alongside existing AZERTY
- `KeyRow`/`KeyButton`: Add long-press gesture for accented character popups on AZERTY

</code_context>

<deferred>
## Deferred Ideas

- **Logo and brand identity (Direction Artistique)** — Pierre wants to brainstorm logo and overall visual identity. Belongs in Phase 4 (DSN-01 to DSN-04).
- **App navigation structure (TabBar)** — Pierre envisions bottom tab bar with home, settings, models pages instead of current single-page app. Belongs in Phase 4 (APP-01 onboarding, APP-03 settings).
- **Full design system pass** — Liquid Glass, SF Pro typography, Dynamic Type, light/dark mode audit. Phase 4 scope.

</deferred>

---

*Phase: 03-dictation-ux*
*Context gathered: 2026-03-06*
