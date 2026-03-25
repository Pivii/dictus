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
- [x] **Phase 15: Design Polish** - French accent audit, model manager redesign, recording overlay and keyboard UX refinements (completed 2026-03-13)
- [x] **Phase 15.1: UI Polish Fixes** - Button alignment, app name/logo, swipe-back overlay, recording sound feedback (INSERTED) (completed 2026-03-13)
- [x] **Phase 15.2: Cleaning and Fix GitHub Issues** - Fix ship-blocking bugs (waveform, DI desync, stale cards) and triage GitHub issues (INSERTED) (gap closure in progress) (completed 2026-03-17)
- [x] **Phase 15.3: Keyboard Optimization and Responsiveness** - Reduce input latency with UIKit touch handling, device-adaptive key dimensions, and press feedback (INSERTED) (completed 2026-03-24)
| 15.4. Zero Dead Zones | 1/2 | In Progress|  | - |
- [ ] **Phase 15.4: Zero Dead Zones** - Eliminate dead zones between keyboard keys so every pixel resolves to a key (INSERTED)
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
**Plans**: 4 plans

Plans:
- [x] 14-01-PLAN.md — Remove Large Turbo, RAM-based recommendation, compilation progress fix, retry-with-cleanup
- [x] 14-02-PLAN.md — Dynamic onboarding model selection, Parakeet routing and display name verification
- [x] 14-03-PLAN.md — Gap closure: fix stale ModelInfoTests after Large Turbo v3 removal
- [ ] 14-04-PLAN.md — Gap closure: fix prewarm progress bar stuck at zero (state transition ordering)

### Phase 15: Design Polish
**Goal**: All user-facing UI reaches beta quality with correct French localization and polished interaction details
**Depends on**: Phase 14 (model manager changes must land before cosmetic polish)
**Requirements**: DSGN-01, DSGN-02, DSGN-03, DSGN-04, DSGN-05, DSGN-06, DSGN-07
**Success Criteria** (what must be TRUE):
  1. All French UI strings display correct accents (modele with accent, dictee with accent, reglages with accent, telecharges with accent, etc.)
  2. Active model in model manager has a visible blue border highlight, and tapping anywhere on a downloaded model card selects it
  3. Recording overlay X button has a generous tap area (44pt minimum) with haptic feedback and smooth easeOut dismiss animation
  4. Mic button shows reduced opacity during transcription processing, giving clear visual feedback that work is happening
**Plans**: 10 plans

