---
phase: 1
plan: "1.1"
title: "Project Scaffold"
wave: 1
depends_on: []
requirements: ["APP-06"]
files_modified:
  - Dictus.xcodeproj/project.pbxproj
  - DictusApp/DictusApp.swift
  - DictusApp/ContentView.swift
  - DictusApp/Info.plist
  - DictusApp/DictusApp.entitlements
  - DictusKeyboard/KeyboardViewController.swift
  - DictusKeyboard/Info.plist
  - DictusKeyboard/DictusKeyboard.entitlements
  - DictusCore/Package.swift
  - DictusCore/Sources/DictusCore/AppGroup.swift
  - DictusCore/Sources/DictusCore/DictationStatus.swift
  - DictusCore/Sources/DictusCore/SharedKeys.swift
  - DictusCore/Sources/DictusCore/DarwinNotifications.swift
  - DictusCore/Sources/DictusCore/AppGroupDiagnostic.swift
  - DictusCore/Sources/DictusCore/Logger.swift
  - DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift
autonomous: true
---

# Plan 1.1: Project Scaffold

## Objective
Create the Xcode project structure with two targets (DictusApp + DictusKeyboard), a shared DictusCore local SPM package, and App Group entitlements. Verify that both processes can read and write to the shared container. This is the foundation every other plan depends on.

## must_haves
- [ ] Xcode project builds successfully with both DictusApp and DictusKeyboard targets
- [ ] DictusCore SPM package is linked to both targets and compiles without warnings
- [ ] App Group `group.com.pivi.dictus` is configured in entitlements for both targets
- [ ] `AppGroupDiagnostic.run()` logs `canWrite: true, canRead: true` from both DictusApp and DictusKeyboard
- [ ] `EXTENSION_SAFE_API_ONLY = YES` is set on DictusKeyboard target
- [ ] DictusKeyboard Info.plist contains `RequestsOpenAccess = true` and `PrimaryLanguage = fr-FR`
- [ ] Project compiles for iOS 16.0 minimum deployment target

<tasks>

<task id="1.1.1" title="Create Xcode project with DictusApp target" estimated_effort="M">
**What:** Create the Xcode project and the main app target with SwiftUI lifecycle.
**Why:** The project container is needed before anything else. Using SwiftUI App lifecycle (`@main struct DictusApp: App`) aligns with modern Swift and the project stack.
**How:**
1. Create a new Xcode project: iOS > App, product name `Dictus`, organization `com.pivi`, interface SwiftUI, lifecycle SwiftUI App, language Swift
2. Set minimum deployment target to iOS 16.0
3. Rename the default app struct file to `DictusApp.swift` if Xcode names it differently
4. Create a minimal `ContentView.swift` that shows "Dictus" title and a placeholder for diagnostic output:

```swift
// DictusApp/ContentView.swift
import SwiftUI
import DictusCore

struct ContentView: View {
    @State private var diagnosticResult: DiagnosticResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Dictus")
                    .font(.largeTitle.bold())

                if let result = diagnosticResult {
                    DiagnosticView(result: result)
                } else {
                    ProgressView("Running diagnostics...")
                }
            }
            .padding()
            .navigationTitle("Dictus")
        }
        .task {
            diagnosticResult = AppGroupDiagnostic.run()
        }
    }
}
```

5. Create a simple `DiagnosticView` inside `ContentView.swift` (or a separate file) that displays canRead/canWrite/appGroupID status with green/red indicators

**Files:**
- `DictusApp/DictusApp.swift` — SwiftUI @main entry point
- `DictusApp/ContentView.swift` — Main view with diagnostic display
- `Dictus.xcodeproj/project.pbxproj` — Project configuration

**Done when:**
- DictusApp target builds and runs in simulator showing "Dictus" and diagnostic results
</task>

<task id="1.1.2" title="Create DictusCore local SPM package" estimated_effort="M">
**What:** Create the shared framework as a local Swift Package with all foundation types.
**Why:** DictusCore centralizes all shared logic (App Group access, status models, notification names) so both targets use identical code. This prevents the most common cross-process bug: mismatched keys or group IDs.
**How:**
1. Create directory `DictusCore/` at project root with `Sources/DictusCore/` subdirectory
2. Create `DictusCore/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DictusCore",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "DictusCore", targets: ["DictusCore"])
    ],
    targets: [
        .target(name: "DictusCore", path: "Sources/DictusCore"),
        .testTarget(
            name: "DictusCoreTests",
            dependencies: ["DictusCore"],
            path: "Tests/DictusCoreTests"
        )
    ]
)
```

