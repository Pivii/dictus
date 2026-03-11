# Requirements: Dictus

**Defined:** 2026-03-11
**Core Value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.

## v1.2 Requirements

Requirements for v1.2 Beta Ready milestone. Each maps to roadmap phases.

### Logging

- [ ] **LOG-01**: App logs events with 4 levels (debug/info/warning/error) across all subsystems
- [ ] **LOG-02**: Logs never contain transcription text, keystrokes, or audio content (privacy-safe)
- [ ] **LOG-03**: User can export logs with device header (iOS version, app version, active model) for GitHub issues
- [ ] **LOG-04**: Logs rotate automatically at 500 lines max
- [ ] **LOG-05**: Logging covers all subsystems: DictationCoordinator, AudioRecorder, TranscriptionService, ModelManager, keyboard extension, app lifecycle

### Animation

- [ ] **ANIM-01**: Recording overlay always appears when dictation starts (no intermittent disappearance)
- [ ] **ANIM-02**: Animation state resets properly on rapid status transitions (recording → transcribing → ready)
- [ ] **ANIM-03**: Waveform and mic button animations never get stuck in stale state

### Cold Start

- [ ] **COLD-01**: Keyboard extension can capture audio directly when mic session is active (Audio Bridge)
- [ ] **COLD-02**: App serves only to activate the audio session, then user returns to keyboard
- [ ] **COLD-03**: Keyboard sends captured audio to app for transcription via App Group
- [ ] **COLD-04**: App returns transcription result to keyboard via Darwin notification + App Group
- [ ] **COLD-05**: Cold start shows dedicated "swipe back" overlay instead of full app UI
- [ ] **COLD-06**: Direct recording in app remains functional (two recording modes coexist)
- [ ] **COLD-07**: Recording starts when user returns to keyboard, not when app opens
- [ ] **COLD-08**: Auto-return to previous app via URL scheme for known apps (bundleID → URL scheme mapping)
- [ ] **COLD-09**: Fallback "swipe back" animation with guided instruction for unknown apps

### Model Pipeline

- [ ] **MODEL-01**: Large Turbo v3 gated behind device RAM check (hidden on ≤4GB devices) or removed from catalog
- [ ] **MODEL-02**: CoreML pre-compilation runs immediately after model download with visible progress indication
- [ ] **MODEL-03**: Onboarding reorders steps to start download earlier (during keyboard setup)
- [ ] **MODEL-04**: Model download/compilation shows full-screen modal preventing app interference
- [ ] **MODEL-05**: Prewarming failure triggers retry-with-cleanup instead of permanent error state
- [ ] **MODEL-06**: Mic button disabled (or shows message) in keyboard while model is compiling
- [ ] **MODEL-07**: Parakeet transcription bug fixed (engine routing actually invokes Parakeet, not WhisperKit)
- [ ] **MODEL-08**: Parakeet model displays correct name ("Parakeet v3" not "Whisper Parakeet v3")

### Design Polish

- [ ] **DSGN-01**: All French UI strings have correct accents (modèle, dictée, réglages, téléchargés, etc.)
- [ ] **DSGN-02**: Active model has blue border highlight in model manager (replaces subtle badge)
- [ ] **DSGN-03**: Model card layout improved (download button placement, badge/gauge alignment)
- [ ] **DSGN-04**: Tap anywhere on downloaded model card to select it
- [ ] **DSGN-05**: X close button on recording overlay has 44pt hit area + haptic feedback
- [ ] **DSGN-06**: Recording overlay dismissal uses smooth easeOut animation
- [ ] **DSGN-07**: Mic button shows reduced opacity during transcription processing

### TestFlight

- [ ] **TF-01**: Xcode signing migrated to professional developer account
- [ ] **TF-02**: Privacy Manifest (PrivacyInfo.xcprivacy) created for both DictusApp and DictusKeyboard targets
- [ ] **TF-03**: App successfully archived and uploaded to App Store Connect
- [ ] **TF-04**: First TestFlight beta build distributed to testers

## Future Requirements

Deferred to v1.3+. Tracked but not in current roadmap.

### Logging

- **LOG-F01**: DebugLogView with filtering by level and subsystem
- **LOG-F02**: Markdown-friendly export format for GitHub issues
- **LOG-F03**: GitHub issue template with pre-formatted debug logs section

### Keyboard UX

- **KBD-F01**: Trackpad vertical movement free and fluid (not locked by line)
- **KBD-F02**: Full Access banner URL opens app correctly
- **KBD-F03**: Key sizing matches iOS native keyboard proportions

### Model Pipeline

- **MODEL-F01**: Smart queue — transcription waits for compilation to finish instead of running in parallel on ANE
- **MODEL-F02**: Background model downloads with URLSession delegate
- **MODEL-F03**: Automatic model updates

### Infrastructure

- **INFRA-F01**: Filler words toggle removal (Whisper handles natively)
- **INFRA-F02**: DictusUI SPM package (eliminate design file duplication)
- **INFRA-F03**: Fastlane/CI automation for TestFlight uploads

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Cloud logging / analytics | Contradicts privacy identity |
| Real-time streaming transcription | Scope creep, batch approach works |
| iPad support | iPhone-first, defer to v2+ |
| LSApplicationWorkspace for auto-return | Private API, App Store rejection confirmed |
| _hostBundleID KVC for bundle detection | Crashes, removed in previous attempt |
| Full emoji picker in keyboard extension | Memory-unsafe (emoji glyph cache) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LOG-01 | — | Pending |
| LOG-02 | — | Pending |
| LOG-03 | — | Pending |
| LOG-04 | — | Pending |
| LOG-05 | — | Pending |
| ANIM-01 | — | Pending |
| ANIM-02 | — | Pending |
| ANIM-03 | — | Pending |
| COLD-01 | — | Pending |
| COLD-02 | — | Pending |
| COLD-03 | — | Pending |
| COLD-04 | — | Pending |
| COLD-05 | — | Pending |
| COLD-06 | — | Pending |
| COLD-07 | — | Pending |
| COLD-08 | — | Pending |
| COLD-09 | — | Pending |
| MODEL-01 | — | Pending |
| MODEL-02 | — | Pending |
| MODEL-03 | — | Pending |
| MODEL-04 | — | Pending |
| MODEL-05 | — | Pending |
| MODEL-06 | — | Pending |
| MODEL-07 | — | Pending |
| MODEL-08 | — | Pending |
| DSGN-01 | — | Pending |
| DSGN-02 | — | Pending |
| DSGN-03 | — | Pending |
| DSGN-04 | — | Pending |
| DSGN-05 | — | Pending |
| DSGN-06 | — | Pending |
| DSGN-07 | — | Pending |
| TF-01 | — | Pending |
| TF-02 | — | Pending |
| TF-03 | — | Pending |
| TF-04 | — | Pending |

**Coverage:**
- v1.2 requirements: 36 total
- Mapped to phases: 0
- Unmapped: 36 ⚠️

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after initial definition*
