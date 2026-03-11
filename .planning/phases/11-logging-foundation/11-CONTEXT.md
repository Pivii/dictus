# Phase 11: Logging Foundation - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Production-ready persistent logging across all subsystems (DictationCoordinator, AudioRecorder, TranscriptionService, ModelManager, keyboard extension, app lifecycle) with privacy safeguards and user-facing export. No filtering UI, no markdown export, no analytics — those are future requirements.

</domain>

<decisions>
## Implementation Decisions

### Export experience
- Export button lives in Settings (not inside DebugLogView)
- Triggers standard iOS share sheet
- Exported as plain text (.txt file)
- Device header includes: iOS version, app version, active model name, device model (e.g. iPhone 14)
- No memory/disk/locale info in header — essential only

### Privacy boundaries
- Sensitive data = transcription text, keystrokes, audio content only
- Model names, file paths, error messages, timing data are all OK to log
- Privacy enforced by design: logging API accepts predefined event types with structured parameters, no free-text string logging
- Same privacy rules apply to ALL log levels (debug/info/warning/error equally)
- WhisperKit/Parakeet error messages logged verbatim (they don't contain user content)

### Log visibility
- DebugLogView stays visible in Settings (no hidden gesture)
- No filtering by level or subsystem in this phase (deferred to LOG-F01 in v1.3+)
- Viewer auto-scrolls to latest entry (newest at bottom)

### Subsystem granularity
- Key events only per subsystem: start/stop/complete/fail (~5-10 entries per dictation session)
- No per-frame, per-buffer, or progress percentage logging
- Keyboard extension and main app write to the same App Group log file (interleaved timeline)
- ModelManager: log download start/complete/fail with model name + size, no progress percentages
- App lifecycle: log ALL transitions (launch, didBecomeActive, willResignActive, didEnterBackground) — critical for cold start diagnosis
- All log levels always active — no runtime toggle, fixed at compile time
- 500-line rotation limit (up from current 200)

### Claude's Discretion
- Color-coding of log entries by level in DebugLogView (pick what looks good with Liquid Glass design)
- Exact structured event type definitions and parameter lists per subsystem
- Internal architecture: evolve PersistentLog or build fresh, relationship with DictusLogger
- Thread-safety approach for cross-process file writes

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PersistentLog` (DictusCore/PersistentLog.swift): File-based logger with App Group storage, trim logic. Needs upgrade: no levels, no subsystems, 200-line limit, free-text API
- `DictusLogger` (DictusCore/Logger.swift): os.log wrapper with 3 categories (app, keyboard, appGroup). Could remain as console-side companion
- `DebugLogView` (DictusApp/Views/DebugLogView.swift): SwiftUI log viewer with clear/copy. Needs: share sheet, auto-scroll, structured format display
- `AppGroup.containerURL`: Already used for log file storage

### Established Patterns
- DictusCore framework shared between App and Keyboard extension — logging must live here
- Darwin notifications for cross-process IPC (existing pattern)
- Serial dispatch queue for thread-safe file writes (already in PersistentLog)

### Integration Points
- SettingsView: add export button + link to upgraded DebugLogView
- DictationCoordinator: ~10 existing PersistentLog.log() calls to migrate to structured API
- DictusApp.swift: ~3 existing PersistentLog.log() calls to migrate
- AudioRecorder, TranscriptionService, ModelManager, KeyboardViewController: no logging yet — need instrumentation
- App lifecycle logging hooks in DictusApp (scenePhase or UIApplicationDelegate)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- DebugLogView filtering by level and subsystem — LOG-F01 (v1.3+)
- Markdown-friendly export format for GitHub issues — LOG-F02/F03 (v1.3+)

</deferred>

---

*Phase: 11-logging-foundation*
*Context gathered: 2026-03-11*
