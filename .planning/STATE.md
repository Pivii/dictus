# Project State: Dictus

## Project Reference
See: .planning/PROJECT.md (updated 2026-03-04)
**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard — no subscription, no cloud, no account.
**Current focus:** Phase 1

## Current Phase
Phase: 1
Status: In Progress
Plans completed: 2/3
Current plan: 1.3 (Keyboard shell)

## Phase History

### Plan 1.1: Project Scaffold — COMPLETED (2026-03-05)
- Xcode project created with DictusApp + DictusKeyboard targets
- DictusCore local SPM package with 7 source files + 6 unit tests (all passing)
- Both targets build successfully (iOS 16.0, iPhone 17 simulator)
- App Group entitlements configured on both targets
- DictusKeyboard: RequestsOpenAccess=true, PrimaryLanguage=fr-FR
- APPLICATION_EXTENSION_API_ONLY=YES on DictusKeyboard
- AppGroupDiagnostic wired into both launch paths

### Plan 1.2: Cross-Process Signaling — COMPLETED (2026-03-05)
- `dictus://` URL scheme registered in DictusApp Info.plist
- `DictationCoordinator` (ObservableObject) in DictusApp: handles URL, stubs recording+transcription, writes to App Group, posts Darwin notifications
- `DictusApp.swift` updated with `.onOpenURL` routing `dictus://dictate` to coordinator
- `ContentView.swift` updated with `DictationStatusView` shown when status != .idle
- `DictationView.swift` created: `DictationStatusView` component with icon+label per status
- `KeyboardState` (ObservableObject) in DictusKeyboard: observes Darwin notifications, reads App Group data, 100ms retry guard for race condition, deinit cleanup
- `MicButtonDisabled` view in DictusKeyboard/Views: popover with Full Access instructions
- `KeyboardViewController` updated with viewDidDisappear + textDidChange lifecycle hooks

## Key Decisions

### DarwinNotifications C callback
Module-level registry (`_darwinCallbacks: [String: () -> Void]`) protected by `NSLock`, exposed via a `let _darwinCallback: CFNotificationCallback` constant. This is the required pattern — `CFNotificationCenterAddObserver` takes a C function pointer that cannot capture Swift context.

### Logger availability
`DictusLogger` uses `@available(iOS 14.0, macOS 11.0, *)`. `AppGroupDiagnostic` uses `os_log()` for the hot path to avoid availability gates in test targets (macOS runner). All call sites in DictusApp/DictusKeyboard wrap logger usage with `#available(iOS 14.0, *)`.

### No Xcode workspace
Local SPM package reference (`XCLocalSwiftPackageReference`) in the `.xcodeproj` is sufficient. No workspace needed.

### No `dictus://return`
No App Store-approved API exists on iOS 16-18 to programmatically return to the previous app. iOS automatically shows `< [Previous App]` status bar chevron when DictusApp opens via URL scheme. No code required.

### `KeyboardState` owned by `KeyboardRootView` as `@StateObject`
Ties `KeyboardState` lifetime to the SwiftUI view. `deinit` removes Darwin observers automatically when hosting controller is deallocated — prevents leaks across keyboard show/hide cycles.

### 100ms UserDefaults retry in `KeyboardState`
Darwin notifications are posted immediately after `defaults.synchronize()`, but cross-App-Group UserDefaults propagation can lag on-device. A 100ms deferred read guards against receiving the notification before the value is readable.

---
*State initialized: 2026-03-04*
*Plan 1.1 completed: 2026-03-05*
*Plan 1.2 completed: 2026-03-05*
