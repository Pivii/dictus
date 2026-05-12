// DictusCore/Sources/DictusCore/Polish/PolishMetrics.swift
import Foundation
import os.log

/// One polish invocation, emitted to `os_log` and consumed by the in-memory
/// debug ring buffer in DictusApp. No disk persistence at round 1.
public struct PolishMetrics: Sendable {
    public enum Outcome: String, Sendable {
        case success
        case rejectedGuardrail
        case skipped
        case cancelled
        case engineFailed
    }

    public let engine: String
    public let mode: PolishMode?           // nil when skipped (no mode chosen)
    public let targetLanguage: SupportedLanguage
    public let detectedLanguage: String?   // BCP-47 ("fr","en",…) or nil for gibberish
    public let rawCharCount: Int
    public let polishedCharCount: Int      // equals rawCharCount when not polished
    public let latencyMs: Int
    public let outcome: Outcome

    public init(engine: String,
                mode: PolishMode?,
                targetLanguage: SupportedLanguage,
                detectedLanguage: String?,
                rawCharCount: Int,
                polishedCharCount: Int,
                latencyMs: Int,
                outcome: Outcome) {
        self.engine = engine
        self.mode = mode
        self.targetLanguage = targetLanguage
        self.detectedLanguage = detectedLanguage
        self.rawCharCount = rawCharCount
        self.polishedCharCount = polishedCharCount
        self.latencyMs = latencyMs
        self.outcome = outcome
    }

    /// Emit one line to the `polish` os_log category. Prefixed with `📊 polish`
    /// so debug log readers can grep for the polish stream.
    public static func log(_ m: PolishMetrics) {
        if #available(iOS 14.0, macOS 11.0, *) {
            PolishLog.logger.info(
                "📊 polish outcome=\(m.outcome.rawValue, privacy: .public) engine=\(m.engine, privacy: .public) mode=\(m.mode?.rawValue ?? "-", privacy: .public) target=\(m.targetLanguage.rawValue, privacy: .public) detected=\(m.detectedLanguage ?? "-", privacy: .public) chars=\(m.rawCharCount, privacy: .public)→\(m.polishedCharCount, privacy: .public) latencyMs=\(m.latencyMs, privacy: .public)"
            )
        }
    }
}

private enum PolishLog {
    @available(iOS 14.0, macOS 11.0, *)
    static let logger = Logger(subsystem: "com.pivi.dictus", category: "polish")
}
