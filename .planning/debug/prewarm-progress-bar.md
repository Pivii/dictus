---
status: diagnosed
trigger: "Progress bar stuck at zero during model prewarm (optimization after download)"
created: 2026-03-12T00:00:00Z
updated: 2026-03-12T00:00:00Z
---

## Current Focus

hypothesis: The bug is NOT in ModelCardView's prewarm case -- it correctly shows only a spinner + text. The real issue is a timing gap: downloadProgress is removed AFTER download completes but BEFORE the state transitions from .downloading to .prewarming, causing a brief stuck-at-zero progress bar.
test: Code trace through downloadWhisperKitModel flow
expecting: Confirm ordering of state transitions vs downloadProgress cleanup
next_action: Return diagnosis

## Symptoms

expected: During prewarm, user should see only a spinner and "Optimisation en cours..." text (no progress bar)
actual: A progress bar appears stuck at zero during the prewarm phase
errors: None (visual-only bug)
reproduction: Download any WhisperKit model, observe the UI after download completes and prewarm begins
started: Since ModelCardView was implemented

## Eliminated

- hypothesis: ModelCardView .prewarming case renders a progress bar
  evidence: Code at lines 140-146 shows only `ProgressView()` (indeterminate spinner) + text label. No `ProgressView(value:total:)` determinate bar.
  timestamp: 2026-03-12

- hypothesis: ModelManagerView or parent view adds an extra progress bar
  evidence: Grep for ProgressView across all Views/ files shows only two instances, both in ModelCardView (line 131 for .downloading, line 142 for .prewarming). No external progress bar overlay.
  timestamp: 2026-03-12

## Evidence

- timestamp: 2026-03-12
  checked: ModelCardView.swift trailingContent switch
  found: |
    .downloading case (lines 129-138): Shows `ProgressView(value: downloadProgress[id] ?? 0, total: 1.0)` -- a DETERMINATE progress bar with percentage text.
    .prewarming case (lines 140-146): Shows `ProgressView()` -- an INDETERMINATE spinner with "Optimisation en cours..." text. No progress bar.
  implication: The .prewarming case itself is correct. The bug must be a state transition timing issue.

- timestamp: 2026-03-12
  checked: ModelManager.downloadWhisperKitModel() flow (lines 124-204)
  found: |
    After WhisperKit.download() completes:
    1. Line 155: `downloadProgress.removeValue(forKey: identifier)` -- removes progress data
    2. Lines 158-161: While loop waiting for prewarm lock, setting state to `.prewarming`
    3. Line 163: `modelStates[identifier] = .prewarming`

    CRITICAL: Between line 155 (progress removed) and line 163 (state set to prewarming),
    the state is STILL `.downloading` (set at line 132). With downloadProgress removed (or
    set to 0 before removal), the `.downloading` case in the view renders a progress bar
    with value 0.

    More specifically: the `downloadProgress` callback at line 143-146 runs in a
    `Task { @MainActor in ... }` which means progress updates are dispatched asynchronously.
    The download can complete with progress never reaching exactly 1.0 in the UI.

    Then at line 155, progress is removed. The `?? 0` fallback on line 131 kicks in,
    showing a progress bar at 0%. The state is still `.downloading` because line 163
    hasn't executed yet (or the while-loop at 158 is waiting).
  implication: There is a window where state=.downloading but progress=0 (removed), showing a stuck-at-zero bar.

- timestamp: 2026-03-12
  checked: Parakeet download path (lines 217-258)
  found: |
    Line 218: Sets state to `.downloading`
    Line 219: Sets downloadProgress to 0.0
    Line 229: Sets state to `.prewarming` BEFORE any actual download progress updates
    Line 236: Removes downloadProgress AFTER prewarm completes

    For Parakeet, progress stays at 0 the entire time because FluidAudio has no progress
    callback. The state transitions to .prewarming relatively quickly, but there's still
    a window showing a zero progress bar.
  implication: Both WhisperKit and Parakeet paths have this timing gap.

## Resolution

root_cause: |
  State transition ordering bug in ModelManager.downloadWhisperKitModel():

  After download completes, `downloadProgress` is removed (line 155) but `modelStates`
  stays as `.downloading` until line 163 (after the prewarm-lock while-loop). During
  this gap, ModelCardView's `.downloading` case renders a determinate progress bar that
  reads `downloadProgress[id] ?? 0` = 0, showing a bar stuck at zero.

  If another model is already prewarming (isPrewarming == true), the while-loop at
  lines 158-161 can keep the state as `.downloading` for many seconds (polling every
  500ms), making the stuck-at-zero bar clearly visible.

  The Parakeet path has a similar but shorter gap (lines 218-229).

fix: |
  Two options (from simplest to most robust):

  **Option A (recommended -- minimal change):**
  In downloadWhisperKitModel(), move the `.prewarming` state transition to BEFORE
  removing downloadProgress, or at least immediately after:

  ```swift
  // Line 155-163 should become:
  modelStates[identifier] = .prewarming   // transition FIRST
  downloadProgress.removeValue(forKey: identifier)  // then clean up progress

  while isPrewarming {
      try await Task.sleep(nanoseconds: 500_000_000)
  }
  ```

  This ensures the view never sees state=.downloading with progress=nil/0.

  **Option B (belt-and-suspenders):**
  Additionally, in ModelCardView's `.downloading` case, only show the progress bar
  if downloadProgress actually contains a value for this model:

  ```swift
  case .downloading:
      if let progress = modelManager.downloadProgress[model.identifier] {
          VStack(spacing: 2) {
              ProgressView(value: progress, total: 1.0)
                  .frame(width: 60)
                  .tint(.dictusAccent)
              Text("\(Int(progress * 100))%")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
          }
      } else {
          // Progress removed but state not yet transitioned -- show spinner
          ProgressView()
      }
  ```

verification: Not yet verified (diagnosis only)
files_changed: []
