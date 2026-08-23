// DictusCore/Tests/DictusCoreTests/Polish/PolishEventStoreTests.swift
// The polish ring has two writers since #361. These pin the coordination that makes
// decision 8's "only the app performs destructive operations" actually safe.

import XCTest
@testable import DictusCore

final class PolishEventStoreTests: XCTestCase {

    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("polish-events-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func entry(_ raw: String, ageDays: Double = 0) -> PolishDebugEntry {
        var e = PolishDebugEntry(
            raw: raw,
            polished: nil,
            metrics: PolishMetrics(
                engine: "apple-fm", mode: .natural, targetLanguage: .french,
                detectedLanguage: "fr", rawCharCount: raw.count, polishedCharCount: raw.count,
                latencyMs: 1, outcome: .success
            ),
            writer: "<KBD>"
        )
        if ageDays > 0 {
            // Re-encode with a backdated timestamp; the struct's `timestamp` is set at
            // init, and retention is the only thing that reads it.
            e = Self.backdated(e, byDays: ageDays)
        }
        return e
    }

    /// Round-trips an entry through JSON with its timestamp moved back, which is the
    /// only way to build an old event without a clock injection the type does not have.
    private static func backdated(_ entry: PolishDebugEntry, byDays days: Double) -> PolishDebugEntry {
        guard let data = try? PolishEventStore.encoder.encode(entry),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return entry
        }
        let formatter = ISO8601DateFormatter()
        object["timestamp"] = formatter.string(from: Date().addingTimeInterval(-days * 24 * 3600))
        guard let patched = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? PolishEventStore.decoder.decode(PolishDebugEntry.self, from: patched) else {
            return entry
        }
        return decoded
    }

    // MARK: - Basics

    func testAppendedEventsReadBackInOrder() {
        PolishEventStore.append(entry("un"), to: url)
        PolishEventStore.append(entry("deux"), to: url)
        let all = PolishEventStore.readAll(applyingRetention: false, from: url)
        XCTAssertEqual(all.map(\.raw), ["un", "deux"])
    }

    func testPruneDropsEntriesPastRetentionAndKeepsTheRest() {
        PolishEventStore.append(entry("vieux", ageDays: 9), to: url)
        PolishEventStore.append(entry("récent"), to: url)
        PolishEventStore.pruneOldEntries(at: url)
        XCTAssertEqual(
            PolishEventStore.readAll(applyingRetention: false, from: url).map(\.raw),
            ["récent"]
        )
    }

    func testClearEmptiesTheFile() {
        PolishEventStore.append(entry("un"), to: url)
        PolishEventStore.clear(at: url)
        XCTAssertTrue(PolishEventStore.readAll(applyingRetention: false, from: url).isEmpty)
    }

    // MARK: - The two-writer race

    /// The regression this coordination exists for: the keyboard appends while the app
    /// prunes. Before the fix the prune read, rewrote and installed a replacement
    /// without taking the coordinator, so an append landing in between was written to
    /// the file being replaced and disappeared with it.
    ///
    /// The assertion is deliberately "nothing is lost" rather than a fixed count: the
    /// two orders are both legitimate, and what must never happen is an append that
    /// leaves no trace.
    func testConcurrentAppendsSurviveAPrune() {
        for index in 0..<40 {
            PolishEventStore.append(entry("seed-\(index)"), to: url)
        }

        let appended = 40
        let group = DispatchGroup()
        let writer = DispatchQueue(label: "test.append")
        let pruner = DispatchQueue(label: "test.prune")

        writer.async(group: group) {
            for index in 0..<appended {
                PolishEventStore.append(self.entry("live-\(index)"), to: self.url)
            }
        }
        pruner.async(group: group) {
            for _ in 0..<8 {
                PolishEventStore.pruneOldEntries(at: self.url)
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success, "coordination deadlocked")

        let survivors = Set(PolishEventStore.readAll(applyingRetention: false, from: url).map(\.raw))
        let missing = (0..<appended).map { "live-\($0)" }.filter { !survivors.contains($0) }
        XCTAssertTrue(missing.isEmpty, "appends lost to a concurrent prune: \(missing)")
    }

    /// Same race against `clear()`, which replaces the file wholesale. An append that
    /// happens after the clear must survive it; one that happens before is legitimately
    /// gone. What must not happen is a torn or unreadable file.
    func testConcurrentAppendsAndClearsLeaveAReadableFile() {
        let group = DispatchGroup()
        DispatchQueue(label: "test.append2").async(group: group) {
            for index in 0..<40 {
                PolishEventStore.append(self.entry("live-\(index)"), to: self.url)
            }
        }
        DispatchQueue(label: "test.clear").async(group: group) {
            for _ in 0..<8 {
                PolishEventStore.clear(at: self.url)
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success, "coordination deadlocked")

        // Every line still decodes: no half-written record, no interleaved bytes.
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        let decoded = PolishEventStore.readAll(applyingRetention: false, from: url)
        XCTAssertEqual(decoded.count, lines.count, "a line failed to decode — the file tore")
    }
}
