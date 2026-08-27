// DictusApp/Polish/PolishMetricsRing.swift
import Foundation
import DictusCore

/// One observable polish event for the debug screen and export pipeline.
///
/// `polished` is `nil` when the engine never produced an output (skipped,
/// cancelled, engine failure). When the guardrail rejected the polished
/// output, `polished` still carries the engine's response so the developer
/// can see *what* was rejected.
public struct PolishDebugEntry: Identifiable, Sendable, Codable {
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

/// Disk-backed store of recent polish events.
///
/// The original sketch kept events in memory only on the assumption that
/// round-1 iteration would happen within a single session. Real-device testing
/// killed that assumption: an app kill (deliberate, or iOS terminating a
/// backgrounded extension host) wipes every event Pierre is trying to ship for
/// analysis — defeating the iteration loop. Persisting locally matches what
/// `PersistentLog` already does for debug logs.
///
/// Layout:
/// - On-disk format: JSON Lines (`polish_events.jsonl` in the App Group
///   container). One JSON-encoded `PolishDebugEntry` per line. Append-only
///   writes, no in-place edits, so concurrent appends don't tear earlier
///   entries.
/// - Retention: 7 days. Older entries are pruned on first-access bootstrap
///   and again before every export.
/// - In-memory cache: the most recent `memoryCacheLimit` entries are kept
///   resident for fast UI snapshots; full-window reads (used by export) hit
///   disk.
///
/// Privacy stance: `raw` and `polished` are user dictation text. They never
/// leave the device — the file lives in the App Group container, only the
/// main app reads/writes it, and the export-to-share flow is explicitly user-
/// triggered. Behavior is identical to `PersistentLog`, which already stores
/// transcription metadata in the same container.
public actor PolishMetricsRing {

    /// In-memory cap for the UI snapshot. The full 7-day window stays on disk.
    private static let memoryCacheLimit = 200
    private static let retentionPeriod: TimeInterval = 7 * 24 * 3600
    private static let fileName = "polish_events.jsonl"

    private var memoryCache: [PolishDebugEntry] = []
    private var bootstrapped = false

    public init() {}

    // MARK: - Public API

    public func append(_ entry: PolishDebugEntry) async {
        await bootstrapIfNeeded()
        memoryCache.append(entry)
        if memoryCache.count > Self.memoryCacheLimit {
            memoryCache.removeFirst(memoryCache.count - Self.memoryCacheLimit)
        }
        appendToDisk(entry)
    }

    /// Most recent entries (capped at `memoryCacheLimit`) for the debug UI.
    public func snapshot() async -> [PolishDebugEntry] {
        await bootstrapIfNeeded()
        return memoryCache
    }

    /// All entries within the 7-day retention window — used by the JSON export.
    /// Reads from disk to bypass the memory cap.
    public func allEntries() async -> [PolishDebugEntry] {
        await bootstrapIfNeeded()
        return readAllFromDisk(applyingRetention: true)
    }

    /// Total entries within the retention window. Cheap-enough disk read.
    public func storedCount() async -> Int {
        await bootstrapIfNeeded()
        return readAllFromDisk(applyingRetention: true).count
    }

    public func clear() async {
        memoryCache.removeAll()
        clearDisk()
    }

    // MARK: - Bootstrap

    private func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        pruneOldEntries()
        let recent = readAllFromDisk(applyingRetention: true)
        let tail = recent.suffix(Self.memoryCacheLimit)
        memoryCache = Array(tail)
    }

    // MARK: - Disk I/O

    private var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(Self.fileName)
    }

    private func appendToDisk(_ entry: PolishDebugEntry) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = json + "\n"

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        if let payload = line.data(using: .utf8) {
            try? handle.write(contentsOf: payload)
        }
    }

    private func readAllFromDisk(applyingRetention: Bool) -> [PolishDebugEntry] {
        guard let url = fileURL,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cutoff = Date().addingTimeInterval(-Self.retentionPeriod)
        var out: [PolishDebugEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(PolishDebugEntry.self, from: data) else { continue }
            if applyingRetention && entry.timestamp < cutoff { continue }
            out.append(entry)
        }
        return out
    }

    /// Rewrite the file dropping entries older than the retention window.
    private func pruneOldEntries() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let keep = readAllFromDisk(applyingRetention: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var rewritten = ""
        for entry in keep {
            guard let data = try? encoder.encode(entry),
                  let json = String(data: data, encoding: .utf8) else { continue }
            rewritten += json + "\n"
        }
        try? rewritten.write(to: url, atomically: true, encoding: .utf8)
    }

    private func clearDisk() {
        guard let url = fileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
}
