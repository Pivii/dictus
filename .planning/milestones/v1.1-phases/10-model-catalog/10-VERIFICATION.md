---
phase: 10-model-catalog
verified: 2026-03-11T10:30:00Z
status: passed
score: 7/7 must-haves verified
re_verification:
  previous_status: passed
  previous_score: 7/7
  uat_gaps_found: 2
  uat_gaps_closed:
    - "Large Turbo identifier uses underscore matching WhisperKit repo (was hyphen)"
    - "distil-whisper_distil-large-v3_turbo removed from catalog (English-only)"
    - "Language default 'fr' persisted in App Group UserDefaults at app init"
    - "French accents corrected in all ModelManagerView UI text"
  gaps_remaining: []
  regressions: []
---

# Phase 10: Model Catalog Verification Report

**Phase Goal:** Users see only performant models in the catalog and can choose between WhisperKit and Parakeet engines for transcription
**Verified:** 2026-03-11T10:30:00Z
**Status:** passed
**Re-verification:** Yes -- after UAT gap closure (plan 10-04)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Underperforming models removed from catalog | VERIFIED | `ModelInfo.all` filters by `.available`; Tiny/Base are `.deprecated`. distil-whisper removed entirely (English-only). Catalog now has 7 models total, 5 available. |
| 2 | Already-downloaded Tiny/Base models still function | VERIFIED | `ModelManager` loops `allIncludingDeprecated` for state init. `ModelManagerView` downloaded section uses `allIncludingDeprecated.filter`. `forIdentifier` searches `allIncludingDeprecated`. |
| 3 | Parakeet v3 available as alternative STT engine | VERIFIED | `ParakeetEngine.swift` (105 lines) wraps FluidAudio. `DictationCoordinator` routes `.parakeet` engine. `ModelInfo.all` includes Parakeet on iOS 17+. |
| 4 | Model selection UI displays both engines with metadata | VERIFIED | `ModelCardView` (220 lines) shows engine badge, gauge bars, description. `ModelManagerView` (183 lines) has Downloaded/Available sections with correct French accents throughout. |
| 5 | SmartModelRouter removed from codebase | VERIFIED | `grep -r "SmartModelRouter" --include="*.swift"` returns zero results. |
| 6 | TranscriptionService routes to correct engine | VERIFIED | `TranscriptionService.transcribe()` checks `activeEngine` first, falls back to WhisperKit. Logs language value via DictusLogger before transcription. |
| 7 | Unit tests consistent with final catalog state | VERIFIED | `ModelInfoTests.swift` (93 lines, 10 tests) asserts: count==5 available, count==7 total, 2 deprecated, 6 WhisperKit + 1 Parakeet. All identifiers checked including `openai_whisper-large-v3_turbo` (underscore). No reference to removed distil model. |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `DictusCore/Sources/DictusCore/ModelInfo.swift` | Corrected 7-model catalog | VERIFIED | 181 lines. distil removed, turbo uses underscore identifier, 5 available + 2 deprecated |
| `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` | Tests for 7-model catalog | VERIFIED | 93 lines, 10 tests, assertions match 7-model catalog exactly |
| `DictusApp/DictusApp.swift` | Language default persistence | VERIFIED | 77 lines. Lines 32-35 persist "fr" via SharedKeys.language with nil-check guard |
| `DictusApp/Audio/TranscriptionService.swift` | Diagnostic logging + engine routing | VERIFIED | 155 lines. Line 106 logs language value. activeEngine protocol dispatch at line 109-110 |
| `DictusApp/Audio/SpeechModelProtocol.swift` | Protocol + WhisperKitEngine | VERIFIED | 113 lines, unchanged from previous verification |
| `DictusApp/Audio/ParakeetEngine.swift` | FluidAudio Parakeet STT | VERIFIED | 105 lines, unchanged from previous verification |
| `DictusApp/Views/GaugeBarView.swift` | 5-segment gauge bar | VERIFIED | 54 lines, unchanged |
| `DictusApp/Views/ModelCardView.swift` | Model card with badges and gauges | VERIFIED | 220 lines, unchanged |
| `DictusApp/Views/ModelManagerView.swift` | Sections + engine descriptions + correct accents | VERIFIED | 183 lines. All French text uses correct accents: Telecharges->Telecharges, Modeles->Modeles, developpe->developpe, optimise->optimise, entraines->entraines |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| DictusApp.init() | App Group UserDefaults | SharedKeys.language persistence | WIRED | Lines 32-35: nil-check then set "fr" |
| TranscriptionService | DictusLogger | Language diagnostic log | WIRED | Line 106: logs language before transcription |
| ModelCardView | ModelInfo | model.accuracyScore, speedScore, engine | WIRED | Unchanged, no regression |
| ModelManagerView | ModelInfo.all / allIncludingDeprecated | Filter into sections | WIRED | Unchanged, no regression |
| DictationCoordinator | SpeechModelProtocol | Engine routing by SpeechEngine | WIRED | Unchanged, no regression |
| TranscriptionService | SpeechModelProtocol | activeEngine dispatch | WIRED | Unchanged, no regression |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MOD-01 | 10-01, 10-04 | Model catalog cleaned -- remove underperforming models | SATISFIED | Tiny/Base deprecated, distil removed entirely (English-only), turbo identifier corrected |
| MOD-02 | 10-03 | Parakeet v3 integrated as alternative STT option | SATISFIED | ParakeetEngine, SpeechModelProtocol, FluidAudio SPM, multi-engine routing |
| MOD-03 | 10-02, 10-04 | Model selection UI updated for both engines | SATISFIED | GaugeBarView, ModelCardView with badges, ModelManagerView with correct French accents |

