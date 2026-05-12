// DictusApp/Polish/PolishMetricsRing.swift
import Foundation
import DictusCore

/// One observable polish event for the in-memory debug ring buffer.
///
/// `polished` is `nil` when the engine never produced an output (skipped,
/// cancelled, engine failure). When the guardrail rejected the polished
/// output, `polished` still carries the engine's response so the developer
/// can see *what* was rejected.
public struct PolishDebugEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let raw: String
    public let polished: String?
    public let metrics: PolishMetrics

    public init(raw: String, polished: String?, metrics: PolishMetrics) {
        self.id = UUID()
        self.timestamp = Date()
        self.raw = raw
        self.polished = polished
        self.metrics = metrics
    }
}

/// Bounded in-memory ring buffer of recent polish events. No disk persistence —
/// `raw` and `polished` hold user text and are intentionally scoped to a single
/// process lifetime. ADR 0002 §"PolishMetrics" reserves disk logging for round 2.
public actor PolishMetricsRing {

    private var entries: [PolishDebugEntry] = []
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func append(_ entry: PolishDebugEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func snapshot() -> [PolishDebugEntry] {
        entries
    }

    public func clear() {
        entries.removeAll()
    }
}
