# Phase 11: Logging Foundation - Research

**Researched:** 2026-03-11
**Domain:** Structured logging for iOS app + keyboard extension with shared App Group storage
**Confidence:** HIGH

## Summary

Phase 11 upgrades the existing `PersistentLog` free-text logger into a structured, privacy-safe, level-aware logging system shared between DictusApp and DictusKeyboard via App Group. The existing codebase already has the foundation: `PersistentLog` writes to App Group file with trim logic, `DictusLogger` wraps os.log with subsystem categories, and `DebugLogView` displays logs in SwiftUI. The work is an evolution, not a greenfield build.

The core challenge is designing a structured event API that enforces privacy by construction (no free-text strings that could leak transcription content) while remaining ergonomic enough for instrumentation across 6+ subsystems. Cross-process file writes (app + keyboard extension writing to the same file) require careful serialization -- the existing serial dispatch queue approach works within a single process but needs file-level coordination for cross-process safety.

**Primary recommendation:** Evolve `PersistentLog` into a structured logger with typed `LogEvent` entries (level, subsystem, event enum, parameters dictionary). Keep `DictusLogger` as the os.log companion. Add share sheet export to `DebugLogView`. Privacy is enforced by the event type system -- callers pass enum cases with structured parameters, never raw strings.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Export button lives in Settings (not inside DebugLogView)
- Triggers standard iOS share sheet
- Exported as plain text (.txt file)
- Device header includes: iOS version, app version, active model name, device model
- No memory/disk/locale info in header
- Sensitive data = transcription text, keystrokes, audio content only
- Model names, file paths, error messages, timing data are all OK to log
- Privacy enforced by design: logging API accepts predefined event types with structured parameters, no free-text string logging
- Same privacy rules apply to ALL log levels equally
- WhisperKit/Parakeet error messages logged verbatim
- DebugLogView stays visible in Settings (no hidden gesture)
- No filtering by level or subsystem in this phase
- Viewer auto-scrolls to latest entry (newest at bottom)
- Key events only per subsystem (~5-10 entries per dictation session)
- No per-frame, per-buffer, or progress percentage logging
- Keyboard extension and main app write to the same App Group log file
- ModelManager: log download start/complete/fail with model name + size
- App lifecycle: log ALL transitions (launch, didBecomeActive, willResignActive, didEnterBackground)
- All log levels always active -- no runtime toggle, fixed at compile time
- 500-line rotation limit

### Claude's Discretion
- Color-coding of log entries by level in DebugLogView
- Exact structured event type definitions and parameter lists per subsystem
- Internal architecture: evolve PersistentLog or build fresh, relationship with DictusLogger
- Thread-safety approach for cross-process file writes

### Deferred Ideas (OUT OF SCOPE)
- DebugLogView filtering by level and subsystem -- LOG-F01 (v1.3+)
- Markdown-friendly export format for GitHub issues -- LOG-F02/F03 (v1.3+)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LOG-01 | App logs events with 4 levels (debug/info/warning/error) across all subsystems | LogLevel enum + Subsystem enum + structured LogEvent type in DictusCore |
| LOG-02 | Logs never contain transcription text, keystrokes, or audio content | Privacy enforced by typed event API -- no free-text parameter; event enums define allowed data |
| LOG-03 | User can export logs with device header for GitHub issues | Share sheet via UIActivityViewController from Settings; device header assembled from UIDevice + Bundle APIs |
| LOG-04 | Logs rotate automatically at 500 lines max | Upgrade existing PersistentLog.maxLines from 200 to 500; trim logic already exists |
| LOG-05 | Logging covers all subsystems | Instrument DictationCoordinator (migrate ~10 calls), AudioRecorder, TranscriptionService, ModelManager, KeyboardViewController, app lifecycle |
</phase_requirements>

## Standard Stack

### Core
| Component | Source | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| `PersistentLog` (evolved) | DictusCore (existing) | File-based structured logging to App Group | Already handles file I/O, trim, App Group path -- extend rather than replace |
| `DictusLogger` (kept) | DictusCore (existing) | os.log companion for Xcode console | Separate concern: console debugging vs. persistent export |
| `UIActivityViewController` | UIKit | Share sheet for log export | Standard iOS sharing pattern, no dependencies needed |
| `UIDevice` / `Bundle` | UIKit/Foundation | Device header info | Native APIs for iOS version, device model, app version |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `NSFileCoordinator` | Cross-process file safety | When keyboard extension and app write to same log file |
| `ScrollViewReader` | Auto-scroll to bottom | In DebugLogView to scroll to latest entry |
| `ISO8601DateFormatter` | Timestamp formatting | Already used in PersistentLog, keep consistent |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom file logger | OSLog + OSLogStore | OSLogStore requires iOS 15+ and cannot read across processes (extension vs app); file-based approach is simpler and already works |
| NSFileCoordinator | POSIX file locks (flock) | flock is lower-level and less idiomatic in Swift; NSFileCoordinator is Apple's recommended approach |
| Custom share sheet | ShareLink (SwiftUI) | ShareLink (iOS 16+) could work but requires wrapping text in a Transferable; UIActivityViewController gives more control and is proven |

