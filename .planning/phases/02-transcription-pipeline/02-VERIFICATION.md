---
phase: 02-transcription-pipeline
verified: 2026-03-06T12:00:00Z
status: passed
score: 13/13 must-haves verified
gaps: []
human_verification:
  - test: "Verify transcription speed under 3 seconds for 10s audio on iPhone 12+"
    expected: "STT-05 requires transcription completes in under 3 seconds for 10 seconds of audio"
    why_human: "Performance timing requires physical device measurement"
  - test: "Verify filler word removal in live transcription"
    expected: "Speaking 'euh bonjour euh comment ca va' produces clean output without filler words"
    why_human: "End-to-end speech recognition quality cannot be verified programmatically"
---

# Phase 2: Transcription Pipeline Verification Report

**Phase Goal:** Real WhisperKit transcription pipeline with model management, smart routing, and filler word removal.
**Verified:** 2026-03-06
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User speaks French into the main app and receives transcription text | VERIFIED | TranscriptionService.swift uses `language: "fr"`, `temperature: 0.0`, joins segments, returns cleaned text. DictationCoordinator orchestrates full record->transcribe->write pipeline. |
| 2 | Recording starts via dictus://dictate URL scheme | VERIFIED | DictationCoordinator.startDictation() checks modelReady, requests mic permission, initializes WhisperKit, calls audioRecorder.startRecording(). Double-start guard present. |
| 3 | User taps stop button -- waveform + elapsed time visible during recording | VERIFIED | RecordingView.swift has WaveformView (HStack of RoundedRectangles from bufferEnergy), formattedTime from bufferSeconds, stop button calling coordinator.stopDictation(). |
| 4 | Transcription includes automatic punctuation from Whisper | VERIFIED | DecodingOptions has `task: .transcribe`, `language: "fr"` with no post-processing that strips punctuation. Whisper natively produces punctuation. |
| 5 | After transcription completes, result is written to App Group and keyboard is notified | VERIFIED | DictationCoordinator.stopDictation() writes to SharedKeys.lastTranscription, SharedKeys.lastTranscriptionTimestamp, SharedKeys.dictationStatus, then posts DarwinNotificationName.statusChanged and .transcriptionReady. All writes before notifications (race condition fix). |
| 6 | Filler words are removed from transcription output | VERIFIED | FillerWordFilter.clean() called in TranscriptionService.transcribe() at line 126. Filter handles 8 filler words with lookahead/lookbehind regex preserving French words. |
| 7 | Valid French words containing filler substrings are NOT corrupted | VERIFIED | FillerWordFilter uses `(?<=\s|^)` and `(?=\s|$|[,.!?;:])` instead of `\b` to avoid apostrophe boundary issues. Unit tests cover "humain", "errer", "benevole". |
| 8 | Double spaces and orphaned punctuation cleaned after filler removal | VERIFIED | FillerWordFilter.clean() collapses multiple spaces, removes orphaned punctuation, trims whitespace. |
| 9 | Audio under 5s routes to fast model, over 5s to accurate model | VERIFIED | DictationCoordinator.stopDictation() calls SmartModelRouter.selectModel(audioDuration:downloadedModels:) at line 153. Router uses 5.0s threshold, fastModels=[tiny,base], accurateModels=[small,medium]. |
| 10 | If only one model downloaded, that model is always used | VERIFIED | SmartModelRouter.selectModel() has explicit guard: `if downloadedModels.count == 1 { return downloadedModels[0] }`. |
| 11 | User can see, download, select, and delete Whisper models | VERIFIED | ModelManagerView shows ModelInfo.all with size/accuracy/speed labels, download button, progress bar, select button, delete with confirmation alert. ModelManager handles full lifecycle. |
| 12 | Cannot delete the last remaining model | VERIFIED | ModelManager.deleteModel() guards `downloadedModels.count > 1`, throws cannotDeleteLastModel. UI disables delete for isLastModel. |
| 13 | modelReady flag written to App Group | VERIFIED | ModelManager.persistState() writes `!downloadedModels.isEmpty` to SharedKeys.modelReady. DictationCoordinator.startDictation() checks `defaults.bool(forKey: SharedKeys.modelReady)` before proceeding. |

