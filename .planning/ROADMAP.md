# Roadmap: Dictus

**Created:** 2026-03-04
**Granularity:** Coarse
**Phases:** 5
**Requirements:** 21 active (2 dropped)

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
- [x] Plan 1.3: Keyboard shell — `UIInputViewController` subclass with `UIHostingController`-hosted SwiftUI view, functional AZERTY layout (all 50 keys), graceful degradation when Full Access is off (typing works, mic button disabled) *(completed 2026-03-05)*
- [x] Plan 1.4: UAT gap closure — fix keyboard click sounds (inputView hierarchy), fix cross-process transcription display (notification race, StatusBar spinner) *(completed 2026-03-05)*

---

## Phase 2: Transcription Pipeline

**Goal:** A user can speak French into the main app and receive clean, accurate text back in the keyboard extension ready to insert.

**Requirements:** STT-01, STT-02, STT-03, STT-04, STT-05, APP-02

**Plans:** 3/3 plans executed

### Success Criteria
1. Recording 10 seconds of spoken French in the main app produces a transcription in under 3 seconds on an iPhone 12 or newer
2. Filler words ("euh", "hm", "bah", "voila", "um", "uh") are absent from the transcription output
3. Automatic punctuation from Whisper is preserved — sentences end with periods, questions with question marks
4. Short utterances (under 5 seconds) route to `whisper-tiny`; longer utterances route to `whisper-small` automatically
5. User can download, select, and delete Whisper models (tiny, base, small, medium, large-v3-turbo) from within the app

### Plans
- [x] 02-01-PLAN.md — WhisperKit SPM integration, AudioRecorder, TranscriptionService, RecordingView with waveform + stop + timer, DictationCoordinator rewrite *(completed 2026-03-05)*
- [x] 02-02-PLAN.md — FillerWordFilter (TDD), SmartModelRouter (TDD), ModelInfo, SharedKeys extensions *(completed 2026-03-05)*
- [x] 02-03-PLAN.md — ModelManager + ModelManagerView (download/select/delete), wire SmartModelRouter + FillerWordFilter into pipeline *(completed 2026-03-06)*

---

## Phase 3: Dictation UX

**Goal:** Wispr Flow-inspired dictation loop -- tap mic, record with immersive keyboard UI, auto-insert transcribed text -- works fluidly from the keyboard. Includes QWERTY layout, accented characters, and in-app test screen.

**Requirements:** DUX-01, DUX-02 (DROPPED by user decision), DUX-03, DUX-04, KBD-02, KBD-03, KBD-05, APP-04

**Plans:** 4/4 plans complete

### Success Criteria
1. Tapping mic in keyboard toolbar opens DictusApp briefly; keyboard shows recording overlay (waveform, timer, cancel/stop)
2. After stop, transcribed text auto-inserts into the active text field via `textDocumentProxy.insertText()` -- no preview bar, no confirmation
3. DUX-02 (undo button) intentionally omitted per user decision -- manual select+delete instead
4. Haptic feedback fires on recording start, recording stop, and text insertion
5. Animated waveform visible during active recording; mic button shows distinct idle, recording, and transcribing states
6. Both AZERTY and QWERTY layouts available; AZERTY default, switchable from Settings
7. Long-press accented character popups on AZERTY keys (e, a, u, i, o, c, y, n)
8. In-app test dictation screen allows end-to-end transcription testing without leaving Dictus

### Plans
- [x] 03-01-PLAN.md — DictusCore contracts (SharedKeys, Darwin notifications, QWERTY layout data, accented character mappings, haptic helper), DictationCoordinator wired for keyboard stop/cancel signals and waveform forwarding *(completed 2026-03-06)*
- [x] 03-02-PLAN.md — Wispr Flow-inspired keyboard recording UX (ToolbarView with mic button, RecordingOverlay replacing keyboard, auto-insert via textDocumentProxy, haptic feedback, mic button states) *(completed 2026-03-06)*
- [x] 03-03-PLAN.md — QWERTY layout switching in keyboard, accented character long-press popup on AZERTY, in-app TestDictationView *(completed 2026-03-06)*
- [x] 03-04-PLAN.md — UAT gap closure: replace Link with Button in ToolbarView mic button, add startRecording() to KeyboardState, wire callback through KeyboardRootView *(completed 2026-03-06)*

---

## Phase 4: Main App, Onboarding, and Polish

