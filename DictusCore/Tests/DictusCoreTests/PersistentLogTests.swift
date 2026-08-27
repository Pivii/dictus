// DictusCore/Tests/DictusCoreTests/PersistentLogTests.swift
// Tests for the evolved PersistentLog with structured API and rotation.
import XCTest
@testable import DictusCore

final class PersistentLogTests: XCTestCase {

    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        // Use a temp file for isolation -- avoids polluting App Group
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dictus_\(UUID().uuidString).log")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    // MARK: - Structured logging

    func testLogEventWritesFormattedOutput() {
        let event = LogEvent.dictationStarted(fromURL: true, appState: "active", engineRunning: false)
        PersistentLog.appendForTesting(event.formatted() + "\n", to: tempFileURL)

        let content = PersistentLog.readForTesting(from: tempFileURL)
        XCTAssertTrue(content.contains("dictationStarted"))
        XCTAssertTrue(content.contains("fromURL=true"))
        XCTAssertTrue(content.contains("[dictation]"))
        XCTAssertTrue(content.contains("INFO"))
    }

    func testLogEventWritesMultipleEntries() {
        PersistentLog.appendForTesting(
            LogEvent.audioEngineStarted.formatted() + "\n", to: tempFileURL)
        PersistentLog.appendForTesting(
            LogEvent.audioEngineStopped.formatted() + "\n", to: tempFileURL)

        let content = PersistentLog.readForTesting(from: tempFileURL)
        XCTAssertTrue(content.contains("audioEngineStarted"))
        XCTAssertTrue(content.contains("audioEngineStopped"))
    }

    // MARK: - Size-based trim

    func testMaxFileSizeIs1MB() {
        XCTAssertEqual(PersistentLog.testableMaxFileSize, 1_000_000)
    }

    /// The low-water mark is what stops the trim rewriting the file on every line.
    func testTrimTargetIsBelowMaxFileSize() {
        XCTAssertLessThan(PersistentLog.testableTrimTargetSize, PersistentLog.testableMaxFileSize)
        XCTAssertEqual(PersistentLog.testableTrimTargetSize, 850_000)
    }

