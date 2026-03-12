# Roadmap: Dictus

**Created:** 2026-03-04
**Granularity:** Coarse

---

## Milestones

- v1.0 MVP -- Phases 1-5 (shipped 2026-03-07)
- v1.1 UX & Keyboard -- Phases 6-10 (shipped 2026-03-11)
- **v1.2 Beta Ready** -- Phases 11-16 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-5) -- SHIPPED 2026-03-07</summary>

- [x] Phase 1: Cross-Process Foundation (4/4 plans) -- completed 2026-03-05
- [x] Phase 2: Transcription Pipeline (3/3 plans) -- completed 2026-03-06
- [x] Phase 3: Dictation UX (4/4 plans) -- completed 2026-03-06
- [x] Phase 4: Main App, Onboarding, and Polish (5/5 plans) -- completed 2026-03-07
- [x] Phase 5: Wire Settings & Code Hygiene (2/2 plans) -- completed 2026-03-07

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>v1.1 UX & Keyboard (Phases 6-10) -- SHIPPED 2026-03-11</summary>

- [x] Phase 6: Infrastructure & App Polish (5/5 plans) -- completed 2026-03-07
- [x] Phase 7: Keyboard Parity & Visual (12/12 plans) -- completed 2026-03-08
- [x] Phase 8: Text Prediction (2/2 plans) -- completed 2026-03-09
- [x] Phase 9: Keyboard Modes (6/6 plans) -- completed 2026-03-10
- [x] Phase 10: Model Catalog (4/4 plans) -- completed 2026-03-11

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

### v1.2 Beta Ready

**Milestone Goal:** Fix bugs, improve UX, and deploy to TestFlight for public beta.

- [x] **Phase 11: Logging Foundation** - Production-ready persistent logging across all subsystems with privacy safeguards and export (completed 2026-03-11)
- [x] **Phase 12: Animation State Fixes** - Eliminate intermittent recording overlay and waveform animation bugs (completed 2026-03-12)
- [x] **Phase 13: Cold Start Audio Bridge** - Audio Bridge pattern for keyboard-captured audio with graceful return-to-keyboard UX (completed 2026-03-12)
- [x] **Phase 14: Model Pipeline** - CoreML compilation UX, model download modal, device RAM gating, Parakeet fixes (completed 2026-03-12)
- [ ] **Phase 15: Design Polish** - French accent audit, model manager redesign, recording overlay and keyboard UX refinements
- [ ] **Phase 16: TestFlight Deployment** - Developer account migration, Privacy Manifest, archive, and first beta distribution

## Phase Details

### Phase 11: Logging Foundation
**Goal**: Developers and beta testers can diagnose issues with structured, privacy-safe logs exportable from the app
**Depends on**: Nothing (first phase of v1.2)
**Requirements**: LOG-01, LOG-02, LOG-03, LOG-04, LOG-05
**Success Criteria** (what must be TRUE):
  1. App and keyboard extension write structured log entries with level (debug/info/warning/error) and subsystem tags visible in exported output
  2. Exported logs contain zero transcription text, keystrokes, or audio content regardless of log level
  3. User can tap a button in Settings to share a log file that includes device header (iOS version, app version, active model)
  4. Log file never exceeds 500 lines -- oldest entries are discarded when limit is reached
**Plans**: 2 plans

Plans:
- [ ] 11-01-PLAN.md — Structured logging API (LogEvent types, PersistentLog evolution, unit tests)
- [ ] 11-02-PLAN.md — Subsystem instrumentation, DebugLogView upgrade, export in Settings

### Phase 12: Animation State Fixes
**Goal**: Recording overlay and waveform animations behave reliably across all dictation state transitions
**Depends on**: Phase 11 (logging needed to diagnose intermittent issues on device)
**Requirements**: ANIM-01, ANIM-02, ANIM-03
**Success Criteria** (what must be TRUE):
  1. Recording overlay appears every time user taps mic and dictation starts -- zero intermittent disappearances across 20 consecutive tests
  2. Rapid mic tap sequences (start/stop/start within 1 second) never leave the overlay or waveform in a stale state
  3. Waveform animation stops cleanly when transcription completes and mic button returns to ready state
**Plans**: 2 plans

Plans:
- [x] 12-01-PLAN.md — Overlay visibility fix, .requested state, animation race fixes, diagnostic log events
- [x] 12-02-PLAN.md — Watchdog recovery mechanisms (keyboard + app), reset-on-appear, device verification

### Phase 13: Cold Start Audio Bridge
**Goal**: Users experience seamless dictation even when the app was killed by iOS, with minimal manual intervention to return to the keyboard
**Depends on**: Phase 12 (stable animation required before adding new recording paths)
**Requirements**: COLD-01, COLD-02, COLD-03, COLD-04, COLD-05, COLD-06, COLD-07, COLD-08, COLD-09
**Success Criteria** (what must be TRUE):
  1. On cold start, keyboard captures audio directly after the app activates the audio session, and transcription result appears in the text field
  2. App shows a minimal "swipe back" overlay on cold start instead of full app UI
  3. Recording begins when user returns to the keyboard, not when the app opens
  4. For apps with known URL schemes, user is auto-returned to the previous app after audio session activation
  5. Direct recording from the app (non-keyboard flow) still works identically to v1.1
**Plans**: 3 plans

