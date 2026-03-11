---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: UX & Keyboard
status: completed
stopped_at: Completed 10-04-PLAN.md
last_updated: "2026-03-11T09:26:09.018Z"
last_activity: 2026-03-10 — Plan 10-03 Parakeet integration shipped (iOS 17, FluidAudio)
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 29
  completed_plans: 29
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-07)

**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 9 — Keyboard Modes

## Current Position

Phase: 10 of 10 (Model Catalog)
Plan: 4 of 4 in current phase (4 complete)
Status: Completed
Last activity: 2026-03-11 — Plan 10-04 UAT gap closure (catalog fixes, language default, accents)

Progress: [██████████] 100% (Phase 10: 4/4 plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 18 (v1.0)
- Average duration: ~25 min
- Total execution time: ~7.5 hours (v1.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Foundation | 4 | ~100 min | ~25 min |
| 2. Transcription | 3 | ~75 min | ~25 min |
| 3. Dictation UX | 4 | ~100 min | ~25 min |
| 4. App & Polish | 5 | ~125 min | ~25 min |
| 5. Settings | 2 | ~50 min | ~25 min |
| 6. Infra & Polish | 3/3 | ~14 min | ~5 min |

**Recent Trend:**
- v1.0: 18 plans in 4 days
- v1.1: Plan 1 in 9 min, Plan 2 in 1 min, Plan 3 in 5 min
- Trend: Stable

*Updated after each plan completion*
| Phase 06 P03 | 5min | 3 tasks | 6 files |
| Phase 07 P03 | 5min | 2 tasks | 4 files |
| Phase 07 P01 | 5min | 2 tasks | 6 files |
| Phase 07 P02 | 5min | 2 tasks | 7 files |
| Phase 07 P04 | 2min | 2 tasks | 3 files |
| Phase 07 P06 | 4min | 1 tasks | 3 files |
| Phase 07 P08 | 4min | 2 tasks | 7 files |
| Phase 07 P07 | 4min | 2 tasks | 4 files |
| Phase 07 P11 | 6min | 2 tasks | 2 files |
| Phase 07 P12 | 2min | 2 tasks | 2 files |
| Phase 08 P01 | 7min | 3 tasks | 10 files |
| Phase 08 P02 | 12min | 2 tasks | 6 files |
| Phase 09 P01 | 2min | 1 tasks | 3 files |
| Phase 09 P02 | 3min | 2 tasks | 4 files |
| Phase 09 P03 | 3min | 2 tasks | 4 files |
| Phase 09 P04 | 2min | 1 tasks | 2 files |
| Phase 09 P05 | 3min | 1 tasks | 1 files |
| Phase 09 P06 | 2min | 1 tasks | 1 files |
| Phase 10 P01 | 3min | 3 tasks | 7 files |
| Phase 10 P02 | 8min | 3 tasks | 4 files |
| Phase 10 P03 | 3min | 3 tasks | 9 files |
| Phase 10 P04 | 3min | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [06-01]: Design files consolidated into DictusCore with public access -- INFRA-01 resolved
- [06-01]: public extension pattern for cross-module design tokens (Color.dictusAccent etc.)
- [06-01]: CoreGraphics script for reproducible app icon generation
- [v1.0]: FillerWordFilter removed -- Whisper handles fillers natively
- [v1.0]: SmartModelRouter bypassed -- runtime model switching breaks background recording
- [Phase 06]: onAppear loadState() to fix stale model state after onboarding
- [06-03]: RecordingMode enum (.onboarding/.standalone) for shared RecordingView
- [06-03]: switch/case replaces TabView to block onboarding step swiping
- [06-03]: Keyboard auto-detection via UITextInputMode.activeInputModes, no manual confirm
- [Phase 06]: RecordingMode enum (.onboarding/.standalone) for shared RecordingView
- [07-03]: AnyShape type erasure for conditional Circle/Capsule rendering in AnimatedMicButton
- [07-03]: Canvas single-pass rendering for BrandWaveform (solid Color, not per-bar gradient)
- [07-03]: dictusSuccess green for validate button to distinguish from cancel
- [Phase 07]: Pre-allocated static UIImpactFeedbackGenerator instances eliminate 2-5ms per-tap haptic latency
- [Phase 07]: Device-adaptive key height: 42pt SE, 46pt standard, 50pt Plus/Max via UIScreen.main.bounds
- [Phase 07]: KBD-05: system dictation mic icon is iOS limitation with no public API to suppress
- [Phase 07]: Apostrophe as adaptive key default -- most common non-letter char in French
- [Phase 07]: Long-press on adaptive key only when showing accent (not apostrophe)
- [Phase 07]: Removed duplicate haptic from onSpace -- SpaceKey handles own haptics via DragGesture
- [Phase 07]: Vertical cursor movement: proportional 1-char-per-15pt with velocity acceleration (replaces 40-char line jumps)
- [07-07]: Word-level delete via manual word boundary detection (UITextDocumentProxy lacks deleteWordBackward)
- [07-07]: Autocap uses NotificationCenter for textDidChange bridging between UIKit controller and SwiftUI view
- [07-06]: Accent replacement logic in KeyboardView onAccentAdaptive handler (deleteBackward+insert pattern)
- [07-10]: Accent case derived from lastTypedChar not isShifted -- avoids auto-unshift timing bug
- [07-06]: SF Symbol face.smiling for emoji key matches Apple native AZERTY visual style
- [Phase 07]: Toolbar 48pt height for mic pill glow room; 0.05 silence threshold; unconditional playInputClick on all keys
- [Phase 07]: Cancel uses collectSamples() not stopRecording() to preserve engine for background recording
- [Phase 07]: Emoji key cycling accepted as iOS limitation — no public API to target emoji keyboard
- [07-11]: AudioServicesPlaySystemSound over playInputClick for 3-category key sounds (letter/delete/modifier)
- [07-11]: 40-char line estimate for vertical cursor jumps (UITextDocumentProxy has no line-width API)
- [07-11]: Delete sound in DeleteKey view, not callbacks, to avoid duplication
- [08-01]: FrequencyDictionary as pure Swift struct in DictusCore for testability without UIKit
- [08-01]: TextPredictionEngine as class (not struct) due to UITextChecker reference type
- [08-01]: Frequency-ranked UITextChecker completions for better suggestion quality
- [08-01]: Single language loaded at a time to minimize memory in keyboard extension
- [Phase 08]: Gear icon hidden during suggestions to maximize horizontal space for 3 slots
- [Phase 08]: DispatchQueue.main.async for suggestion updates after keystroke to avoid stale proxy reads
- [Phase 08]: Autocorrect undo stores original word and restores on immediate backspace
- [Phase 09]: KeyboardMode defaults to .full to protect existing users on update
- [Phase 09]: KeyboardMode follows LayoutType pattern exactly for DictusCore consistency
- [Phase 09]: Custom 120pt mic pill instead of scaleEffect to avoid retina blur
- [Phase 09]: RecordingOverlay above mode switch for all-mode coverage; isEmojiMode only in .full mode
- [Phase 09]: Empty string default in onboarding forces explicit mode selection
- [Phase 09]: Conditional toggles: AZERTY/QWERTY and autocorrect only for Complet, haptics hidden for Micro
- [Phase 09]: NotificationCenter bridge over computed property to avoid reading UserDefaults on every SwiftUI body evaluation
- [10-01]: SpeechEngine enum with WK/PK raw values for multi-engine model catalog
- [10-01]: CatalogVisibility soft-deprecation: Tiny/Base hidden but still resolvable
- [10-01]: All 3 new WhisperKit candidates added (turbo, distil, small216) -- user will test on device
- [10-01]: Fallback model changed from tiny to small in DictationCoordinator
- [09-05]: secondarySystemBackground for MicroModeView to match system keyboard chrome
- [09-05]: Mic button disabled during .requested state to prevent double-tap race with Darwin notification
- [Phase 09]: Gear icon replaces globe in EmojiMicroModeView -- iOS provides system globe, gear opens settings
- [Phase 10]: 5-segment gauge bar for model accuracy/speed visualization in catalog UI
- [Phase 10]: Downloaded section uses allIncludingDeprecated so deprecated models remain visible if on device
- [Phase 10-03]: Ship Parakeet: raise deployment target from iOS 16 to iOS 17, remove conditional compilation
- [Phase 10]: Persist language default in App Group at init() rather than relying on @AppStorage defaults

### Pending Todos

None yet.

### Blockers/Concerns

- MOD-02 (Parakeet v3) is highest-risk requirement — FluidAudio SDK maturity and French accuracy unproven. May need to defer to v1.2 during Phase 10 planning.
- COLD-* requirements deferred to v1.2 — cold start partially addressed manually, full solution needs deeper research
- PRED memory budget — text prediction must stay under 5MB resident in keyboard extension. Needs real-device profiling.

## Session Continuity

Last session: 2026-03-11T09:26:09.016Z
Stopped at: Completed 10-04-PLAN.md
Resume file: None

---
*State initialized: 2026-03-04*
*v1.1 roadmap created: 2026-03-07*
