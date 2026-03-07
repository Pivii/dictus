# Phase 2: Transcription Pipeline - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

A user can speak French into the main app and receive clean, accurate text back in the keyboard extension ready to insert. Covers: WhisperKit integration, AVAudioEngine recording pipeline, filler word removal, smart model routing by audio duration, and a model manager screen for downloading/selecting/deleting Whisper models. This phase replaces the stub in `DictationCoordinator.startDictation()` with real audio recording and transcription.

</domain>

<decisions>
## Implementation Decisions

### Recording behavior
- User taps a stop button in the main app to end recording — no auto-stop on silence
- No maximum recording duration — user records as long as needed
- Recording screen shows a live audio waveform visualization + stop button + elapsed time counter
- After transcription completes, auto-return immediately to keyboard — no result preview in the main app (brief "Done" checkmark, then user switches back)
- Recording starts automatically when app opens via `dictus://dictate` (carried forward from Phase 1)

### Model routing & defaults
- User chooses which model to download during initial setup (no pre-selected default)
- Smart model routing: audio under 5 seconds uses tiny/base (fast), audio over 5 seconds uses small (accurate)
- If only one model is downloaded, always use that model regardless of duration — no error, no prompt
- Pre-compile (warm up) Core ML model after download for faster first transcription (~10-30 seconds, only once)
- `modelReady` flag written to App Group so keyboard extension knows transcription is available

### Model Manager screen
- Each model displays: size (MB/GB), accuracy label (Good/Better/Best), speed indicator (Fast/Balanced/Slow), recommended badge for device
- Downloads run in background (URLSession background download) — progress bar visible when returning to app
- Delete requires confirmation alert showing model name and size
- Cannot delete the last remaining model — disable delete button with "At least one model required" message
- Available models: tiny, base, small, medium, large-v3-turbo (per roadmap)

### Filler word removal
- Standard fillers only: euh, hm, bah, ben, voila, um, uh, er — no aggressive patterns
- No hallucination filtering (no "quoi", "en fait", "du coup") — conservative approach
- After removing fillers, basic text cleanup: collapse double spaces, remove orphaned punctuation
- On by default, toggle available in Settings (Phase 4 delivers the toggle UI)

### Claude's Discretion
- AVAudioEngine + AVAudioSession configuration details
- WhisperKit API integration approach and model loading strategy
- Audio format and sample rate choices
- Exact waveform visualization implementation
- Model download URL management and storage location
- Filler word regex vs token-based approach
- Error handling and retry logic for failed transcriptions
- Smart model router implementation details (threshold tuning)

</decisions>

<specifics>
## Specific Ideas

- Recording screen should feel immediate — "I tap mic on keyboard, app opens, waveform is already moving"
- The flow is: keyboard mic tap -> app opens -> auto-records with waveform -> user taps stop -> transcription runs -> checkmark flash -> user goes back to keyboard -> text appears
- Model manager should make it clear which model is best for this device — users shouldn't need to understand Whisper model names
- Pierre referenced Super Whisper as inspiration for the keyboard mic button placement (wide button above keyboard) — captured as deferred idea for Phase 3

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictationCoordinator` (DictusApp/DictationCoordinator.swift): Integration point — `startDictation()` currently stubs recording + transcription with `Task.sleep`. Replace internals with real AVAudioEngine + WhisperKit pipeline
- `DictationStatus` enum (DictusCore): Already has all needed states (idle, requested, recording, transcribing, ready, failed)
- `SharedKeys` (DictusCore): Already has `lastTranscription`, `lastTranscriptionTimestamp`, `dictationStatus`, `lastError` keys
- `AppGroup.defaults` and `AppGroup.containerURL`: Ready for model storage and cross-process data
- `DarwinNotificationCenter` (DictusCore): Notification posting for cross-process signaling already wired

### Established Patterns
- `@MainActor` on coordinator classes with `@Published` properties
- Darwin notifications + UserDefaults synchronize pattern for cross-process communication (write all values before posting notification to avoid race conditions)
- `Task`-based async operations with cancellation support
- `#available(iOS 14.0, *)` guards for DictusLogger usage

### Integration Points
- `DictationCoordinator.startDictation()` — replace stub with real recording + transcription
- `DictationCoordinator.writeTranscription()` — already writes to App Group, will receive real text
- `DictusApp.swift` `.onOpenURL` — already routes `dictus://dictate` to coordinator
- `ContentView.swift` / `DictationView.swift` — recording UI lives here, needs waveform + stop button
- `DictusCore/Package.swift` — WhisperKit SPM dependency added to main app target only

</code_context>

<deferred>
## Deferred Ideas

- **Wide mic button above keyboard** — Pierre wants a nearly full-width mic button placed above the keyboard rows (instead of current small button next to space bar), inspired by Super Whisper's layout. This is Phase 3 (Dictation UX) scope.

</deferred>

---

*Phase: 02-transcription-pipeline*
*Context gathered: 2026-03-05*
