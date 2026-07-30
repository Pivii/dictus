// DictusCore/Sources/DictusCore/PersistentLog.swift
// File-based structured logging that persists in the App Group container.
// Readable even when the Xcode debugger disconnects (Signal 9).
import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Persistent file-based logger for debugging without Xcode console.
///
/// WHY this exists:
/// When the app is opened via URL scheme from the keyboard, iOS often kills the
/// debugger connection (Signal 9). os.log messages are lost. This logger writes
/// to a file in the App Group container that can be read later from the Settings
/// screen or from a subsequent debug session.
///
/// WHY App Group container (not Documents):
/// The log file needs to be accessible from both the main app and the keyboard
/// extension for cross-process debugging.
///
/// WHY NSFileCoordinator:
/// Both DictusApp and DictusKeyboard write to the same log file. Without
/// coordination, concurrent writes corrupt the file. NSFileCoordinator
/// serializes cross-process access via the App Group.
public enum PersistentLog {

    /// Process source tag — set once at app/extension launch.
    /// WHY static var (not auto-detected): Bundle.main.bundleIdentifier is
    /// unreliable in keyboard extensions (can return the host app's ID).
    public static var source: String = "?"

    /// Human-readable code revision marker, auto-injected at build time.
    ///
    /// The "Inject Git SHA into Info.plist" Xcode build phase writes `GitCommitSHA`
    /// (and `GitBranch`) into every target's built Info.plist on each build. This
    /// computed property reads that value at runtime, so every log export carries
    /// the exact commit the binary was built from with zero manual discipline.
    ///
    /// Fallbacks: returns "unknown" in environments where the Info.plist keys are
    /// missing (unit tests linking DictusCore standalone, Swift Package previews,
    /// or a build done outside the Xcode build phase).
    public static var codeRevision: String {
        let info = Bundle.main.infoDictionary
        let sha = info?["GitCommitSHA"] as? String ?? "unknown"
        if let branch = info?["GitBranch"] as? String, !branch.isEmpty, branch != "unknown" {
            return "\(sha)@\(branch)"
        }
        return sha
    }

    // MARK: - Constants

    /// Maximum log file size in bytes (~1MB = ~7000 lines at ~150 bytes/line).
    ///
    /// WHY size-based (not line-based): Checking file size is O(1) via FileManager
    /// attributes, while counting lines requires reading the entire file O(n).
    /// The old line-counting approach caused write amplification on every log() call.
    ///
    /// WHY 1MB and not the old 200KB (#255): 200KB retained roughly 4 minutes of a
    /// real session, so a device-validation export routinely lost the very evidence
    /// it was taken for. After the per-instance duplicate emissions were removed, a
    /// dictation session costs ~36KB/minute, which puts a 30-minute session at
    /// ~1.08MB.
    ///
    /// WHY not larger: `coordinatedTrim` loads the whole file into memory when it
    /// fires, and it fires inside the keyboard extension too, which lives under a
    /// ~50MB ceiling. At 1MB the transient allocation is ~1.7MB, negligible. At
    /// several MB the measuring instrument would start adding memory pressure to
    /// the very process whose jetsam kills it exists to diagnose.
    static let maxFileSize: UInt64 = 1_000_000

    /// Low-water mark the trim cuts down to: 70% of `maxFileSize`.
    ///
    /// WHY a low-water mark at all (#255): the old trim kept exactly `maxFileSize`
    /// trailing bytes and then dropped the partial first line, leaving the file
    /// ~150 bytes *under* the cap. The next single line pushed it over again, so
    /// once saturated — i.e. permanently — every logged line triggered a full file
    /// read plus a full atomic rewrite inside a cross-process `.forReplacing`
    /// coordination block, contended between DictusApp and DictusKeyboard.
    /// Cutting back to 70% means a rewrite happens once per ~300KB written instead,
    /// roughly once per 2000 lines.
    static let trimTargetSize: UInt64 = 700_000

    /// Retention period in seconds (7 days).
    /// WHY 7 days: Keeps logs relevant for debugging recent issues while preventing
    /// unbounded growth. Pruning happens before export (not on every write) because
    /// date parsing is more expensive than the O(1) size check.
    static let retentionPeriod: TimeInterval = 7 * 24 * 3600

    private static let fileName = "dictus_debug.log"

    /// Serial queue for ordering writes within a single process.
    /// Cross-process safety is handled by NSFileCoordinator.
    private static let writeQueue = DispatchQueue(label: "com.pivi.dictus.persistentlog", qos: .utility)

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    // MARK: - Public API (Structured)

