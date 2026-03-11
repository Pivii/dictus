---
status: investigating
trigger: "After first model download, transcription outputs English instead of French. Toggle language in Settings crashes, restart fixes."
created: 2026-03-11T00:00:00Z
updated: 2026-03-11T00:00:00Z
---

## Current Focus

hypothesis: Multiple contributing factors — language key never persisted at install, distil-whisper model is English-only, and no crash protection when toggling language mid-session
test: Exhaustive code path tracing + WhisperKit source analysis
expecting: Identify all contributing root causes
next_action: Present findings to user for verification

## Symptoms

expected: After first model download, transcription should output French
actual: Transcription outputs English. User must toggle language in Settings (which crashes), restart app, then French works.
errors: Crash/freeze when toggling language in Settings
reproduction: Fresh install -> onboarding -> download model -> first transcription -> English output
started: Since initial implementation

## Eliminated

- hypothesis: "TranscriptionService doesn't pass language to WhisperKit"
  evidence: TranscriptionService.swift line 105 reads language with `?? "fr"` fallback, passes to activeEngine.transcribe() at line 109. WhisperKitEngine.transcribe() creates DecodingOptions with explicit language parameter at line 92.
  timestamp: 2026-03-11

- hypothesis: "activeEngine is not set on first use"
  evidence: DictationCoordinator.ensureWhisperKitEngineReady() lines 593-596 create WhisperKitEngine and set it as activeEngine. Both cold start and warm start paths call ensureEngineReady() before transcription.
  timestamp: 2026-03-11

- hypothesis: "App Group defaults returns nil"
  evidence: AppGroup.swift uses guard + fatalError for defaults property. TranscriptionService.swift creates its own Optional instance via UserDefaults(suiteName:) which could theoretically be nil, but uses the same App Group identifier that works elsewhere.
  timestamp: 2026-03-11

- hypothesis: "WhisperKit ignores language parameter when usePrefillPrompt is true"
  evidence: WhisperKit TextDecoder.swift line 314-325 shows that when usePrefillPrompt is true AND model is multilingual, it explicitly constructs language token from options.language, appends to prefillTokens, and forces them during decoding. Language IS honored.
  timestamp: 2026-03-11

## Evidence

- timestamp: 2026-03-11
  checked: All writes to SharedKeys.language across entire codebase
  found: ZERO explicit writes. Only @AppStorage in SettingsView (line 20-21) which only writes when user interacts with the Picker.
  implication: On fresh install, key "dictus.language" does not exist in App Group UserDefaults. Code relies on `?? "fr"` fallback.

- timestamp: 2026-03-11
  checked: TranscriptionService.transcribe() line 104-105
  found: Creates new UserDefaults(suiteName: AppGroup.identifier) — returns Optional. Uses `defaults?.string(forKey:) ?? "fr"`.
  implication: If UserDefaults init succeeds (it should), fallback "fr" only applies when key is missing. Either way, language should be "fr".

- timestamp: 2026-03-11
  checked: WhisperKit DecodingOptions init (Configurations.swift line 189)
  found: language parameter is `String?` with default nil. When Dictus passes "fr", it's non-nil String.
  implication: WhisperKit receives explicit language, should use it.

- timestamp: 2026-03-11
  checked: WhisperKit TextDecoder.prefillDecoderInputs() lines 316-324
  found: Default languageToken is englishToken. For multilingual models, it constructs `"<|fr|>"` from options.language, looks up token ID. Fallback if lookup fails: englishToken.
  implication: If tokenizer.convertTokenToId("<|fr|>") returns nil (tokenizer issue), falls back to English silently.

- timestamp: 2026-03-11
  checked: WhisperKit Constants.defaultLanguageCode (Models.swift line 1539)
  found: `public static let defaultLanguageCode: String = "en"`
  implication: Every fallback in WhisperKit defaults to English.

- timestamp: 2026-03-11
  checked: distil-whisper model documentation
  found: distil-whisper/distil-large-v3 is ENGLISH-ONLY. "The checkpoints on the distil-whisper organisation currently only support English."
  implication: If user downloads distil-whisper_distil-large-v3_turbo model, it will ALWAYS produce English regardless of language parameter.

- timestamp: 2026-03-11
  checked: WhisperKit model multilingual detection (ModelUtilities.swift line 133-134)
  found: `isModelMultilingual = logitsDim != 51864`. English-only models have logitsDim=51864.
  implication: For English-only distil model, isModelMultilingual=false, language tokens are NOT added to prefill. Model outputs English regardless.

- timestamp: 2026-03-11
  checked: SettingsView language toggle behavior
  found: No onChange handler for language. @AppStorage writes to UserDefaults immediately on Picker change. No reinitialization of WhisperKit or audio pipeline.
  implication: Language change is safe (read at next transcription time). Crash/freeze is likely unrelated to language toggle itself.

## Resolution

root_cause: THREE CONTRIBUTING ISSUES

**Issue 1 (High Confidence): Language key never explicitly initialized**
File: No initialization code exists anywhere
- SharedKeys.language is NEVER written to App Group defaults during onboarding, first launch, or anywhere outside the SettingsView Picker.
- @AppStorage does NOT write its default value to UserDefaults — it only uses it as an in-memory fallback.
- TranscriptionService and WhisperKitEngine code use `?? "fr"` fallback which SHOULD work, but this creates a fragile dependency on fallback behavior.
- If ANY code path reads the key without the fallback, it gets nil, and WhisperKit defaults to "en".

**Issue 2 (High Confidence for distil model): distil-whisper is English-only**
File: DictusCore/Sources/DictusCore/ModelInfo.swift line 148-157
- The `distil-whisper_distil-large-v3_turbo` model in the catalog is ENGLISH-ONLY.
- WhisperKit detects this via logitsDim check (isModelMultilingual = false).
- When isModelMultilingual is false, TextDecoder does NOT add language tokens to prefill.
- Result: transcription is always English regardless of language parameter.
- The catalog shows this as "available" with no language restriction warning.

**Issue 3 (Needs verification): Crash when toggling language in Settings**
File: DictusApp/Views/SettingsView.swift
- No crash protection or onChange handler exists.
- The crash is likely NOT caused by the language toggle itself.
- Possible cause: toggling triggers a SwiftUI re-render that interacts badly with an ongoing dictation or WhisperKit operation.
- Needs device testing to reproduce and diagnose.

fix: (not yet applied)
verification: (not yet verified)
files_changed: []
