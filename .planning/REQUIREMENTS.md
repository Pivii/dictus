# Requirements: Dictus

**Defined:** 2026-03-04
**Core Value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Transcription

- [x] **STT-01**: User can dictate text and receive accurate French transcription via on-device WhisperKit
- [x] **STT-02**: Filler words (euh, hm, voilà, um, uh) are automatically removed from transcription
- [x] **STT-03**: Transcription includes automatic punctuation (provided natively by Whisper)
- [x] **STT-04**: Smart Model Routing switches between fast model (tiny/base) and accurate model (small) based on audio duration
- [x] **STT-05**: Transcription completes in under 3 seconds for 10 seconds of audio

### Keyboard Extension

- [x] **KBD-01**: User can switch to Dictus keyboard via globe key in any app
- [x] **KBD-02**: Full AZERTY keyboard layout is available and functional
- [x] **KBD-03**: QWERTY keyboard layout is available as alternative (configurable in settings)
- [x] **KBD-04**: Keyboard remains functional for basic typing when Full Access is not enabled (graceful degradation)
- [ ] **KBD-05**: Mic button with clear visual states (idle, recording, transcribing)
- [ ] **KBD-06**: Keyboard uses iOS 26 Liquid Glass design

### Dictation UX

- [ ] **DUX-01**: Transcribed text is auto-inserted into the active text field via textDocumentProxy
- [ ] **DUX-02**: User can undo the last transcription insertion with a dedicated button
- [x] **DUX-03**: Haptic feedback triggers on recording start, recording stop, and text insertion
- [ ] **DUX-04**: Animated waveform displays during active recording
- [x] **DUX-05**: Dictation flow uses two-process architecture (keyboard triggers main app for recording + transcription)

### Main App

- [ ] **APP-01**: Onboarding guides user through microphone permission, keyboard addition, Full Access enablement, and model download
- [x] **APP-02**: Model Manager allows downloading, selecting, and deleting Whisper models (tiny, base, small, medium, large-v3-turbo)
- [ ] **APP-03**: Settings screen for active model, transcription language, keyboard layout, filler word toggle, haptic toggle
- [ ] **APP-04**: In-app test dictation screen for testing transcription without leaving the app
- [x] **APP-05**: App handles `dictus://dictate` URL scheme to receive dictation requests from keyboard extension
- [x] **APP-06**: All shared data passes through App Group (`group.com.pivi.dictus`)

### Design

- [ ] **DSN-01**: All UI surfaces use iOS 26 Liquid Glass material (.glassEffect)
- [ ] **DSN-02**: Mic button has animated states (idle glow, recording pulse, transcribing shimmer)
- [ ] **DSN-03**: Light and dark mode supported automatically
- [ ] **DSN-04**: SF Pro Rounded for headings, SF Pro Text for body, Dynamic Type throughout

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Text Prediction

- **PRED-01**: Suggestion bar above keyboard with 3 tappable word predictions
- **PRED-02**: Autocorrect for common typos
- **PRED-03**: Accented character long-press on AZERTY (é, è, ê, à, ù...)
- **PRED-04**: UILexicon integration for system word list

### Smart Modes

- **MODE-01**: LLM post-processing of transcription (reformat as email, SMS, note, Slack)
- **MODE-02**: Default modes: Email, SMS/iMessage, Note, Slack
- **MODE-03**: Custom mode editor with system prompt
- **MODE-04**: OpenAI API key management (App Group Keychain)
- **MODE-05**: Mode selector in keyboard

### Transcription History

- **HIST-01**: Last 20 transcriptions stored locally
- **HIST-02**: Tap past transcription to re-insert
- **HIST-03**: Auto-clear after 7 days

### Advanced

- **ADV-01**: Real-time streaming transcription (word-by-word while recording)
- **ADV-02**: Additional LLM providers (Claude, Groq, Ollama)
- **ADV-03**: iPad support
- **ADV-04**: iCloud sync for preferences and custom modes

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cloud transcription | Contradicts privacy/offline identity |
| Subscription / monetization | Contradicts open-source positioning |
| Android port | Different platform entirely, v3+ |
| Apple Watch companion | Too niche for roadmap |
| iOS Shortcuts integration | Nice-to-have, not core |
| QWERTZ layout | Insufficient demand for v1, easy to add later |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DUX-05 | Phase 1: Cross-Process Foundation | Complete |
| APP-05 | Phase 1: Cross-Process Foundation | Complete |
| APP-06 | Phase 1: Cross-Process Foundation | Complete |
| KBD-01 | Phase 1: Cross-Process Foundation | Complete |
| KBD-04 | Phase 1: Cross-Process Foundation | Complete |
| STT-01 | Phase 2: Transcription Pipeline | Complete |
| STT-02 | Phase 2: Transcription Pipeline | Complete |
| STT-03 | Phase 2: Transcription Pipeline | Complete |
| STT-04 | Phase 2: Transcription Pipeline | Complete |
| STT-05 | Phase 2: Transcription Pipeline | Complete |
| APP-02 | Phase 2: Transcription Pipeline | Complete |
| DUX-01 | Phase 3: Dictation UX | Not Started |
| DUX-02 | Phase 3: Dictation UX | Not Started |
| DUX-03 | Phase 3: Dictation UX | Not Started |
| DUX-04 | Phase 3: Dictation UX | Not Started |
| KBD-02 | Phase 3: Dictation UX | Not Started |
| KBD-03 | Phase 3: Dictation UX | Not Started |
| KBD-05 | Phase 3: Dictation UX | Not Started |
| APP-04 | Phase 3: Dictation UX | Not Started |
| APP-01 | Phase 4: Main App, Onboarding, and Polish | Not Started |
| APP-03 | Phase 4: Main App, Onboarding, and Polish | Not Started |
| KBD-06 | Phase 4: Main App, Onboarding, and Polish | Not Started |
| DSN-01 | Phase 4: Main App, Onboarding, and Polish | Not Started |
| DSN-02 | Phase 4: Main App, Onboarding, and Polish | Not Started |
| DSN-03 | Phase 4: Main App, Onboarding, and Polish | Not Started |
| DSN-04 | Phase 4: Main App, Onboarding, and Polish | Not Started |

**Coverage:**
- v1 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-03-04*
*Last updated: 2026-03-04 after initial definition*
