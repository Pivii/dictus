# Phase 1: Cross-Process Foundation — Research

**Researched:** 2026-03-04
**Status:** Complete

## Executive Summary

The two-process dictation architecture is well-established and technically sound for iOS, but contains one critical unsolved problem: there is no App Store-approved API to automatically return the user from the main app back to the host app after dictation. Opening the main app from the keyboard extension works via SwiftUI `Link` (the old selector-based method broke in iOS 18). The App Group + `UserDefaults(suiteName:)` pattern is reliable for data sharing. The keyboard shell built with `UIHostingController` + SwiftUI inside `UIInputViewController` is a proven pattern. All five phase plans are achievable with the constraints noted below.

---

## 1. iOS Keyboard Extension Architecture

### UIInputViewController

The keyboard extension's primary view controller is a subclass of `UIInputViewController`. It manages the keyboard's lifecycle and provides access to `textDocumentProxy` for text insertion.

Key lifecycle methods:
- `viewDidLoad()` — one-time setup; add the SwiftUI view here
- `viewWillAppear()` — called each time the keyboard becomes visible
- `viewDidDisappear()` — called when the keyboard hides
- `textDidChange(_ textInput: UITextInput?)` — called when cursor position or text changes; use to react to keyboard type, return key type, autocapitalization

Key property:
- `textDocumentProxy: UITextDocumentProxy` — insert text with `insertText("a")`, delete with `deleteBackward()`, move cursor with `adjustTextPositionByCharacterOffset(_:)`

### Memory Limit

The memory budget for keyboard extensions is officially undocumented, but is experimentally confirmed to be approximately **48–50 MB**. Developer reports show that exceeding this causes `EXC_RESOURCE (RESOURCE_TYPE_MEMORY)` termination with no user-facing error. The CLAUDE.md figure of ~50 MB is consistent with this.

**Practical implication for Phase 1:** No ML models are loaded in the keyboard extension. The keyboard shell alone is safe. WhisperKit models load only in the main app (DictusApp target). Phase 1 is safe from memory pressure.

### APPLICATION_EXTENSION_API_ONLY

Xcode automatically sets `APPLICATION_EXTENSION_API_ONLY = YES` on new extension targets. This causes the compiler to reject calls to APIs annotated as `@available(iOSApplicationExtension, unavailable)`. The most important forbidden APIs for Dictus:

- `UIApplication.shared` — unavailable; use `textDocumentProxy` or responder chain workarounds
- `AVAudioSession` microphone recording — only available with Full Access granted
- Most inter-process communication except via shared containers and URL schemes via `Link`

For the DictusCore local SPM package: code shared between both targets must annotate any app-only APIs with `@available(iOSApplicationExtension, unavailable)` or the compiler will warn on the extension target. In Xcode 13+, linking a Swift package from an extension target emits warnings for unsafe APIs but does not fail the build — you must address them explicitly.

### textDocumentProxy API

```swift
// Insert character
textDocumentProxy.insertText("a")

// Delete backward (backspace)
textDocumentProxy.deleteBackward()

// Move cursor right by 1
textDocumentProxy.adjustTextPositionByCharacterOffset(1)

// Insert space
textDocumentProxy.insertText(" ")

// Insert newline (Return key)
textDocumentProxy.insertText("\n")
```

---

## 2. App Group & Cross-Process Communication

### Setup

Both targets (DictusApp and DictusKeyboard) must have the App Group capability added in Xcode under Signing & Capabilities. The group identifier must be identical in both — `group.com.pivi.dictus`. Each target needs its own `.entitlements` file with the `com.apple.security.application-groups` key.

In Xcode 15+, managed capabilities can be enabled directly in the Signing & Capabilities tab, which updates provisioning profiles automatically.

### Shared UserDefaults