## Architecture Patterns

### Recommended Project Structure
```
DictusCore/Sources/DictusCore/
  PersistentLog.swift          # Evolved: structured events, 500-line trim, file coordination
  Logger.swift                 # Kept: os.log companion (add subsystem categories)
  LogEvent.swift               # NEW: LogLevel, Subsystem, LogEvent enums + formatting

DictusApp/Views/
  DebugLogView.swift           # Evolved: color-coded entries, auto-scroll, share button
  SettingsView.swift           # Modified: add export button

DictusApp/
  DictusApp.swift              # Migrate existing PersistentLog.log() calls
  DictationCoordinator.swift   # Migrate ~10 existing calls to structured API
  Audio/AudioRecorder.swift    # NEW instrumentation
  Audio/TranscriptionService.swift  # NEW instrumentation
  Models/ModelManager.swift    # NEW instrumentation

DictusKeyboard/
  KeyboardViewController.swift # NEW instrumentation
```

### Pattern 1: Typed Event Logging (Privacy by Construction)
**What:** Define all loggable events as enum cases with typed associated values. No free-text API exposed.
**When to use:** Every log call site.
**Example:**
```swift
// LogEvent.swift in DictusCore

public enum LogLevel: String, CaseIterable {
    case debug, info, warning, error
}

public enum Subsystem: String {
    case dictation, audio, transcription, model, keyboard, lifecycle
}

/// Each enum case defines exactly what data can be logged.
/// No free-text strings -- privacy enforced at the type level.
public enum LogEvent {
    // Dictation
    case dictationStarted(fromURL: Bool, appState: String, engineRunning: Bool)
    case dictationCompleted(durationMs: Int)
    case dictationFailed(error: String)
    case dictationDeferred(reason: String)

    // Audio
    case audioEngineStarted
    case audioEngineStopped
    case audioSessionConfigured(category: String)
    case audioSessionFailed(error: String)

    // Transcription
    case transcriptionStarted(modelName: String)
    case transcriptionCompleted(durationMs: Int, wordCount: Int)
    case transcriptionFailed(error: String)

    // Model
    case modelDownloadStarted(name: String, sizeMB: Int)
    case modelDownloadCompleted(name: String)
    case modelDownloadFailed(name: String, error: String)
    case modelSelected(name: String)
    case modelCompilationStarted(name: String)
    case modelCompilationCompleted(name: String, durationMs: Int)

    // Keyboard
    case keyboardDidAppear
    case keyboardDidDisappear
    case keyboardMicTapped
    case keyboardTextInserted  // no content logged!

    // Lifecycle
    case appLaunched(version: String)
    case appDidBecomeActive
    case appWillResignActive
    case appDidEnterBackground
    case appWhisperKitLoaded(modelName: String)

    var subsystem: Subsystem { /* derived from case */ }
    var level: LogLevel { /* derived: failures=error, starts=info, etc. */ }
    var message: String { /* formatted string from associated values */ }
}
```

### Pattern 2: Cross-Process File Safety with NSFileCoordinator
**What:** Both app and keyboard extension write to the same App Group log file. Use NSFileCoordinator for safe concurrent access.
**When to use:** Every write and read of the log file.
**Example:**
```swift
// In PersistentLog.swift
private static func appendToFile(_ entry: String) {
    guard let url = fileURL else { return }
    let coordinator = NSFileCoordinator()
    var error: NSError?
    coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { coordURL in
        if !FileManager.default.fileExists(atPath: coordURL.path) {
            FileManager.default.createFile(atPath: coordURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: coordURL) else { return }
        handle.seekToEndOfFile()
        if let data = entry.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    }
}
```

### Pattern 3: Device Header for Export
**What:** Assemble device context at export time, prepend to log content.
**When to use:** When user taps export button.
**Example:**
```swift
static func exportContent() -> String {
    let device = UIDevice.current
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    let activeModel = AppGroup.defaults.string(forKey: SharedKeys.selectedModel) ?? "none"

    let header = """
    Dictus Debug Log
    iOS \(device.systemVersion) | App \(version) (\(build)) | \(device.model) | Model: \(activeModel)
    ---

    """
    return header + PersistentLog.read()
}
```

