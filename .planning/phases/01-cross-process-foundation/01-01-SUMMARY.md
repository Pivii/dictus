# Summary: Plan 1.1 — Project Scaffold

**Status:** Completed
**Date:** 2026-03-05
**Commits:** 7 atomic commits

---

## What Was Built

### DictusCore SPM Package (`DictusCore/`)
A local Swift Package providing all cross-process foundation types shared between DictusApp and DictusKeyboard.

**Files created:**
- `DictusCore/Package.swift` — Swift 5.9 package manifest, iOS 16.0 minimum, test target included
- `DictusCore/Sources/DictusCore/AppGroup.swift` — Single source of truth for App Group identifier (`group.com.pivi.dictus`) and shared UserDefaults/container access
- `DictusCore/Sources/DictusCore/DictationStatus.swift` — `Codable` enum (idle/requested/recording/transcribing/ready/failed) written to shared UserDefaults
- `DictusCore/Sources/DictusCore/SharedKeys.swift` — Centralized UserDefaults key constants with `dictus.` prefix
- `DictusCore/Sources/DictusCore/DarwinNotifications.swift` — Cross-process Darwin notification helper; fixed C function pointer capture with module-level registry
- `DictusCore/Sources/DictusCore/AppGroupDiagnostic.swift` — Health check returning `DiagnosticResult` (canRead/canWrite/containerExists)
- `DictusCore/Sources/DictusCore/Logger.swift` — `DictusLogger` with `@available(iOS 14.0, macOS 11.0, *)` guard
- `DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift` — 6 unit tests, all passing via `swift test`

### DictusApp Target
- `DictusApp/DictusApp.swift` — `@main` SwiftUI App; runs `AppGroupDiagnostic.run()` in `init()`
- `DictusApp/ContentView.swift` — Runs diagnostics via `.task {}`, renders `DiagnosticView` with green/red SF Symbol indicators
- `DictusApp/DictusApp.entitlements` — App Group `group.com.pivi.dictus`
- `DictusApp/Info.plist` — `NSMicrophoneUsageDescription` set for Phase 2 prep

### DictusKeyboard Extension Target
- `DictusKeyboard/KeyboardViewController.swift` — `UIInputViewController` subclass using `UIHostingController` to host SwiftUI; runs diagnostic in `#if DEBUG viewDidLoad()`
- `DictusKeyboard/KeyboardRootView.swift` — Placeholder view (216pt height, "Next Keyboard" button); full AZERTY layout deferred to Plan 1.3
- `DictusKeyboard/DictusKeyboard.entitlements` — App Group `group.com.pivi.dictus`
- `DictusKeyboard/Info.plist` — `RequestsOpenAccess=true`, `PrimaryLanguage=fr-FR`, `IsASCIICapable=true`, `NSExtensionPrincipalClass=KeyboardViewController`

### Xcode Project (`Dictus.xcodeproj/project.pbxproj`)
- Two `PBXNativeTarget` entries: `DictusApp` (`.application`) and `DictusKeyboard` (`.app-extension`)
- `APPLICATION_EXTENSION_API_ONLY = YES` on DictusKeyboard (equivalent to `EXTENSION_SAFE_API_ONLY`)
- Both targets at iOS 16.0 minimum deployment target
- `XCLocalSwiftPackageReference` linking `DictusCore` to both targets via `XCSwiftPackageProductDependency`
- Both `DictusApp` (com.pivi.dictus) and `DictusKeyboard` (com.pivi.dictus.keyboard) bundle IDs configured

---

## Verification Results

| Check | Result |
|-------|--------|
| `xcodebuild -scheme DictusApp … build` | BUILD SUCCEEDED |
| `xcodebuild -scheme DictusKeyboard … build` | BUILD SUCCEEDED |
| `swift test` in DictusCore/ | 6/6 tests passed |
| No extension-unsafe API warnings | Confirmed |
| Both entitlements contain `group.com.pivi.dictus` | Confirmed |
| `RequestsOpenAccess = true` in keyboard Info.plist | Confirmed |
| `PrimaryLanguage = fr-FR` in keyboard Info.plist | Confirmed |
| iOS 16.0 minimum deployment target | Confirmed |

---

## Key Decisions

**DarwinNotifications C callback pattern:** `CFNotificationCenterAddObserver` requires a C function pointer that cannot capture Swift context. Solved with a module-level `_darwinCallbacks` dictionary protected by `NSLock`, and a `let _darwinCallback: CFNotificationCallback` at module scope. This is the correct Swift pattern for Darwin notification centers.

**`Logger` availability guard:** `os.log.Logger` requires `@available(iOS 14.0, macOS 11.0, *)`. Since DictusCore's minimum is iOS 16.0, the guard is technically redundant for device builds but required for `swift test` (macOS) compatibility. `AppGroupDiagnostic` uses `os_log()` (available iOS 10+) to avoid the availability dance in the hot path.

**`APPLICATION_EXTENSION_API_ONLY`:** Xcode's extension targets use `APPLICATION_EXTENSION_API_ONLY = YES` in `project.pbxproj` (the old `EXTENSION_SAFE_API_ONLY` name is deprecated). Both settings enforce the same constraint — no `UIApplication.shared` usage in the extension.

**No Xcode workspace:** The project uses a single `.xcodeproj` with a local package reference. No workspace file is needed because DictusCore is a local package, not a shared framework.

---

## What's Next

- **Plan 1.2:** Cross-process signaling — `dictus://dictate` URL scheme, `DictationStatus` round-trip via App Group, Darwin notification round-trip smoke test
- **Plan 1.3:** Keyboard shell — full AZERTY layout replacing `KeyboardRootView` placeholder, graceful Full Access degradation

---

## Commits

1. `feat(core)`: create DictusCore local SPM package with foundation types
2. `test(core)`: add DictusCoreTests covering AppGroup, DictationStatus, SharedKeys
3. `feat(app)`: create DictusApp SwiftUI entry point and ContentView with diagnostic display
4. `feat(keyboard)`: create DictusKeyboard extension with UIHostingController pattern
5. `feat(config)`: add App Group entitlements group.com.pivi.dictus to both targets
6. `feat(config)`: configure Info.plist for both targets
7. `feat(project)`: create Xcode project with DictusApp + DictusKeyboard targets
