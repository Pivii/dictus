// DictusApp/Views/DebugLogView.swift
// Displays persistent debug logs from App Group file with color-coded entries.
import SwiftUI
import DictusCore

/// A single parsed log entry from the persistent log file.
///
/// WHY parse into a struct instead of displaying raw text:
/// Structured entries allow color-coding by level, filtering by subsystem,
/// and a cleaner visual layout with distinct timestamp/level/message columns.
private struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: String     // Time-only portion (HH:mm:ss)
    let level: String         // DEBUG, INFO, WARNING, ERROR
    let subsystem: String     // dictation, audio, etc.
    let eventName: String     // e.g. dictationStarted
    let params: String        // key=value pairs (may be empty)

    /// Color for the level indicator, matching Dictus design language.
    var levelColor: Color {
        switch level.trimmingCharacters(in: .whitespaces).lowercased() {
        case "error":   return .red
        case "warning": return .orange
        case "info":    return .accentColor
        case "debug":   return .secondary
        default:        return .primary
        }
    }

    /// SF Symbol icon for the level.
    var levelIcon: String {
        switch level.trimmingCharacters(in: .whitespaces).lowercased() {
        case "error":   return "exclamationmark.triangle.fill"
        case "warning": return "exclamationmark.circle.fill"
        case "info":    return "info.circle.fill"
        case "debug":   return "ant.circle.fill"
        default:        return "circle.fill"
        }
    }
}

/// Displays persistent debug logs that survive debugger disconnection.
///
/// WHY this view exists:
/// When the app is opened via URL scheme from the keyboard, iOS often kills
/// the Xcode debugger (Signal 9). os.log messages are lost. This view reads
/// from a persistent log file in the App Group container, allowing the user
/// to check what happened after the fact.
///
/// Color-coded by log level with auto-scroll to newest entry.
struct DebugLogView: View {
    /// The complete retained file. Backs Copy, which must never be bounded.
    @State private var logContent = ""
    @State private var entries: [LogEntry] = []
    /// How many older lines the display dropped, so the screen can say so.
    @State private var hiddenLineCount = 0
    @State private var isLoading = false

    /// Identifies the most recently started reload.
    ///
    /// WHY (#255): the read moved off the main thread, so two reloads can now be
    /// in flight at once — a pull-to-refresh returns immediately and Clear Logs
    /// starts its own. Without this token the slower completion wins on arrival
    /// order alone, so clearing the log while a reload is still reading puts the
    /// old content straight back on screen. Only the newest reload may publish.
    @State private var reloadToken = 0

    /// Most recent lines the screen parses and renders.
    ///
    /// WHY bounded (#255): the log cap is now 1MB, roughly 7000 lines. Parsing all
    /// of them allocates a UUID per line on the main thread from .onAppear, which
    /// visibly freezes the screen. The tail is what anyone opening this screen is
    /// looking at anyway, and Copy still yields the whole file.
    private static let displayedLineLimit = 3000