### Pattern 4: Auto-Scroll DebugLogView
**What:** Use ScrollViewReader + onChange to keep view scrolled to bottom.
**Example:**
```swift
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(alignment: .leading) {
            ForEach(logEntries) { entry in
                LogEntryRow(entry: entry)
                    .id(entry.id)
            }
        }
    }
    .onChange(of: logEntries.count) { _ in
        if let last = logEntries.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
```

### Anti-Patterns to Avoid
- **Free-text log API:** Never expose `log(_ message: String)` publicly. This is how transcription text leaks into logs. The existing `PersistentLog.log()` must become internal/private and only called by the structured event handler.
- **Separate log files per process:** Complicates export and timeline reconstruction. Use a single interleaved file with process tags.
- **Synchronous file I/O on main thread:** Always dispatch writes to a background queue (existing pattern already does this).
- **Re-creating DateFormatter on every call:** `ISO8601DateFormatter()` is expensive to allocate. Use a static instance.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Share sheet | Custom sharing UI | UIActivityViewController | Standard iOS share sheet, handles all share targets |
| Cross-process file locking | Custom lock files / POSIX locks | NSFileCoordinator | Apple's recommended API for coordinated file access |
| Device info collection | Manual plist parsing | UIDevice.current + Bundle.main | Standard APIs, always up to date |
| Log file rotation | Complex log rotation system | Simple line-count trim (existing pattern) | 500 lines is tiny; no need for size-based rotation or multiple files |

**Key insight:** This phase is fundamentally simple -- structured text appended to a file with a trim. The complexity is in API design (privacy enforcement) and cross-process coordination, not in the logging mechanism itself.

## Common Pitfalls

### Pitfall 1: Cross-Process File Corruption
**What goes wrong:** Both app and keyboard extension write simultaneously, interleaving bytes mid-line.
**Why it happens:** DispatchQueue serialization only works within a single process. The keyboard extension is a separate process.
**How to avoid:** Use `NSFileCoordinator` for all file reads and writes. Both processes will block briefly waiting for the other.
**Warning signs:** Garbled log lines, partial timestamps, JSON parse errors if using structured format.

### Pitfall 2: Leaking Sensitive Data Through Error Messages
**What goes wrong:** A catch block logs `error.localizedDescription` which contains transcription text from a downstream error.
**Why it happens:** Some errors embed user content in their description (e.g., "Failed to process: [transcribed text]").
**How to avoid:** WhisperKit/Parakeet errors are safe per user decision. For custom errors, only log error codes and types, never user-generated content. The typed event API prevents this by design.
**Warning signs:** Review all `.error` associated values in LogEvent -- they should only accept framework error strings.

### Pitfall 3: DateFormatter Performance
**What goes wrong:** Creating `ISO8601DateFormatter()` on every log call causes measurable overhead.
**Why it happens:** DateFormatter allocation is expensive in Apple frameworks.
**How to avoid:** Use a static `let formatter` at the enum level.
**Warning signs:** Logging calls taking >1ms in Instruments.

### Pitfall 4: Keyboard Extension Memory Pressure
**What goes wrong:** Logging infrastructure uses too much memory in the keyboard extension (~50MB limit).
**Why it happens:** Loading entire log file into memory for trim, or buffering too many entries.
**How to avoid:** The structured log API lives in DictusCore (already loaded by keyboard). Keep log reads lazy -- only load full content in DebugLogView (app only). Trim reads the file but this is infrequent.
**Warning signs:** Keyboard extension crashes with memory warnings.

### Pitfall 5: UIActivityViewController in SwiftUI
**What goes wrong:** Cannot present UIActivityViewController directly from SwiftUI button.
**Why it happens:** UIActivityViewController is UIKit, needs a UIViewController to present from.
**How to avoid:** Use a simple UIViewControllerRepresentable wrapper, or get the window's root view controller via the UIApplication scene API. Since this is in the main app (not keyboard extension), UIApplication.shared is available.
**Warning signs:** Compile errors about missing presenting view controller.

## Code Examples

### Log Entry Format (Plain Text)
```
[2026-03-11T14:23:01Z] INFO  [dictation] dictationStarted fromURL=true appState=active engineRunning=true
[2026-03-11T14:23:05Z] INFO  [transcription] transcriptionCompleted duration=3200ms words=42
[2026-03-11T14:23:05Z] DEBUG [audio] audioEngineStopped
[2026-03-11T14:23:06Z] ERROR [model] modelDownloadFailed name=large-v3 error=networkTimeout
```

### Export File Format
```
Dictus Debug Log
iOS 18.2 | App 1.2 (42) | iPhone 14 | Model: base
---

[2026-03-11T14:23:01Z] INFO  [dictation] dictationStarted fromURL=true appState=active engineRunning=true
...
```