    /// Log a structured event to the persistent file.
    /// This is the primary public API — callers pass typed LogEvent cases.
    public static func log(_ event: LogEvent) {
        // Timestamp and payload are built on the calling thread so the line carries
        // the time of the event, not the time the queued write happens to run.
        let timestamp = LogEvent.timestamp()
        let payload = event.payload()

        // Forward to os.log for Xcode console visibility.
        // WHY every occurrence, including collapsed ones: os.log is a live stream
        // with its own ring buffer, not the budgeted file. Suppressing there would
        // only make the Xcode console lie.
        forwardToOSLog(event)

        guard let url = fileURL else { return }

        writeQueue.async {
            appendCollapsing(payload: payload, timestamp: timestamp, to: url)
        }
    }

    /// Read the full log contents.
    public static func read() -> String {
        guard let url = fileURL else { return "(no logs)" }
        flushPendingRepeats()
        return coordinatedRead(from: url)
    }

    /// Clear all logs.
    public static func clear() {
        guard let url = fileURL else { return }
        writeQueue.sync { resetCollapseState() }
        coordinatedWrite("", to: url)
    }

    /// Remove log entries older than retentionPeriod (7 days).
    /// Called before export to keep exported logs relevant and file size manageable.
    /// WHY not on every write: Date parsing is more expensive than size check.
    /// Pruning before export is sufficient -- size-based trim handles per-write limits.
    public static func pruneOldEntries() {
        guard let url = fileURL else { return }
        pruneOldEntries(url: url, cutoffDate: Date().addingTimeInterval(-retentionPeriod))
    }