```swift
// Create a shared UserDefaults — use this everywhere in DictusCore
let sharedDefaults = UserDefaults(suiteName: "group.com.pivi.dictus")

// Write (e.g., from DictusApp after transcription)
sharedDefaults?.set("Bonjour le monde", forKey: "lastTranscription")
sharedDefaults?.set("idle", forKey: "dictationStatus")

// Read (e.g., from DictusKeyboard)
let result = sharedDefaults?.string(forKey: "lastTranscription")
```

**Gotcha — synchronize():** The `.synchronize()` method is deprecated but is sometimes needed immediately before suspension to flush pending writes. Omitting it can cause the reading process to see stale data. The safe pattern: write then call `.synchronize()` explicitly when the data must be readable immediately by another process.

**Gotcha — App Group ID mismatch:** If the `suiteName` strings are even slightly different between targets, reads return `nil` silently. Centralise the group ID string as a constant in DictusCore:

```swift
// DictusCore/Sources/DictusCore/AppGroup.swift
public enum AppGroup {
    public static let identifier = "group.com.pivi.dictus"
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier)! // Force-unwrap justified: misconfiguration is fatal
    }
}
```

### Shared File Container

Beyond UserDefaults, both processes can access a shared directory:

```swift
let containerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.pivi.dictus"
)
```

Use this for larger data (e.g., audio buffers, future model metadata). For Phase 1, UserDefaults keys are sufficient.

### Darwin Notifications for Cross-Process Signaling

UserDefaults alone does not wake a suspended process. To signal the keyboard that new data is available, use Darwin Notifications (system-wide, cross-process):

```swift
// Post a signal (from DictusApp when transcription is ready)
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    "com.pivi.dictus.transcriptionReady" as CFNotificationName,
    nil, nil, true
)

// Observe (from DictusKeyboard)
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDarwinNotifyCenter(),
    nil,
    { _, _, name, _, _ in
        // New transcription available — read from UserDefaults
    },
    "com.pivi.dictus.transcriptionReady" as CFString,
    nil,
    .deliverImmediately
)
```

**Limitation:** Darwin notifications carry no payload. They are ping-only. The actual data is read from shared UserDefaults after receiving the notification. This is the standard pattern — notify + read.

### Race Conditions

Write-then-notify is safe if the write completes before the notification is posted. The risk is the keyboard reading UserDefaults before the write flushes. Mitigation: call `sharedDefaults.synchronize()` before posting the Darwin notification.

---

## 3. URL Scheme Communication

### Opening the Main App from the Keyboard Extension

**This is the most nuanced problem in Phase 1.** The history of approaches:

| Approach | iOS 16 | iOS 17 | iOS 18 | App Store Safe |
|----------|--------|--------|--------|----------------|
| Responder chain selector `openURL:` | Works | Works | Broken | No |
| `UIApplication.shared.open()` | Unavailable in extension | Unavailable | Unavailable | N/A |
| SwiftUI `Link(destination:)` | Works | Works | Works | Yes |
| `openURL` environment value | Works | Works | Works | Yes |

**The only App Store-safe, iOS 18-compatible approach is SwiftUI `Link`.**

A SwiftUI `Link` view, when tapped, causes the system to open the URL, switching to the target app. It works from within a keyboard extension because the system handles the URL opening — not UIApplication directly.

```swift
// In the keyboard's SwiftUI view
Link(destination: URL(string: "dictus://dictate")!) {
    MicButton()
}
```

**Limitation of Link:** You get a `Link` view, not a fully customizable button with arbitrary gesture recognizers. You can style it with `.buttonStyle()` and wrap your custom view inside, but you cannot intercept the tap to perform pre-flight logic and then conditionally open the URL. For Phase 1 (mic button triggers dictation unconditionally), this is not a problem.

### Registering the URL Scheme in DictusApp

In `DictusApp/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.pivi.dictus</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>dictus</string>
        </array>
    </dict>
</array>
```

### Handling the URL in DictusApp

With SwiftUI and the `@main` App lifecycle:

```swift
@main
struct DictusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "dictus" else { return }
        switch url.host {
        case "dictate":
            // Start recording immediately
            DictationCoordinator.shared.startDictation()
        default:
            break
        }
    }
}
```

