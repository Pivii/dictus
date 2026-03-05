# Roadmap: Dictus

**Created:** 2026-03-04
**Granularity:** Coarse
**Phases:** 4
**Requirements:** 22 mapped

---

## Phase 1: Cross-Process Foundation

**Goal:** Prove the two-process dictation architecture works end-to-end on a real device before any other feature is built.

**Requirements:** DUX-05, APP-05, APP-06, KBD-01, KBD-04

### Success Criteria
1. Tapping a mic button stub in the keyboard extension launches the Dictus main app via `dictus://dictate` on a physical iPhone
2. The main app records audio and writes a transcription result to the App Group shared container
3. The keyboard extension reads that result and displays it — completing a round trip without crashing
4. Basic AZERTY typing (characters, space, delete, return) works in any app without Full Access enabled
5. `AppGroupDiagnostic` logs confirm both targets can read and write to `group.com.pivi.dictus`

### Plans
- [x] Plan 1.1: Project scaffold — Xcode workspace, two targets (app + extension), App Group entitlements, `APPLICATION_EXTENSION_API_ONLY = YES`, local `DictusCore` SPM package, `AppGroupDiagnostic` check on both launch paths *(completed 2026-03-05)*
- [x] Plan 1.2: Cross-process signaling — `dictus://dictate` URL scheme handler in main app, `DictationStatus` enum written/read via App Group `UserDefaults`, Darwin notification signaling, `KeyboardState` observer in extension, stub round-trip *(completed 2026-03-05)*
- Plan 1.3: Keyboard shell — `UIInputViewController` subclass with `UIHostingController`-hosted SwiftUI view, functional AZERTY layout (all 50 keys), graceful degradation when Full Access is off (typing works, mic button disabled)

---

## Phase 2: Transcription Pipeline

**Goal:** A user can speak French into the main app and receive clean, accurate text back in the keyboard extension ready to insert.

**Requirements:** STT-01, STT-02, STT-03, STT-04, STT-05, APP-02

### Success Criteria
1. Recording 10 seconds of spoken French in the main app produces a transcription in under 3 seconds on an iPhone 12 or newer
2. Filler words ("euh", "hm", "bah", "voilà", "um", "uh") are absent from the transcription output
3. Automatic punctuation from Whisper is preserved — sentences end with periods, questions with question marks
4. Short utterances (under 5 seconds) route to `whisper-tiny`; longer utterances route to `whisper-small` automatically
5. User can download, select, and delete Whisper models (tiny, base, small, medium, large-v3-turbo) from within the app

### Plans
- Plan 2.1: WhisperKit integration — add `argmaxinc/WhisperKit` via SPM to main app target only, `AVAudioEngine` + `AVAudioSession` recording pipeline, model pre-compilation on first launch with `modelReady` flag written to App Group, file integrity check after download
- Plan 2.2: Transcription quality — `FillerWordFilter` (French + English word list, rule-based), `SmartModelRouter` (duration threshold → tiny vs small), punctuation pass-through validation, latency benchmarks on physical device
- Plan 2.3: Model Manager screen — list of available models with size and WER labels, download progress indicator, active model selection, delete with confirmation, `modelReady` state surfaced to keyboard extension

---

## Phase 3: Dictation UX

**Goal:** The full dictation loop — record, preview, confirm, insert, undo — works fluidly from the keyboard without leaving the context.

**Requirements:** DUX-01, DUX-02, DUX-03, DUX-04, KBD-02, KBD-03, KBD-05, APP-04

### Success Criteria
1. After a dictation round trip, transcribed text appears in a preview bar inside the keyboard before any insertion
2. Tapping confirm inserts the text into the active text field via `textDocumentProxy`; tapping dismiss clears the preview
3. An undo button deletes the last inserted transcription block character-by-character via `deleteBackward()`
4. Haptic feedback fires on recording start, recording stop, and text insertion
5. An animated waveform is visible during active recording; the mic button shows distinct idle, recording, and transcribing states
6. Both AZERTY and QWERTY layouts are available and switchable from Settings; AZERTY is default
7. The in-app test dictation screen allows end-to-end transcription testing without leaving Dictus

### Plans
- Plan 3.1: Transcription preview and insertion — `TranscriptionPreviewBar` SwiftUI component in keyboard, confirm/dismiss actions, `textDocumentProxy.insertText()`, undo via `deleteBackward() × N` tracked in local state, `lastInsertedLength` in App Group for cross-launch undo support
- Plan 3.2: Recording feedback — animated waveform component using `AVAudioEngine` metering tap, mic button state machine (idle / recording / transcribing), `UIImpactFeedbackGenerator` haptics at three trigger points
- Plan 3.3: Keyboard layout switcher + test screen — QWERTY layout implementation, layout preference persisted in App Group `UserDefaults`, in-app `TestDictationView` with local recording → transcription → result display flow

---

## Phase 4: Main App, Onboarding, and Polish

**Goal:** A new user can install Dictus, complete onboarding, and dictate their first sentence — and every screen looks like it belongs on iOS 26.

**Requirements:** APP-01, APP-03, KBD-06, DSN-01, DSN-02, DSN-03, DSN-04

### Success Criteria
1. A first-time user who has never installed a third-party keyboard reaches their first successful dictation solely by following the onboarding flow — no external documentation needed
2. The Settings screen lets a user change active model, transcription language, keyboard layout, filler word toggle, and haptic toggle — changes persist across app launches
3. Every screen in the app and keyboard extension uses `.glassEffect()` (iOS 26) with `Material.regularMaterial` fallback on iOS 16–25
4. Mic button shows idle glow, recording pulse, and transcribing shimmer animations
5. All text in the app respects Dynamic Type — no truncation or overflow at any accessibility text size
6. Light and dark mode render correctly without any hardcoded colors

### Plans
- Plan 4.1: Onboarding flow — four-step guided sequence: microphone permission request, keyboard addition instructions with Settings deep link, Full Access enablement instructions with screenshot, model download trigger; non-dismissible Full Access banner on keyboard when Full Access is off with Settings deep link
- Plan 4.2: Settings screen — `AppSettings` model persisted in App Group `UserDefaults`, five toggles/pickers (model, language, layout, filler words, haptics), live preview of current model status, links to GitHub and licenses
- Plan 4.3: Design system pass — `.glassEffect()` applied to all surfaces behind `#available(iOS 26, *)` guards with `Material.regularMaterial` fallbacks, SF Pro Rounded headings, SF Pro Text body, Dynamic Type throughout, mic button animation polish (idle glow, recording pulse, transcribing shimmer), light/dark mode audit on all screens

---

## Requirement Coverage

| Phase | Requirements |
|-------|-------------|
| Phase 1 | DUX-05, APP-05, APP-06, KBD-01, KBD-04 |
| Phase 2 | STT-01, STT-02, STT-03, STT-04, STT-05, APP-02 |
| Phase 3 | DUX-01, DUX-02, DUX-03, DUX-04, KBD-02, KBD-03, KBD-05, APP-04 |
| Phase 4 | APP-01, APP-03, KBD-06, DSN-01, DSN-02, DSN-03, DSN-04 |
| **Total** | **22 / 22** |

---
*Roadmap created: 2026-03-04*
*Granularity: Coarse (3–5 phases per config.json)*
