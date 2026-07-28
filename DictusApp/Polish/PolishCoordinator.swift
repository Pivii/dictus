// DictusApp/Polish/PolishCoordinator.swift
import Foundation
import NaturalLanguage
import DictusCore

/// Orchestrates the polish layer:
/// 1. Honour the global toggle (`SharedKeys.polishEnabled`).
/// 2. Branch on the resolved prompt selection (#239): per-language path for
///    follow/explicit modes, language-agnostic auto path for Auto-detect.
/// 3. Detect the language of the raw STT output via `NLLanguageRecognizer`;
///    skip on gibberish (top hypothesis below `confidenceThreshold`).
/// 4. Choose mode: `.natural` for Whisper or `.natural`/`.repair` for Parakeet
///    depending on detected-vs-target match; `.auto` in Auto-detect mode.
/// 5. Run the engine with cancellation support, apply the guardrail, emit metrics.
///
/// Hooked into the dictation pipeline in `DictationCoordinator` between the STT
/// final result and the App Group write. See ADR 0003.
@MainActor
public final class PolishCoordinator {

    public static let shared = PolishCoordinator()

    // MARK: - Private state

    /// Apple Foundation Models engine. Created once on iOS 26+ when the SDK is
    /// available, regardless of `SystemLanguageModel.default.availability` at
    /// that exact moment — that flag is *runtime* (Apple Intelligence may finish
    /// downloading or be toggled on by the user after `init()`). The engine
    /// itself is cheap to instantiate; gating is done dynamically in `polish()`
    /// by `PolishAvailability.isAppleFMAvailable` so a single launch can recover
    /// once iOS flips the state to `.available`.
    private let appleFMEngine: PolishEngineProtocol?
    private let passthroughEngine: PolishEngineProtocol = PassthroughPolishEngine()
    private let defaults: UserDefaults
    private let metricsRing = PolishMetricsRing()
    private var inflight: Task<PolishPipeline.Result, Never>?