**Score:** 13/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `DictusApp/Audio/AudioRecorder.swift` | WhisperKit AudioProcessor wrapper with energy levels | VERIFIED | 119 lines, uses whisperKit.audioProcessor.startRecordingLive, publishes bufferEnergy and bufferSeconds |
| `DictusApp/Audio/TranscriptionService.swift` | WhisperKit transcription with French language | VERIFIED | 135 lines, DecodingOptions with language:"fr", imports DictusCore, applies FillerWordFilter.clean() |
| `DictusApp/Views/RecordingView.swift` | Waveform + stop button + elapsed time UI | VERIFIED | 185 lines, WaveformView struct, stop.circle.fill button, formattedTime, transcribing/ready/failed states |
| `DictusApp/DictationCoordinator.swift` | Real recording + transcription pipeline | VERIFIED | 295 lines, no stubs, full pipeline with SmartModelRouter integration and error handling |
| `DictusCore/Sources/DictusCore/FillerWordFilter.swift` | Regex-based filler word removal | VERIFIED | 52 lines, 8 filler words, lookahead/lookbehind regex, cleanup post-processing |
| `DictusCore/Sources/DictusCore/SmartModelRouter.swift` | Duration-based model selection | VERIFIED | 60 lines, 5.0s threshold, fastModels/accurateModels arrays, single-model fallback |
| `DictusCore/Sources/DictusCore/ModelInfo.swift` | Model metadata for WhisperKit variants | VERIFIED | 69 lines, 4 models (large-v3-turbo removed for ANE), Identifiable, forIdentifier lookup |
| `DictusApp/Models/ModelManager.swift` | Download, select, delete, state tracking | VERIFIED | 318 lines, full lifecycle with App Group persistence, serial prewarming, cleanup for failed models |
| `DictusApp/Views/ModelManagerView.swift` | Model list UI with controls | VERIFIED | 245 lines, ModelRow with all 5 states, delete confirmation alert, error alert, swipe + explicit delete |
| `DictusCore/Tests/DictusCoreTests/FillerWordFilterTests.swift` | Unit tests for filler removal | VERIFIED | File exists in test directory |
| `DictusCore/Tests/DictusCoreTests/SmartModelRouterTests.swift` | Unit tests for model routing | VERIFIED | File exists in test directory |
| `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` | Unit tests for model metadata | VERIFIED | File exists in test directory |
| `DictusCore/Sources/DictusCore/SharedKeys.swift` | Extended with model keys | VERIFIED | activeModel, modelReady, downloadedModels keys present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| DictationCoordinator | AudioRecorder | startRecording/stopRecording | WIRED | Line 110: `audioRecorder.startRecording()`, line 136: `audioRecorder.stopRecording()` |
| DictationCoordinator | TranscriptionService | transcribe call | WIRED | Line 171: `transcriptionService.transcribe(audioSamples: samples)` |
| DictationCoordinator | App Group + Darwin | writes + notifications | WIRED | Lines 180-187: writes to SharedKeys, posts Darwin notifications |
| RecordingView | DictationCoordinator | observes status/energy | WIRED | `coordinator.status`, `coordinator.bufferEnergy`, `coordinator.bufferSeconds` |
| DictationCoordinator | SmartModelRouter | selectModel call | WIRED | Line 153: `SmartModelRouter.selectModel(audioDuration:downloadedModels:)` |
| TranscriptionService | FillerWordFilter | clean call | WIRED | Line 126: `FillerWordFilter.clean(trimmed)` |
| ModelManager | SharedKeys (App Group) | persistState | WIRED | Line 296-301: writes downloadedModels, activeModel, modelReady to defaults |
| ContentView | ModelManagerView | NavigationLink | WIRED | Lines 39-41 and 49-53: NavigationLink to ModelManagerView |
| ModelManager | WhisperKit download | download + prewarm | WIRED | Line 119: `WhisperKit.download(variant:from:progressCallback:)`, line 160: `WhisperKit(config)` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-----------|-------------|--------|----------|
| STT-01 | 02-01 | French transcription via on-device WhisperKit | SATISFIED | TranscriptionService with language:"fr", AudioRecorder wrapping WhisperKit AudioProcessor |
| STT-02 | 02-02 | Filler words automatically removed | SATISFIED | FillerWordFilter with 8 filler words, wired into TranscriptionService, 12 unit tests |
| STT-03 | 02-01 | Automatic punctuation from Whisper | SATISFIED | Whisper natively produces punctuation; no stripping in pipeline |
| STT-04 | 02-02 | Smart Model Routing by audio duration | SATISFIED | SmartModelRouter with 5s threshold, wired into DictationCoordinator, 8 unit tests |
| STT-05 | 02-01, 02-03 | Transcription under 3s for 10s audio | NEEDS HUMAN | Performance timing requires physical device measurement |
| APP-02 | 02-03 | Model Manager for download/select/delete | SATISFIED | ModelManager + ModelManagerView with full lifecycle, delete guard, App Group persistence |

No orphaned requirements found -- all 6 requirement IDs (STT-01 through STT-05, APP-02) are claimed by plans and have implementation evidence.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | - | - | - | No anti-patterns detected |

No TODOs, FIXMEs, placeholders, or stub implementations found in any phase 2 files.

### Human Verification Required

### 1. Transcription Performance (STT-05)

**Test:** Record 10 seconds of French speech on physical iPhone 12+, measure time from stop button to transcription result
**Expected:** Transcription completes in under 3 seconds
**Why human:** Performance timing requires physical device with Neural Engine; cannot verify in simulator or statically

### 2. End-to-End Filler Removal

**Test:** Speak "euh bonjour euh comment ca va" into the app
**Expected:** Transcription output contains "bonjour comment ca va" (or similar) without "euh"
**Why human:** Speech recognition accuracy and filler detection in live audio cannot be verified programmatically

### 3. Model Download and Prewarming

**Test:** Download a model from Model Manager, observe progress bar and "Optimisation..." state
**Expected:** Model downloads with visible progress, prewarms successfully, appears as "Active"
**Why human:** Network download and CoreML compilation require real device

### Gaps Summary

No gaps found. All 13 observable truths verified. All 12 artifacts exist, are substantive, and are wired. All 9 key links confirmed. All 6 requirement IDs accounted for with implementation evidence.

The only items requiring human verification are performance timing (STT-05) and end-to-end speech quality, which cannot be verified through static code analysis. The SUMMARY documents indicate these were verified on a physical device during development.

Notable deviation from original plan: ModelInfo.all contains 4 models instead of the planned 5 -- large-v3-turbo was removed due to ANE incompatibility discovered during device testing. This is a valid engineering decision documented in the 02-03-SUMMARY.md.

---

_Verified: 2026-03-06_
_Verifier: Claude (gsd-verifier)_
