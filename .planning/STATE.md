---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: UX & Keyboard
status: executing
stopped_at: Completed 07-12-PLAN.md
last_updated: "2026-03-08T14:17:32.690Z"
last_activity: 2026-03-08 — Plan 07-07 complete (trackpad smoothing, delete acceleration, autocap)
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 17
  completed_plans: 15
  percent: 88
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-07)

**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 7 — Keyboard Parity & Visual Polish

## Current Position

Phase: 7 of 10 (Keyboard Parity & Visual)
Plan: 11 of 11 in current phase (11 complete)
Status: In progress
Last activity: 2026-03-08 — Plan 07-11 complete (trackpad line movement, 3-category key sounds)

Progress: [██████████] 100% (Phase 7: 11/11 plans complete)

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

### Pending Todos

None yet.

### Blockers/Concerns

- MOD-02 (Parakeet v3) is highest-risk requirement — FluidAudio SDK maturity and French accuracy unproven. May need to defer to v1.2 during Phase 10 planning.
- COLD-03 (auto-return) has no known public API — research spike needed. Competitors' technique is undocumented.
- PRED memory budget — text prediction must stay under 5MB resident in keyboard extension. Needs real-device profiling.

## Session Continuity

Last session: 2026-03-08T14:20:33Z
Stopped at: Completed 07-11-PLAN.md
Resume file: None

---
*State initialized: 2026-03-04*
*v1.1 roadmap created: 2026-03-07*