No orphaned requirements found.

### Anti-Patterns Found

No anti-patterns found. No TODO/FIXME/placeholder comments in any modified files.

### Human Verification Required

### 1. Fresh install transcription language

**Test:** Delete app data, reinstall, download a WhisperKit model, record French speech immediately
**Expected:** Transcription outputs French text on first use (no settings toggle needed)
**Why human:** Verifies the language default persistence fix works end-to-end on device

### 2. Large Turbo model download

**Test:** Tap download on "Large Turbo" model in the catalog
**Expected:** Model downloads successfully from WhisperKit repo (no "No models found" error)
**Why human:** Network download from argmaxinc/whisperkit-coreml repo requires real device

### 3. Visual inspection of corrected French accents

**Test:** Navigate to Settings > Modeles
**Expected:** Title shows "Modeles" (with accent), section shows "Telecharges" (with accents), engine descriptions show "developpe", "optimise", "entraines" (all with accents)
**Why human:** Visual rendering of UTF-8 accented characters on device

## UAT Gap Closure Summary

Plan 10-04 closed both UAT-identified gaps plus two related improvements:

1. **Wrong turbo identifier (blocker):** `openai_whisper-large-v3-turbo` (hyphen) changed to `openai_whisper-large-v3_turbo` (underscore) in ModelInfo.swift line 148. Verified: no hyphen variant exists anywhere in the file.

2. **English-only distil model (major):** `distil-whisper_distil-large-v3_turbo` completely removed from `allIncludingDeprecated` array. Catalog reduced from 8 to 7 models. Verified: zero occurrences of "distil" in ModelInfo.swift.

3. **Language default persistence (major):** `DictusApp.init()` now writes "fr" to App Group UserDefaults via SharedKeys.language on first launch (nil-check guard preserves user overrides). TranscriptionService logs the language value for diagnostics.

4. **French accent corrections:** All UI strings in ModelManagerView now use proper French accents. Verified: grep for unaccented variants returns zero matches.

All 10 test assertions in ModelInfoTests updated to match the corrected 7-model catalog (5 available, 2 deprecated, 6 WK + 1 PK).

No regressions detected -- all 7 previously-verified truths remain verified. All non-modified artifacts retain their line counts and structure.

---

_Verified: 2026-03-11T10:30:00Z_
_Verifier: Claude (gsd-verifier)_
