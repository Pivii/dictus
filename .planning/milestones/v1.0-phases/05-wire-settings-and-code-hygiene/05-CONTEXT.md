# Phase 5: Wire Settings & Code Hygiene - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Make all Settings toggles functional end-to-end (language, filler words, haptics) and clean up minor code hygiene issues from the v1 build. Fix haptic feedback bug (currently not firing at all). Unify BrandWaveform bar count. Replace hardcoded AccentPopup color.

</domain>

<decisions>
## Implementation Decisions

### Language setting
- French and English only for v1 — no additional languages
- Language picker affects WhisperKit transcription language only — app UI stays in French (no localization)
- Switching language just changes the language hint passed to WhisperKit on next transcription — no model reload needed
- No language indicator badge on keyboard toolbar — keep toolbar clean

### Filler word toggle
- Always filter both French and English fillers regardless of active transcription language (users mix languages)
- Toggle OFF = skip FillerWordFilter.clean() entirely — raw Whisper output goes straight through
- Toggle ON = current behavior (apply FillerWordFilter.clean() to all output)

### Haptic feedback
- BUG: haptics currently don't fire at all — must be diagnosed and fixed in this phase
- Add light haptic feedback on every key tap (UIImpactFeedbackGenerator(.light)) — matching native iOS keyboard feel
- Keep existing distinct patterns for dictation events: medium impact (recording start), light impact (recording stop), success notification (text insertion)
- One master toggle in Settings controls all haptics (key taps + dictation events) — no per-event granularity

### AccentPopup color
- Replace hardcoded Color.blue with DictusColors equivalent — straightforward swap

### BrandWaveform unification
- Unify to 30 bars everywhere (app and keyboard) — not just document the divergence
- Bar width adapts automatically to fit available space in each context (no fixed bar width)
- This changes the keyboard's current 40-bar / 5pt-width configuration to 30 bars with adaptive width

### Claude's Discretion
- Exact diagnosis and fix for haptic feedback bug
- Bar width calculation approach for adaptive BrandWaveform sizing
- Where to read the haptics setting in DictusKeyboard (KeyboardState or KeyButton level)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SharedKeys.language` / `.fillerWordsEnabled` / `.hapticsEnabled`: Already defined in DictusCore, already used by SettingsView via @AppStorage
- `HapticFeedback` enum in DictusCore: 3 static methods (recordingStarted, recordingStopped, textInserted) — needs key tap method added
- `FillerWordFilter.clean()` in DictusCore: Static method, currently always called in TranscriptionService line 126
- `DictusColors` in DictusApp/Design: Full adaptive color system, ready to replace AccentPopup's Color.blue

### Established Patterns
- Settings stored via App Group UserDefaults — read with `UserDefaults(suiteName: AppGroup.identifier)`
- SettingsView uses `@AppStorage(SharedKeys.xxx, store: ...)` for two-way binding
- TranscriptionService reads settings at transcription time (not cached) — same pattern should work for language and filler toggle
- HapticFeedback uses `#if canImport(UIKit) && !os(macOS)` guard for SPM test compatibility

### Integration Points
- `TranscriptionService.swift:98` — hardcoded `language: "fr"` must read from App Group
- `TranscriptionService.swift:126` — `FillerWordFilter.clean(trimmed)` must be conditional on filler toggle
- `KeyboardState.swift:94, 160, 184, 233` — HapticFeedback calls must check hapticsEnabled setting
- `KeyButton.swift` — needs haptic feedback call on key press (currently only has click sounds)
- `AccentPopup.swift:35` — `Color.blue` must become DictusColors equivalent
- `DictusKeyboard/Design/BrandWaveform.swift` — 40 bars / 5pt width must become 30 bars / adaptive width

</code_context>

<specifics>
## Specific Ideas

- "Je veux reproduire la meme chose que le clavier de base iOS" — key tap haptics should feel identical to native iOS keyboard
- Haptics were completely unfelt during testing — this is a bug, not just a missing feature. Diagnosis needed (possibly prepare() timing, extension sandboxing, or Taptic Engine not ready)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-wire-settings-and-code-hygiene*
*Context gathered: 2026-03-07*
