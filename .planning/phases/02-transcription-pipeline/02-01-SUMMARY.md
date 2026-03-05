---
phase: 02-transcription-pipeline
plan: 01
subsystem: audio, transcription
tags: [whisperkit, spm, avaudiosession, swiftui, waveform, french-stt]

# Dependency graph
requires:
  - phase: 01-cross-process-foundation
    provides: "DictationCoordinator stubs, App Group signaling, Darwin notifications, DictusCore shared types"
provides:
  - "WhisperKit SPM dependency integrated into DictusApp"
  - "AudioRecorder wrapping WhisperKit AudioProcessor with energy levels"
  - "TranscriptionService with French language transcription"
  - "RecordingView with waveform, stop button, elapsed time"
  - "DictationCoordinator rewritten with real recording + transcription pipeline"
affects: [02-03-model-manager, 03-dictation-ux]

# Tech tracking
tech-stack:
  added: [WhisperKit 0.16.0+, AVAudioSession]
  patterns: [WhisperKit AudioProcessor for recording, greedy decoding with language hint]

key-files:
  created:
    - DictusApp/Audio/AudioRecorder.swift
    - DictusApp/Audio/TranscriptionService.swift
    - DictusApp/Views/RecordingView.swift
  modified:
    - Dictus.xcodeproj/project.pbxproj
    - DictusApp/DictationCoordinator.swift
    - DictusApp/ContentView.swift

key-decisions:
  - "WhisperKit AudioProcessor used directly — no custom AVAudioEngine pipeline needed"
  - "ContiguousArray<Float> wrapped with Array() for WhisperKit audioSamples compatibility"

patterns-established:
  - "WhisperKit init pattern: lazy initialization on first dictation, reuse across sessions"
  - "Energy buffer forwarding: AudioProcessor.relativeEnergy -> coordinator -> RecordingView"

requirements-completed: [STT-01, STT-03, STT-05]

# Metrics
duration: ~45min
completed: 2026-03-05
---

# Phase 2 Plan 1: WhisperKit Integration Summary

**WhisperKit SPM integrated with AudioRecorder, TranscriptionService, and RecordingView delivering real French speech-to-text with waveform visualization on device**

## Performance

- **Duration:** ~45 min (across two agent sessions)
- **Tasks:** 3 (2 auto + 1 human-verify)
- **Files created:** 3
- **Files modified:** 3

## Accomplishments
- WhisperKit added as SPM dependency linked to DictusApp target only (not DictusKeyboard due to 50MB memory limit)
- AudioRecorder wraps WhisperKit's AudioProcessor for 16kHz mono recording with live energy levels for waveform
- TranscriptionService transcribes with French language hint and greedy decoding (temperature 0.0)
- RecordingView displays animated waveform, stop button, and elapsed time counter
- DictationCoordinator fully rewritten — no stubs remain, real recording + transcription pipeline
- Verified on physical iPhone: French speech produces accurate transcription with automatic punctuation

## Task Commits

Each task was committed atomically:

1. **Task 1: Add WhisperKit SPM + AudioRecorder + TranscriptionService** - `3076787` (feat)
2. **Task 2: Rewrite DictationCoordinator + RecordingView + wire UI** - `5d5a2e9` (feat)
3. **Task 3: Verify recording and transcription on device** - checkpoint:human-verify (approved)

## Files Created/Modified
- `DictusApp/Audio/AudioRecorder.swift` - WhisperKit AudioProcessor wrapper with energy levels and recording timer
- `DictusApp/Audio/TranscriptionService.swift` - WhisperKit transcription with French language, greedy decoding
- `DictusApp/Views/RecordingView.swift` - Waveform visualization, stop button, elapsed time, transcribing/ready states
- `Dictus.xcodeproj/project.pbxproj` - WhisperKit SPM reference, new file registrations
- `DictusApp/DictationCoordinator.swift` - Replaced Phase 1 stubs with real WhisperKit pipeline
- `DictusApp/ContentView.swift` - Routes to RecordingView when status is recording/transcribing/ready

## Decisions Made
- WhisperKit's built-in AudioProcessor handles 16kHz mono Float32 conversion internally, so no custom AVAudioEngine pipeline was needed
- Default model hardcoded to "openai_whisper-tiny" as fallback until Plan 02-03 adds model selection UI

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ContiguousArray/Array type mismatch in AudioRecorder.stopRecording()**
- **Found during:** Task 1 (AudioRecorder implementation)
- **Issue:** WhisperKit's `audioProcessor.audioSamples` returns `ContiguousArray<Float>`, but the method signature returns `[Float]`
- **Fix:** Wrapped with `Array()` initializer: `return Array(samples)`
- **Files modified:** DictusApp/Audio/AudioRecorder.swift
- **Verification:** Build succeeds, transcription works on device
- **Committed in:** 3076787 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Minor type conversion fix required for WhisperKit API compatibility. No scope creep.

## Issues Encountered
None beyond the ContiguousArray type mismatch documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 02-02 (FillerWordFilter + SmartModelRouter) already completed
- Plan 02-03 (ModelManager + pipeline wiring) is the remaining plan in Phase 2
- Recording and transcription pipeline is ready for SmartModelRouter and FillerWordFilter integration

## Self-Check: PASSED
- 02-01-SUMMARY.md: FOUND
- AudioRecorder.swift: FOUND
- TranscriptionService.swift: FOUND
- RecordingView.swift: FOUND
- Commit 3076787: FOUND
- Commit 5d5a2e9: FOUND

---
*Phase: 02-transcription-pipeline*
*Completed: 2026-03-05*
