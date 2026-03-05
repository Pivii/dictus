# Project State: Dictus

## Project Reference
See: .planning/PROJECT.md (updated 2026-03-04)
**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 1

## Current Phase
Phase: 1
Status: In Progress
Plans completed: 1/3
Current plan: 1.2 (Cross-process signaling)

## Phase History

### Plan 1.1: Project Scaffold — COMPLETED (2026-03-05)
- Xcode project created with DictusApp + DictusKeyboard targets
- DictusCore local SPM package with 7 source files + 6 unit tests (all passing)
- Both targets build successfully (iOS 16.0, iPhone 17 simulator)
- App Group entitlements configured on both targets
- DictusKeyboard: RequestsOpenAccess=true, PrimaryLanguage=fr-FR
- APPLICATION_EXTENSION_API_ONLY=YES on DictusKeyboard
- AppGroupDiagnostic wired into both launch paths

## Key Decisions

### DarwinNotifications C callback
Module-level registry (`_darwinCallbacks: [String: () -> Void]`) protected by `NSLock`, exposed via a `let _darwinCallback: CFNotificationCallback` constant. This is the required pattern — `CFNotificationCenterAddObserver` takes a C function pointer that cannot capture Swift context.

### Logger availability
`DictusLogger` uses `@available(iOS 14.0, macOS 11.0, *)`. `AppGroupDiagnostic` uses `os_log()` for the hot path to avoid availability gates in test targets (macOS runner).

### No Xcode workspace
Local SPM package reference (`XCLocalSwiftPackageReference`) in the `.xcodeproj` is sufficient. No workspace needed.

---
*State initialized: 2026-03-04*
*Plan 1.1 completed: 2026-03-05*