### The Return-to-Keyboard Problem

**There is no App Store-approved way to automatically return the user from DictusApp to the previous app after dictation completes.**

Research findings:
- `LSApplicationWorkspace` (private API) was rejected by Apple in App Store review
- The responder chain selector approach works in iOS 17 but is rejected by Apple and broken in iOS 18
- `UIApplication.shared.suspend()` returns to the home screen, not the previous app
- x-callback-url requires cooperation from the host app (the app where the keyboard is active)

**What this means for the CONTEXT.md decision "auto-return to the previous app":** This decision cannot be implemented with a supported API. The user will need to manually switch back using the iOS app switcher or the `<` back button that iOS shows when you launch one app from another.

**Recommended approach for Phase 1:** DictusApp should minimize itself as aggressively as possible after transcription. The iOS system's "back to previous app" button (the status bar button or back gesture on certain devices) will appear automatically when the user was in another app and Dictus was opened via URL scheme. Do not implement a `dictus://return` scheme — it cannot be made to reliably navigate back. Write the result to App Group storage, signal via Darwin notification, then call the equivalent of "close the app" by using `UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)` (which is the `suspend` approach — takes user to home, not back). **The cleanest UX for Phase 1 is to let iOS show its natural "< Previous App" chevron in the top-left corner after the URL open.** No code required — iOS handles this automatically when App A opens App B via URL scheme.

---

## 4. SwiftUI in Keyboard Extensions

### UIHostingController Setup Pattern

The standard and reliable approach to embed SwiftUI inside `UIInputViewController`:

```swift
class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboardView = KeyboardView(controller: self)
        let hosting = UIHostingController(rootView: keyboardView)

        // Must retain or it will be deallocated immediately
        self.hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

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

**Critical gotcha — strong reference:** If `hostingController` is not stored as a property, it gets deallocated immediately after `viewDidLoad()` returns, causing a blank keyboard. Always store it.

### Passing textDocumentProxy to SwiftUI

The SwiftUI view cannot directly access `textDocumentProxy` (it's on `UIInputViewController`). Pass it as a dependency or via an `ObservableObject`:

```swift
// Option A: Pass controller reference (simpler for Phase 1)
struct KeyboardView: View {
    let controller: UIInputViewController

    var body: some View {
        // ...
        Button("A") {
            controller.textDocumentProxy.insertText("a")
        }
    }
}

// Option B: ObservableObject coordinator (cleaner for Phase 2+)
class KeyboardCoordinator: ObservableObject {
    weak var inputViewController: UIInputViewController?
    // ...
}
```

### Size and Layout

The keyboard extension view's height is determined by its content. iOS does not enforce a fixed height — your SwiftUI layout dictates the keyboard height. Use fixed heights for rows to maintain stable layout. Target approximately 216pt (portrait iPhone) and 162pt (landscape iPhone) for standard keyboard height, matching the system keyboard.

### Dark/Light Mode

SwiftUI adapts to the trait collection of the host app automatically. Inside the extension, use standard SwiftUI colors (`Color(.systemBackground)`, `Color(.label)`, `Color(.secondarySystemBackground)`) to get automatic dark/light mode support. The keyboard extension inherits the user interface style from the host text field's parent app.

### Performance

- Keyboard must appear within ~300ms of user switching to it or iOS will show a blank view
- Avoid heavy computation in `viewDidLoad()` and `viewWillAppear()`
- SwiftUI views should be lightweight; avoid `@StateObject` creation that triggers network calls on appear
- System font and SF Symbols load quickly and require no additional setup

---

## 5. AZERTY Keyboard Layout

### Standard French AZERTY Layout (iOS-matching)

The iOS native French AZERTY keyboard uses this key arrangement:

**Row 1 (top letters):**
`A  Z  E  R  T  Y  U  I  O  P`

**Row 2 (home row):**
`Q  S  D  F  G  H  J  K  L  M`

**Row 3 (with shift key):**
`[Shift]  W  X  C  V  B  N  [Delete]`

**Row 4 (bottom):**
`[Globe]  [123]  [Mic]  [Space]  [Return]`

### Accented Characters via Long Press

Standard French accented characters via long press (matching iOS native behavior):

| Key | Long press options |
|-----|--------------------|
| A | à â ä æ |
| E | é è ê ë |
| I | î ï |
| O | ô ö œ |
| U | ù û ü |
| C | ç |
| Y | ÿ |

### Numbers/Symbols Layer

When `[123]` is tapped, the keyboard switches to a numbers/symbols layer. Standard iOS AZERTY number row:

**Row 1:** `1  2  3  4  5  6  7  8  9  0`
**Row 2:** `-  /  :  ;  (  )  €  &  @  "`
**Row 3:** `[#+= toggle]  .  ,  ?  !  '  [Delete]`
**Row 4:** `[ABC]  [Space]  [Return]`

