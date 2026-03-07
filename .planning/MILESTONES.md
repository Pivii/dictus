# Milestones

## v1.0 MVP (Shipped: 2026-03-07)

**Phases completed:** 5 phases, 18 plans
**Timeline:** 4 days (2026-03-04 -> 2026-03-07)
**Commits:** 137 | **Files:** 156 | **LOC:** 7,305 Swift

**Delivered:** A free, open-source iOS keyboard with on-device French speech-to-text via WhisperKit, AZERTY/QWERTY layouts, and iOS 26 Liquid Glass design.

**Key accomplishments:**
1. Two-process dictation architecture — keyboard extension triggers main app via Darwin notifications + URL scheme
2. On-device French speech-to-text — WhisperKit integration with model manager (5 Whisper models)
3. Wispr Flow-inspired dictation UX — mic tap, recording overlay with waveform/haptics, auto-insert into any text field
4. Full AZERTY/QWERTY keyboard — 3-layer layout, accented character long-press, shift/caps lock, delete repeat
5. iOS 26 Liquid Glass design — .glassEffect() throughout with Material fallback on iOS 16-25
6. Guided 5-step onboarding — mic permission, keyboard setup, model download, test dictation

**Git range:** `feat(01-01)` -> `refactor(05)`

### Known Gaps
- **STT-04** (Smart Model Routing): Dropped — runtime model switching breaks background recording. User selects model once.
- **APP-03** (Settings): 3/4 toggles wired in Phase 5. Language toggle functional but limited by Whisper model language support.
- SmartModelRouter code exists but bypassed at runtime (intentional)
- FullAccessBanner cannot open URLs from keyboard extension (iOS limitation)
- 6 design files duplicated between DictusApp and DictusKeyboard (manual sync required)

---