    /// Internal pruning with injectable cutoff date (shared by public API and tests).
    static func pruneOldEntries(url: URL, cutoffDate: Date) {
        let formatter = ISO8601DateFormatter()

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            guard let content = try? String(contentsOf: coordURL, encoding: .utf8) else { return }
            let filtered = content
                .components(separatedBy: "\n")
                .filter { line in
                    // Log format: [2026-03-27T10:30:00Z] ...
                    guard line.count > 2,
                          let closeBracket = line.firstIndex(of: "]"),
                          line.first == "[" else {
                        return true // keep unparseable lines
                    }
                    let dateStr = String(line[line.index(after: line.startIndex)..<closeBracket])
                    guard let date = formatter.date(from: dateStr) else {
                        return true // keep unparseable dates
                    }
                    return date > cutoffDate
                }
                .joined(separator: "\n")
            try? filtered.write(to: coordURL, atomically: true, encoding: .utf8)
        }
    }

    /// Export log with device header for sharing.
    /// Returns header + full log content.
    #if canImport(UIKit)
    public static func exportContent() -> String {
        pruneOldEntries()  // Remove entries older than 7 days before export
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let activeModel = AppGroup.defaults.string(forKey: SharedKeys.activeModel) ?? "none"

        let content = read()
        let header = buildExportHeader(
            iosVersion: iosVersion,
            appVersion: appVersion,
            buildNumber: buildNumber,
            deviceModel: deviceModel,
            activeModel: activeModel,
            codeRevision: codeRevision,
            retainedWindow: retainedWindow(of: content)
        )
        return header + content
    }
    #endif

    /// Testable header builder — accepts injected values so tests don't need UIDevice.
    static func buildExportHeader(
        iosVersion: String,
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        activeModel: String,
        codeRevision: String = PersistentLog.codeRevision,
        retainedWindow: String = "unknown"
    ) -> String {
        "Dictus Debug Log\n"
            + "iOS \(iosVersion) | App \(appVersion) (\(buildNumber)) | rev \(codeRevision) | \(deviceModel) | Model: \(activeModel)\n"
            + "Window: \(retainedWindow)\n"
            + "---\n"
    }

    /// First timestamp, last timestamp, line count and byte size of the retained
    /// file, as a single header line.
    ///
    /// WHY the export states its own window (#255): the file is a rotating buffer,
    /// so an export can silently be missing the event it was taken for. During the
    /// #249 validation the whole session had rotated out and nothing in the file
    /// said so, which made the evidence unverifiable rather than merely absent.
    static func retainedWindow(of content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard let first = lines.first, let last = lines.last else {
            return "empty"
        }
        let firstStamp = leadingTimestamp(of: first) ?? "?"
        let lastStamp = leadingTimestamp(of: last) ?? "?"
        return "\(firstStamp) to \(lastStamp) | \(lines.count) lines | \(content.utf8.count) bytes"
    }

    /// The `[...]` timestamp a log line starts with, or nil for an unparseable line.
    private static func leadingTimestamp(of line: Substring) -> String? {
        guard line.first == "[", let closeBracket = line.firstIndex(of: "]") else { return nil }
        return String(line[line.index(after: line.startIndex)..<closeBracket])
    }

    // MARK: - Legacy API (Deprecated)

    /// Legacy free-text log method. Use `log(_ event: LogEvent)` instead.
    @available(*, deprecated, message: "Use log(_ event: LogEvent) instead")
    public static func log(_ message: String, function: String = #function) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(function): \(message)\n"

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("\(message, privacy: .public)")
        }

        guard let url = fileURL else { return }

        writeQueue.async {
            // Close any open collapsed run first, otherwise its summary line would
            // land after this entry and report a run that had already ended.
            let text = (takePendingRepeatLine() ?? "") + entry
            resetCollapseState()
            coordinatedAppend(text, to: url)
            coordinatedTrim(url: url)
        }
    }

    // MARK: - Consecutive Duplicate Collapsing

    /// Payload of the last line this process actually wrote, and the run of
    /// identical payloads suppressed since.
    ///
    /// WHY plain statics with no lock: every read and write below happens on
    /// `writeQueue`, which is serial. The queue is the synchronisation.
    private static var lastPayload: String?
    private static var suppressedRepeatCount = 0
    private static var suppressedRepeatLastTimestamp = ""

    /// Append `payload`, collapsing a run of identical consecutive payloads into
    /// the first line plus a closing line carrying `repeated=N`.
    ///
    /// WHY the first occurrence is written immediately rather than held back until
    /// the run ends (#255): this log exists to survive a process being killed
    /// without warning. Buffering the first line would lose the event entirely
    /// whenever iOS terminates the extension mid-run, which is precisely the
    /// situation the file is read for afterwards. The price is one extra summary
    /// line per collapsed run — a run of 9 costs 2 lines instead of 9.
    ///
    /// Only *consecutive* payloads collapse: any different line closes the run, so
    /// two identical lines separated by a third are both written in full. Payloads
    /// that differ in any parameter are different payloads and never merge.
    private static func appendCollapsing(payload: String, timestamp: String, to url: URL) {
        if payload == lastPayload {
            suppressedRepeatCount += 1
            suppressedRepeatLastTimestamp = timestamp
            return
        }

        // takePendingRepeatLine() reads lastPayload, so it must run before the
        // assignment below replaces it.
        var text = takePendingRepeatLine() ?? ""
        text += "[\(timestamp)] \(payload)\n"
        lastPayload = payload

        coordinatedAppend(text, to: url)
        coordinatedTrim(url: url)
    }

    /// The closing line for an open run, or nil when no duplicate was suppressed.
    /// Consumes the counter, so calling it twice never double-reports.
    ///
    /// The line repeats the collapsed payload verbatim and carries the timestamp of
    /// the *last* occurrence, so the file holds both ends of the run: the first
    /// timestamp on the original line, the last one here.
    private static func takePendingRepeatLine() -> String? {
        defer { suppressedRepeatCount = 0 }
        guard suppressedRepeatCount > 0, let payload = lastPayload else { return nil }
        return "[\(suppressedRepeatLastTimestamp)] \(payload) repeated=\(suppressedRepeatCount)\n"
    }

    /// Write out an open repeat run so a reader never sees a truncated count.
    /// Called before every read and export.
    static func flushPendingRepeats() {
        guard let url = fileURL else { return }
        writeQueue.sync {
            guard let line = takePendingRepeatLine() else { return }
            coordinatedAppend(line, to: url)
            coordinatedTrim(url: url)
        }
    }

    /// Forget the current run. Must be called on `writeQueue`.
    private static func resetCollapseState() {
        lastPayload = nil
        suppressedRepeatCount = 0
    }

    // MARK: - NSFileCoordinator Helpers

    private static func coordinatedAppend(_ text: String, to url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { coordURL in
            if !FileManager.default.fileExists(atPath: coordURL.path) {
                FileManager.default.createFile(atPath: coordURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: coordURL) else { return }
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    private static func coordinatedRead(from url: URL) -> String {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result = "(no logs)"

        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordURL in
            if let content = try? String(contentsOf: coordURL, encoding: .utf8) {
                result = content
            }
        }
        return result
    }

    private static func coordinatedWrite(_ text: String, to url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            try? text.write(to: coordURL, atomically: true, encoding: .utf8)
        }
    }

    /// Rewrite the file down to `trimTargetSize` when it exceeds `maxFileSize`.
    /// Returns whether a rewrite actually happened, so tests can count rewrites
    /// rather than infer them.
    @discardableResult
    private static func coordinatedTrim(url: URL) -> Bool {
        // O(1) size check -- no file read needed
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else { return false }

        // Only read file when we actually need to trim
        var didTrim = false
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            guard let data = try? Data(contentsOf: coordURL) else { return }
            // Re-check under coordination: the other process may have trimmed the
            // file between the stat above and this block acquiring the lock.
            guard UInt64(data.count) > maxFileSize else { return }
            try? trimmedTail(of: data).write(to: coordURL)
            didTrim = true
        }
        return didTrim
    }

    /// The trailing `trimTargetSize` bytes of `data`, starting at a line boundary.
    ///
    /// The partial first line is dropped so a trimmed file always begins with a
    /// whole log line — readers (and `pruneOldEntries`) parse line by line and a
    /// half line at the top corrupts the first entry.
    private static func trimmedTail(of data: Data) -> Data {
        let tail = data.suffix(Int(trimTargetSize))
        guard let newlineIndex = tail.firstIndex(of: UInt8(ascii: "\n")) else { return tail }
        return tail.suffix(from: tail.index(after: newlineIndex))
    }

    // MARK: - os.log Forwarding

    private static func forwardToOSLog(_ event: LogEvent) {
        guard #available(iOS 14.0, *) else { return }

        let logger: Logger
        switch event.subsystem {
        case .dictation, .audio, .transcription, .model, .lifecycle:
            logger = DictusLogger.app
        case .keyboard:
            logger = DictusLogger.keyboard
        }

        // WHY privacy: .public — LogEvent is privacy-safe by design (no user text,
        // no keystrokes). Without .public, os.log masks ALL interpolated values as
        // <private> in the Xcode console, making debugging impossible.
        let msg = "\(event.name) \(event.message)"
        switch event.level {
        case .debug: logger.debug("\(msg, privacy: .public)")
        case .info: logger.info("\(msg, privacy: .public)")
        case .warning: logger.warning("\(msg, privacy: .public)")
        case .error: logger.error("\(msg, privacy: .public)")
        }
    }

    // MARK: - Test Helpers

    /// Append text to an arbitrary URL (for unit tests with temp files).
    static func appendForTesting(_ text: String, to url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    }

    /// Read from an arbitrary URL (for unit tests with temp files).
    static func readForTesting(from url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "(no logs)"
    }

    /// Check if a file exceeds maxFileSize (for unit tests).
    static func shouldTrimForTesting(url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return false }
        return size > maxFileSize
    }

    /// Trim an arbitrary URL using size-based logic (for unit tests).
    /// Returns whether the file was actually rewritten.
    @discardableResult
    static func trimBySizeForTesting(url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else { return false }

        guard let data = try? Data(contentsOf: url) else { return false }
        try? trimmedTail(of: data).write(to: url)
        return true
    }

    /// Append through the duplicate-collapsing path against an arbitrary URL
    /// (for unit tests). Runs synchronously on the write queue so the test can
    /// assert on the file straight after.
    static func appendCollapsingForTesting(payload: String, timestamp: String, to url: URL) {
        writeQueue.sync { appendCollapsing(payload: payload, timestamp: timestamp, to: url) }
    }

    /// Flush an open collapsed run to an arbitrary URL (for unit tests).
    static func flushPendingRepeatsForTesting(to url: URL) {
        writeQueue.sync {
            guard let line = takePendingRepeatLine() else { return }
            coordinatedAppend(line, to: url)
        }
    }

    /// Forget the current collapsed run (for unit tests, which share process state).
    static func resetCollapseStateForTesting() {
        writeQueue.sync { resetCollapseState() }
    }

    /// Expose trimTargetSize for test assertions.
    static var testableTrimTargetSize: UInt64 { trimTargetSize }

    /// Prune old entries from an arbitrary URL with custom cutoff (for unit tests).
    static func pruneOldEntriesForTesting(url: URL, cutoffDate: Date) {
        pruneOldEntries(url: url, cutoffDate: cutoffDate)
    }

    /// Clear an arbitrary URL (for unit tests).
    static func clearForTesting(url: URL) {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Expose maxFileSize for test assertions.
    static var testableMaxFileSize: UInt64 { maxFileSize }
}