3. Create `AppGroup.swift` — single source of truth for the App Group identifier:

```swift
// DictusCore/Sources/DictusCore/AppGroup.swift
import Foundation

public enum AppGroup {
    public static let identifier = "group.com.pivi.dictus"

    /// Shared UserDefaults for cross-process data.
    /// Force-unwrap justified: if this fails, the App Group entitlement
    /// is misconfigured and the app cannot function.
    public static var defaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            fatalError("App Group '\(identifier)' not configured. Check entitlements.")
        }
        return defaults
    }

    /// Shared file container URL for larger data (audio, models metadata).
    public static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }
}
```

4. Create `DictationStatus.swift`:

```swift
// DictusCore/Sources/DictusCore/DictationStatus.swift
import Foundation

/// Represents the current state of a dictation round-trip.
/// Written to App Group UserDefaults so both processes can track progress.
public enum DictationStatus: String, Codable {
    case idle         // No dictation in progress
    case requested    // Keyboard triggered dictus://dictate
    case recording    // Main app is recording audio
    case transcribing // Main app is running transcription
    case ready        // Transcription result available in shared storage
    case failed       // Something went wrong
}
```

5. Create `SharedKeys.swift` — all UserDefaults keys in one place:

```swift
// DictusCore/Sources/DictusCore/SharedKeys.swift
import Foundation

/// Centralized UserDefaults keys for App Group shared storage.
/// Using an enum with static properties prevents typo-based bugs.
public enum SharedKeys {
    public static let dictationStatus = "dictus.dictationStatus"
    public static let lastTranscription = "dictus.lastTranscription"
    public static let lastTranscriptionTimestamp = "dictus.lastTranscriptionTimestamp"
    public static let lastError = "dictus.lastError"
}
```

6. Create `DarwinNotifications.swift`:

```swift
// DictusCore/Sources/DictusCore/DarwinNotifications.swift
import Foundation

/// Darwin notification names for cross-process signaling.
/// Darwin notifications carry no payload — they are ping-only.
/// After receiving a notification, read the actual data from AppGroup.defaults.
public enum DarwinNotificationName {
    /// Posted by DictusApp when transcription result is written to App Group.
    public static let transcriptionReady = "com.pivi.dictus.transcriptionReady" as CFString

    /// Posted by DictusApp when dictation status changes.
    public static let statusChanged = "com.pivi.dictus.statusChanged" as CFString
}

/// Helper to post and observe Darwin notifications.
/// Thread safety: `observerCallbacks` is accessed from the main thread
/// (registration) and from the Darwin notify thread (callback dispatch).
/// An `NSLock` protects all reads and writes to the dictionary.
public enum DarwinNotificationCenter {
    private static let lock = NSLock()
    private static var observerCallbacks: [String: () -> Void] = [:]

    public static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil, nil, true
        )
    }

    public static func addObserver(
        for name: CFString,
        callback: @escaping () -> Void
    ) {
        lock.lock()
        observerCallbacks[name as String] = callback
        lock.unlock()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, cfName, _, _ in
                guard let cfName = cfName else { return }
                let key = cfName.rawValue as String
                lock.lock()
                let cb = observerCallbacks[key]
                lock.unlock()
                cb?()
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    /// Remove a specific observer by notification name.
    /// Prefer this over removeAllObservers() for safer cleanup.
    public static func removeObserver(for name: CFString) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(
            center,
            nil,
            CFNotificationName(name),
            nil
        )
        lock.lock()
        observerCallbacks.removeValue(forKey: name as String)
        lock.unlock()
    }

    /// Remove all registered observers.
    /// Uses per-notification removal for safety instead of
    /// CFNotificationCenterRemoveEveryObserver (which requires a
    /// non-nil observer pointer to be safe).
    public static func removeAllObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        lock.lock()
        let names = Array(observerCallbacks.keys)
        observerCallbacks.removeAll()
        lock.unlock()

        for name in names {
            CFNotificationCenterRemoveObserver(
                center,
                nil,
                CFNotificationName(name as CFString),
                nil
            )
        }
    }
}
```

7. Create `AppGroupDiagnostic.swift`:

```swift
// DictusCore/Sources/DictusCore/AppGroupDiagnostic.swift
import Foundation
import os.log

public struct DiagnosticResult {
    public let canWrite: Bool
    public let canRead: Bool
    public let appGroupID: String
    public let containerExists: Bool
    public let timestamp: Date

    public var isHealthy: Bool {
        canWrite && canRead && containerExists
    }
}

public enum AppGroupDiagnostic {
    private static let logger = Logger(
        subsystem: "com.pivi.dictus",
        category: "diagnostic"
    )

    /// Run a full diagnostic check on the App Group shared container.
    /// Call from both DictusApp.init() and KeyboardViewController.viewDidLoad().
    public static func run() -> DiagnosticResult {
        let defaults = AppGroup.defaults
        let testKey = "diagnostic.test"
        let testValue = "ok-\(Date().timeIntervalSince1970)"

        // Write test
        defaults.set(testValue, forKey: testKey)
        defaults.synchronize()

        // Read test
        let readBack = defaults.string(forKey: testKey)
        let canWrite = readBack == testValue
        let canRead = readBack != nil

        // Container test
        let containerExists = AppGroup.containerURL != nil

        let result = DiagnosticResult(
            canWrite: canWrite,
            canRead: canRead,
            appGroupID: AppGroup.identifier,
            containerExists: containerExists,
            timestamp: Date()
        )

        logger.info(
            "AppGroup diagnostic: canWrite=\(canWrite) canRead=\(canRead) container=\(containerExists)"
        )

        // Clean up test key
        defaults.removeObject(forKey: testKey)

        return result
    }
}
```

8. Create `Logger.swift` for consistent logging across both targets:

```swift
// DictusCore/Sources/DictusCore/Logger.swift
import os.log

/// Centralized loggers for Dictus subsystems.
/// Usage: DictusLogger.keyboard.debug("message")
public enum DictusLogger {
    public static let app = Logger(subsystem: "com.pivi.dictus", category: "app")
    public static let keyboard = Logger(subsystem: "com.pivi.dictus", category: "keyboard")
    public static let appGroup = Logger(subsystem: "com.pivi.dictus", category: "appGroup")
}
```

9. Add the local package to Xcode project: drag `DictusCore/` folder into the project navigator, then add `DictusCore` library to both DictusApp and DictusKeyboard under "Frameworks, Libraries, and Embedded Content"

**Files:**
- `DictusCore/Package.swift` — Package manifest
- `DictusCore/Sources/DictusCore/AppGroup.swift` — App Group access singleton
- `DictusCore/Sources/DictusCore/DictationStatus.swift` — Status enum
- `DictusCore/Sources/DictusCore/SharedKeys.swift` — UserDefaults key constants
- `DictusCore/Sources/DictusCore/DarwinNotifications.swift` — Cross-process signals
- `DictusCore/Sources/DictusCore/AppGroupDiagnostic.swift` — Health check
- `DictusCore/Sources/DictusCore/Logger.swift` — os.log wrappers

**Done when:**
- `import DictusCore` compiles in both DictusApp and DictusKeyboard targets
- All seven source files compile without warnings
- `DictusCoreTests` target exists in Package.swift
</task>

<task id="1.1.7" title="Add DictusCoreTests with basic unit tests" estimated_effort="S">
**What:** Create a test target in the DictusCore package with unit tests for `AppGroupDiagnostic`, `DictationStatus`, and `SharedKeys`.
**Why:** DictusCore contains all shared logic — testing it early catches misconfigurations before they surface as cross-process bugs. The research notes that keyboard extension code cannot be unit tested directly, so all testable logic should live in DictusCore.
**How:**
1. Create `DictusCore/Tests/DictusCoreTests/` directory
2. Create `DictusCoreTests.swift`:

```swift
// DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift
import XCTest
@testable import DictusCore

final class DictusCoreTests: XCTestCase {

    func testAppGroupIdentifier() {
        XCTAssertEqual(AppGroup.identifier, "group.com.pivi.dictus")
    }

    func testDictationStatusRawValues() {
        // Verify raw values match what we write to UserDefaults
        XCTAssertEqual(DictationStatus.idle.rawValue, "idle")
        XCTAssertEqual(DictationStatus.requested.rawValue, "requested")
        XCTAssertEqual(DictationStatus.recording.rawValue, "recording")
        XCTAssertEqual(DictationStatus.transcribing.rawValue, "transcribing")
        XCTAssertEqual(DictationStatus.ready.rawValue, "ready")
        XCTAssertEqual(DictationStatus.failed.rawValue, "failed")
    }

    func testDictationStatusCodable() throws {
        let status = DictationStatus.recording
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DictationStatus.self, from: data)
        XCTAssertEqual(decoded, status)
    }

    func testSharedKeysAreUnique() {
        let keys = [
            SharedKeys.dictationStatus,
            SharedKeys.lastTranscription,
            SharedKeys.lastTranscriptionTimestamp,
            SharedKeys.lastError,
        ]
        XCTAssertEqual(keys.count, Set(keys).count, "SharedKeys must be unique")
    }

    func testSharedKeysPrefix() {
        // All keys should use dictus. prefix to avoid collisions
        XCTAssertTrue(SharedKeys.dictationStatus.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.lastTranscription.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.lastTranscriptionTimestamp.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.lastError.hasPrefix("dictus."))
    }

    func testAppGroupDiagnosticRun() {
        // Note: This test works in simulator where App Group may not be
        // configured. It verifies the function runs without crashing.
        // On device with correct entitlements, canWrite/canRead should be true.
        let result = AppGroupDiagnostic.run()
        XCTAssertEqual(result.appGroupID, AppGroup.identifier)
        // containerExists may be false in test environment — that's OK
    }
}
```

**Files:**
- `DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift` — Unit tests for core types

**Done when:**
- `swift test` in `DictusCore/` directory passes all tests
- Tests verify SharedKeys uniqueness, DictationStatus encoding, and AppGroup identifier
</task>

<task id="1.1.3" title="Create DictusKeyboard extension target" estimated_effort="M">
**What:** Add a Custom Keyboard Extension target to the Xcode project with a minimal `UIInputViewController` subclass that hosts an empty SwiftUI view.
**Why:** The keyboard extension is the second process in the two-process architecture. It must exist as a separate target with its own Info.plist, entitlements, and build settings.
**How:**
1. In Xcode: File > New > Target > iOS > Custom Keyboard Extension, name `DictusKeyboard`
2. Xcode generates `KeyboardViewController.swift` — replace with the UIHostingController pattern:

```swift
// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import DictusCore

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Run diagnostic on every keyboard load (debug builds)
        #if DEBUG
        let result = AppGroupDiagnostic.run()
        DictusLogger.keyboard.debug(
            "Diagnostic: canWrite=\(result.canWrite) canRead=\(result.canRead)"
        )
        #endif

        let rootView = KeyboardRootView(controller: self)
        let hosting = UIHostingController(rootView: rootView)

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        // Remove default background so the keyboard blends with host app
        hosting.view.backgroundColor = .clear

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
```

3. Create a minimal `KeyboardRootView.swift` placeholder:

```swift
// DictusKeyboard/KeyboardRootView.swift
import SwiftUI

/// Root SwiftUI view for the keyboard extension.
/// Plan 1.3 replaces this placeholder with the full AZERTY layout.
struct KeyboardRootView: View {
    let controller: UIInputViewController

    var body: some View {
        VStack {
            Text("Dictus Keyboard")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Next Keyboard") {
                controller.advanceToNextInputMode()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .background(Color(.secondarySystemBackground))
    }
}
```

4. Verify `EXTENSION_SAFE_API_ONLY = YES` in DictusKeyboard build settings (Xcode sets this automatically for new extension targets — confirm it)
5. Set DictusKeyboard deployment target to iOS 16.0

**Files:**
- `DictusKeyboard/KeyboardViewController.swift` — UIInputViewController + UIHostingController
- `DictusKeyboard/KeyboardRootView.swift` — Placeholder SwiftUI view
- `DictusKeyboard/Info.plist` — Extension configuration

**Done when:**
- DictusKeyboard target builds without warnings
- Keyboard can be selected via Globe key in simulator and shows "Dictus Keyboard" text
- "Next Keyboard" button switches away from Dictus keyboard
</task>

