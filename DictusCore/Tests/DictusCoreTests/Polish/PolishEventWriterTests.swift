// DictusCore/Tests/DictusCoreTests/Polish/PolishEventWriterTests.swift
// Tests for the writer marker on polish events (#361 decision 8) and for the
// backward compatibility the seven-day ring depends on.

import XCTest
@testable import DictusCore

final class PolishEventWriterTests: XCTestCase {

    private func metrics() -> PolishMetrics {
        PolishMetrics(
            engine: "apple-fm",
            mode: "natural",
            targetLanguage: .french,
            detectedLanguage: "fr",
            rawCharCount: 21,
            polishedCharCount: 23,
            latencyMs: 4_412,
            outcome: .engineFailed,
            failureReason: .rateLimited
        )
    }

    // MARK: - The marker

    /// The marker is stored spelled exactly as the persistent log writes it, so one
    /// grep answers "was the keyboard rate-limited" in either artefact.
    func testWriterIsStoredWithTheLogsAngleBrackets() {
        let entry = PolishDebugEntry(raw: "bonjour", polished: nil, metrics: metrics(), writer: "<KBD>")
        XCTAssertEqual(entry.writer, "<KBD>")
    }

    func testCurrentWriterFollowsThePersistentLogSource() {
        let previous = PersistentLog.source
        defer { PersistentLog.source = previous }

        PersistentLog.source = "KBD"
        XCTAssertEqual(PolishDebugEntry.currentWriter, "<KBD>")
        PersistentLog.source = "APP"
        XCTAssertEqual(PolishDebugEntry.currentWriter, "<APP>")
    }

    func testDefaultWriterIsTheCallingProcess() {
        let previous = PersistentLog.source
        defer { PersistentLog.source = previous }

        PersistentLog.source = "KBD"
        let entry = PolishDebugEntry(raw: "bonjour", polished: nil, metrics: metrics())
        XCTAssertEqual(entry.writer, "<KBD>")
    }

    // MARK: - Seven days of events written by older builds

    func testEntryRoundTripsThroughTheStoresCoding() throws {
        let entry = PolishDebugEntry(raw: "bonjour", polished: "Bonjour.", metrics: metrics(), writer: "<KBD>")
        let data = try PolishEventStore.encoder.encode(entry)
        let decoded = try PolishEventStore.decoder.decode(PolishDebugEntry.self, from: data)
        XCTAssertEqual(decoded.writer, "<KBD>")
        XCTAssertEqual(decoded.raw, "bonjour")
        XCTAssertEqual(decoded.polished, "Bonjour.")
        XCTAssertEqual(decoded.metrics.failureReason, .rateLimited)
    }

    /// An event persisted before polish could run in the keyboard carries no `writer`
    /// key. It must still decode — the ring holds seven days, and a build that
    /// dropped every pre-upgrade event would throw away the comparison the marker
    /// exists to make.
    func testEntryWithNoWriterKeyStillDecodes() throws {
        let entry = PolishDebugEntry(raw: "bonjour", polished: nil, metrics: metrics(), writer: "<APP>")
        let data = try PolishEventStore.encoder.encode(entry)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "writer")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try PolishEventStore.decoder.decode(PolishDebugEntry.self, from: legacy)
        XCTAssertNil(decoded.writer, "absent means 'not recorded then', never a guessed value")
        XCTAssertEqual(decoded.raw, "bonjour")
    }
}
