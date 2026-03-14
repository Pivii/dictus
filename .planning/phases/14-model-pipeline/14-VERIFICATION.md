---
phase: 14-model-pipeline
verified: 2026-03-12T23:30:00Z
status: human_needed
score: 8/8 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 6/8
  gaps_closed:
    - "Unit tests pass after Large Turbo v3 removal — ModelInfoTests.swift fully updated with correct counts (4 available, 6 total, 5 WhisperKit) and stale large-v3_turbo assertion removed"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "On a device with >=6GB RAM (iPhone 14 Pro+, iPhone 15, iPhone 16), open Dictus onboarding to the model download step"
    expected: "Model card shows 'Parakeet v3', '~800 MB', 'Rapide et precis (NVIDIA)'; on a <=4GB device (iPhone 13 mini, 12 mini) it shows 'Small' / '~250 MB'"
    why_human: "Simulator reports RAM differently from real hardware. ProcessInfo.processInfo.physicalMemory values in iOS Simulator do not match real device tiers."
  - test: "Download a WhisperKit model, force a download error (airplane mode mid-download), then tap Reessayer"
    expected: "Corrupted/partial files are cleaned up, model returns to .notDownloaded state, fresh download is possible"
    why_human: "Requires real network interruption to trigger .error state. Static analysis confirms cleanupFailedModel() is called; end-to-end behavior needs device confirmation."
  - test: "On an iOS 17+ device with >=6GB RAM, download Parakeet v3 and dictate a French sentence"
    expected: "Transcription completes without crashing; DictusLogger shows 'ParakeetEngine: v3 models loaded and ready'"
    why_human: "FluidAudio SDK (AsrModels.downloadAndLoad, AsrManager.transcribe) cannot be exercised statically. Engine routing is verified in code but actual FluidAudio invocation requires device execution."
---

# Phase 14: Model Pipeline Verification Report

**Phase Goal:** CoreML compilation UX, model download modal, device RAM gating, Parakeet fixes
**Verified:** 2026-03-12T23:30:00Z
**Status:** human_needed — all automated checks pass; 3 items require device testing
**Re-verification:** Yes — after gap closure (previous status: gaps_found, score 6/8)

---

## Re-Verification Summary

**Gap from previous verification:** ModelInfoTests.swift contained 5 stale assertions referencing the removed Large Turbo v3 model and incorrect catalog counts.

**Resolution confirmed:** `ModelInfoTests.swift` has been fully updated:
- Line 11: `XCTAssertEqual(ModelInfo.all.count, 4)` — correct (was 5)
- Line 19: `XCTAssertFalse(ids.contains("openai_whisper-large-v3_turbo"))` — correct negative assertion (was a positive assert)
- Line 24: `XCTAssertEqual(ModelInfo.allIncludingDeprecated.count, 6)` — correct (was 7)
- Line 28: `XCTAssertEqual(available.count, 4)` — correct (was 5)
- Line 70: `XCTAssertEqual(whisperKitModels.count, 5, ...)` — correct (was 6)

No regressions found in previously-verified items.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Large Turbo v3 does not appear in model catalog or UI | VERIFIED | `ModelInfo.allIncludingDeprecated` has 6 entries; zero occurrences of `openai_whisper-large-v3_turbo` in any Swift source |
| 2 | Device with >=6GB RAM shows Parakeet v3 as recommended; <=4GB shows Small | VERIFIED | `recommendedIdentifier()` returns `"parakeet-tdt-0.6b-v3"` when `ramGB >= 6`, `"openai_whisper-small"` otherwise (ModelInfo.swift lines 186-196) |
| 3 | During CoreML compilation, user sees spinner with 'Optimisation en cours...' | VERIFIED | ModelCardView.swift line 143 and ModelDownloadPage.swift line 82 both show `"Optimisation en cours..."` with `ProgressView()` in `.prewarming` case |
| 4 | Retry button on failed model cleans up files before re-attempting download | VERIFIED | ModelCardView.swift line 182 calls `modelManager.cleanupFailedModel(model.identifier)`; method deletes files and resets state (ModelManager.swift lines 322-348) |
| 5 | Onboarding recommends Parakeet v3 on >=6GB RAM, Small on <=4GB | VERIFIED | ModelDownloadPage.swift lines 25-27: computed `recommendedModel` property delegates to `ModelInfo.recommendedIdentifier()` |
| 6 | Onboarding model card shows dynamic name, size, description from catalog | VERIFIED | ModelDownloadPage.swift lines 150-174: `modelCard` reads from `ModelInfo.forIdentifier(recommendedModel)` |
| 7 | Parakeet model displays as 'Parakeet v3' everywhere (not 'Whisper Parakeet v3') | VERIFIED | `displayName: "Parakeet v3"` in ModelInfo.swift line 149; zero occurrences of "Whisper Parakeet" in codebase |
| 8 | Unit tests pass after Large Turbo v3 removal | VERIFIED | ModelInfoTests.swift fully updated with correct counts (4/6/5) and negative assertion for large-v3_turbo |