    func testShouldTrimReturnsFalseUnderLimit() {
        // Write ~500KB (well under the 1MB limit)
        let smallContent = String(repeating: "A", count: 500_000) + "\n"
        try? smallContent.write(to: tempFileURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(PersistentLog.shouldTrimForTesting(url: tempFileURL))
    }

    func testShouldTrimReturnsTrueOverLimit() {
        // Write ~1.2MB (over the 1MB limit)
        let largeContent = String(repeating: "B", count: 1_200_000) + "\n"
        try? largeContent.write(to: tempFileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(PersistentLog.shouldTrimForTesting(url: tempFileURL))
    }

    func testTrimBySizeKeepsSuffix() {
        // Write ~1.5MB of numbered lines so we can verify the LAST ~850KB is kept
        var lines: [String] = []
        for i in 1...15000 {
            lines.append("line \(i) " + String(repeating: "X", count: 90))  // ~100 bytes each
        }
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(PersistentLog.trimBySizeForTesting(url: tempFileURL))

        let trimmed = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        let resultSize = trimmed.utf8.count
        // Should be roughly trimTargetSize (850KB), minus the dropped partial first line
        XCTAssertLessThanOrEqual(resultSize, 850_000, "Trimmed file should be ~850KB or less")
        XCTAssertGreaterThan(resultSize, 750_000, "Trimmed file should retain significant content")
        // Last line should be the very last line we wrote
        XCTAssertTrue(trimmed.contains("line 15000"), "Should keep the most recent (last) lines")
        // First lines should be gone
        XCTAssertFalse(trimmed.contains("line 1 "), "Should have removed the oldest lines")
    }

    /// A trimmed file must always start on a line boundary, never mid-line.
    func testTrimBySizeStartsAtLineBoundary() {
        let line = "PREFIX " + String(repeating: "Y", count: 92) + "\n"  // 100 bytes
        let content = String(repeating: line, count: 15_000)             // 1.5MB
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        PersistentLog.trimBySizeForTesting(url: tempFileURL)

        let trimmed = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(trimmed.hasPrefix("PREFIX "), "Trimmed file must begin with a whole line")
    }

    func testNoTrimWhenUnderSizeLimit() {
        let content = (1...100).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(PersistentLog.trimBySizeForTesting(url: tempFileURL))

        let result = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        let resultLines = result.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(resultLines.count, 100)
    }

    /// Issue #255: once saturated, the old trim rewrote the whole file on every
    /// single logged line. With an 85% low-water mark, a rewrite must cost at least
    /// ~15% of the cap in freshly written bytes.
    func testSaturatedFileRewritesOncePerLowWaterGap() {
        let line = String(repeating: "Z", count: 99) + "\n"  // 100 bytes
        // Start just over the cap so the very first append is already saturated.
        try? String(repeating: line, count: 10_001)
            .write(to: tempFileURL, atomically: true, encoding: .utf8)

        // Write 600KB one line at a time, trimming after each append like log() does.
        var rewrites = 0
        let appendedLines = 6000
        for _ in 0..<appendedLines {
            PersistentLog.appendForTesting(line, to: tempFileURL)
            if PersistentLog.trimBySizeForTesting(url: tempFileURL) {
                rewrites += 1
            }
        }

        // 600KB written across a 150KB low-water gap: 4 rewrites, plus the initial
        // one that brings the pre-saturated file down. The point of the assertion is
        // the order of magnitude: it used to be one rewrite per line (6000).
        XCTAssertLessThanOrEqual(rewrites, 8, "Expected a handful of rewrites, got \(rewrites)")
        XCTAssertGreaterThan(rewrites, 0, "The file was saturated, it must have been trimmed")
        XCTAssertLessThan(
            Double(rewrites) / Double(appendedLines), 0.005,
            "Rewrites per logged line must be near zero"
        )
    }

    // MARK: - Consecutive duplicate collapsing

    func testIdenticalConsecutiveLinesCollapse() {
        PersistentLog.resetCollapseStateForTesting()
        let payload = "INFO    [dictation] <KB> statusChanged from=idle to=requested source=keyboardState"

        for i in 0..<9 {
            PersistentLog.appendCollapsingForTesting(
                payload: payload, timestamp: "2026-07-31T10:00:0\(i)Z", to: tempFileURL
            )
        }
        PersistentLog.flushPendingRepeatsForTesting(to: tempFileURL)

        let lines = PersistentLog.readForTesting(from: tempFileURL)
            .components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2, "9 identical lines should collapse to first + summary")
        XCTAssertTrue(lines[0].hasPrefix("[2026-07-31T10:00:00Z]"), "First occurrence keeps its timestamp")
        XCTAssertFalse(lines[0].contains("repeated="), "The first occurrence is not a summary")
        XCTAssertTrue(lines[1].hasSuffix("repeated=8"), "Summary reports the 8 suppressed repeats")
        XCTAssertTrue(lines[1].hasPrefix("[2026-07-31T10:00:08Z]"), "Summary carries the last timestamp")
        XCTAssertTrue(lines[1].contains("statusChanged from=idle to=requested"), "Summary repeats the payload")
    }

    func testNonConsecutiveIdenticalLinesAreNotMerged() {
        PersistentLog.resetCollapseStateForTesting()
        let payloadA = "INFO    [dictation] <KB> overlayShown status=recording"
        let payloadB = "INFO    [dictation] <KB> overlayHidden status=idle"

        PersistentLog.appendCollapsingForTesting(payload: payloadA, timestamp: "t1", to: tempFileURL)
        PersistentLog.appendCollapsingForTesting(payload: payloadB, timestamp: "t2", to: tempFileURL)
        PersistentLog.appendCollapsingForTesting(payload: payloadA, timestamp: "t3", to: tempFileURL)

        let lines = PersistentLog.readForTesting(from: tempFileURL)
            .components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 3, "A different line between two identical ones breaks the run")
        XCTAssertFalse(lines.contains { $0.contains("repeated=") }, "Nothing was suppressed")
    }

