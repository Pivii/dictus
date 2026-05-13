// DictusApp/Polish/PolishCoordinator.swift
import Foundation
import NaturalLanguage
import DictusCore

/// Orchestrates the polish layer:
/// 1. Honour the global toggle (`SharedKeys.polishEnabled`).
/// 2. Detect the language of the raw STT output via `NLLanguageRecognizer`.
/// 3. Skip on gibberish (top hypothesis below `confidenceThreshold`).
/// 4. Choose mode: `.light` for Whisper or `.light`/`.repair` for Parakeet
///    depending on detected-vs-target match.
/// 5. Run the engine with cancellation support, apply the guardrail, emit metrics.
///
/// Hooked into the dictation pipeline in `DictationCoordinator` between the STT
/// final result and the App Group write. See ADR 0002.
@MainActor
public final class PolishCoordinator {

    public static let shared = PolishCoordinator()

    // MARK: - Private state

    private let engine: PolishEngineProtocol
    private let defaults: UserDefaults
    private let metricsRing = PolishMetricsRing()
    private var inflight: Task<PolishOutcomeBundle, Never>?

    private init() {
        self.defaults = AppGroup.defaults
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), PolishAvailability.isAppleFMAvailable {
            self.engine = AppleFoundationModelsPolishEngine()
        } else {
            self.engine = PassthroughPolishEngine()
        }
        #else
        self.engine = PassthroughPolishEngine()
        #endif
    }

    // MARK: - Public API

    /// Cancel any in-flight polish. Called by `DictationCoordinator.startDictation()`
    /// so a new recording does not pile up behind the previous polish.
    public func cancelInflight() {
        inflight?.cancel()
        inflight = nil
    }

    /// Warm up the active engine for the user's current target language.
    /// Called from `DictusApp.init()` so the first dictation pays no
    /// session-creation cost.
    public func prewarm() {
        let target = SupportedLanguage.active
        let currentEngine = engine
        Task { await currentEngine.prewarm(targetLanguage: target) }
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
    public func polish(raw: String, sttEngine: SpeechEngine) async -> String {
        guard defaults.bool(forKey: SharedKeys.polishEnabled) else {
            return raw
        }

        let target = SupportedLanguage.active
        let detected = Self.detectLanguage(in: raw)

        // Skip on gibberish — preserves trust per ADR 0002 §"skip-on-gibberish rule".
        guard let detected else {
            let m = PolishMetrics(
                engine: engine.identifier,
                mode: nil,
                targetLanguage: target,
                detectedLanguage: nil,
                rawCharCount: raw.count,
                polishedCharCount: raw.count,
                latencyMs: 0,
                outcome: .skipped
            )
            PolishMetrics.log(m)
            await metricsRing.append(PolishDebugEntry(raw: raw, polished: nil, metrics: m))
            return raw
        }

        let mode = Self.modeFor(sttEngine: sttEngine, detected: detected, target: target)

        inflight?.cancel()
        let currentEngine = engine
        let start = Date()
        let task = Task { () -> PolishOutcomeBundle in
            do {
                let polished = try await currentEngine.polish(
                    raw: raw, targetLanguage: target, mode: mode
                )
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                if Task.isCancelled {
                    return PolishOutcomeBundle(engineOutput: polished, outcome: .cancelled, latencyMs: latency)
                }
                guard PolishGuardrail.accepts(raw: raw, polished: polished, mode: mode) else {
                    return PolishOutcomeBundle(engineOutput: polished, outcome: .rejectedGuardrail, latencyMs: latency)
                }
                guard PolishGuardrail.detectedLanguageMatches(polished: polished, target: target) else {
                    return PolishOutcomeBundle(engineOutput: polished, outcome: .rejectedGuardrail, latencyMs: latency)
                }
                return PolishOutcomeBundle(engineOutput: polished, outcome: .success, latencyMs: latency)
            } catch is CancellationError {
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                return PolishOutcomeBundle(engineOutput: nil, outcome: .cancelled, latencyMs: latency)
            } catch {
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                return PolishOutcomeBundle(engineOutput: nil, outcome: .engineFailed, latencyMs: latency)
            }
        }
        inflight = task

        let bundle = await task.value
        let returned: String = (bundle.outcome == .success) ? (bundle.engineOutput ?? raw) : raw

        let m = PolishMetrics(
            engine: engine.identifier,
            mode: mode,
            targetLanguage: target,
            detectedLanguage: detected.rawValue,
            rawCharCount: raw.count,
            polishedCharCount: returned.count,
            latencyMs: bundle.latencyMs,
            outcome: bundle.outcome
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
            // Whisper respects the language picker upstream — always Light.
            return .light
        case .parakeet:
            // Parakeet auto-detects; rebuild intent when detected ≠ target.
            return detected == target ? .light : .repair
        }
    }
}

private struct PolishOutcomeBundle: Sendable {
    /// The engine's actual output, or `nil` when the engine never ran successfully
    /// (cancelled before completion, threw an error). Kept around even when the
    /// guardrail rejected it so the debug screen can show *what* was rejected.
    let engineOutput: String?
    let outcome: PolishMetrics.Outcome
    let latencyMs: Int
}