**Score: 8/8 truths verified**

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `DictusCore/Sources/DictusCore/ModelInfo.swift` | Catalog without Large Turbo; `recommendedIdentifier()` and `isRecommended()` | VERIFIED | 6 entries in `allIncludingDeprecated`; both static methods present |
| `DictusApp/Models/ModelManager.swift` | `isRecommended()` delegates to `ModelInfo.isRecommended()` | VERIFIED | Line 317: `ModelInfo.isRecommended(identifier)` |
| `DictusApp/Views/ModelCardView.swift` | Spinner + "Optimisation en cours...", retry calls `cleanupFailedModel()` | VERIFIED | Lines 140-146 (prewarm UI), lines 178-194 (error/retry) |
| `DictusApp/Onboarding/ModelDownloadPage.swift` | Dynamic recommendation via `ModelInfo.recommendedIdentifier` | VERIFIED | Computed property lines 25-27; data-driven card lines 150-174 |
| `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` | All assertions aligned with 4 available / 6 total / 5 WhisperKit catalog | VERIFIED | All 5 previously-stale assertions corrected |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ModelManager.isRecommended()` | `ModelInfo.isRecommended()` | delegation | WIRED | ModelManager.swift line 317 |
| `ModelCardView` retry button | `ModelManager.cleanupFailedModel()` | button action | WIRED | ModelCardView.swift line 182 |
| `ModelDownloadPage.recommendedModel` | `ModelInfo.recommendedIdentifier()` | computed property | WIRED | ModelDownloadPage.swift line 26 |
| `DictationCoordinator.ensureEngineReady()` | `ParakeetEngine` via `transcriptionService.prepare(engine:)` | switch on engine type | WIRED | DictationCoordinator.swift lines 644-649, 740-748 |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MODEL-01 | 14-01 | Large Turbo v3 removed or gated | SATISFIED | Completely removed from `allIncludingDeprecated`; no references in source |
| MODEL-02 | 14-01 | CoreML pre-compilation with visible progress | SATISFIED | `ProgressView()` + "Optimisation en cours..." in `.prewarming` case in ModelCardView and ModelDownloadPage |
| MODEL-03 | 14-02 | Onboarding step reorder | REMOVED SCOPE | Plan documents: "removed by user decision — no implementation tasks" |
| MODEL-04 | 14-02 | Full-screen modal during download | REMOVED SCOPE | Plan documents: "removed by user decision — no implementation tasks" |
| MODEL-05 | 14-01 | Retry-with-cleanup on prewarming failure | SATISFIED | `cleanupFailedModel()` called from retry button; deletes files and resets state |
| MODEL-06 | 14-02 | Mic button disabled while compiling | REMOVED SCOPE | Plan documents: "removed by user decision — no implementation tasks" |
| MODEL-07 | 14-02 | Parakeet engine routing verified correct | SATISFIED | `ensureParakeetReady()` creates `ParakeetEngine`, calls `transcriptionService.prepare(engine:)` |
| MODEL-08 | 14-02 | Parakeet displays as "Parakeet v3" | SATISFIED | `displayName: "Parakeet v3"` in catalog; no "Whisper Parakeet" string in any target |

MODEL-03, MODEL-04, and MODEL-06 were explicitly removed from scope by user decision and documented as such in 14-02-PLAN.md. Their REQUIREMENTS.md checkboxes reflect "resolved by decision," not "implemented."

---

## Anti-Patterns Found

None. The previous blocker (stale test assertions in ModelInfoTests.swift) has been resolved.

---

## Human Verification Required

### 1. RAM-based recommendation on real device

**Test:** On a device with >=6GB RAM (iPhone 14 Pro+, iPhone 15, iPhone 16), go through onboarding to the model download step.
**Expected:** Model card shows "Parakeet v3" as the recommended model with "~800 MB" and the Parakeet description. On a <=4GB device (iPhone 13 mini, 12 mini), model card shows "Small" / "~250 MB".
**Why human:** Simulator reports RAM differently from real hardware. `ProcessInfo.processInfo.physicalMemory` values in iOS Simulator do not match real device tiers, so the RAM branch cannot be exercised in simulation.

### 2. Retry-with-cleanup on failed download

**Test:** Start downloading a WhisperKit model, enable airplane mode mid-download to force failure. When the error state appears, tap "Reessayer".
**Expected:** Retry button cleans up partial/corrupted files, model returns to `.notDownloaded` state, download arrow reappears, and a fresh attempt succeeds.
**Why human:** Requires real network interruption to trigger the `.error` state. Static analysis confirms `cleanupFailedModel()` is called, but end-to-end behavior on device needs confirmation.

### 3. Parakeet transcription on device

**Test:** On an iOS 17+ device with >=6GB RAM, download Parakeet v3 and dictate a French sentence.
**Expected:** Text is transcribed in French without crashing. DictusLogger output confirms "ParakeetEngine: v3 models loaded and ready" and "Initializing ParakeetEngine for model: parakeet-tdt-0.6b-v3".
**Why human:** FluidAudio SDK (`AsrModels.downloadAndLoad`, `AsrManager.transcribe`) cannot be exercised statically. Engine routing is verified in source but actual FluidAudio invocation requires device execution.

---

_Verified: 2026-03-12T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
