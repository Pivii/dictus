# Roadmap: Dictus

**Created:** 2026-03-04
**Granularity:** Coarse

---

## Milestones

- ✅ **v1.0 MVP** — Phases 1-5 (shipped 2026-03-07)
- 🚧 **v1.1 UX & Keyboard** — Phases 6-10 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-5) — SHIPPED 2026-03-07</summary>

- [x] Phase 1: Cross-Process Foundation (4/4 plans) — completed 2026-03-05
- [x] Phase 2: Transcription Pipeline (3/3 plans) — completed 2026-03-06
- [x] Phase 3: Dictation UX (4/4 plans) — completed 2026-03-06
- [x] Phase 4: Main App, Onboarding, and Polish (5/5 plans) — completed 2026-03-07
- [x] Phase 5: Wire Settings & Code Hygiene (2/2 plans) — completed 2026-03-07

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

### 🚧 v1.1 UX & Keyboard (In Progress)

**Milestone Goal:** Bring the keyboard to Apple-level parity and polish the overall UX — cold start, trackpad, prediction, haptics, animations, and model catalog.

- [ ] **Phase 6: Infrastructure & App Polish** - Consolidate design files into shared package, generate app icon, fix app-side visual bugs and onboarding flow (UAT gap closure in progress)
- [x] **Phase 7: Keyboard Parity & Visual** - Spacebar trackpad, adaptive accent key, haptics, bottom row cleanup, mic/recording pill redesign, waveform rework, performance optimization (completed 2026-03-08)
- [x] **Phase 8: Text Prediction** - 3-slot suggestion bar with French autocorrect and accent suggestions (completed 2026-03-09)
- [ ] **Phase 9: Keyboard Modes** - Three switchable keyboard layouts (full, mic-only, emoji+mic) with live preview in settings (UAT gap closure in progress)
- [x] **Phase 10: Model Catalog** - Clean underperforming models, integrate Parakeet v3, update model selection UI (completed 2026-03-10)

## Phase Details

### Phase 6: Infrastructure & App Polish
**Goal**: Eliminate design file duplication and fix all app-side visual issues so every subsequent phase builds on a clean, consolidated codebase
**Depends on**: Phase 5 (v1.0 complete)
**Requirements**: INFRA-01, INFRA-02, VIS-04, VIS-05, VIS-06, VIS-07, VIS-08
**Success Criteria** (what must be TRUE):
  1. Design components (colors, styles, shared views) live in one place and are imported by both DictusApp and DictusKeyboard — no duplicated design files
  2. App icon renders correctly in light and dark mode on the home screen, generated from the brand kit
  3. HomeView shows correct state after onboarding (no stale "download model" prompt when a model exists, no side band artifacts)
  4. Onboarding flow blocks progression until each step is completed (mic permission, keyboard added, model downloaded)
  5. Test recording and recording stop screens match the app's Liquid Glass theme with no visual inconsistencies
**Plans**: 5 plans

Plans:
- [x] 06-01-PLAN.md — Consolidate design files into DictusCore and generate app icon
- [x] 06-02-PLAN.md — Fix HomeView duplicate title and model state bug
- [x] 06-03-PLAN.md — Redesign test recording screen and fix onboarding blocking
- [ ] 06-04-PLAN.md — Fix app icon proportions and dark variant (gap closure)
- [ ] 06-05-PLAN.md — Fix HomeView stale state, centering, recording navbar, processing animation (gap closure)

### Phase 7: Keyboard Parity & Visual
**Goal**: Users perceive the Dictus keyboard as equal to or better than Apple's native keyboard in core interactions, with a polished mic button and recording experience
**Depends on**: Phase 6 (shared design package available)
**Requirements**: KBD-01, KBD-02, KBD-03, KBD-04, KBD-05, KBD-06, VIS-01, VIS-02, VIS-03
**Success Criteria** (what must be TRUE):
  1. User can long-press the spacebar and drag to move the cursor through text, with haptic ticks per character and a greyed-out keyboard overlay
  2. The key next to N shows apostrophe or accent contextually based on what the user just typed — no more 3-tap layer switching for apostrophes
  3. Every key tap (letters, space, return, delete, symbols) produces haptic feedback and click sound
  4. Bottom row has emoji button (cycles to system emoji keyboard) instead of duplicate globe, and Apple dictation mic is hidden or minimized
  5. Mic button and recording validate/cancel buttons are pill-shaped, larger, and waveform animation runs at smooth 60fps
**Plans**: 12 plans

Plans:
- [x] 07-01-PLAN.md — Haptic pre-allocation, universal key haptics, dynamic height, banner fix, popup clipping
- [x] 07-02-PLAN.md — Emoji button replacing globe, adaptive accent key on AZERTY
- [x] 07-03-PLAN.md — Mic pill redesign, recording pill buttons, Canvas waveform with zero-energy stillness
- [x] 07-04-PLAN.md — Spacebar trackpad mode (long-press, cursor drag, overlay)
- [x] 07-05-PLAN.md — Full keyboard UAT checkpoint (gaps found)
- [x] 07-06-PLAN.md — Fix accent key replacement, SF Symbol icons for special keys (gap closure)
- [x] 07-07-PLAN.md — Smooth trackpad, delete acceleration, autocapitalisation (gap closure)
- [x] 07-08-PLAN.md — Mic pill clip fix, waveform silence, processing animation, key sounds, dictation mic overlay (gap closure)
- [x] 07-09-PLAN.md — Gap closure UAT checkpoint
- [ ] 07-10-PLAN.md — Fix accent uppercase, special key colors, shift styling (gap closure)
- [ ] 07-11-PLAN.md — Trackpad vertical line movement, 3-category key sounds (gap closure)
- [ ] 07-12-PLAN.md — Fix waveform after cancel, document emoji limitation (gap closure)

