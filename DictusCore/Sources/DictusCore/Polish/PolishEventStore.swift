// DictusCore/Sources/DictusCore/Polish/PolishEventStore.swift
// The polish debug ring's file, shared by the two processes that now write it (#361).
import Foundation

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

    /// Which process produced this event: `"<KBD>"` or `"<APP>"` (#361 decision 8).
    ///
    /// WHY it is not cosmetic: the whole #315 investigation rested on being able to
    /// read `appState` in the captures. After polish moved into the keyboard, an
    /// export with no `rateLimited` in it could equally mean the keyboard is not
    /// rate-limited or that little dictating happened, and nothing on the event
    /// would say which. The marker is what makes decision 13's acceptance
    /// criterion — zero `rateLimited` marked `<KBD>` over a dense session — a
    /// thing a reader can check rather than infer.
    ///
    /// WHY the angle brackets are stored rather than added at render time: the
    /// persistent log already writes `<KBD>` / `<APP>`, and one spelling across
    /// both artefacts means one grep answers the question in either of them.
    ///
    /// Optional because the ring holds seven days of events and the ones written
    /// before this build carry no key. Absent means "written by a build where only
    /// the app could write", which is `<APP>` — but it is left absent rather than
    /// backfilled, so an export never claims a fact it did not record.
    public let writer: String?

    /// The marker for the process calling this, read off `PersistentLog.source` so
    /// the two artefacts cannot disagree about who wrote what.
    public static var currentWriter: String { "<\(PersistentLog.source)>" }

    public init(raw: String,
                polished: String?,
                metrics: PolishMetrics,
                writer: String = PolishDebugEntry.currentWriter) {
        self.id = UUID()
        self.timestamp = Date()
        self.raw = raw
        self.polished = polished
        self.metrics = metrics
        self.writer = writer
    }
}

/// The on-disk half of the polish debug ring: one JSON Lines file in the App Group
/// container, and the primitives that read and write it.
///
/// The original sketch kept events in memory only on the assumption that
/// round-1 iteration would happen within a single session. Real-device testing
/// killed that assumption: an app kill (deliberate, or iOS terminating a
/// backgrounded extension host) wipes every event Pierre is trying to ship for
/// analysis — defeating the iteration loop. Persisting locally matches what
/// `PersistentLog` already does for debug logs.
///
/// ### Two writers, one destructive owner (#361 decision 8)
///
/// Since polish moved into the keyboard, both processes append here. Only DictusApp
/// prunes, rewrites, clears and exports, so every destructive operation stays
/// single-writer and the concurrency story does not change. The keyboard's whole
/// interaction with this file is `append`, which deliberately does not bootstrap:
/// a read of the seven-day window would pull the entire file into a process living
/// under a ~50 MB ceiling, which is the one thing the extension cannot afford.
///
/// Appends go through `NSFileCoordinator`, for the reason `PersistentLog` does:
/// `FileHandle(forWritingTo:)` seeks and writes as two steps, and two processes
/// doing that on the same file can interleave a line into the middle of another.
///
/// Privacy stance: `raw` and `polished` are user dictation text. They never
/// leave the device — the file lives in the App Group container, and the
/// export-to-share flow is explicitly user-triggered. Behavior is identical to
/// `PersistentLog`, which already stores transcription metadata in the same
/// container.
public enum PolishEventStore {

    public static let retentionPeriod: TimeInterval = 7 * 24 * 3600
    static let fileName = "polish_events.jsonl"

    public static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    // MARK: - Append (both processes)

    /// Append one event. Never reads the file, never prunes it, never allocates
    /// more than the one encoded line — the contract the keyboard depends on.
    public static func append(_ entry: PolishDebugEntry) {
        guard let url = fileURL,
              let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8),
              let payload = (json + "\n").data(using: .utf8) else { return }

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { coordURL in
            if !FileManager.default.fileExists(atPath: coordURL.path) {
                FileManager.default.createFile(atPath: coordURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: coordURL) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        }
    }

    // MARK: - Read and destructive operations (DictusApp only)

    /// Every decodable event in the file, optionally dropping those outside the
    /// retention window.
    public static func readAll(applyingRetention: Bool) -> [PolishDebugEntry] {
        guard let url = fileURL,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let cutoff = Date().addingTimeInterval(-retentionPeriod)
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
    public static func pruneOldEntries() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        var rewritten = ""
        for entry in readAll(applyingRetention: true) {
            guard let data = try? encoder.encode(entry),
                  let json = String(data: data, encoding: .utf8) else { continue }
            rewritten += json + "\n"
        }
        try? rewritten.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func clear() {
        guard let url = fileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Coding

    /// Encode and decode one line. Shared so the writer and the reader cannot
    /// drift on the date strategy, which is what would silently drop every event.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Where a `PolishService` sends the events it produces.
///
/// WHY a protocol rather than a direct call to `PolishEventStore` (#361): the two
/// processes need different behaviour on the same event. DictusApp keeps a memory
/// cache for its debug screen and owns retention, so it records through
/// `PolishMetricsRing`; the keyboard appends and forgets. The service does the
/// same work either way and does not know which side it is on.
public protocol PolishEventSink: Sendable {
    func record(_ entry: PolishDebugEntry) async
}

/// The keyboard's sink: straight to disk, nothing retained, nothing read.
public struct AppendOnlyPolishEventSink: PolishEventSink {
    public init() {}
    public func record(_ entry: PolishDebugEntry) async {
        PolishEventStore.append(entry)
    }
}
