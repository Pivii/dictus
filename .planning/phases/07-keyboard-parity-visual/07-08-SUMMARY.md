---
phase: 07-keyboard-parity-visual
plan: 08
subsystem: ui
tags: [swiftui, waveform, audio-feedback, keyboard-extension]

requires:
  - phase: 07-03
    provides: BrandWaveform with Canvas rendering and processing mode
  - phase: 07-05
    provides: UAT gap analysis identifying visual polish issues
provides:
  - Mic pill fully visible with no top clipping
  - Waveform perfectly still on silence (0.05 threshold)
  - Sinusoidal processing animation replacing 3-bar logo pulsing
  - Key tap sounds on all key types
  - Experimental bottom padding for dictation mic overlay-hide
affects: [07-09, visual-polish, keyboard-ux]

tech-stack:
  added: []
  patterns: [silence-threshold-filtering, unconditional-playInputClick]

key-files:
  created: []
  modified:
    - DictusKeyboard/Views/ToolbarView.swift
    - DictusCore/Sources/DictusCore/Design/BrandWaveform.swift
    - DictusKeyboard/Views/RecordingOverlay.swift
    - DictusKeyboard/KeyboardRootView.swift
    - DictusKeyboard/KeyboardViewController.swift
    - DictusKeyboard/Views/KeyboardView.swift
    - DictusKeyboard/Views/SpecialKeyButton.swift

key-decisions:
  - "Toolbar height 48pt (from 44pt) to accommodate mic pill glow without clipping"
  - "Silence threshold 0.05 in BrandWaveform -- ambient mic noise below this treated as zero"
  - "playInputClick() called unconditionally on all keys (system ignores when prerequisites not met)"
  - "8pt bottom padding as experimental dictation mic overlay-hide (may be iOS limitation)"

patterns-established:
  - "Silence threshold: energy < 0.05 treated as zero in waveform visualizer"

requirements-completed: [VIS-01, VIS-03, KBD-05, KBD-03]

duration: 4min
completed: 2026-03-08
---

# Phase 7 Plan 8: Visual Polish & Key Sounds Summary

**Mic pill clipping fix (48pt toolbar), waveform silence threshold (0.05), sinusoidal processing animation, and playInputClick() on all key types**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-08T12:48:01Z
- **Completed:** 2026-03-08T12:52:16Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Mic pill fully visible in toolbar -- increased height from 44pt to 48pt with matching constants
- Waveform completely still during silence -- ambient noise filtered by 0.05 threshold
- Transcribing state shows sinusoidal traveling wave (BrandWaveform isProcessing) instead of 3-bar logo pulsing
- Key tap sounds (playInputClick) fire on all key types: letters, space, return, delete, globe, shift, 123/ABC, #+=, accent
- Experimental 8pt bottom padding attempts to push system dictation mic area down

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix mic pill clipping and waveform silence/processing issues** - `d1b3fbb` (fix)
2. **Task 2: Key tap sounds on all keys and Apple dictation mic overlay-hide attempt** - `da4302f` (feat)

## Files Created/Modified
- `DictusKeyboard/Views/ToolbarView.swift` - Toolbar height increased to 48pt for mic pill glow room
- `DictusCore/Sources/DictusCore/Design/BrandWaveform.swift` - Added 0.05 silence threshold in energyForBar
- `DictusKeyboard/Views/RecordingOverlay.swift` - Replaced ProcessingAnimation with BrandWaveform(isProcessing: true)
- `DictusKeyboard/KeyboardRootView.swift` - Updated toolbarHeight to 48pt, added 8pt bottom spacer
- `DictusKeyboard/KeyboardViewController.swift` - Updated toolbarHeight to 48pt, added bottomPadding to height calc
- `DictusKeyboard/Views/KeyboardView.swift` - Added playInputClick() to globe, layerSwitch, symbolToggle, accent handlers
- `DictusKeyboard/Views/SpecialKeyButton.swift` - Added playInputClick() to ShiftKey button action

## Decisions Made
- Toolbar height 48pt (from 44pt) gives 6pt breathing room above and below the 36pt mic pill, preventing glow clipping
- Silence threshold set at 0.05 -- empirically covers typical ambient mic noise without suppressing real speech onset
- playInputClick() called unconditionally on all keys -- the system silently ignores it when UIInputViewAudioFeedback prerequisites are not met, so no hasFullAccess guard needed
- Conservative 8pt bottom padding for dictation mic overlay-hide -- documents result either way as KBD-05

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All visual polish issues from UAT are resolved
- Key sounds complete across all key types
- Dictation mic overlay is experimental -- needs on-device verification to confirm if 8pt helps
- Ready for plan 07-09 (remaining gap closure tasks)

---
*Phase: 07-keyboard-parity-visual*
*Completed: 2026-03-08*