### Phase 8: Text Prediction
**Goal**: Users get French word completions and spelling corrections as they type, bridging the gap between dictation keyboard and full replacement keyboard
**Depends on**: Phase 7 (keyboard layout finalized, gesture architecture stable)
**Requirements**: PRED-01, PRED-02, PRED-03
**Success Criteria** (what must be TRUE):
  1. A 3-slot suggestion bar appears above the keyboard and updates with word completions on each keystroke
  2. Tapping a suggestion inserts the word and adds a space — misspelled words get auto-corrected on validation
  3. When typing characters that could be accented (a, e, u, etc.), the suggestion bar offers accented variants (a, à, â)
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md — Core prediction engine, frequency dictionary, suggestion state
- [ ] 08-02-PLAN.md — Suggestion bar UI, autocorrect wiring, undo-on-backspace, settings toggle

### Phase 9: Keyboard Modes
**Goal**: Users choose the keyboard layout that fits their usage — dictation-focused (mic only), emoji+mic, or full AZERTY — with a live preview in settings
**Depends on**: Phase 8 (keyboard features complete), Phase 7 (emoji picker built)
**Requirements**: MODE-01, MODE-02, MODE-03, MODE-04
**Success Criteria** (what must be TRUE):
  1. Three keyboard modes available: "Micro" (large centered mic button + globe), "Emoji + Micro" (emoji picker with mic in toolbar), "Clavier complet" (current full AZERTY)
  2. User selects their preferred mode in the app's Settings screen
  3. Settings screen shows a non-interactive SwiftUI preview of each mode so the user sees what they're choosing
  4. The keyboard extension reads the selected mode from App Group and renders the correct layout
**Plans**: 6 plans

Plans:
- [x] 09-01-PLAN.md — KeyboardMode enum, SharedKey, unit tests (DictusCore foundation)
- [x] 09-02-PLAN.md — MicroModeView, EmojiMicroModeView, KeyboardRootView mode switching
- [x] 09-03-PLAN.md — KeyboardModePicker with previews, Settings integration, onboarding step
- [ ] 09-04-PLAN.md — Fix App Group mode sync via viewWillAppear notification (gap closure)
- [x] 09-05-PLAN.md — Fix MicroModeView background, utility keys, mic states (gap closure)
- [ ] 09-06-PLAN.md — Fix EmojiMicroModeView overflow, toolbar gear, ABC wiring (gap closure)

### Phase 10: Model Catalog
**Goal**: Users see only performant models in the catalog and can choose between WhisperKit and Parakeet engines for transcription
**Depends on**: Phase 7 (keyboard stable, no pipeline changes during keyboard work)
**Requirements**: MOD-01, MOD-02, MOD-03
**Success Criteria** (what must be TRUE):
  1. Underperforming models (confirmed unhelpful tiny/base variants) are removed from the catalog — users only see models worth downloading
  2. Parakeet v3 is available as an alternative STT engine via the SpeechModel protocol abstraction
  3. Model selection UI clearly displays both engines (WhisperKit and Parakeet) with relevant metadata (size, accuracy, speed)
**Plans**: 3 plans

Plans:
- [ ] 10-01-PLAN.md — Catalog cleanup, ModelInfo extension (engine/gauges/visibility), SmartModelRouter removal
- [ ] 10-02-PLAN.md — Model selection UI redesign with gauge bars, sections, engine badges
- [ ] 10-03-PLAN.md — Parakeet v3 integration via FluidAudio SDK (go/no-go checkpoint)

## Progress

**Execution Order:**
Phases execute in numeric order: 6 → 7 → 8 → 9 → 10
Note: Phase 9 (Cold Start) is independent of Phases 7-8 and could execute in parallel if needed.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Cross-Process Foundation | v1.0 | 4/4 | Complete | 2026-03-05 |
| 2. Transcription Pipeline | v1.0 | 3/3 | Complete | 2026-03-06 |
| 3. Dictation UX | v1.0 | 4/4 | Complete | 2026-03-06 |
| 4. Main App & Polish | v1.0 | 5/5 | Complete | 2026-03-07 |
| 5. Wire Settings & Hygiene | v1.0 | 2/2 | Complete | 2026-03-07 |
| 6. Infrastructure & App Polish | v1.1 | 3/5 | Gap closure | - |
| 7. Keyboard Parity & Visual | 12/12 | Complete   | 2026-03-08 | - |
| 8. Text Prediction | 2/2 | Complete   | 2026-03-09 | - |
| 9. Keyboard Modes | 5/6 | In Progress|  | - |
| 10. Model Catalog | 3/3 | Complete   | 2026-03-10 | - |

---
*Roadmap created: 2026-03-04*
*v1.1 phases added: 2026-03-07*
