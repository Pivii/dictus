# Phase 10: Model Catalog - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Clean up the model catalog (remove underperforming WhisperKit models), integrate Parakeet v3 as an alternative STT engine via a SpeechModel protocol abstraction, and redesign the model selection UI with gauge-based metadata display. Languages stay fr/en only.

</domain>

<decisions>
## Implementation Decisions

### Model cleanup
- Remove Tiny and Base from catalog — both confirmed bad for French dictation
- Keep Small and Medium as WhisperKit offerings
- Already-downloaded Tiny/Base keep working but can't be re-downloaded (soft deprecation)
- Re-test large-v3-turbo — was removed early in project due to ANE compilation issue, but codebase is now stable; worth retrying
- Research newer WhisperKit model variants (distil, turbo fixes, etc.) during phase research
- Recommended default: deferred to after benchmarking all final models

### Parakeet v3 integration
- Full integration attempted (SpeechModel protocol + FluidAudio runtime + downloadable in catalog)
- If FluidAudio SDK proves unstable or French accuracy is poor: defer to v1.2, don't block the phase
- Languages: fr/en only for all engines (no new languages in this phase)

### Model selection UI redesign
- Layout: "Téléchargés" / "Disponibles" sections (like Handy app reference)
- Engine badge on each model card (WK/PK) rather than engine-based sections
- Gauge bars for accuracy and speed (inspired by Handy screenshot) replacing text labels (Good/Better/Best, Fast/Balanced/Slow)
- Short description per model ("Précis et équilibré", "Rapide et précis", etc.)
- Taille en MB visible sur tous les modèles
- Engine description paragraphs: brief text under each engine section explaining what it is, who develops it, philosophy

### Claude's Discretion
- SpeechModel protocol design (keep or remove if Parakeet fails — evaluate based on added complexity)
- Exact section layout (Downloaded/Available vs Engine-first — user said "fais au mieux")
- Gauge bar visual design (colors, scale, number of segments)
- Model description copywriting
- SmartModelRouter cleanup (currently bypassed — decide whether to remove or update)

</decisions>

<specifics>
## Specific Ideas

- "J'aimerais un système de jauge pour évaluer la vitesse et la précision, à l'image de ce qu'a fait Andy" — reference screenshot from Handy app (macOS dictation app with gauge bars for accuracy/speed per model)
- "Ça pourrait être intéressant dans chaque engine de faire un petit topo sur ce que c'est, par qui c'est développé, la philosophie" — brief engine descriptions in the catalog
- "Le modèle turbo, je pense que c'était pas lié au turbo le bug, c'était plutôt lié au fait qu'on était au tout début" — re-evaluate large-v3-turbo with current stable codebase
- "Je pense qu'il faut qu'on teste" (Parakeet) — user wants to try even if risky, with clean fallback

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ModelInfo` (DictusCore): Current model metadata struct with identifier, displayName, sizeLabel, accuracyLabel, speedLabel, sizeBytes — needs extension for engine type and gauge values
- `ModelManager` (DictusApp): Full download/select/delete lifecycle — needs protocol abstraction for multi-engine support
- `ModelManagerView` + `ModelRow`: Current UI with glass cards, download progress, state display — needs redesign for gauges
- `TranscriptionService`: Currently WhisperKit-only — needs protocol-based engine switching
- `SmartModelRouter` (DictusCore): Bypassed but still in codebase — candidate for cleanup or update

### Established Patterns
- App Group for cross-process state (SharedKeys.activeModel, SharedKeys.downloadedModels)
- @MainActor + ObservableObject for model state management
- WhisperKit.download() for HuggingFace model fetching with progress callback
- Serial prewarm lock (one CoreML compilation at a time to avoid ANE crashes)
- dictusGlass() modifier for card styling

### Integration Points
- `ModelInfo.all` is referenced by ModelManager init and ModelManagerView ForEach — changing the catalog updates both
- `TranscriptionService.prepare(modelPath:)` is the transcription entry point — new engine would need equivalent
- `DictationCoordinator` orchestrates the recording→transcription flow — may need engine-aware routing
- Onboarding `ModelDownloadPage` references ModelInfo for first model download

</code_context>

<deferred>
## Deferred Ideas

- Multi-language support beyond fr/en — future phase when user base grows
- Device-adaptive model recommendation (WhisperKit.recommendedModels()) — decide after benchmarking
- Background download sessions (URLSession background) — current foreground approach is sufficient

</deferred>

---

*Phase: 10-model-catalog*
*Context gathered: 2026-03-10*
