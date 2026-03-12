# Requirements: Dictus

**Defined:** 2026-03-11
**Core Value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard -- no subscription, no cloud, no account.

## v1.2 Requirements

Requirements for v1.2 Beta Ready milestone. Each maps to roadmap phases.

### Logging

- [ ] **LOG-01**: App logs events with 4 levels (debug/info/warning/error) across all subsystems
- [ ] **LOG-02**: Logs never contain transcription text, keystrokes, or audio content (privacy-safe)
- [x] **LOG-03**: User can export logs with device header (iOS version, app version, active model) for GitHub issues
- [ ] **LOG-04**: Logs rotate automatically at 500 lines max
- [x] **LOG-05**: Logging covers all subsystems: DictationCoordinator, AudioRecorder, TranscriptionService, ModelManager, keyboard extension, app lifecycle

### Animation

- [x] **ANIM-01**: Recording overlay always appears when dictation starts (no intermittent disappearance)
- [x] **ANIM-02**: Animation state resets properly on rapid status transitions (recording -> transcribing -> ready)
- [x] **ANIM-03**: Waveform and mic button animations never get stuck in stale state

### Cold Start

- [x] **COLD-01**: Keyboard extension can capture audio directly when mic session is active (Audio Bridge)
- [x] **COLD-02**: App serves only to activate the audio session, then user returns to keyboard
- [x] **COLD-03**: Keyboard sends captured audio to app for transcription via App Group
- [x] **COLD-04**: App returns transcription result to keyboard via Darwin notification + App Group
- [x] **COLD-05**: Cold start shows dedicated "swipe back" overlay instead of full app UI
- [x] **COLD-06**: Direct recording in app remains functional (two recording modes coexist)
- [x] **COLD-07**: Recording starts when user returns to keyboard, not when app opens
- [x] **COLD-08**: Auto-return to previous app via URL scheme for known apps (bundleID -> URL scheme mapping)
- [x] **COLD-09**: Fallback "swipe back" animation with guided instruction for unknown apps

### Model Pipeline

- [x] **MODEL-01**: Large Turbo v3 gated behind device RAM check (hidden on <=4GB devices) or removed from catalog
- [x] **MODEL-02**: CoreML pre-compilation runs immediately after model download with visible progress indication
- [ ] **MODEL-03**: Onboarding reorders steps to start download earlier (during keyboard setup)
- [ ] **MODEL-04**: Model download/compilation shows full-screen modal preventing app interference
- [x] **MODEL-05**: Prewarming failure triggers retry-with-cleanup instead of permanent error state
- [ ] **MODEL-06**: Mic button disabled (or shows message) in keyboard while model is compiling
- [ ] **MODEL-07**: Parakeet transcription bug fixed (engine routing actually invokes Parakeet, not WhisperKit)
- [ ] **MODEL-08**: Parakeet model displays correct name ("Parakeet v3" not "Whisper Parakeet v3")

### Design Polish

- [ ] **DSGN-01**: All French UI strings have correct accents (modele, dictee, reglages, telecharges, etc.)
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
- [ ] **TF-05**: App Store Review Guidelines checklist verified (permissions justified, privacy policy, content rules)
- [ ] **TF-06**: README.md updated with build instructions, prerequisites (Xcode version, iOS target, SPM dependencies)
- [ ] **TF-07**: CONTRIBUTING.md with PR guidelines, code conventions, review process
- [ ] **TF-08**: GitHub issue templates (bug report with debug logs section, feature request)
- [ ] **TF-09**: Public TestFlight link in README for joining the beta

## Future Requirements

Deferred to v1.3+. Tracked but not in current roadmap.

### Logging

- **LOG-F01**: DebugLogView with filtering by level and subsystem
- **LOG-F02**: Markdown-friendly export format for GitHub issues
- **LOG-F03**: Markdown-friendly log export with pre-formatted code blocks

### Keyboard UX

- **KBD-F01**: Trackpad vertical movement free and fluid (not locked by line)
- **KBD-F02**: Full Access banner URL opens app correctly
- **KBD-F03**: Key sizing matches iOS native keyboard proportions

### Model Pipeline

- **MODEL-F01**: Smart queue -- transcription waits for compilation to finish instead of running in parallel on ANE
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
| LOG-01 | Phase 11 | Pending |
| LOG-02 | Phase 11 | Pending |
| LOG-03 | Phase 11 | Complete |
| LOG-04 | Phase 11 | Pending |
| LOG-05 | Phase 11 | Complete |
| ANIM-01 | Phase 12 | Complete |
| ANIM-02 | Phase 12 | Complete |
| ANIM-03 | Phase 12 | Pending |
| COLD-01 | Phase 13 | Complete |
| COLD-02 | Phase 13 | Complete |
| COLD-03 | Phase 13 | Complete |
| COLD-04 | Phase 13 | Complete |
| COLD-05 | Phase 13 | Complete |
| COLD-06 | Phase 13 | Complete |
| COLD-07 | Phase 13 | Complete |
| COLD-08 | Phase 13 | Complete |
| COLD-09 | Phase 13 | Complete |
| MODEL-01 | Phase 14 | Complete |
| MODEL-02 | Phase 14 | Complete |
| MODEL-03 | Phase 14 | Pending |
| MODEL-04 | Phase 14 | Pending |
| MODEL-05 | Phase 14 | Complete |
| MODEL-06 | Phase 14 | Pending |
| MODEL-07 | Phase 14 | Pending |
| MODEL-08 | Phase 14 | Pending |
| DSGN-01 | Phase 15 | Pending |
| DSGN-02 | Phase 15 | Pending |
| DSGN-03 | Phase 15 | Pending |
| DSGN-04 | Phase 15 | Pending |
| DSGN-05 | Phase 15 | Pending |
| DSGN-06 | Phase 15 | Pending |
| DSGN-07 | Phase 15 | Pending |
| TF-01 | Phase 16 | Pending |
| TF-02 | Phase 16 | Pending |
| TF-03 | Phase 16 | Pending |
| TF-04 | Phase 16 | Pending |
| TF-05 | Phase 16 | Pending |
| TF-06 | Phase 16 | Pending |
| TF-07 | Phase 16 | Pending |
| TF-08 | Phase 16 | Pending |
| TF-09 | Phase 16 | Pending |

**Coverage:**
- v1.2 requirements: 41 total
- Mapped to phases: 41
- Unmapped: 0

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after roadmap creation*
