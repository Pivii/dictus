# Phase 14: Model Pipeline - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Model download, CoreML compilation, and engine selection work reliably with clear progress feedback. Large Turbo v3 removed from catalog, Parakeet v3 becomes the recommended default model (RAM-gated), progress bar bug fixed for compilation phase, and all Parakeet display/routing issues verified.

</domain>

<decisions>
## Implementation Decisions

### Large Turbo v3 — hard removal
- **Remove entirely** from `ModelInfo.allIncludingDeprecated` (not just deprecated)
- No users in beta yet — no backward compatibility concern
- Rationale: too large (~954 MB), slow to download, Parakeet v3 is superior in speed and accuracy
- Delete the `openai_whisper-large-v3_turbo` entry from the catalog array

### Smart default model based on device RAM
- `ProcessInfo.processInfo.physicalMemory` to detect RAM at runtime
- **≥6 GB RAM** → Parakeet v3 recommended (iPhone 12 Pro, 13 Pro, 14+, 15+, 16+)
- **≤4 GB RAM** → Small recommended (iPhone 12, 12 mini, 13, 13 mini)
- `isRecommended()` becomes dynamic instead of hardcoded "openai_whisper-small"
- Onboarding ModelDownloadPage should pre-highlight the recommended model
- Model manager should show "Recommandé" badge on the RAM-appropriate model

### Progress bar bug fix — compilation shows 0%
- **Root cause:** FluidAudio's `AsrModels.downloadAndLoad()` does not expose a progress callback
- For Parakeet: replace determinate progress bar (stuck at 0%) with **indeterminate ProgressView** (spinner) during the compilation/optimization phase
- For WhisperKit: download has progress callback (works), but prewarm also has no progress — same fix needed (indeterminate spinner during "Optimisation...")
- Label should say "Optimisation en cours..." with spinner, not "0%"

### Parakeet routing (MODEL-07) — verify only
- User (Pierre) reports Parakeet v3 works daily for transcription
- Code inspection shows `DictationCoordinator.ensureParakeetReady()` correctly creates `ParakeetEngine` and sets it via `transcriptionService.prepare(engine:)`
- **Action:** Verify in code that engine routing is correct. No rewrite expected unless bug found.

### Parakeet display name (MODEL-08) — verify only
- `ModelInfo` catalog already shows `displayName: "Parakeet v3"` (not "Whisper Parakeet v3")
- **Action:** Verify no other UI location displays incorrect name. Quick grep + fix if needed.

### Retry with cleanup (MODEL-05) — verify existing
- `ModelManager.cleanupFailedModel()` already exists: removes files + resets state to `.notDownloaded`
- `cleanupModelFiles()` cleans both App Group container and WhisperKit download location
- **Action:** Verify this works for Parakeet models too (FluidAudio cache path may differ)

### Scope removed (decided during discussion)
- ~~MODEL-03: Onboarding step reorder~~ — **Removed.** Current onboarding flow (Welcome → Mic → Keyboard → Mode → Model → Test) works well. No reordering needed.
- ~~MODEL-04: Full-screen modal during download~~ — **Removed.** Current inline download UX is sufficient. Modal was over-engineering for the actual risk.
- ~~MODEL-06: Mic disabled during compilation~~ — **Removed.** Without a blocking modal, this edge case is too rare to justify the complexity. If compilation is fast (as observed), user won't have time to switch to keyboard.

### FluidAudio cache behavior (discovered during discussion)
- FluidAudio caches downloaded models persistently — survives app deletion and device restart
- This means re-downloads of Parakeet are near-instant (only compilation, no download)
- Not a bug — beneficial for UX. No action needed, just awareness for testing.

</decisions>

<code_context>
## Existing Code Insights

### Files to modify
- `DictusCore/Sources/DictusCore/ModelInfo.swift` — Remove Large Turbo entry, update `isRecommended` logic (or move it)
- `DictusApp/Models/ModelManager.swift` — Dynamic `isRecommended()` using `ProcessInfo.physicalMemory`, fix progress bar for prewarm phase
- `DictusApp/Views/ModelCardView.swift` — Handle indeterminate progress for prewarm state
- `DictusApp/Onboarding/OnboardingView.swift` — Pre-select recommended model (if not already)

### Files to verify (no changes expected)
- `DictusApp/DictationCoordinator.swift` — Parakeet routing (ensureParakeetReady)
- `DictusApp/Audio/TranscriptionService.swift` — activeEngine routing
- `DictusApp/Audio/ParakeetEngine.swift` — Parakeet transcription
- `DictusCore/Sources/DictusCore/SpeechEngine.swift` — Engine enum

### Patterns to follow
- `CatalogVisibility` enum for model visibility control
- `ModelState` enum for lifecycle states (downloading/prewarming/ready/error)
- `@MainActor` on ModelManager for thread safety
- `PersistentLog.log()` for all state transitions
- RAM detection: `ProcessInfo.processInfo.physicalMemory` returns bytes (UInt64), divide by 1_073_741_824 for GB

</code_context>

<specifics>
## Specific Ideas

- The progress bar bug is the most visible fix — users see "0%" during optimization which looks broken
- isRecommended() should be a computed property on ModelInfo (static func) rather than on ModelManager, since it's catalog-level logic
- Consider adding a "Recommandé pour votre iPhone" label instead of just "Recommandé" to make the RAM-gating feel personalized

</specifics>

<deferred>
## Deferred Ideas

- **Background downloads with URLSession delegate** — mentioned by Pierre as a concern (iOS killing app during download), but current foreground approach works. Defer to MODEL-F02.
- **Smart queue for ANE** — compilation waits for transcription to finish. Already tracked as MODEL-F01.
- **Full-screen download modal** — discussed and rejected for v1.2, but could reconsider if beta testers report download failures from app being killed. Track as future enhancement.

</deferred>

---

*Phase: 14-model-pipeline*
*Context gathered: 2026-03-12*
