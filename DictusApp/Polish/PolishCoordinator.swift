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
        let target = SupportedLanguage.active
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
    /// `sttModelID` is the active model identifier (e.g. "openai_whisper-small",
    /// "parakeet-tdt-0.6b-v3"). It's carried through to metrics so the JSON
    /// export is self-describing — analysis doesn't need to cross-reference the
    /// app log to know which STT model produced each event.
    public func polish(raw: String,
                       sttEngine: SpeechEngine,
                       sttModelID: String,
                       recordingDuration: TimeInterval) async -> String {
        guard defaults.bool(forKey: SharedKeys.polishEnabled) else {
            return raw
        }

        let target = SupportedLanguage.active

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
            let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let m = PolishMetrics(
                engine: engineID,
                mode: nil,
                targetLanguage: target,
                detectedLanguage: nil,
                rawCharCount: raw.count,
                polishedCharCount: raw.count,
                latencyMs: preprocessMs,
                outcome: .skipped,
                sttEngine: sttEngine.rawValue,
                sttModelID: sttModelID,
                timings: PolishTimings(preprocessMs: preprocessMs, engineMs: 0, postprocessMs: 0)
            )
            PolishMetrics.log(m)
            await metricsRing.append(PolishDebugEntry(raw: raw, polished: nil, metrics: m))
            return raw
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
        let returned: String = (bundle.outcome == .success) ? (bundle.engineOutput ?? raw) : raw

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

    /// Recording duration (seconds) below which the LLM polish is skipped (#141).
    /// On flash dictations the user wants instant text and the model rarely adds
    /// value for ~3-6s of latency. Deterministic passes still run. Tunable.
    private static let engineMinDuration: TimeInterval = 2.0
}
