---
status: resolved
phase: 10-model-catalog
source: 10-01-SUMMARY.md, 10-02-SUMMARY.md, 10-03-SUMMARY.md
started: 2026-03-11T10:00:00Z
updated: 2026-03-11T12:00:00Z
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
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "After downloading a WhisperKit model, transcription uses the configured language (French) immediately"
  status: resolved
  reason: "User reported: After first download, transcription outputs English instead of French. Must toggle language in settings, restart app, then it works. Also ANE compilation/pre-warming is very slow on first use."
  severity: major
  test: 6
  root_cause: "Two issues: (1) Language preference never written to UserDefaults on fresh install — @AppStorage default 'fr' is in-memory only, never persisted, so scattered ?? 'fr' fallbacks are fragile. (2) distil-whisper_distil-large-v3_turbo is English-only (logitsDim=51864 triggers isModelMultilingual=false in WhisperKit, silently ignoring language parameter)."
  artifacts:
    - path: "DictusApp/Views/SettingsView.swift"
      issue: "@AppStorage default 'fr' never written to UserDefaults — only written when user interacts with Picker"
    - path: "DictusCore/Sources/DictusCore/ModelInfo.swift"
      issue: "distil-large-v3_turbo listed as available without English-only warning"
    - path: "DictusApp/Audio/TranscriptionService.swift"
      issue: "Language read with ?? 'fr' fallback but key may not exist in UserDefaults"
  missing:
    - "Persist language default ('fr') in UserDefaults during app init or onboarding"
    - "Mark distil-large-v3_turbo as English-only or remove from French catalog"
    - "Add diagnostic logging for language value passed to WhisperKit"
  debug_session: ".planning/debug/language-default-english.md"

- truth: "Large Turbo model can be downloaded from WhisperKit repo"
  status: resolved
  reason: "User reported: Download fails with error 'No models found matching *openai*openai_whisper-large-v3-turbo/*'. Also distil-large-v3_turbo is English-only and must be removed from catalog."
  severity: blocker
  test: 6
  root_cause: "Two issues: (1) Wrong identifier — catalog has 'openai_whisper-large-v3-turbo' (hyphen) but WhisperKit repo uses 'openai_whisper-large-v3_turbo' (underscore). (2) distil-whisper_distil-large-v3_turbo is English-only (confirmed on HuggingFace) — must be removed from catalog since app targets French."
  artifacts:
    - path: "DictusCore/Sources/DictusCore/ModelInfo.swift"
      issue: "Line 159: identifier 'openai_whisper-large-v3-turbo' has hyphen instead of underscore"
    - path: "DictusCore/Sources/DictusCore/ModelInfo.swift"
      issue: "Lines 148-157: distil-large-v3_turbo is English-only, should not be in multilingual catalog"
  missing:
    - "Fix identifier to 'openai_whisper-large-v3_turbo'"
    - "Remove distil-whisper_distil-large-v3_turbo from catalog entirely"
    - "Update ModelInfoTests for 7→6 model count"
  debug_session: ""

## UX Improvement Notes (from passing tests)

- **Active model highlight:** Blue border around active model card (liquid glass style) instead of subtle "Actif" badge
- **Missing French accents:** Fix all text across the app (Modeles→Modèles, Telecharges→Téléchargés, Precis→Précis, developpe→développé, equilibre→équilibré, etc.)
- **Download button placement:** Move to top-right, aligned with model name
- **Card layout balance:** Better alignment of badges, gauges, descriptions within cards
- **Tap to select:** Tap anywhere on downloaded card to select (remove "Choisir" button)
- **Engine descriptions:** Move to bottom of page once, not duplicated in each section
- **Download/optimization animation:** Improve progress UX (future iteration)
