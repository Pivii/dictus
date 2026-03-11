# Phase 12: Animation State Fixes - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Eliminate intermittent recording overlay and waveform animation bugs across all dictation state transitions. The overlay must appear reliably every time, rapid taps must never leave stale state, and animations must stop cleanly. This phase fixes the CURRENT recording architecture (warm + cold start paths via app). Phase 13 will add the Audio Bridge path — ~80% of Phase 12's work is foundational and survives that change.

</domain>

<decisions>
## Implementation Decisions

### Overlay visibility on .requested
- Overlay appears IMMEDIATELY on mic tap (when status transitions to .requested)
- During .requested: flat waveform bars (no energy data yet), cancel button only (no validate), status text "Démarrage..."
- When .recording arrives: waveform starts moving, validate button appears, status changes to "Listening..." + timer
- No timeout message — overlay stays with "Démarrage..." until .recording arrives, even on cold start URL scheme path

### Rapid tap behavior
- Claude's discretion on the exact mechanism (disable during transitions, debounce, or combination)
- Short recordings (< 1s) are still transcribed — honor user intent, let WhisperKit handle empty results
- No cooldown after transcription — mic re-enables instantly when status returns to .idle/.ready
- Power users can dictate sentence by sentence rapidly

### State reset and recovery
- TWO recovery mechanisms (belt and suspenders):
  1. **Periodic watchdog** during active recording/transcribing: if no waveform updates for ~5s, force-reset to .idle
  2. **Reset on keyboard appear** (viewWillAppear): check if dictationStatus is stale and force-reset
- Recovery applies to BOTH keyboard (KeyboardState) AND main app (DictationCoordinator)
  - Keyboard watchdog: during .recording/.transcribing states
  - App watchdog: if transcription hangs for ~30s, auto-reset to .idle
- Silent reset — no user-facing error message, just log the event. "It just fixed itself."

### Logging for diagnosis
- Claude's discretion on exact depth, calibrated for diagnosing intermittent bugs
- Minimum: every DictationStatus state change with timestamp + source (keyboard vs app)
- Recommended additions: overlay show/hide events, watchdog triggers, rapid tap rejections
- Consistent with Phase 11's structured logging approach (LogEvent types, not free-text)
- No per-frame or per-buffer logging

### Claude's Discretion
- Exact rapid tap protection mechanism (disable during transitions vs debounce vs combo)
- Logging depth calibration (state transitions + overlay events + watchdog events, skip silent periodic checks)
- Animation reset implementation details (SwiftUI state invalidation approach)
- Whether to refactor DictationStatus enum or add overlay-specific state tracking
- Watchdog timer intervals and stale thresholds

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RecordingOverlay` (DictusKeyboard/Views/RecordingOverlay.swift): Full overlay with waveform, timer, cancel/stop. Needs .requested state support
- `AnimatedMicButton` (DictusCore/Design/AnimatedMicButton.swift): 4-state animated button. Uses onChange(of: status) + DispatchQueue.main.asyncAfter — potential race condition source
- `BrandWaveform` (DictusCore/Design/BrandWaveform.swift): Canvas-based 30-bar waveform with lerp smoothing. Already handles isProcessing mode
- `KeyboardState` (DictusKeyboard/KeyboardState.swift): Observes cross-process state via Darwin notifications. Has refreshFromDefaults() and waveform reading
- `DictationCoordinator` (DictusApp/DictationCoordinator.swift): Manages dictation lifecycle. updateStatus() writes to App Group + posts Darwin notification

### Key Bug Surface Areas
- `KeyboardRootView.swift:72`: Overlay condition is `status == .recording || .transcribing` — missing `.requested`
- `AnimatedMicButton.swift:185`: asyncAfter(deadline: .now() + 0.3) for success flash — race condition on rapid transitions
- `KeyboardState.swift:107-109`: requestCancel() resets local state immediately but Darwin notification is async — potential mismatch
- `DictationCoordinator.swift:183`: startDictation guard doesn't cover .requested state — could allow duplicate starts

### Established Patterns
- Darwin notifications + App Group UserDefaults for cross-process state sync
- @MainActor + DispatchQueue.main.async for thread safety in notification handlers
- Combine sinks for forwarding AudioRecorder state to coordinator
- PersistentLog.log(.event) structured logging API from Phase 11

### Integration Points
- `KeyboardRootView`: Overlay visibility condition needs .requested state
- `RecordingOverlay`: Needs new .requested visual state (flat waveform + "Démarrage..." + cancel only)
- `KeyboardState`: Needs watchdog timer during active states
- `DictationCoordinator`: Needs transcription timeout watchdog
- `AnimatedMicButton`: Needs race-safe animation transitions

</code_context>

<specifics>
## Specific Ideas

- User confirmed seeing intermittent animation bugs on device — logging must be sufficient to diagnose these in beta
- Phase 13 compatibility: the animation state machine and recovery mechanisms should be generic enough to support the future Audio Bridge recording path without rework

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. User raised a valid concern about Phase 13 overlap, but analysis showed ~80% of Phase 12 work is foundational and the roadmap order is correct ("stable animation required before adding new recording paths").

</deferred>

---

*Phase: 12-animation-state-fixes*
*Context gathered: 2026-03-11*
