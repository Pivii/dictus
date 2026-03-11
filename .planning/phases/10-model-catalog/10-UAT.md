---
status: complete
phase: 10-model-catalog
source: 10-01-SUMMARY.md, 10-02-SUMMARY.md, 10-03-SUMMARY.md
started: 2026-03-11T10:00:00Z
updated: 2026-03-11T10:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Model Catalog Available Section
expected: Open the app > go to Model Manager. You should see an "Disponibles" section listing available models. Each model appears as a card with gauge bars (blue for accuracy, green for speed), a size label, a French description, and a download button.
result: pass

### 2. Engine Badge on Model Cards
expected: Each model card shows an engine badge pill — "WK" for WhisperKit models and "PK" for the Parakeet model.
result: pass

### 3. Downloaded Section
expected: If you have models already downloaded, they appear in a separate "Telecharges" section at the top. The active model is indicated. You can select a different downloaded model or delete one.
result: pass

### 4. Deprecated Models Hidden from Available
expected: Tiny and Base models do NOT appear in the "Disponibles" section. If you had them downloaded before, they still show in "Telecharges".
result: pass

### 5. Parakeet v3 in Catalog
expected: Parakeet v3 appears in the "Disponibles" section with a "PK" engine badge, its own accuracy/speed gauges, and a French description.
result: pass

### 6. Download a WhisperKit Model
expected: Tap download on a WhisperKit model (e.g., small or large-v3-turbo). A progress indicator appears. Once complete, the model moves to the "Telecharges" section and can be selected.
result: issue
reported: "Apres premier telechargement d'un modele WhisperKit, la transcription sort en anglais au lieu du francais. Il faut aller dans les reglages, basculer anglais puis francais, ca bugue, fermer l'app, et apres reouverture ca fonctionne en francais. Aussi le pre-warming est tres long (compilation ANE)."
severity: major

### 7. Download Parakeet Model
expected: Tap download on Parakeet v3. A progress indicator appears. Once complete, Parakeet moves to "Telecharges" and can be selected as the active model.
result: pass

### 8. Multi-Engine Transcription
expected: With a WhisperKit model active, record and transcribe — works normally. Switch to Parakeet as active model. Record and transcribe — transcription uses Parakeet engine. Both produce French text output.
result: pass

## Summary

total: 8
passed: 7
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "After downloading a WhisperKit model, transcription uses the configured language (French) immediately"
  status: failed
  reason: "User reported: After first download, transcription outputs English instead of French. Must toggle language in settings, restart app, then it works. Also ANE compilation/pre-warming is very slow on first use."
  severity: major
  test: 6
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

## UX Improvement Notes (from passing tests)

- **Active model highlight:** Blue border around active model card (liquid glass style) instead of subtle "Actif" badge
- **Missing French accents:** Fix all text across the app (Modeles→Modèles, Telecharges→Téléchargés, Precis→Précis, developpe→développé, equilibre→équilibré, etc.)
- **Download button placement:** Move to top-right, aligned with model name
- **Card layout balance:** Better alignment of badges, gauges, descriptions within cards
- **Tap to select:** Tap anywhere on downloaded card to select (remove "Choisir" button)
- **Engine descriptions:** Move to bottom of page once, not duplicated in each section
- **Download/optimization animation:** Improve progress UX (future iteration)