<task id="1.1.4" title="Configure App Group entitlements on both targets" estimated_effort="S">
**What:** Add the App Group capability with identifier `group.com.pivi.dictus` to both DictusApp and DictusKeyboard targets.
**Why:** Without matching App Group entitlements on both targets, `UserDefaults(suiteName:)` returns nil and cross-process data sharing fails silently — the most common configuration bug in keyboard extension projects.
**How:**
1. Select DictusApp target > Signing & Capabilities > + Capability > App Groups
2. Add `group.com.pivi.dictus`
3. Xcode creates `DictusApp/DictusApp.entitlements` with:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.pivi.dictus</string>
</array>
```

4. Repeat for DictusKeyboard target — creates `DictusKeyboard/DictusKeyboard.entitlements`
5. Verify both `.entitlements` files contain the identical group ID string

**Files:**
- `DictusApp/DictusApp.entitlements` — App Group capability
- `DictusKeyboard/DictusKeyboard.entitlements` — App Group capability

**Done when:**
- Both entitlement files exist with `group.com.pivi.dictus`
- `AppGroupDiagnostic.run()` returns `canRead: true, canWrite: true` from the DictusApp target in simulator
</task>

<task id="1.1.5" title="Configure DictusKeyboard Info.plist" estimated_effort="S">
**What:** Set the required NSExtension attributes in the keyboard extension's Info.plist: RequestsOpenAccess, PrimaryLanguage, IsASCIICapable, and NSExtensionPrincipalClass.
**Why:** `RequestsOpenAccess = true` is required for Full Access (which enables App Group writes and mic triggering). `PrimaryLanguage = fr-FR` tells iOS this is a French keyboard. These must be set correctly or the keyboard will not function as expected.
**How:**
1. Open `DictusKeyboard/Info.plist` and ensure the NSExtension dictionary contains:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>RequestsOpenAccess</key>
        <true/>
        <key>PrimaryLanguage</key>
        <string>fr-FR</string>
        <key>IsASCIICapable</key>
        <true/>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.keyboard-service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).KeyboardViewController</string>
</dict>
```

2. Add `NSMicrophoneUsageDescription` to DictusApp's Info.plist (needed for Phase 2 recording, but good to set early):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Dictus needs microphone access to transcribe your voice.</string>
```

**Files:**
- `DictusKeyboard/Info.plist` — Extension attributes
- `DictusApp/Info.plist` — Microphone usage description

**Done when:**
- Keyboard appears in Settings > General > Keyboard > Keyboards > Add New Keyboard as "Dictus"
- Full Access toggle is visible when Dictus keyboard is added
</task>

<task id="1.1.6" title="Run AppGroupDiagnostic from both launch paths" estimated_effort="S">
**What:** Call `AppGroupDiagnostic.run()` at startup in both DictusApp and KeyboardViewController, and display results visually in DictusApp.
**Why:** This is the Phase 1 success criterion: "AppGroupDiagnostic logs confirm both targets can read and write to group.com.pivi.dictus." Having it run automatically on every launch catches entitlement misconfigurations immediately.
**How:**
1. In `DictusApp.swift`, add diagnostic logging in init:

```swift
@main
struct DictusApp: App {
    init() {
        let result = AppGroupDiagnostic.run()
        DictusLogger.app.info(
            "AppGroup diagnostic: healthy=\(result.isHealthy)"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

2. KeyboardViewController already runs diagnostic in `viewDidLoad()` (added in task 1.1.3)
3. The `ContentView` from task 1.1.1 already displays `DiagnosticView` — implement it with clear green/red indicators:

```swift
struct DiagnosticView: View {
    let result: DiagnosticResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "App Group: \(result.appGroupID)",
                systemImage: result.containerExists ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundColor(result.containerExists ? .green : .red)

            Label(
                "Read: \(result.canRead ? "OK" : "Failed")",
                systemImage: result.canRead ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundColor(result.canRead ? .green : .red)

            Label(
                "Write: \(result.canWrite ? "OK" : "Failed")",
                systemImage: result.canWrite ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundColor(result.canWrite ? .green : .red)
        }
        .font(.system(.body, design: .monospaced))
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}
```

**Files:**
- `DictusApp/DictusApp.swift` — Add diagnostic call in init
- `DictusApp/ContentView.swift` — DiagnosticView implementation

**Done when:**
- DictusApp shows green checkmarks for all three diagnostic items in simulator
- Xcode console shows diagnostic log from KeyboardViewController when switching to Dictus keyboard
</task>

</tasks>

## Verification
- [ ] `xcodebuild -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 15' build` succeeds
- [ ] `xcodebuild -scheme DictusKeyboard -destination 'platform=iOS Simulator,name=iPhone 15' build` succeeds
- [ ] DictusApp launches and shows three green diagnostic checkmarks
- [ ] Dictus keyboard appears in Settings > Keyboards list in simulator
- [ ] Switching to Dictus keyboard via Globe key shows placeholder view without crash
- [ ] Xcode console shows AppGroupDiagnostic logs from both targets
- [ ] No compiler warnings related to extension-unsafe API usage
- [ ] `swift test` passes in `DictusCore/` directory (DictusCoreTests)
