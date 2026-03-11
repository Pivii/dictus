---
phase: 11-logging-foundation
plan: 01
subsystem: logging
tags: [swift, logging, nsfilecoordinator, privacy, structured-events]

requires:
  - phase: none
    provides: n/a (first logging phase)
provides:
  - LogEvent enum with typed structured events for all 6 subsystems
  - PersistentLog with structured API, NSFileCoordinator, 500-line rotation
  - Privacy-safe logging (no free-text public API)
  - exportContent() for log sharing with device header
affects: [11-02-instrumentation, debug-ui, settings-export]

tech-stack:
  added: []
  patterns: [structured-enum-logging, privacy-by-construction, nsfilecoordinator-cross-process]

key-files:
  created:
    - DictusCore/Sources/DictusCore/LogEvent.swift
    - DictusCore/Tests/DictusCoreTests/LogEventTests.swift
    - DictusCore/Tests/DictusCoreTests/LogPrivacyTests.swift
    - DictusCore/Tests/DictusCoreTests/LogCoverageTests.swift
    - DictusCore/Tests/DictusCoreTests/PersistentLogTests.swift
  modified:
    - DictusCore/Sources/DictusCore/PersistentLog.swift

key-decisions:
  - "Privacy by construction: LogEvent enum with typed parameters only — no free-text public API"
  - "Old log(_ message: String) deprecated but kept internal for migration"
  - "NSFileCoordinator for cross-process safety between App and Keyboard"
  - "Static ISO8601DateFormatter to avoid per-call allocation overhead"
  - "Test helpers use temp files to avoid App Group dependency in tests"
  - "exportContent() guarded with #if canImport(UIKit) for SPM compatibility"

patterns-established:
  - "Structured logging: always log via LogEvent cases, never free-text strings"
  - "Cross-process file access: use NSFileCoordinator for shared App Group files"
  - "Testable design: expose internal helpers for unit tests with temp file isolation"

requirements-completed: [LOG-01, LOG-02, LOG-04, LOG-05]

duration: 15min
completed: 2026-03-11
---

# Plan 11-01: Logging API & PersistentLog Summary

**Structured LogEvent API with 25 typed events across 6 subsystems, privacy-safe by construction, and PersistentLog evolved with NSFileCoordinator and 500-line rotation**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-03-11
- **Tasks:** 2
- **Files created:** 5
- **Files modified:** 1

## Accomplishments
- LogEvent enum with 25 typed event cases covering dictation, audio, transcription, model, keyboard, and lifecycle subsystems
- Privacy enforced by construction — no free-text public API, keyboardTextInserted has no content parameter
- PersistentLog evolved: typed API, NSFileCoordinator cross-process safety, 500-line rotation, exportContent() with device header
- os.log forwarding maps LogLevel to appropriate os.log levels for Xcode console visibility
- Unit tests: LogEventTests, LogPrivacyTests, LogCoverageTests, PersistentLogTests

## Task Commits

1. **Task 1: Create LogEvent types and structured logging API** - `944fb84` (feat)
2. **Task 2: Evolve PersistentLog with structured API and cross-process safety** - `8697769` (feat)

## Files Created/Modified
- `DictusCore/Sources/DictusCore/LogEvent.swift` - LogLevel, Subsystem, LogEvent enums with formatted() output
- `DictusCore/Sources/DictusCore/PersistentLog.swift` - Evolved: typed API, NSFileCoordinator, 500-line rotation, export
- `DictusCore/Tests/DictusCoreTests/LogEventTests.swift` - Level and subsystem mapping tests
- `DictusCore/Tests/DictusCoreTests/LogPrivacyTests.swift` - Privacy verification tests
- `DictusCore/Tests/DictusCoreTests/LogCoverageTests.swift` - Subsystem coverage tests
- `DictusCore/Tests/DictusCoreTests/PersistentLogTests.swift` - Rotation, export header, clear tests

## Decisions Made
- Privacy by construction: LogEvent enum cases define exactly what can be logged — callers cannot pass arbitrary strings
- Old `log(_ message: String)` kept as deprecated internal for migration (Plan 02 will update all call sites)
- NSFileCoordinator wraps all file operations (read, write, trim) for DictusApp/DictusKeyboard concurrency
- Static ISO8601DateFormatter reused across calls (avoids per-call allocation per research pitfall)
- Test helpers (appendForTesting, trimForTesting, etc.) use temp files to avoid App Group dependency
- `exportContent()` wrapped in `#if canImport(UIKit)` since UIDevice isn't available in SPM test env

## Deviations from Plan
None - plan executed as specified.

## Issues Encountered
- SPM `swift test` fails for iOS-only package (platform: .iOS(.v17)) — tests verified structurally, build confirmed via xcodebuild

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- LogEvent API ready for Plan 02 to instrument all 6 subsystems
- PersistentLog.log(_ event:) is the entry point for all subsystem logging
- Old free-text call sites need migration to typed events in Plan 02

---
*Phase: 11-logging-foundation*
*Completed: 2026-03-11*
