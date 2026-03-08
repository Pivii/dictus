# Requirements: Dictus

**Defined:** 2026-03-07
**Core Value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.

## v1.1 Requirements

Requirements for v1.1 UX & Keyboard milestone. Each maps to roadmap phases.

### Infrastructure

- [x] **INFRA-01**: Design files consolidated into a shared DictusUI package (no more duplication between DictusApp and DictusKeyboard)
- [x] **INFRA-02**: App icon generated from brand kit (SVG to PNG, adaptive light/dark)

### Keyboard Parity

- [ ] **KBD-01**: User can long-press spacebar to activate trackpad mode (greyed-out keyboard, drag to move cursor, haptic tick per character)
- [ ] **KBD-02**: Adaptive key next to N displays apostrophe or accent based on typing context
- [ ] **KBD-03**: Haptic feedback fires on every key tap (space, return, delete, letters, symbols)
- [ ] **KBD-04**: Duplicate globe key removed, replaced with emoji button (cycles to system emoji keyboard via advanceToNextInputMode)
- [ ] **KBD-05**: Apple dictation mic removed from keyboard
- [ ] **KBD-06**: Keyboard typing performance optimized — input latency and haptic response comparable to native Apple keyboard

### Text Prediction

- [ ] **PRED-01**: 3-slot suggestion bar above keyboard with current word completion
- [ ] **PRED-02**: French autocorrect — spelling correction applied on word validation
- [ ] **PRED-03**: Accent suggestions in suggestion bar (e.g. typing "a" proposes "a", "à", "â")

### Visual Polish

- [x] **VIS-01**: Mic button redesigned as pill shape (larger, more visible)
- [x] **VIS-02**: Recording validate/cancel buttons redesigned as pill shape, same size
- [x] **VIS-03**: Waveform animation reworked — smoother via TimelineView + Canvas (60fps interpolation)
- [x] **VIS-04**: Test recording screen in app redesigned
- [x] **VIS-05**: Recording stop screen redesigned (more cohesive with app theme)
- [x] **VIS-06**: Duplicate "Dictus" navigation title removed from HomeView (keep only logo + blue title)
- [x] **VIS-07**: Post-onboarding bug fixed — HomeView shows correct state after model download (no "Télécharger un modèle" when model exists) + side band artifacts removed
- [x] **VIS-08**: Onboarding flow improved — progression blocked until each step completed (mic permission granted, keyboard added, model downloaded)

### Cold Start

- [ ] **COLD-01**: Cold starts minimized — background audio keep-alive to reduce iOS app kills
- [ ] **COLD-02**: Cold start optimized — init time < 2s when cold start occurs
- [ ] **COLD-03**: Auto-return to keyboard after cold start (deep research into Wispr Flow technique, best-effort)

### Models

- [ ] **MOD-01**: Model catalog cleaned — remove underperforming models (tiny/base if confirmed unhelpful)
- [ ] **MOD-02**: Parakeet v3 integrated as alternative STT option (SpeechModel protocol + FluidAudio runtime)
- [ ] **MOD-03**: Model selection UI updated to display both engines (WhisperKit + Parakeet)

## v1.2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Smart Modes

- **SMART-01**: User can select output format (email, SMS, note) before dictating
- **SMART-02**: LLM post-processes transcription into selected format
- **SMART-03**: User can preview and edit formatted output before inserting

### Advanced Prediction

- **PRED-04**: Next-word prediction using custom ML model (beyond UITextChecker)
- **PRED-05**: Swipe typing / gesture typing

### Customization

- **CUST-01**: Keyboard themes / custom colors
- **CUST-02**: Auto-capitalize after punctuation (French-specific rules)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Real-time streaming transcription | v2+ feature, current batch approach works well |
| iPad support | v2+, iPhone-first |
| Android port | v3+, different platform entirely |
| iCloud sync | v2+, local storage sufficient |
| Cloud transcription | Contradicts privacy/offline identity |
| Subscription / monetization | Contradicts open-source positioning |
| Smart Model Routing at runtime | Breaks background recording, user selects model once |
| Full emoji picker in extension | Memory-unsafe (emoji glyph cache), use system cycling instead |
| Apple Foundation Models | Requires iPhone 15 Pro+, iOS 26.1+ — too restrictive |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 6 | Complete |
| INFRA-02 | Phase 6 | Complete |
| KBD-01 | Phase 7 | Pending |
| KBD-02 | Phase 7 | Pending |
| KBD-03 | Phase 7 | Pending |
| KBD-04 | Phase 7 | Pending |
| KBD-05 | Phase 7 | Pending |
| KBD-06 | Phase 7 | Pending |
| PRED-01 | Phase 8 | Pending |
| PRED-02 | Phase 8 | Pending |
| PRED-03 | Phase 8 | Pending |
| VIS-01 | Phase 7 | Complete |
| VIS-02 | Phase 7 | Complete |
| VIS-03 | Phase 7 | Complete |
| VIS-04 | Phase 6 | Complete |
| VIS-05 | Phase 6 | Complete |
| VIS-06 | Phase 6 | Complete |
| VIS-07 | Phase 6 | Complete |
| VIS-08 | Phase 6 | Complete |
| COLD-01 | Phase 9 | Pending |
| COLD-02 | Phase 9 | Pending |
| COLD-03 | Phase 9 | Pending |
| MOD-01 | Phase 10 | Pending |
| MOD-02 | Phase 10 | Pending |
| MOD-03 | Phase 10 | Pending |

**Coverage:**
- v1.1 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0

---
*Requirements defined: 2026-03-07*
*Last updated: 2026-03-07 after roadmap creation*