Plans:
- [ ] 13-01-PLAN.md — Cold start infrastructure: SharedKeys, KnownAppSchemes, launch mode detection, conditional MainTabView
- [ ] 13-02-PLAN.md — SwipeBackOverlayView with animated swipe gesture, brand gradient, bilingual text
- [ ] 13-03-PLAN.md — Auto-return via URL scheme, keyboard source detection, Info.plist schemes, device verification

### Phase 14: Model Pipeline
**Goal**: Model download, CoreML compilation, and engine selection work reliably with clear progress feedback and no crashes on constrained devices
**Depends on**: Phase 11 (logging for compilation diagnostics)
**Requirements**: MODEL-01, MODEL-02, MODEL-03, MODEL-04, MODEL-05, MODEL-06, MODEL-07, MODEL-08
**Success Criteria** (what must be TRUE):
  1. Large Turbo v3 is hidden or gated on devices with 4GB RAM or less -- user cannot trigger a compilation crash
  2. After downloading a model, CoreML compilation starts automatically with a visible progress indicator, and user cannot accidentally navigate away
  3. If model prewarming fails, user sees a retry option that cleans up and re-attempts instead of a permanent error
  4. Mic button in keyboard is disabled with a message while a model is compiling in the main app
  5. Selecting a Parakeet model actually invokes Parakeet for transcription, and the model displays as "Parakeet v3" (not "Whisper Parakeet v3")
**Plans**: 3 plans

Plans:
- [x] 14-01-PLAN.md — Remove Large Turbo, RAM-based recommendation, compilation progress fix, retry-with-cleanup
- [x] 14-02-PLAN.md — Dynamic onboarding model selection, Parakeet routing and display name verification
- [x] 14-03-PLAN.md — Gap closure: fix stale ModelInfoTests after Large Turbo v3 removal

### Phase 15: Design Polish
**Goal**: All user-facing UI reaches beta quality with correct French localization and polished interaction details
**Depends on**: Phase 14 (model manager changes must land before cosmetic polish)
**Requirements**: DSGN-01, DSGN-02, DSGN-03, DSGN-04, DSGN-05, DSGN-06, DSGN-07
**Success Criteria** (what must be TRUE):
  1. All French UI strings display correct accents (modele with accent, dictee with accent, reglages with accent, telecharges with accent, etc.)
  2. Active model in model manager has a visible blue border highlight, and tapping anywhere on a downloaded model card selects it
  3. Recording overlay X button has a generous tap area (44pt minimum) with haptic feedback and smooth easeOut dismiss animation
  4. Mic button shows reduced opacity during transcription processing, giving clear visual feedback that work is happening
**Plans**: TBD

Plans:
- [ ] 15-01: TBD
- [ ] 15-02: TBD

### Phase 16: TestFlight Deployment
**Goal**: First beta build distributed to testers, with open-source repo ready for contributors
**Depends on**: Phase 15 (all features and polish must be stable)
**Requirements**: TF-01, TF-02, TF-03, TF-04, TF-05, TF-06, TF-07, TF-08, TF-09
**Success Criteria** (what must be TRUE):
  1. Xcode project signs with the professional developer account for both DictusApp and DictusKeyboard targets
  2. Privacy Manifest (PrivacyInfo.xcprivacy) exists for both targets and passes App Store Connect validation
  3. App Store Review Guidelines checklist verified (permissions, privacy policy, content)
  4. App is successfully archived, uploaded to App Store Connect, and approved by Beta App Review
  5. At least one external tester receives and can install the TestFlight build
  6. README.md has build instructions and public TestFlight link
  7. CONTRIBUTING.md and GitHub issue templates are in place for contributors
**Plans**: TBD

Plans:
- [ ] 16-01: TBD
- [ ] 16-02: TBD
- [ ] 16-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 11 -> 12 -> 13 -> 14 -> 15 -> 16

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Cross-Process Foundation | v1.0 | 4/4 | Complete | 2026-03-05 |
| 2. Transcription Pipeline | v1.0 | 3/3 | Complete | 2026-03-06 |
| 3. Dictation UX | v1.0 | 4/4 | Complete | 2026-03-06 |
| 4. Main App & Polish | v1.0 | 5/5 | Complete | 2026-03-07 |
| 5. Wire Settings & Hygiene | v1.0 | 2/2 | Complete | 2026-03-07 |
| 6. Infrastructure & App Polish | v1.1 | 5/5 | Complete | 2026-03-07 |
| 7. Keyboard Parity & Visual | v1.1 | 12/12 | Complete | 2026-03-08 |
| 8. Text Prediction | v1.1 | 2/2 | Complete | 2026-03-09 |
| 9. Keyboard Modes | v1.1 | 6/6 | Complete | 2026-03-10 |
| 10. Model Catalog | v1.1 | 4/4 | Complete | 2026-03-11 |
| 11. Logging Foundation | v1.2 | 2/2 | Complete | 2026-03-11 |
| 12. Animation State Fixes | v1.2 | Complete    | 2026-03-12 | 2026-03-12 |
| 13. Cold Start Audio Bridge | 3/3 | Complete   | 2026-03-12 | - |
| 14. Model Pipeline | v1.2 | 3/3 | Complete | 2026-03-12 |
| 15. Design Polish | v1.2 | 0/2 | Not started | - |
| 16. TestFlight Deployment | v1.2 | 0/2 | Not started | - |

---
*Roadmap created: 2026-03-04*
*v1.1 shipped: 2026-03-11*
*v1.2 roadmap added: 2026-03-11*
