---
phase: 14-model-pipeline
plan: 04
status: complete
gap_closure: true
commits: [c94bd85, f4aa855]
---

## Summary

Fixed the prewarm progress bar stuck at 0% (UAT test 3) and discovered/fixed two additional issues during human verification: Parakeet model deletion not cleaning FluidAudio cache, and Parakeet download progress bar jumping erratically.

## What was built

### Progress bar fix (both engines)
- **ModelManager.swift**: State transitions to `.prewarming` BEFORE `downloadProgress` is removed — eliminates timing gap where state=.downloading with progress=nil
- **ModelCardView.swift**: `.downloading` case uses `if let progress` instead of `?? 0` — nil progress shows spinner, not a bar at 0%
- **ModelDownloadPage.swift**: Same `if let` fix applied to onboarding download screen

### Parakeet model deletion fix
- `deleteModel()` and `cleanupModelFiles()` now clean FluidAudio's cache at `Application Support/FluidAudio/Models/` for all `AsrModelVersion` variants
- Deletion is engine-aware: detects Parakeet models via `ModelInfo.engine` and cleans the right paths

### Parakeet download progress fix
- Replaced `AsrModels.download()` (4 sequential per-model calls, each resetting progress) with `DownloadUtils.downloadRepo()` (single call, byte-weighted aggregate progress)
- Download and compilation now properly separated: download with progress bar → prewarm with spinner

### Model lifecycle logging
- Added 4 new `PersistentLog` events: `modelDeleted`, `modelDeleteFailed`, `modelPrewarmStarted`, `modelCleanupPerformed`
- Privacy-safe: only logs model identifiers and engine names, no user data

## Key files

### Modified
- `DictusApp/Models/ModelManager.swift` — state transition ordering, Parakeet deletion, download progress, logging
- `DictusApp/Views/ModelCardView.swift` — defensive nil-check on download progress
- `DictusApp/Onboarding/ModelDownloadPage.swift` — same nil-check fix
- `DictusCore/Sources/DictusCore/LogEvent.swift` — 4 new model lifecycle events

## Deviations

- **Scope expanded beyond original plan**: Plan only covered ModelManager state ordering + ModelCardView defensive check. Human verification revealed the same bug in onboarding, plus Parakeet deletion not working (FluidAudio cache not cleaned), plus broken download progress reporting. All fixed.
- **No Parakeet path change was planned**: Original plan stated "No changes needed for Parakeet path" but the Parakeet path had the same (worse) timing gap.

## Self-Check: PASSED
- [x] Prewarm shows spinner only, no bar at 0% (Model Manager)
- [x] Prewarm shows spinner only, no bar at 0% (Onboarding)
- [x] Parakeet deletion cleans FluidAudio cache — re-download takes 13-14s
- [x] Download progress bar works for Parakeet (minor cosmetic jump due to FluidAudio reporting)
- [x] WhisperKit models unaffected — download/delete cycle works as before
- [x] Build succeeds