### Share Sheet Presentation from SwiftUI
```swift
// In SettingsView or a helper
func shareLogFile() {
    let content = PersistentLog.exportContent()
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dictus-logs.txt")
    try? content.write(to: tempURL, atomically: true, encoding: .utf8)

    let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return }
    root.present(activityVC, animated: true)
}
```

### Color-Coded Log Entries (Liquid Glass Design)
```swift
extension LogLevel {
    var color: Color {
        switch self {
        case .debug: return .secondary          // subtle gray
        case .info:  return .primary            // default text
        case .warning: return Color(.systemOrange)
        case .error: return Color(.systemRed)   // matches recording red #EF4444
        }
    }

    var icon: String {
        switch self {
        case .debug: return "ant"
        case .info:  return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| os.log only | os.log + file-based persistent log | Already in codebase | File logs survive debugger disconnection |
| Free-text logging | Typed event enums | This phase | Privacy by construction, no accidental data leaks |
| OSLogStore for reading | Direct file I/O via App Group | N/A | OSLogStore cannot read cross-process; file approach is simpler |

**Deprecated/outdated:**
- `OSLogStore` for cross-process log reading: Only reads logs from the calling process. Not suitable for app+extension shared logging.
- `asl` (Apple System Log): Fully deprecated since iOS 10, replaced by os.log.

## Open Questions

1. **NSFileCoordinator overhead in keyboard extension**
   - What we know: NSFileCoordinator is Apple's recommended cross-process file coordination API. It works in extensions.
   - What's unclear: Whether the coordination overhead is noticeable when both processes write near-simultaneously (e.g., during a dictation session).
   - Recommendation: Implement with NSFileCoordinator. If profiling shows issues, fall back to simple append-only writes (append is atomic on most filesystems for small writes) with a process tag prefix.

2. **Exact SharedKeys key for active model name**
   - What we know: ModelManager stores the selected model in UserDefaults. SharedKeys likely has a constant.
   - What's unclear: The exact key name.
   - Recommendation: Check SharedKeys.swift during implementation to find the correct key for device header.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing / XCTest (SPM) |
| Config file | DictusCore/Package.swift (test target: DictusCoreTests) |
| Quick run command | `cd DictusCore && swift test --filter LogEventTests` |
| Full suite command | `cd DictusCore && swift test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LOG-01 | LogEvent produces correct level + subsystem for each event | unit | `cd DictusCore && swift test --filter LogEventTests` | No -- Wave 0 |
| LOG-02 | No event format string contains sensitive patterns | unit | `cd DictusCore && swift test --filter LogPrivacyTests` | No -- Wave 0 |
| LOG-03 | Export content includes device header | unit | `cd DictusCore && swift test --filter LogExportTests` | No -- Wave 0 |
| LOG-04 | Trim keeps exactly 500 lines after exceeding limit | unit | `cd DictusCore && swift test --filter PersistentLogTests` | No -- Wave 0 |
| LOG-05 | Each subsystem has at least one LogEvent case | unit | `cd DictusCore && swift test --filter LogCoverageTests` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `cd DictusCore && swift test --filter Log`
- **Per wave merge:** `cd DictusCore && swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `DictusCore/Tests/DictusCoreTests/LogEventTests.swift` -- covers LOG-01 (level/subsystem mapping)
- [ ] `DictusCore/Tests/DictusCoreTests/LogPrivacyTests.swift` -- covers LOG-02 (no sensitive data patterns)
- [ ] `DictusCore/Tests/DictusCoreTests/LogExportTests.swift` -- covers LOG-03 (header format)
- [ ] `DictusCore/Tests/DictusCoreTests/PersistentLogTests.swift` -- covers LOG-04 (500-line rotation)
- [ ] `DictusCore/Tests/DictusCoreTests/LogCoverageTests.swift` -- covers LOG-05 (all subsystems have events)

## Sources

### Primary (HIGH confidence)
- Existing codebase: PersistentLog.swift, Logger.swift, DebugLogView.swift, SettingsView.swift -- direct file reads
- Apple documentation: NSFileCoordinator, UIActivityViewController, UIDevice -- standard iOS APIs
- CONTEXT.md -- user decisions and constraints

### Secondary (MEDIUM confidence)
- NSFileCoordinator for App Group cross-process coordination -- well-documented Apple pattern, commonly used in widget/extension scenarios

### Tertiary (LOW confidence)
- None -- this phase uses well-established iOS patterns with no novel technology

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all native iOS/Swift, no third-party dependencies, existing code to evolve
- Architecture: HIGH -- typed event enum pattern is well-established; existing PersistentLog proves the file I/O approach works
- Pitfalls: HIGH -- cross-process file coordination is the only non-trivial concern, and NSFileCoordinator is Apple's answer

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable -- all native APIs, no fast-moving dependencies)