**Goal:** A new user can install Dictus, complete onboarding, and dictate their first sentence — and every screen looks like it belongs on iOS 26.

**Requirements:** APP-01, APP-03, KBD-06, DSN-01, DSN-02, DSN-03, DSN-04

**Plans:** 5/5 plans complete

### Success Criteria
1. A first-time user who has never installed a third-party keyboard reaches their first successful dictation solely by following the onboarding flow — no external documentation needed
2. The Settings screen lets a user change active model, transcription language, keyboard layout, filler word toggle, and haptic toggle — changes persist across app launches
3. Every screen in the app and keyboard extension uses `.glassEffect()` (iOS 26) with `Material.regularMaterial` fallback on iOS 16-25
4. Mic button shows idle glow, recording pulse, and transcribing shimmer animations
5. All text in the app respects Dynamic Type — no truncation or overflow at any accessibility text size
6. Light and dark mode render correctly without any hardcoded colors

### Plans
- [x] 04-01-PLAN.md — SharedKeys extensions (language, haptics, fillerWords, hasCompletedOnboarding), Design system components (GlassModifier, DictusColors, BrandWaveform, AnimatedMicButton, DictusTypography), app restructure into TabView with Home/Models/Settings tabs *(completed 2026-03-06)*
- [x] 04-02-PLAN.md — 5-step onboarding flow (welcome, mic permission, keyboard+Full Access, model download, test transcription), Settings screen with 3 sections (Transcription, Clavier, A propos) *(completed 2026-03-06)*
- [x] 04-03-PLAN.md — Design system pass: glass + multi-bar waveform on all surfaces, AnimatedMicButton in keyboard toolbar, Dynamic Type via @ScaledMetric, light/dark mode audit, human verification passed *(completed 2026-03-06)*
- [x] 04-04-PLAN.md — UAT gap closure: onboarding fixes (animated waveform, button contrast, persistent state, adaptive colors) + glass on Models/Settings tabs *(completed 2026-03-07)*
- [x] 04-05-PLAN.md — UAT gap closure: keyboard fixes (layout shift, key sizing, Dynamic Type, FullAccessBanner, waveform enlargement, light mode colors) *(completed 2026-03-07)*

---

## Phase 5: Wire Settings & Code Hygiene

**Goal:** Make all settings toggles functional end-to-end and clean up minor code hygiene issues from the v1 build.

**Requirements:** APP-03 (full closure), STT-01, STT-02, DUX-03 (integration fixes)
**Gap Closure:** Closes all gaps from v1.0 milestone audit
**Plans:** 1/2 plans executed

### Success Criteria
1. Changing "language" in Settings changes the transcription language used by WhisperKit (not hardcoded to "fr")
2. Toggling "filler words" off in Settings causes FillerWordFilter to skip filtering; toggling on re-enables it
3. Toggling "haptics" off in Settings suppresses all haptic feedback; toggling on re-enables it
4. AccentPopup uses DictusColors instead of hardcoded Color.blue
5. BrandWaveform unified to 30 adaptive-width bars in both app and keyboard

### Plans
- [ ] 05-01-PLAN.md — Wire settings in DictusCore + DictusApp: HapticFeedback isEnabled() guard + keyTapped() method, TranscriptionService dynamic language + conditional filler filter
- [ ] 05-02-PLAN.md — Keyboard haptics + visual fixes: KeyButton key tap haptic, AccentPopup brand color, BrandWaveform 30-bar adaptive unification

---

## Requirement Coverage

| Phase | Requirements |
|-------|-------------|
| Phase 1 | DUX-05, APP-05, APP-06, KBD-01, KBD-04 |
| Phase 2 | STT-01, STT-02, STT-03, ~~STT-04~~ (DROPPED), STT-05, APP-02 |
| Phase 3 | DUX-01, DUX-02 (DROPPED), DUX-03, DUX-04, KBD-02, KBD-03, KBD-05, APP-04 |
| Phase 4 | APP-01, KBD-06, DSN-01, DSN-02, DSN-03, DSN-04 |
| Phase 5 | APP-03, STT-01, STT-02, DUX-03 (gap closure) |
| **Total** | **21 / 21 active** (2 dropped: STT-04, DUX-02) |

---
*Roadmap created: 2026-03-04*
*Granularity: Coarse (3-5 phases per config.json)*