    var body: some View {
        Group {
            if entries.isEmpty {
                Text(isLoading ? "Loading logs…" : "No logs available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if hiddenLineCount > 0 {
                                Text("\(hiddenLineCount) older lines hidden. Use Copy for the full log.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            }
                            ForEach(entries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                    // Keyed on the newest entry, not the count: once the file is
                    // saturated the displayed tail sits at `displayedLineLimit`
                    // forever, so a count-based trigger would stop firing exactly
                    // when the log is busiest.
                    .onChange(of: entries.last?.id) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Debug Logs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        PersistentLog.clear()
                        Task { await reloadLogs() }
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }

                    Button {
                        UIPasteboard.general.string = logContent
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            Task { await reloadLogs() }
        }
        .refreshable {
            await reloadLogs()
        }
    }

    // MARK: - Private

    /// Render a single log entry row with level icon, timestamp, subsystem tag, and message.
    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.levelIcon)
                .font(.caption2)
                .foregroundColor(entry.levelColor)
                .frame(width: 14)

            Text(entry.timestamp)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)

            Text("[\(entry.subsystem)]")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(entry.levelColor)

            Text(entry.params.isEmpty ? entry.eventName : "\(entry.eventName) \(entry.params)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    /// Scroll to the last entry (newest log).
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = entries.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    /// Reload log content from PersistentLog and parse the displayed tail.
    ///
    /// WHY off the main thread (#255): reading and splitting a 1MB file, then
    /// parsing thousands of lines, is long enough to drop frames if it runs inside
    /// .onAppear. The full content is kept for Copy; only the tail is parsed.
    /// WHY async rather than fire-and-forget: `.refreshable` dismisses its spinner
    /// when the closure returns, so a reload that only *starts* the work makes the
    /// pull-to-refresh report success before anything has been read.
    private func reloadLogs() async {
        isLoading = true
        reloadToken += 1
        let token = reloadToken

        let limit = Self.displayedLineLimit
        let (content, parsed, hidden) = await Task.detached(priority: .userInitiated) {
            let content = PersistentLog.read()
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            return (content, Self.parseEntries(from: lines.suffix(limit)), max(0, lines.count - limit))
        }.value

        // A newer reload has started since this one began; its result is the
        // current truth, so drop ours rather than overwrite it.
        guard token == reloadToken else { return }
        logContent = content
        entries = parsed
        hiddenLineCount = hidden
        isLoading = false
    }

    /// Parse raw log text into structured LogEntry values.
    ///
    /// Expected format per line (from LogEvent.formatted()):
    ///   [2026-03-11T12:00:00Z] INFO    [dictation] dictationStarted fromURL=true ...
    ///
    /// WHY regex parsing: The format is machine-generated by LogEvent.formatted(),
    /// so it follows a strict pattern. If a line doesn't match (e.g., legacy format),
    /// it falls through to a raw-text fallback entry.
    ///
    /// WHY static: it runs on a background queue, so it must not capture the view.
    ///
    /// WHY `nonisolated`: a `View`'s members are main-actor isolated by default, so
    /// calling this off the main actor is a Swift 6 error. Parsing text touches no
    /// view state, and the whole point (#255) is that it does not run on the main
    /// thread — the isolation was never real, only invisible behind GCD.
    private nonisolated static func parseEntries(from lines: ArraySlice<Substring>) -> [LogEntry] {
        lines.compactMap { line in
            // Pattern: [timestamp] LEVEL   [subsystem] eventName params...
            // The timestamp is ISO8601, level is 7-char padded, subsystem in brackets
            guard let bracketEnd = line.firstIndex(of: "]"),
                  line.first == "[" else {
                return nil
            }

            let timestampFull = String(line[line.index(after: line.startIndex)..<bracketEnd])
            // Extract time portion (HH:mm:ss) from ISO8601 timestamp
            let timeOnly: String
            if let tIndex = timestampFull.firstIndex(of: "T") {
                let afterT = timestampFull[timestampFull.index(after: tIndex)...]
                // Remove trailing Z or timezone
                timeOnly = String(afterT.prefix(8))
            } else {
                timeOnly = String(timestampFull.suffix(8))
            }

            // After "] " comes the level (7 chars padded), then " [subsystem] eventName params"
            let afterTimestamp = String(line[line.index(bracketEnd, offsetBy: 2)...])

            // Find the subsystem bracket
            guard let subStart = afterTimestamp.firstIndex(of: "["),
                  let subEnd = afterTimestamp.firstIndex(of: "]", after: subStart) else {
                return nil
            }

            let level = String(afterTimestamp[afterTimestamp.startIndex..<subStart])
                .trimmingCharacters(in: .whitespaces)
            let subsystem = String(afterTimestamp[afterTimestamp.index(after: subStart)..<subEnd])

            // Everything after "] " is eventName + optional params
            let rest = String(afterTimestamp[afterTimestamp.index(subEnd, offsetBy: 2)...])
            let parts = rest.split(separator: " ", maxSplits: 1)
            let eventName = parts.isEmpty ? rest : String(parts[0])
            let params = parts.count > 1 ? String(parts[1]) : ""

            return LogEntry(
                timestamp: timeOnly,
                level: level,
                subsystem: subsystem,
                eventName: eventName,
                params: params
            )
        }
    }
}

/// Helper to find index of a character after a given position.
private extension StringProtocol {
    func firstIndex(of element: Character, after index: Index) -> Index? {
        let searchRange = self.index(after: index)..<endIndex
        return self[searchRange].firstIndex(of: element)
    }
}