### Key Dimensions (Standard iPhone, Portrait)

- Total keyboard width: screen width
- Letter key width: approximately screen_width / 10 (with small gaps)
- Standard key height: approximately 42pt
- Space bar: approximately 50% of row width
- Bottom row: proportionally wider keys

### Globe Key (Keyboard Switcher)

The globe key calls `advanceToNextInputMode()` on the input view controller:

```swift
Button {
    controller.advanceToNextInputMode()
} label: {
    Image(systemName: "globe")
}
```

### System Click Sound

The system keyboard click sound requires the `UIInputViewAudioFeedback` protocol on the keyboard view's *UIView subclass* (not the SwiftUI view). When using `UIHostingController`, the hosting view does not automatically conform. You need to subclass `UIView` and override `enableInputClicksWhenVisible`:

```swift
class InputView: UIView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { return true }
}
```

Then set this as the `inputView` of `UIInputViewController`. Alternatively, call `UIDevice.current.playInputClick()` directly from button tap handlers — but note that this **may hang for several seconds** if Full Access is not granted. Play click sounds **only when `hasFullAccess == true`**.

---

## 6. Full Access Detection & Graceful Degradation

### Checking Full Access

```swift
// Inside UIInputViewController or any code that has a reference to it
let hasFull: Bool = inputViewController.hasFullAccess
```

`hasFullAccess` is available since iOS 11. Returns `true` only if:
1. The extension's Info.plist has `RequestsOpenAccess = YES`
2. The user has enabled Full Access in Settings > General > Keyboard > Dictus

### What Full Access Enables

