// DictusApp/Polish/PolishCoordinator.swift
import Foundation
import NaturalLanguage
import DictusCore

/// Orchestrates the polish layer:
/// 1. Honour the global toggle (`SharedKeys.polishEnabled`).
/// 2. Detect the language of the raw STT output via `NLLanguageRecognizer`.
/// 3. Skip on gibberish (top hypothesis below `confidenceThreshold`).
/// 4. Choose mode: `.natural` for Whisper or `.natural`/`.repair` for Parakeet
///    depending on detected-vs-target match.
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
        // Resolve the polish target through the engine-aware language policy
        // (#226): explicit mode targets the dictated language, not the keyboard
        // one; Whisper auto mode skips polish entirely (see polish()) so there
        // is nothing to warm — don't pay to load the model into memory. With
        // Parakeet active the setting is ineffective and this resolves to the
        // keyboard language in every mode, exactly the pre-#226 behavior.
        // Prewarm has no dictation-scoped policy to receive (it fires at app
        // launch and ~1.5s into recording), so it snapshots on its own — a
        // stale warm target is harmless (prewarm is best-effort).
        guard let target = TranscriptionLanguagePolicy.snapshot().polishTargetLanguage else { return }
        Task { await engineToWarm.prewarm(targetLanguage: target) }
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

        let sttEngine = languagePolicy.engine
        let sttModelID = languagePolicy.modelIdentifier

        // Transcription language decoupling (#226): the polish prompts AND the
        // deterministic typography pre/post passes (verbal punctuation, French
        // NBSP) are tuned for the four tested languages. In Whisper Auto-detect
        // mode the output language is unknown (could be zh, it, pt, …), so the
        // whole polish layer is bypassed — the raw STT output is returned
        // untouched. Stopgap until the dedicated auto-detect prompt lands (#239).
        // The bypass IS recorded (outcome .skippedAutoMode, ~0ms, no engine
        // run): device testing showed a silent return makes the debug export
        // look like the dictation never reached polish, which reads as a bug.
        // In explicit mode, polish targets the dictated language (not the
        // keyboard language) so typography/prompts match the actual output.
        // With Parakeet active the setting is ineffective: the policy resolves
        // every mode to the keyboard language, i.e. the pre-#226 behavior.
        guard let target = languagePolicy.polishTargetLanguage else {
            await recordAutoModeBypass(raw: raw, languagePolicy: languagePolicy)
            return raw
        }

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
            PolishMetrics.log(m)
            await metricsRing.append(PolishDebugEntry(raw: raw, polished: finalShort, metrics: m))
            return finalShort
        }

        let detected = PolishPipeline.detectLanguage(in: preprocessed)

        // Resolve the engine for this call — see `activeEngine` doc-comment.
        let currentEngine = activeEngine
        let engineID = currentEngine.identifier

        // Skip on gibberish — preserves trust per ADR 0002 §"skip-on-gibberish rule".
        guard let detected else {
            // Return the deterministic floor, NOT the literal raw: the verbal-
            // punctuation pre-pass already ran (~0ms) and the user expects their
            // spoken "virgule"/"point" turned into marks even when the LLM is
            // skipped. Same value the < engineMinDuration gate returns. (#185)
            let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let postStart = Date()
            let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
            let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
            let m = PolishMetrics(
                engine: engineID,
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
            PolishMetrics.log(m)
            await metricsRing.append(PolishDebugEntry(raw: raw, polished: nil, metrics: m))
            return fallback
        }

        let mode = PolishPipeline.mode(sttEngine: sttEngine, detected: detected, target: target)

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
        let returned = PolishPipeline.resolvedOutput(bundle, preprocessed: preprocessed, target: target)

        let m = PolishMetrics(
            engine: engineID,
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
        PolishMetrics.log(m)
        await metricsRing.append(PolishDebugEntry(raw: raw, polished: bundle.engineOutput, metrics: m))

        return returned
    }

    // MARK: - Helpers

    /// Record the Whisper Auto-detect bypass (#226) as a `.skippedAutoMode`
    /// event: ~0ms, no mode, no engine run. `targetLanguage` is metrics
    /// context only (nothing was targeted) — the keyboard language documents
    /// the session state, matching what the JSON export's settings block shows.
    private func recordAutoModeBypass(raw: String,
                                      languagePolicy: TranscriptionLanguagePolicy) async {
        let m = PolishMetrics(
            engine: activeEngine.identifier,
            mode: nil,
            targetLanguage: languagePolicy.keyboardLanguage,
            detectedLanguage: nil,
            rawCharCount: raw.count,
            polishedCharCount: raw.count,
            latencyMs: 0,
            outcome: .skippedAutoMode,
            sttEngine: languagePolicy.engine.rawValue,
            sttModelID: languagePolicy.modelIdentifier,
            timings: PolishTimings(preprocessMs: 0, engineMs: 0, postprocessMs: 0)
        )
        PolishMetrics.log(m)
        await metricsRing.append(PolishDebugEntry(raw: raw, polished: nil, metrics: m))
    }

    /// Recording duration (seconds) below which the LLM polish is skipped (#141).
    /// On flash dictations the user wants instant text and the model rarely adds
    /// value for ~3-6s of latency. Deterministic passes still run. Tunable.
    private static let engineMinDuration: TimeInterval = 2.0
}
