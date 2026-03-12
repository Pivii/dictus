# Phase 13: Cold Start Audio Bridge - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

When iOS has killed the app (cold start), users experience seamless dictation: mic tap opens the app, app activates audio session, user returns to keyboard, keyboard captures audio directly, app transcribes, result auto-inserts into text field. Includes swipe-back overlay UX and auto-return via URL scheme for known apps. Direct recording from the app (HomeView mic button) remains fully functional.

</domain>

<decisions>
## Implementation Decisions

### Cold start flow (core sequence)
- User taps mic in keyboard → keyboard opens app via URL scheme
- App activates audio session + loads WhisperKit
- App attempts auto-return to previous app via URL scheme (for known apps)
- If auto-return fails → shows swipe-back overlay
- **Recording does NOT start when app opens** — it starts when user returns to keyboard
- Keyboard detects it's back in foreground and starts capturing audio directly
- Keyboard sends captured audio to app for transcription
- App transcribes and sends result back via Darwin notification + App Group
- Keyboard auto-inserts result into text field (same as current flow)

### Audio capture (Audio Bridge)
- Keyboard extension captures audio directly using its own AVAudioEngine (Audio Bridge pattern)
- App's role on cold start is limited to: activate audio session, load WhisperKit, transcribe
- Audio transfer from keyboard to app: Claude's Discretion (evaluate App Group file vs UserDefaults vs shared container — research needed on size limits and reliability)
- Recording trigger on keyboard return: Claude's Discretion (evaluate viewWillAppear with App Group flag vs other keyboard lifecycle hooks)

### Swipe-back overlay
- Full-screen replacement view (NOT overlay on top of normal app UI) — only shows on cold start from keyboard
- Background: Dictus brand gradient (#0D2040 → #071020)
- Content: iPhone outline with animated hand/thumb performing swipe gesture (SwiftUI animation, no Lottie)
- Reference: SuperWhisper's swipe-back overlay (screenshot in /tmp/superwhisper_overlay.png)
- Text matches user language setting (SharedKeys.language):
  - FR: "Glisse pour revenir au clavier" + "Glisse vers la droite en bas de l'écran"
  - EN: "Swipe back to the keyboard" + "Swipe right on the bottom of your iPhone"
- Overlay stays visible until user leaves the app (no auto-dismiss timeout)

### Auto-return strategy
- Target: top 10 messaging apps (WhatsApp, iMessage/SMS, Telegram, Messenger, Signal, Slack, Discord, Teams, Instagram DM, Notes)
- Auto-return attempted FIRST, before showing swipe overlay — if URL scheme works, user barely sees the app
- If auto-return fails → swipe overlay appears as fallback
- Source app detection method: Claude's Discretion — requires deep research into public API options (no private APIs like LSApplicationWorkspace or _hostBundleID). Keyboard can write context to App Group before opening URL.

### Two-mode coexistence
- Direct recording (HomeView mic button) must remain fully functional — identical to v1.1
- Both flows can share DictationCoordinator state machine if it simplifies code — Claude's Discretion on architecture
- App distinguishes "opened from keyboard" vs "opened normally": Claude's Discretion (URL parameter, App Group flag, or other)
- Priority: keep code simple and maintainable over complex abstractions

### Transcription result delivery
- Same as current: result written to App Group + Darwin notification to keyboard + auto-insert via textDocumentProxy
- No preview/confirmation step — silent auto-insert

### Claude's Discretion
- Audio transfer mechanism (App Group file vs shared container vs other)
- Keyboard recording trigger (viewWillAppear + flag vs other lifecycle hook)
- Source app detection for auto-return (research needed — must be public API only)
- Launch mode detection (URL parameter vs App Group flag)
- Architecture: whether to unify both recording paths under one DictationCoordinator state machine or keep separate
- iPhone outline + hand animation implementation details (SF Symbols, custom drawing, etc.)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RawAudioCapture` (DictusApp/Audio/RawAudioCapture.swift): Lightweight AVAudioEngine capture, 16kHz mono Float32 output — could be model for keyboard-side capture
- `DictationCoordinator` (DictusApp/DictationCoordinator.swift): Full dictation lifecycle manager with cold start support, RawAudioCapture integration, transcription watchdog
- `DarwinNotificationCenter` (DictusCore/DarwinNotifications.swift): Already has startRecording, stopRecording, cancelRecording, statusChanged, transcriptionReady, waveformUpdate notifications
- `KeyboardState` (DictusKeyboard/KeyboardState.swift): Observes cross-process state, has watchdog timer, openURLFromExtension() for URL scheme
- `RecordingOverlay` (DictusKeyboard/Views/RecordingOverlay.swift): Keyboard-side recording UI with waveform, timer, cancel/stop — needs to work with keyboard-captured audio
- `AudioRecorder` (DictusApp/Audio/AudioRecorder.swift): WhisperKit AudioProcessor wrapper with isEngineRunning state and collectSamples() pattern

### Established Patterns
- Darwin notifications (ping-only) + App Group UserDefaults for cross-process data
- URL scheme `dictus://dictate` for cold start app opening from keyboard
- 500ms Darwin notification timeout → fallback to URL scheme (KeyboardState.swift:279)
- @MainActor singletons for shared state (DictationCoordinator.shared)
- Phase 12 watchdog recovery: 5s waveform watchdog in keyboard, 30s transcription watchdog in app

### Integration Points
- `DictusApp.swift:82`: handleIncomingURL already handles `dictus://dictate` — needs to support swipe overlay mode
- `MainTabView`: needs conditional rendering (swipe overlay vs normal tabs) based on launch mode
- `KeyboardState`: needs new "pending cold start" state + recording trigger on keyboard return
- New Darwin notifications may be needed (e.g., "audio session ready", "keyboard recording complete")
- Brand kit (`assets/brand/dictus-brand-kit.html`): gradient values for swipe overlay background

</code_context>

<specifics>
## Specific Ideas

- Swipe-back overlay should look like SuperWhisper's: iPhone outline with animated hand swiping right on home indicator. Dark branded background, centered vertically, clean typography.
- The priority is getting the base flow working first (mic tap → app opens → swipe overlay → user returns → recording starts). Auto-return is secondary.
- Competitors (Wispr Flow, SuperWhisper) handle cold start with auto-return — this is the #1 UX priority for v1.2.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 13-cold-start-audio-bridge*
*Context gathered: 2026-03-12*