    private init() {
        self.defaults = AppGroup.defaults
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.appleFMEngine = AppleFoundationModelsPolishEngine()
        } else {
            self.appleFMEngine = nil
        }
        #else
        self.appleFMEngine = nil
        #endif
    }

    /// Resolve the engine for this call. Re-checked on every `polish()` so a
    /// late availability flip (model finishes downloading, user toggles Apple
    /// Intelligence on) takes effect without an app relaunch.
    private var activeEngine: PolishEngineProtocol {
        if let appleFMEngine, PolishAvailability.isAppleFMAvailable {
            return appleFMEngine
        }
        return passthroughEngine
    }

    // MARK: - Public API

    /// Cancel any in-flight polish. Called by `DictationCoordinator.startDictation()`
    /// so a new recording does not pile up behind the previous polish.
    public func cancelInflight() {
        inflight?.cancel()
        inflight = nil
    }

    /// Warm up the Apple FM engine (if present) for the user's current target
    /// language. Called from `DictusApp.init()` at launch AND from
    /// `DictationCoordinator` ~1.5s into each recording (#141) — Apple recommends
    /// calling `prewarm()` ≥1s before `respond()`, and the recording duration is
    /// exactly that window. Each call recreates a fresh session, so the engine's
    /// stateless invariant holds (see `AppleFoundationModelsPolishEngine`).
    ///
    /// No-op when the toggle is off (don't pay to load the model into memory if
    /// no polish will run) or when the engine has nothing to warm.
    public func prewarm() {
        guard defaults.bool(forKey: SharedKeys.polishEnabled) else { return }
        guard let engineToWarm = appleFMEngine else { return }
        // Resolve the prompt selection through the engine-aware language
        // policy (#226/#239): explicit mode targets the dictated language, not
        // the keyboard one; Auto mode warms the language-agnostic auto session
        // (the language argument is a placeholder the engine normalizes).
        // Prewarm has no dictation-scoped policy to receive (it fires at app
        // launch and ~1.5s into recording), so it snapshots on its own — a
        // stale warm target is harmless (prewarm is best-effort).
        let selection = TranscriptionLanguagePolicy.snapshot().polishPromptSelection
        Task {
            switch selection {
            case .language(let target):
                await engineToWarm.prewarm(mode: .natural, targetLanguage: target)
            case .autoDetected:
                await engineToWarm.prewarm(mode: .auto, targetLanguage: .english)
            }
        }
    }

    /// Recent polish events (memory-cached) for the debug screen.
    public func metricsSnapshot() async -> [PolishDebugEntry] {
        await metricsRing.snapshot()
    }

    /// All polish events within the 7-day retention window — used by the JSON export.
    public func metricsAllEntries() async -> [PolishDebugEntry] {
        await metricsRing.allEntries()
    }

    /// Count of persisted events within the 7-day retention window.
    public func metricsStoredCount() async -> Int {
        await metricsRing.storedCount()
    }

    /// Empties the debug ring. Triggered from the debug screen's Clear button.
    public func clearMetricsRing() async {
        await metricsRing.clear()
    }

    /// Polish raw STT output. Returns `raw` unchanged when the toggle is off, when
    /// language detection skips, when the engine throws/cancels, or when the
    /// guardrail rejects the output.
    ///
    /// `languagePolicy` is the per-dictation snapshot captured by
    /// DictationCoordinator at transcription start (#226). It carries the STT
    /// engine, the model identifier (e.g. "openai_whisper-small",
    /// "parakeet-tdt-0.6b-v3" — kept in metrics so the JSON export is
    /// self-describing), and the polish target. Using the snapshot instead of
    /// re-reading App Group state here guarantees polish targets the same
    /// language the STT engine was given, even if the user changed the
    /// keyboard language while transcription was running.
    public func polish(raw: String,
                       languagePolicy: TranscriptionLanguagePolicy,
                       recordingDuration: TimeInterval) async -> String {
        guard defaults.bool(forKey: SharedKeys.polishEnabled) else {
            return raw
        }

        // Transcription language decoupling (#226/#239): the prompt selection
        // branches on the resolved mode. Follow/explicit modes run the
        // per-language path (prompts + typography passes tuned for the four
        // tested languages; in explicit mode polish targets the dictated
        // language, not the keyboard one). Auto-detect mode — BOTH engines,
        // per the #239 amendment — runs the language-agnostic auto path: the
        // output language is unknown (could be zh, it, pt, …), so the engine
        // uses the auto prompt and the per-language regex passes stay off.
        switch languagePolicy.polishPromptSelection {
        case .language(let target):
            return await polishTargeted(
                raw: raw, target: target,
                languagePolicy: languagePolicy, recordingDuration: recordingDuration
            )
        case .autoDetected:
            return await polishAutoDetected(
                raw: raw, languagePolicy: languagePolicy, recordingDuration: recordingDuration
            )
        }
    }

    // MARK: - Per-language path

    /// The historical polish path: verbal-punctuation pre-pass, duration gate,
    /// gibberish gate, per-language prompt, typography post-pass. `target` is
    /// the resolved polish language from the policy snapshot.
    private func polishTargeted(raw: String,
                                target: SupportedLanguage,
                                languagePolicy: TranscriptionLanguagePolicy,
                                recordingDuration: TimeInterval) async -> String {
        let sttEngine = languagePolicy.engine
        let sttModelID = languagePolicy.modelIdentifier

        // `methodStart` anchors the full wall-clock the user actually waits for,
        // INCLUDING the deterministic passes (which the old timer excluded).
        // The timing breakdown below proves where the time goes.
        let methodStart = Date()

        // Pre-pass: deterministic regex substitution of verbal punctuation
        // commands. Round 3 testing showed Apple FM cannot be coaxed into
        // doing this reliably in French — handling it in code bypasses the
        // model entirely for this concern.
        let preprocessed = VerbalPunctuationPrepass.apply(raw, language: target)

        // Duration gate (#141): on a flash dictation (< engineMinDuration) the
        // user wants instant text and the LLM rarely adds value — so we skip the
        // model entirely. We KEEP the free deterministic passes though (verbal
        // punctuation above + NBSP below, both ~0ms) so typography stays
        // consistent with longer clips. No language detection / guardrail here
        // since the engine never runs.
        if recordingDuration < Self.engineMinDuration {
            let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let postStart = Date()
            // No engine ran → no newline markers to decode; this only applies
            // the language typography (French NBSP).
            let finalShort = PolishPostpass.decodeFromEngine(preprocessed, language: target)
            let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
            let m = PolishMetrics(
                engine: activeEngine.identifier,
                mode: nil,
                targetLanguage: target,
                detectedLanguage: nil,
                rawCharCount: raw.count,
                polishedCharCount: finalShort.count,
                latencyMs: preprocessMs + postMs,
                outcome: .skippedShort,
                sttEngine: sttEngine.rawValue,
                sttModelID: sttModelID,
                timings: PolishTimings(preprocessMs: preprocessMs, engineMs: 0, postprocessMs: postMs)
            )
            await emit(m, raw: raw, polished: finalShort)
            return finalShort
        }

        // Skip on gibberish — preserves trust per ADR 0002 §"skip-on-gibberish rule".
        guard let detected = PolishPipeline.detectLanguage(in: preprocessed) else {
            // Return the deterministic floor, NOT the literal raw: the verbal-
            // punctuation pre-pass already ran (~0ms) and the user expects their
            // spoken "virgule"/"point" turned into marks even when the LLM is
            // skipped. Same value the < engineMinDuration gate returns. (#185)
            let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let postStart = Date()
            let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
            let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
            let m = PolishMetrics(
                engine: activeEngine.identifier,
                mode: nil,
                targetLanguage: target,
                detectedLanguage: nil,
                rawCharCount: raw.count,
                polishedCharCount: fallback.count,
                latencyMs: preprocessMs + postMs,
                outcome: .skipped,
                sttEngine: sttEngine.rawValue,
                sttModelID: sttModelID,
                timings: PolishTimings(preprocessMs: preprocessMs, engineMs: 0, postprocessMs: postMs)
            )
            await emit(m, raw: raw, polished: nil)
            return fallback
        }

        let mode = PolishPipeline.mode(sttEngine: sttEngine, detected: detected, target: target)

        // Resolve the engine for this call — see `activeEngine` doc-comment.
        let currentEngine = activeEngine

        inflight?.cancel()
        // Everything above (pre-pass + detection + mode) is the preprocess cost;
        // the engine-facing transform (encode → engine → decode → guardrail) is
        // delegated to `PolishPipeline` so the eval harness runs identical code.
        let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)

        let task = Task {
            await PolishPipeline.transform(
                preprocessed: preprocessed, engine: currentEngine, target: target, mode: mode
            )
        }
        inflight = task

        let bundle = await task.value
        // True total, methodStart → here. Any gap vs (pre+engine+post) is
        // Swift Task scheduling / actor-hop overhead — itself worth seeing.
        let totalMs = Int(Date().timeIntervalSince(methodStart) * 1000)
        // On any non-success (engine failed, guardrail rejected, cancelled) fall
        // back to the deterministic floor, never the literal raw — see
        // `PolishPipeline.resolvedOutput`. (#185)
        let returned = PolishPipeline.resolvedOutput(
            bundle, preprocessed: preprocessed, target: target, mode: mode
        )

        let m = PolishMetrics(
            engine: currentEngine.identifier,
            mode: mode,
            targetLanguage: target,
            detectedLanguage: detected.rawValue,
            rawCharCount: raw.count,
            polishedCharCount: returned.count,
            latencyMs: totalMs,
            outcome: bundle.outcome,
            sttEngine: sttEngine.rawValue,
            sttModelID: sttModelID,
            timings: PolishTimings(
                preprocessMs: preprocessMs,
                engineMs: bundle.engineMs,
                postprocessMs: bundle.postprocessMs
            )
        )
        await emit(m, raw: raw, polished: bundle.engineOutput)

        return returned
    }

    // MARK: - Auto-detect path (#239)

    /// Polish for Auto-detect transcription mode, BOTH engines: the input
    /// language is whatever the STT engine detected, so the engine runs with
    /// the language-agnostic auto prompt (`PolishMode.auto`) and the
    /// per-language deterministic passes (verbal punctuation, French NBSP)
    /// stay OFF — the prompt owns typography, and regexes tuned for the four
    /// tested languages would mangle e.g. CJK full-width punctuation. Every
    /// non-success outcome returns `raw` unchanged (worst case output == input).
    ///
    /// Metrics convention: `targetLanguage` is session context only (nothing
    /// is targeted in auto mode) — the keyboard language documents the state,
    /// matching the JSON export's settings block. `detectedLanguage` carries
    /// the raw NLLanguage code of the INPUT (e.g. "it", "zh-Hans"), which is
    /// how device tests validate output language == input language. Engine
    /// runs are identified by `mode == .auto` in the debug export.
    private func polishAutoDetected(raw: String,
                                    languagePolicy: TranscriptionLanguagePolicy,
                                    recordingDuration: TimeInterval) async -> String {
        let methodStart = Date()
        // Engine-API placeholder in auto mode — never used for typography or
        // guardrails (see PolishPipeline); doubles as the metrics context.
        let contextLanguage = languagePolicy.keyboardLanguage

        // Duration gate (#141): on a flash dictation the user wants instant
        // text. Unlike the per-language path there is no deterministic floor
        // to keep (those passes are per-language), so raw is returned as-is.
        if recordingDuration < Self.engineMinDuration {
            let m = autoEventMetrics(
                outcome: .skippedShort, raw: raw, finalCount: raw.count,
                languagePolicy: languagePolicy, engineID: activeEngine.identifier
            )
            await emit(m, raw: raw, polished: nil)
            return raw
        }

        // Gibberish gate — same skip-on-gibberish rule as the per-language
        // path (ADR 0002), but on the raw NLLanguage code: auto mode must
        // accept the whole long tail (zh, it, pt, …), not just the four
        // supported languages.
        guard let detectedCode = PolishPipeline.detectLanguageCode(in: raw) else {
            let detectMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let m = autoEventMetrics(
                outcome: .skipped, raw: raw, finalCount: raw.count,
                languagePolicy: languagePolicy, engineID: activeEngine.identifier,
                latencyMs: detectMs,
                timings: PolishTimings(preprocessMs: detectMs, engineMs: 0, postprocessMs: 0)
            )
            await emit(m, raw: raw, polished: nil)
            return raw
        }

        let currentEngine = activeEngine
        inflight?.cancel()
        // Detection is the only pre-engine work in auto mode (no regex passes).
        let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
        let task = Task {
            await PolishPipeline.transform(
                preprocessed: raw, engine: currentEngine, target: contextLanguage, mode: .auto
            )
        }
        inflight = task

        let bundle = await task.value
        let totalMs = Int(Date().timeIntervalSince(methodStart) * 1000)
        let returned = PolishPipeline.resolvedOutput(
            bundle, preprocessed: raw, target: contextLanguage, mode: .auto
        )
        let m = autoEventMetrics(
            outcome: bundle.outcome, raw: raw, finalCount: returned.count,
            languagePolicy: languagePolicy, engineID: currentEngine.identifier,
            mode: .auto, detectedLanguage: detectedCode, latencyMs: totalMs,
            timings: PolishTimings(
                preprocessMs: preprocessMs,
                engineMs: bundle.engineMs,
                postprocessMs: bundle.postprocessMs
            )
        )
        await emit(m, raw: raw, polished: bundle.engineOutput)
        return returned
    }

    /// Metrics for one auto-path event. Defaults cover the skip exits (no
    /// mode, no detection, ~0ms); the engine-run exit overrides them.
    /// `targetLanguage` is the keyboard language — session context only.
    private func autoEventMetrics(outcome: PolishMetrics.Outcome,
                                  raw: String,
                                  finalCount: Int,
                                  languagePolicy: TranscriptionLanguagePolicy,
                                  engineID: String,
                                  mode: PolishMode? = nil,
                                  detectedLanguage: String? = nil,
                                  latencyMs: Int = 0,
                                  timings: PolishTimings =
                                      PolishTimings(preprocessMs: 0, engineMs: 0, postprocessMs: 0)
    ) -> PolishMetrics {
        PolishMetrics(
            engine: engineID,
            mode: mode,
            targetLanguage: languagePolicy.keyboardLanguage,
            detectedLanguage: detectedLanguage,
            rawCharCount: raw.count,
            polishedCharCount: finalCount,
            latencyMs: latencyMs,
            outcome: outcome,
            sttEngine: languagePolicy.engine.rawValue,
            sttModelID: languagePolicy.modelIdentifier,
            timings: timings
        )
    }

    /// Log one metrics event and append it to the debug ring.
    private func emit(_ m: PolishMetrics, raw: String, polished: String?) async {
        PolishMetrics.log(m)
        await metricsRing.append(PolishDebugEntry(raw: raw, polished: polished, metrics: m))
    }

    /// Recording duration (seconds) below which the LLM polish is skipped (#141).
    /// On flash dictations the user wants instant text and the model rarely adds
    /// value for ~3-6s of latency. Deterministic passes still run. Tunable.
    private static let engineMinDuration: TimeInterval = 2.0
}