Plans:
- [ ] 15-01-PLAN.md — French accent audit, gauge colors, mic button opacity, settings UX
- [ ] 15-02-PLAN.md — Model card redesign (tap-to-select, swipe-to-delete, active highlight)
- [ ] 15-03-PLAN.md — Recording overlay polish (hit area, haptics, dismiss animation, waveform logging)
- [ ] 15-04-PLAN.md — Onboarding success screen, bug fixes (#25 model sync, #26 crash)
- [ ] 15-05-PLAN.md — Gap closure: fix last unaccented French string (MicPermissionPage)
- [ ] 15-06-PLAN.md — Gap closure: model card UX overhaul (progress bar, active border, tap area, section move)
- [ ] 15-07-PLAN.md — Gap closure: overlay fade-out fix, onboarding auto-transition to success
- [ ] 15-08-PLAN.md — Gap closure: keyboard detection crash resilience and diagnostic logging
- [ ] 15-09-PLAN.md — UAT gap closure: active card blue tint + remove switch spinner + swipe delete height
- [ ] 15-10-PLAN.md — UAT gap closure: waveform vertical stability + settings tap feedback

### Phase 15.3: Keyboard optimization and responsiveness (INSERTED)

**Goal:** Reduce keyboard input latency to match native iOS keyboard feel and adjust key spacing/dimensions to match Apple keyboard proportions
**Requirements**: #44, #29
**Depends on:** Phase 15.2
**Success Criteria** (what must be TRUE):
  1. Letter keys use zero-dead-zone DragGesture with contentShape(Rectangle()) for touch handling (UIViewRepresentable reverted — edge clipping issues)
  2. Audio and haptic fire on touchDown (not touchUp), matching Apple keyboard behavior
  3. Suggestion computation runs on background queue with coalescing (not main thread)
  4. Key dimensions are device-adaptive across 3 device classes (compact, standard, large)
  5. Side margins approximately equal inter-key gap (not 3pt margins with 4pt/6pt gaps)
  6. Delete, space, and return keys show background color change on press
  7. OSSignposter instrumentation ready for Instruments profiling on physical device
**Plans:** 4/4 plans complete

Plans:
- [x] 15.3-01-PLAN.md — Quick wins: haptic cache, KeyMetrics static let, pipeline reorder, suggestion background queue, OSSignposter
- [x] 15.3-02-PLAN.md — Zero-dead-zone DragGesture touch handling (UIViewRepresentable reverted)
- [x] 15.3-03-PLAN.md — Device-adaptive key dimensions and press feedback colors
- [x] 15.3-04-PLAN.md — Visual verification + UAT fixes (margins, corner radius, space sound)

### Phase 15.4: Zero Dead Zones (INSERTED)

**Goal:** Eliminate dead zones between keyboard keys — every pixel of the keyboard surface must resolve to a key. See Issue #56 for full context, research (AOSP LatinIME, Apple patent US8232973B2, Fleksy), 3 failed approaches, and implementation leads (A: overlay Color.clear, B: improve catch-all, C: incremental hybrid).
**Requirements**: #56
**Depends on:** Phase 15.3
**Canonical refs:** Issue #56, `.planning/phases/15.4-zero-dead-zones/`
**Plans:** 1/2 plans executed

Plans:
- [ ] 15.4-01-PLAN.md — Version/build logging (#58) + temporary dead zone touch logging
- [ ] 15.4-02-PLAN.md — Improve catch-all resolution, systematic UAT, remove temp logging

### Phase 15.2: Cleaning and Fix GitHub Issues (INSERTED)

**Goal:** Fix ship-blocking bugs (waveform rendering in keyboard extension, Dynamic Island desync after chaining, stale transcription cards) and triage GitHub issues before TestFlight beta
**Requirements**: #37, #42, #41
**Depends on:** Phase 15.1
**Success Criteria** (what must be TRUE):
  1. Waveform bars animate visibly during recording in keyboard extension after both cold and warm starts
  2. Dynamic Island stays in sync with dictation state across 5+ chained recordings
  3. Previous transcription card is always cleared when starting a new recording from any entry path
  4. All resolved/duplicate GitHub issues are closed with references; deferred issues remain open
**Plans:** 4/4 plans complete

Plans:
- [x] 15.2-01-PLAN.md — Waveform rendering fix (#37 residual) + entry path state clearing (#41)
- [x] 15.2-02-PLAN.md — LiveActivityManager state machine refactor (#42)
- [x] 15.2-03-PLAN.md — GitHub issue triage (close resolved, consolidate duplicates)
- [ ] 15.2-04-PLAN.md — Gap closure: waveform/overlay off-screen recovery (#45)

### Phase 15.1: UI polish fixes (#30, #33, #34, #24) (INSERTED)

**Goal:** Fix button alignment (#30), app display name and logo centering (#33), swipe-back overlay improvements (#34), and recording sound feedback with settings (#24) before TestFlight beta
**Requirements**: #30, #33, #34, #24
**Depends on:** Phase 15
**Plans:** 3/3 plans complete

Plans:
- [x] 15.1-01-PLAN.md — App name/logo (#33), button alignment (#30), swipe-back overlay (#34)
- [x] 15.1-02-PLAN.md — Sound feedback service, settings, DictationCoordinator integration (#24)
- [ ] 15.1-03-PLAN.md — Gap closure: sound Bundle path fix, picker layout, button alignment offset

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
**Plans**: 3 plans

Plans:
- [ ] 16-01-PLAN.md — Signing migration, Privacy Manifests, version bump, privacy policy, review checklist (PARTIAL: version bump + Privacy Manifests + PRIVACY.md + review checklist done; signing migration blocked on Team ID)
- [ ] 16-02-PLAN.md — README rewrite, CONTRIBUTING.md, GitHub issue templates
- [ ] 16-03-PLAN.md — Archive, upload, TestFlight distribution, README TestFlight link

## Progress

**Execution Order:**
Phases execute in numeric order: 11 -> 12 -> 13 -> 14 -> 15 -> 15.1 -> 15.2 -> 15.3 -> 15.4 -> 16

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
| 14. Model Pipeline | 4/4 | Complete   | 2026-03-13 | - |
| 15. Design Polish | 10/10 | Complete    | 2026-03-13 | - |
| 15.1. UI Polish Fixes | 3/3 | Complete   | 2026-03-13 | - |
| 15.2. Cleaning & Fix Issues | 4/4 | Complete   | 2026-03-17 | - |
| 15.3. Keyboard Optimization | 4/4 | Complete    | 2026-03-24 | - |
| 15.4. Zero Dead Zones | v1.2 | 0/2 | Planned | - |
| 16. TestFlight Deployment | 1/3 | In Progress|  | - |

---
*Roadmap created: 2026-03-04*
*v1.1 shipped: 2026-03-11*
*v1.2 roadmap added: 2026-03-11*