With Full Access:
- App Group shared container access (write from extension side)
- Network access
- Microphone trigger (though actual recording happens in main app in Dictus's architecture)
- System keyboard click sounds via `playInputClick()`
- Access to pasteboard (UIPasteboard)

**Without Full Access (default):**
- `textDocumentProxy` still works — basic typing works
- App Group reads work (the extension can read data written by the main app)
- App Group writes from the extension side are restricted — this affects status signaling
- No network, no microphone, no pasteboard

**Architecture implication for Dictus:** Because the keyboard extension writes `DictationStatus` to the App Group (to signal "I requested dictation"), this requires Full Access. Without it, the round-trip cannot complete. The CONTEXT.md decision to show a persistent banner when Full Access is off is the correct approach.

### Info.plist Configuration

In `DictusKeyboard/Info.plist`:

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

### Graceful Degradation Pattern

```swift
struct KeyboardView: View {
    let controller: UIInputViewController

    var body: some View {
        VStack(spacing: 0) {
            if !controller.hasFullAccess {
                FullAccessBanner()  // Deep-links to Settings
            }
            KeyboardRows(controller: controller)
        }
    }
}

struct MicButton: View {
    let hasFullAccess: Bool

    var body: some View {
        Button {
            if hasFullAccess {
                // Trigger dictation via Link — see URL scheme section
            } else {
                // Show inline explanation
            }
        } label: {
            Image(systemName: "mic.fill")
                .foregroundColor(hasFullAccess ? .blue : .gray)
        }
        .disabled(!hasFullAccess) // Note: can't use disabled() with Link, handle in tap
    }
}
```

**Settings deep link** (open Dictus settings page):
```swift
Link("Activer l'Accès complet", destination: URL(string: UIApplication.openSettingsURLString)!)
```

Note: `UIApplication.openSettingsURLString` is `@available(iOSApplicationExtension, unavailable)` — access it via a wrapper in DictusCore that is annotated appropriately, or use the literal string `"app-settings:"`.

---

## 7. DictusCore SPM Package Structure

### Creating a Local Package

In Xcode:
1. File > New > Package
2. Name: `DictusCore`
3. Save inside the project directory: `Dictus/DictusCore/`
4. Add to both targets: DictusApp and DictusKeyboard

Alternatively, add a `Package.swift` file manually to the workspace root:

```swift
// DictusCore/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DictusCore",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "DictusCore",
            targets: ["DictusCore"]
        )
    ],
    targets: [
        .target(
            name: "DictusCore",
            path: "Sources/DictusCore"
        )
    ]
)
```

### Extension Safety in DictusCore

When DictusCore is linked from both the app and the extension, any API in DictusCore that calls extension-unavailable APIs must be annotated:

```swift
// DictusCore/Sources/DictusCore/AppGroup.swift

@available(iOSApplicationExtension, unavailable)
public func openSettings() {
    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
}

// Extension-safe alternative
public var settingsURL: URL {
    URL(string: "app-settings:")!
}
```

### Recommended File Structure for Phase 1

```
DictusCore/
├── Package.swift
└── Sources/
    └── DictusCore/
        ├── AppGroup.swift          // AppGroup.identifier, AppGroup.defaults
        ├── DictationStatus.swift   // enum DictationStatus: String
        ├── SharedKeys.swift        // UserDefaults key constants
        ├── AppGroupDiagnostic.swift // Diagnostic check: can read/write?
        └── DarwinNotifications.swift // Cross-process notification names
```

### DictationStatus Model

```swift
// DictusCore/Sources/DictusCore/DictationStatus.swift
public enum DictationStatus: String, Codable {
    case idle         // No dictation in progress
    case requested    // Keyboard sent dictus://dictate, waiting for app
    case recording    // Main app is recording audio
    case transcribing // Main app is running WhisperKit
    case ready        // Transcription result is available in shared storage
    case failed       // Something went wrong
}
```

### AppGroupDiagnostic

```swift
// DictusCore/Sources/DictusCore/AppGroupDiagnostic.swift
public struct AppGroupDiagnostic {
    public static func run() -> DiagnosticResult {
        let defaults = AppGroup.defaults
        let testKey = "diagnostic.test"
        let testValue = "ok-\(Date().timeIntervalSince1970)"

        defaults.set(testValue, forKey: testKey)
        defaults.synchronize()

        let readBack = defaults.string(forKey: testKey)
        let success = readBack == testValue

        return DiagnosticResult(
            canWrite: success,
            canRead: readBack != nil,
            appGroupID: AppGroup.identifier
        )
    }
}

public struct DiagnosticResult {
    public let canWrite: Bool
    public let canRead: Bool
    public let appGroupID: String
}
```

---

## 8. Validation Architecture

### Why XCTest Is Impractical for Keyboard Extensions

Unit tests cannot run directly inside a keyboard extension target. The extension runs in its own process with a different entrypoint and lifecycle. Attempting to create a test target with the keyboard extension as the host will fail because extensions are not apps.

**Working approach:** Put all logic in DictusCore (or a testable framework) and test the framework. The `UIInputViewController` subclass stays thin — it only wires up dependencies.

### Validation Strategy for Phase 1

Since Phase 1 is infrastructure, validation is manual + diagnostic-assisted:

**Level 1: DictusCore Unit Tests**
- Create a separate `DictusCoreTests` test target in the Xcode project (not in SPM)
- Test `AppGroupDiagnostic.run()` → confirm it reads/writes
- Test `DictationStatus` encoding/decoding
- Test `SharedKeys` constants are correct strings
- These tests run in the simulator and on device without any special setup

**Level 2: AppGroupDiagnostic on Both Launch Paths**
- Add `AppGroupDiagnostic.run()` call in `DictusApp.init()` and `KeyboardViewController.viewDidLoad()`
- Log result with `print()` / `os.log` — visible in Xcode console when connected to device
- **Criterion:** Both targets log `canWrite: true, canRead: true`

**Level 3: Device-Only Round-Trip Manual Test**
The success criteria from the phase description requires a physical iPhone (keyboard extensions require real device for full testing — the simulator's keyboard behavior is limited):

1. Install both targets on device via Xcode
2. Go to Settings > General > Keyboard > Keyboards > Add New Keyboard > Dictus
3. Enable Full Access for Dictus
4. Open Notes (or any app with a text field)
5. Switch to Dictus keyboard via Globe key → **Criterion: keyboard appears without crash**
6. Type letters A, Z, E, Space, Delete, Return → **Criterion: text appears correctly in Notes**
7. Tap mic button → **Criterion: DictusApp opens**
8. Observe DictusApp console log: writes transcription stub to App Group
9. System returns user to Notes (via back button or switcher)
10. Keyboard shows status indicator, then inserted stub text → **Criterion: round trip complete**

**Level 4: Instrumentation Checklist**
- Instruments > Memory: confirm keyboard extension stays under 30 MB during normal operation
- Instruments > Time Profiler: confirm keyboard responds within 300ms on first character tap

### Simulator Limitations

- Keyboard extensions can be installed and switched to in the simulator
- Simulator does not support microphone access
- App Group shared container works in simulator (different path from device but functional)
- URL scheme opening does work in simulator

---

## Key Risks & Mitigations

### Risk 1 — Auto-Return from DictusApp is Impossible
**Severity: High | Probability: Confirmed**

There is no App Store-approved API to return the user to the previous app after dictation. Every available approach (LSApplicationWorkspace, responder chain, UIApplication.shared methods) is either a private API or broken in iOS 18.

**Mitigation:** Rely on iOS's natural "< App Name" button that appears in the status bar when one app opens another via URL scheme. This is automatic and requires no code. Update the user decision in CONTEXT.md: "auto-return" should be reframed as "the system provides a back button automatically." Phase 1 should validate this UX is acceptable, not build custom navigation.

### Risk 2 — SwiftUI Link Cannot Be Conditionally Triggered
**Severity: Medium | Probability: Confirmed**

`Link` is the only iOS 18-safe way to open URLs from a keyboard extension. But `Link` activates on tap with no opportunity to run pre-flight logic (e.g., "check if Full Access is enabled before opening").

**Mitigation:** Use a conditional: show `Link` only when `hasFullAccess == true`. When `hasFullAccess == false`, show a regular `Button` that displays the inline explanation. Do not gate the `Link` tap — instead gate whether the `Link` is shown at all.

### Risk 3 — UserDefaults Race Condition
**Severity: Medium | Probability: Possible**

The keyboard reads transcription data from App Group UserDefaults. If the main app writes and signals before UserDefaults flushes to disk, the keyboard reads stale (empty) data.

**Mitigation:** Always call `sharedDefaults.synchronize()` before posting the Darwin notification in DictusApp. On the keyboard side, add a small retry: re-read after 100ms if the value is nil. This is safe and simple for Phase 1.

### Risk 4 — Memory Budget Creep
**Severity: Low for Phase 1, High for Phase 2**

Phase 1 loads no ML models in the keyboard extension. Risk is low now but becomes critical in Phase 2 if any WhisperKit initialization leaks into the extension.

**Mitigation:** Establish a strict rule in CLAUDE.md/architecture: WhisperKit is only initialized in DictusApp. DictusKeyboard never imports WhisperKit. Enforce via `EXTENSION_SAFE_API_ONLY = YES` — it will not catch this directly (WhisperKit is an SPM library, not a system API), so add a code review checklist item.

### Risk 5 — Full Access Not Granted During Testing
**Severity: Low | Probability: High (during development)**

Without Full Access, many Phase 1 features will not function. Developers frequently forget to enable it after reinstalling.

**Mitigation:** DictusApp's initial view should prominently display Full Access status and link to Settings. `AppGroupDiagnostic` should be visible in the debug UI during Phase 1.

### Risk 6 — Keyboard Entitlement Missing on Device
**Severity: High | Probability: Possible**

If the App Group entitlement is not correctly provisioned (not just added in Xcode, but actually in the provisioning profile), `UserDefaults(suiteName:)` returns `nil` silently on device.

**Mitigation:** The `AppGroupDiagnostic` must check for nil on the UserDefaults initializer itself, not just the values. Log a clear error: "App Group not available — check entitlements and provisioning profile."

---

## Technical Recommendations

### 1. Use SwiftUI Link for the Mic Button — Not a Button with openURL Logic

The mic button must be implemented as a `Link(destination: URL(string: "dictus://dictate")!)` wrapping the visual mic button content. This is the only iOS 16–18 compatible, App Store-safe approach. Accept the constraint that you cannot add arbitrary pre-tap logic to the `Link` itself.

### 2. Centralise App Group Access in DictusCore — Never Access It from Targets Directly

Every App Group read/write must go through `AppGroup.defaults` from DictusCore. This prevents the ID-mismatch bug (the most common source of "data not appearing in the other process" bugs). Make `AppGroup.identifier` a `let` constant, not a `var`.

### 3. Implement Darwin Notifications as the Signal Mechanism

Do not poll UserDefaults. Use Darwin notifications to signal the keyboard when transcription is ready. The keyboard's observer sets an `@Published` property on a coordinator, which drives the SwiftUI state update. This is cleaner than timers and works immediately.

### 4. Accept That "Auto-Return" Requires User Action

The phase context decision says "auto-return to the previous app." Research confirms this is not possible with approved APIs on iOS 16–18. Recommend updating the user decision to: "After transcription, DictusApp shows a brief success screen, then the user taps the system `< [App Name]` button to return." This is what every major dictation keyboard app (including those built on KeyboardKit Pro) does.

### 5. Keep DictusKeyboard Target Extremely Thin

`KeyboardViewController.swift` should do only:
- Initialize `UIHostingController` with the SwiftUI keyboard view
- Run `AppGroupDiagnostic` in debug builds
- Expose `textDocumentProxy` to the coordinator

All logic (key press handling, status state, App Group I/O) lives in DictusCore or the SwiftUI layer. This makes it unit-testable.

### 6. Test on Physical Device from Day One

Do not build Phase 1 relying on simulator validation for the round-trip. The simulator's keyboard extension behavior (especially App Group reads between processes) can differ from device. Allocate time for physical device testing as a first-class part of each plan.

### 7. Implement AppGroupDiagnostic as an Actual Debug Screen

Do not rely on console logs alone. Build a simple debug view in DictusApp (hidden behind a Settings toggle or always visible in DEBUG builds) showing:
- App Group ID
- canRead / canWrite status
- Current DictationStatus from shared defaults
- Last transcription value
- Timestamp of last write

This screen saves hours of debugging during Phase 1.

### 8. Use os.log Instead of print() for Cross-Process Debugging

Both targets running simultaneously means interleaved console output. `os.log` with a subsystem allows filtering by target in the Console app:

```swift
import os.log

let logger = Logger(subsystem: "com.pivi.dictus", category: "keyboard")
logger.debug("AppGroup canWrite: \(result.canWrite)")
```

---

*Phase: 01-cross-process-foundation*
*Research completed: 2026-03-04*

## RESEARCH COMPLETE