    func testLinesDifferingInOneParameterAreNotMerged() {
        PersistentLog.resetCollapseStateForTesting()

        PersistentLog.appendCollapsingForTesting(
            payload: "DEBUG   [keyboard] <KB> waveformHeartbeat renderTick=1 energyCount=40",
            timestamp: "t1", to: tempFileURL
        )
        PersistentLog.appendCollapsingForTesting(
            payload: "DEBUG   [keyboard] <KB> waveformHeartbeat renderTick=2 energyCount=40",
            timestamp: "t2", to: tempFileURL
        )

        let lines = PersistentLog.readForTesting(from: tempFileURL)
            .components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2, "Payloads differing in any parameter are different payloads")
    }

    func testCollapsedRunIsClosedByTheNextDifferentLine() {
        PersistentLog.resetCollapseStateForTesting()
        let repeated = "DEBUG   [keyboard] <KB> diagnosticProbe component=X instanceID=Y action=Z details="
        let other = "INFO    [audio] <KB> audioEngineStarted"

        PersistentLog.appendCollapsingForTesting(payload: repeated, timestamp: "t1", to: tempFileURL)
        PersistentLog.appendCollapsingForTesting(payload: repeated, timestamp: "t2", to: tempFileURL)
        PersistentLog.appendCollapsingForTesting(payload: repeated, timestamp: "t3", to: tempFileURL)
        PersistentLog.appendCollapsingForTesting(payload: other, timestamp: "t4", to: tempFileURL)

        let lines = PersistentLog.readForTesting(from: tempFileURL)
            .components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasSuffix("repeated=2"), "Summary lands before the line that closed the run")
        XCTAssertTrue(lines[2].contains("audioEngineStarted"))
    }

    /// The formatted line must be exactly the timestamp plus the payload, otherwise
    /// the collapsed summary and the original line would not be comparable.
    func testFormattedIsTimestampPlusPayload() {
        let event = LogEvent.audioEngineStarted
        let formatted = event.formatted()
        XCTAssertTrue(formatted.hasSuffix(event.payload()))
        XCTAssertTrue(formatted.hasPrefix("["))
    }

    // MARK: - Date-based retention

    func testPruneOldEntriesRemovesOldLines() {
        let formatter = ISO8601DateFormatter()
        let oldDate = Date().addingTimeInterval(-8 * 24 * 3600)  // 8 days ago
        let recentDate = Date().addingTimeInterval(-1 * 24 * 3600)  // 1 day ago
        let oldTimestamp = formatter.string(from: oldDate)
        let recentTimestamp = formatter.string(from: recentDate)

        let content = """
        [\(oldTimestamp)] INFO   [lifecycle] <APP> appLaunched old entry
        [\(recentTimestamp)] INFO   [lifecycle] <APP> appLaunched recent entry
        """
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        // Prune with 7-day cutoff
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        PersistentLog.pruneOldEntriesForTesting(url: tempFileURL, cutoffDate: cutoff)

        let result = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(result.contains("old entry"), "Old entries should be removed")
        XCTAssertTrue(result.contains("recent entry"), "Recent entries should be kept")
    }

    func testPruneOldEntriesKeepsRecentLines() {
        let formatter = ISO8601DateFormatter()
        let recent1 = Date().addingTimeInterval(-1 * 24 * 3600)
        let recent2 = Date().addingTimeInterval(-3 * 24 * 3600)
        let ts1 = formatter.string(from: recent1)
        let ts2 = formatter.string(from: recent2)

        let content = """
        [\(ts1)] INFO   [lifecycle] <APP> appLaunched entry1
        [\(ts2)] INFO   [lifecycle] <APP> appLaunched entry2
        """
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        PersistentLog.pruneOldEntriesForTesting(url: tempFileURL, cutoffDate: cutoff)

        let result = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(result.contains("entry1"), "Recent entry1 should be kept")
        XCTAssertTrue(result.contains("entry2"), "Recent entry2 should be kept")
    }

    func testPruneOldEntriesKeepsUnparseableLines() {
        let formatter = ISO8601DateFormatter()
        let oldDate = Date().addingTimeInterval(-8 * 24 * 3600)
        let oldTimestamp = formatter.string(from: oldDate)

        let content = """
        [\(oldTimestamp)] INFO   [lifecycle] <APP> appLaunched old entry
        This line has no timestamp format
        Another unparseable line
        """
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        PersistentLog.pruneOldEntriesForTesting(url: tempFileURL, cutoffDate: cutoff)

        let result = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(result.contains("old entry"), "Old entry should be removed")
        XCTAssertTrue(result.contains("This line has no timestamp"), "Unparseable lines should be kept")
        XCTAssertTrue(result.contains("Another unparseable"), "Unparseable lines should be kept")
    }

    // MARK: - Code revision

    /// Issue #344: the revision comes from a generated `DictusBuildInfo.plist`, so
    /// the happy path is "the build phase ran and the file is in the bundle".
    func testCodeRevisionReadsGeneratedBuildInfo() throws {
        let url = try writeBuildInfo(["GitCommitSHA": "3e9bdda", "GitBranch": "fix/344-git-sha-injection"])

        XCTAssertEqual(
            PersistentLog.codeRevision(readingBuildInfoAt: url),
            "3e9bdda@fix/344-git-sha-injection")
    }

    /// A detached build stamps `GitBranch = HEAD`, which is meaningful, but a branch
    /// that is empty or literally "unknown" would only add noise to the header.
    func testCodeRevisionDropsAnUninformativeBranch() throws {
        let noBranch = try writeBuildInfo(["GitCommitSHA": "3e9bdda"])
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: noBranch), "3e9bdda")

        let unknownBranch = try writeBuildInfo(["GitCommitSHA": "3e9bdda", "GitBranch": "unknown"])
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: unknownBranch), "3e9bdda")

        let emptyBranch = try writeBuildInfo(["GitCommitSHA": "3e9bdda", "GitBranch": ""])
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: emptyBranch), "3e9bdda")
    }

    /// A build with no revision information has to keep announcing itself. Never a
    /// crash, never an invented sha, never a stale one carried over.
    func testCodeRevisionFallsBackToUnknown() throws {
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: nil), "unknown")

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent_\(UUID().uuidString).plist")
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: missing), "unknown")

        let garbage = FileManager.default.temporaryDirectory
            .appendingPathComponent("garbage_\(UUID().uuidString).plist")
        try Data("not a plist".utf8).write(to: garbage)
        addTeardownBlock { try? FileManager.default.removeItem(at: garbage) }
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: garbage), "unknown")

        let noSHA = try writeBuildInfo(["GitBranch": "develop"])
        XCTAssertEqual(PersistentLog.codeRevision(readingBuildInfoAt: noSHA), "unknown@develop")
    }

    /// Acceptance criterion of #344: a build outside the Xcode build phase — this
    /// very test bundle — reports "unknown" rather than crashing or guessing.
    /// `Bundle.main` here is the XCTest runner, which carries no build info.
    func testCodeRevisionIsUnknownOutsideTheXcodeBuildPhase() {
        XCTAssertEqual(PersistentLog.codeRevision(in: .main), "unknown")
        XCTAssertEqual(PersistentLog.codeRevision, "unknown")
    }

    /// Write a build-info plist to a temp file and register it for cleanup.
    private func writeBuildInfo(_ contents: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("buildinfo_\(UUID().uuidString).plist")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    // MARK: - Export header

    func testExportHeaderFormat() {
        // Use the testable helper with injected values
        let header = PersistentLog.buildExportHeader(
            iosVersion: "18.2",
            appVersion: "1.2",
            buildNumber: "42",
            deviceModel: "iPhone",
            activeModel: "base"
        )

        XCTAssertTrue(header.hasPrefix("Dictus Debug Log\n"))
        XCTAssertTrue(header.contains("iOS 18.2"))
        XCTAssertTrue(header.contains("App 1.2 (42)"))
        XCTAssertTrue(header.contains("iPhone"))
        XCTAssertTrue(header.contains("Model: base"))
        XCTAssertTrue(header.contains("---"))
    }

    /// Issue #255: a reader must be able to tell from the header alone whether the
    /// evidence they are looking for was rotated out of the retained window.
    func testExportHeaderStatesRetainedWindow() {
        let header = PersistentLog.buildExportHeader(
            iosVersion: "18.2",
            appVersion: "1.2",
            buildNumber: "42",
            deviceModel: "iPhone",
            activeModel: "base",
            codeRevision: "abc123",
            retainedWindow: "2026-07-31T07:46:52Z to 2026-07-31T08:16:11Z | 6841 lines | 987654 bytes"
        )

        XCTAssertTrue(header.contains("Window: 2026-07-31T07:46:52Z to 2026-07-31T08:16:11Z"))
        XCTAssertTrue(header.contains("6841 lines"))
        XCTAssertTrue(header.hasSuffix("---\n"), "Content must still start right after the separator")
    }

    func testRetainedWindowReportsFirstLastAndCount() {
        let content = """
        [2026-07-31T07:46:52Z] INFO    [lifecycle] <APP> appLaunched version=1.7
        [2026-07-31T07:48:00Z] INFO    [audio] <APP> audioEngineStarted
        [2026-07-31T08:16:11Z] INFO    [lifecycle] <APP> appDidEnterBackground

        """

        let window = PersistentLog.retainedWindow(of: content)

        XCTAssertTrue(window.hasPrefix("2026-07-31T07:46:52Z to 2026-07-31T08:16:11Z"), window)
        XCTAssertTrue(window.contains("3 lines"), window)
        XCTAssertTrue(window.contains("\(content.utf8.count) bytes"), window)
    }

    func testRetainedWindowOnEmptyContent() {
        XCTAssertEqual(PersistentLog.retainedWindow(of: ""), "empty")
    }

    func testExportHeaderWithMissingValues() {
        let header = PersistentLog.buildExportHeader(
            iosVersion: "?",
            appVersion: "?",
            buildNumber: "?",
            deviceModel: "?",
            activeModel: "none"
        )

        XCTAssertTrue(header.contains("Model: none"))
    }

    // MARK: - Clear

    func testClearRemovesContent() {
        let content = "some log content\n"
        try? content.write(to: tempFileURL, atomically: true, encoding: .utf8)

        PersistentLog.clearForTesting(url: tempFileURL)

        let result = (try? String(contentsOf: tempFileURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(result.isEmpty)
    }
}
