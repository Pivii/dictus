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
    private var inflight: Task<PolishOutcomeBundle, Never>?

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
    /// language. Called from `DictusApp.init()` so the first dictation pays no
    /// session-creation cost. The passthrough engine has nothing to warm.
    public func prewarm() {
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
    public func polish(raw: String, sttEngine: SpeechEngine, sttModelID: String) async -> String {
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
        let detected = Self.detectLanguage(in: preprocessed)

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

        let mode = Self.modeFor(sttEngine: sttEngine, detected: detected, target: target)

        inflight?.cancel()
        // Encode newlines as a marker so Apple FM can't "naturalise" them
        // into ", " + capital — see `PolishPostpass` doc-comment.
        let engineInput = PolishPostpass.encodeForEngine(preprocessed)
        // Everything above (pre-pass + detection + encode) is the preprocess cost.
        let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)

        let task = Task { () -> PolishOutcomeBundle in
            let engineStart = Date()
            do {
                let polishedRaw = try await currentEngine.polish(
                    raw: engineInput, targetLanguage: target, mode: mode
                )
                // `engineMs` isolates the pure LLM call — the number that
                // answers "is the latency the model or our code?".
                let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
                let postStart = Date()
                // Restore newlines from markers + apply FR typographic spacing.
                // Run BEFORE the guardrail so char-ratio compares apples to
                // apples (both sides use `\n`, not the multi-char marker).
                let polished = PolishPostpass.decodeFromEngine(polishedRaw, language: target)
                if Task.isCancelled {
                    let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                    return PolishOutcomeBundle(engineOutput: polished, outcome: .cancelled, engineMs: engineMs, postprocessMs: postMs)
                }
                // Guardrail baseline is the preprocessed text — that's what the
                // engine actually saw (modulo the newline marker, which the
                // post-pass already undid). Using the original raw would bias
                // the char-ratio when the pre-pass made a substantial
                // substitution.
                guard PolishGuardrail.accepts(raw: preprocessed, polished: polished, mode: mode) else {
                    let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                    return PolishOutcomeBundle(engineOutput: polished, outcome: .rejectedGuardrail, engineMs: engineMs, postprocessMs: postMs)
                }
                guard PolishGuardrail.detectedLanguageMatches(polished: polished, target: target) else {
                    let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                    return PolishOutcomeBundle(engineOutput: polished, outcome: .rejectedGuardrail, engineMs: engineMs, postprocessMs: postMs)
                }
                let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
                return PolishOutcomeBundle(engineOutput: polished, outcome: .success, engineMs: engineMs, postprocessMs: postMs)
            } catch is CancellationError {
                let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
                return PolishOutcomeBundle(engineOutput: nil, outcome: .cancelled, engineMs: engineMs, postprocessMs: 0)
            } catch {
                let engineMs = Int(Date().timeIntervalSince(engineStart) * 1000)
                return PolishOutcomeBundle(engineOutput: nil, outcome: .engineFailed, engineMs: engineMs, postprocessMs: 0)
            }
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

    /// Top-language confidence below which raw is treated as gibberish and polish is skipped.
    /// ADR 0002 leaves the exact threshold open; 0.5 is a starting point tuned from logs.
    private static let confidenceThreshold: Double = 0.5

    private static func detectLanguage(in text: String) -> SupportedLanguage? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let top = hypotheses.max(by: { $0.value < $1.value }),
              top.value >= confidenceThreshold else {
            return nil
        }
        return SupportedLanguage(rawValue: top.key.rawValue)
    }

    private static func modeFor(sttEngine: SpeechEngine,
                                detected: SupportedLanguage,
                                target: SupportedLanguage) -> PolishMode {
        switch sttEngine {
        case .whisperKit:
            // Whisper respects the language picker upstream — always Natural.
            return .natural
        case .parakeet:
            // Parakeet auto-detects; rebuild intent when detected ≠ target.
            return detected == target ? .natural : .repair
        }
    }
}

private struct PolishOutcomeBundle: Sendable {
    /// The engine's actual output, or `nil` when the engine never ran successfully
    /// (cancelled before completion, threw an error). Kept around even when the
    /// guardrail rejected it so the debug screen can show *what* was rejected.
    let engineOutput: String?
    let outcome: PolishMetrics.Outcome
    /// Pure LLM call duration (the `session.respond`).
    let engineMs: Int
    /// Marker decode + NBSP + guardrail, measured after the engine returned.
    let postprocessMs: Int
}
