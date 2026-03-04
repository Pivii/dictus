---
phase: 1
plan: "1.2"
title: "Cross-Process Signaling"
wave: 2
depends_on: ["1.1"]
requirements: ["DUX-05", "APP-05"]
files_modified:
  - DictusApp/DictusApp.swift
  - DictusApp/Info.plist
  - DictusApp/DictationCoordinator.swift
  - DictusApp/DictationView.swift
  - DictusApp/ContentView.swift
  - DictusKeyboard/KeyboardViewController.swift
  - DictusKeyboard/KeyboardState.swift
  - DictusKeyboard/Views/MicButtonDisabled.swift
autonomous: true
---

# Plan 1.2: Cross-Process Signaling

## Objective
Implement the two-process dictation round-trip: the keyboard extension triggers the main app via `dictus://dictate` URL scheme, the app writes a stub transcription result to the App Group, signals the keyboard via Darwin notification, and the keyboard reads and displays the result. This proves the core architecture works before any real transcription is added.

**Note on `dictus://return`:** The ROADMAP and CONTEXT.md mention auto-return from DictusApp to the previous app. Research (01-RESEARCH.md, Section 3) confirms there is **no App Store-approved API** to do this on iOS 16-18. Every approach (LSApplicationWorkspace, responder chain selector, UIApplication.shared.suspend()) is either private API, broken in iOS 18, or rejected by App Review. This plan intentionally omits `dictus://return`. Instead, iOS automatically shows a `< [Previous App]` back chevron in the status bar when DictusApp is opened via URL scheme — users tap that to return. No code required.

## must_haves
- [ ] Tapping mic button in keyboard opens DictusApp via `dictus://dictate` URL scheme
- [ ] DictusApp handles `dictus://dictate` URL and writes a stub transcription to App Group
- [ ] DictusApp posts a Darwin notification after writing the transcription
- [ ] DictusKeyboard observes the Darwin notification and reads the transcription from App Group
- [ ] Keyboard displays the stub transcription text as a status message
- [ ] `DictationStatus` transitions correctly: idle -> requested -> recording -> transcribing -> ready
- [ ] iOS shows the natural "< Previous App" back chevron after DictusApp opens via URL scheme
- [ ] The round-trip works on physical device (manual verification)

<tasks>

<task id="1.2.1" title="Register dictus:// URL scheme in DictusApp" estimated_effort="S">
**What:** Add the `dictus` URL scheme to DictusApp's Info.plist so iOS routes `dictus://` URLs to the app.
**Why:** The keyboard extension cannot call `UIApplication.shared.open()` directly. Instead it uses a SwiftUI `Link` that opens `dictus://dictate`, which iOS routes to DictusApp. The URL scheme must be registered or the link does nothing.
**How:**
1. Add to `DictusApp/Info.plist`:

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

2. This can also be done in Xcode: Target > Info > URL Types > Add > URL Schemes: `dictus`, Identifier: `com.pivi.dictus`

**Files:**
- `DictusApp/Info.plist` — CFBundleURLTypes entry

**Done when:**
- Opening `dictus://dictate` in Safari on simulator launches DictusApp
</task>

<task id="1.2.2" title="Create DictationCoordinator in DictusApp" estimated_effort="M">
**What:** Create an `ObservableObject` that manages the dictation lifecycle in the main app: receives the URL trigger, simulates recording and transcription (stub), writes the result to App Group, and signals the keyboard.
**Why:** The coordinator encapsulates the dictation state machine in one place. In Phase 2, the stub will be replaced with real WhisperKit recording and transcription. Keeping it as an `ObservableObject` lets SwiftUI views reactively show the current state.
**How:**
1. Create `DictusApp/DictationCoordinator.swift`:

```swift
// DictusApp/DictationCoordinator.swift
import Foundation
import Combine
import DictusCore

/// Manages the dictation lifecycle in the main app.
/// Phase 1: stub implementation that simulates recording + transcription.
/// Phase 2: replace stubs with real AVAudioEngine + WhisperKit.
@MainActor
class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    @Published var status: DictationStatus = .idle
    @Published var lastResult: String?

    private let defaults = AppGroup.defaults

    private init() {}

    private var dictationTask: Task<Void, Never>?

    /// Called when the app receives dictus://dictate URL.
    func startDictation() {
        DictusLogger.app.info("Dictation started via URL scheme")

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        // Update shared status so keyboard can track progress
        updateStatus(.recording)

        // Simulate recording delay (1.5 seconds)
        dictationTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                // Task was cancelled — clean up
                updateStatus(.idle)
                return
            }
            updateStatus(.transcribing)

            do {
                // Simulate transcription delay (1 second)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                updateStatus(.idle)
                return
            }

            // Write stub result to App Group
            let stubResult = "Bonjour, ceci est un test de dictée."
            writeTranscription(stubResult)
            updateStatus(.ready)

            DictusLogger.app.info("Stub transcription written: \(stubResult)")
        }
    }

    /// Write dictation status to App Group so the keyboard can observe it.
    private func updateStatus(_ newStatus: DictationStatus) {
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()

        // Signal keyboard that status changed
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Write transcription result to App Group and signal the keyboard.
    private func writeTranscription(_ text: String) {
        lastResult = text
        defaults.set(text, forKey: SharedKeys.lastTranscription)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.synchronize()

        // Signal keyboard that transcription is ready
        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
    }

    /// Reset status to idle (e.g., after user returns to keyboard).
    func resetStatus() {
        updateStatus(.idle)
        lastResult = nil
    }
}
```

**Files:**
- `DictusApp/DictationCoordinator.swift` — Dictation state machine and App Group writer

**Done when:**
- Calling `DictationCoordinator.shared.startDictation()` writes status transitions and stub text to App Group defaults
- Darwin notifications are posted at each status change
</task>

<task id="1.2.3" title="Handle dictus:// URL in DictusApp entry point" estimated_effort="S">
**What:** Add `.onOpenURL` handler to the SwiftUI App that parses incoming URLs and routes `dictus://dictate` to the coordinator.
**Why:** SwiftUI's `.onOpenURL` is the modern, clean way to handle incoming URLs in the App lifecycle. It works for both cold launch and warm launch (app already running in background).
**How:**
1. Update `DictusApp/DictusApp.swift`:

```swift
@main
struct DictusApp: App {
    @StateObject private var coordinator = DictationCoordinator.shared

    init() {
        let result = AppGroupDiagnostic.run()
        DictusLogger.app.info(
            "AppGroup diagnostic: healthy=\(result.isHealthy)"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        DictusLogger.app.info("Received URL: \(url.absoluteString)")
        guard url.scheme == "dictus" else { return }

        switch url.host {
        case "dictate":
            coordinator.startDictation()
        default:
            DictusLogger.app.warning("Unknown URL host: \(url.host ?? "nil")")
        }
    }
}
```

2. Update `ContentView.swift` to show dictation status when active:

```swift
struct ContentView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @State private var diagnosticResult: DiagnosticResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Dictus")
                    .font(.largeTitle.bold())

                // Show dictation state when active
                if coordinator.status != .idle {
                    DictationStatusView(status: coordinator.status)
                }

                if let result = coordinator.lastResult {
                    Text("Last result: \(result)")
                        .font(.body)
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                }

                Divider()

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

3. Create a simple `DictationView.swift` that shows current status with appropriate SF Symbol:

```swift
// DictusApp/DictationView.swift
import SwiftUI
import DictusCore

/// Shows the current dictation status with icon and label.
struct DictationStatusView: View {
    let status: DictationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)

            VStack(alignment: .leading) {
                Text(statusLabel)
                    .font(.headline)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var iconName: String {
        switch status {
        case .idle: return "mic.slash"
        case .requested: return "arrow.up.forward"
        case .recording: return "mic.fill"
        case .transcribing: return "text.bubble"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .idle: return .secondary
        case .requested: return .orange
        case .recording: return .red
        case .transcribing: return .blue
        case .ready: return .green
        case .failed: return .red
        }
    }

    private var statusLabel: String {
        switch status {
        case .idle: return "Idle"
        case .requested: return "Requested"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    private var statusDescription: String {
        switch status {
        case .idle: return "Waiting for dictation request"
        case .requested: return "Opening from keyboard"
        case .recording: return "Capturing audio"
        case .transcribing: return "Processing speech"
        case .ready: return "Transcription available"
        case .failed: return "Something went wrong"
        }
    }
}
```

**Files:**
- `DictusApp/DictusApp.swift` — onOpenURL handler
- `DictusApp/ContentView.swift` — Updated to show dictation status
- `DictusApp/DictationView.swift` — Status display component

**Done when:**
- Opening `dictus://dictate` in Safari transitions DictusApp through recording -> transcribing -> ready states visually
- Console logs show URL received and status transitions
</task>

<task id="1.2.4" title="Create KeyboardState observable for cross-process updates" estimated_effort="M">
**What:** Create a `KeyboardState` ObservableObject in DictusKeyboard that listens for Darwin notifications and reads dictation status and transcription results from the App Group.
**Why:** The keyboard needs to reactively update its UI when the main app writes data. Darwin notifications wake the observer immediately; the data is then read from shared UserDefaults. Using `@Published` properties drives SwiftUI updates automatically.
**How:**
1. Create `DictusKeyboard/KeyboardState.swift`:

```swift
// DictusKeyboard/KeyboardState.swift
import Foundation
import Combine
import DictusCore

/// Observes cross-process state changes from DictusApp via Darwin notifications.
/// Reads actual data from App Group UserDefaults after each notification.
class KeyboardState: ObservableObject {
    @Published var dictationStatus: DictationStatus = .idle
    @Published var lastTranscription: String?
    @Published var statusMessage: String?

    private let defaults = AppGroup.defaults

    init() {
        // Read initial state from App Group
        refreshFromDefaults()

        // Observe Darwin notifications for real-time updates
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.statusChanged
        ) { [weak self] in
            // Darwin callbacks are on arbitrary threads — dispatch to main
            DispatchQueue.main.async {
                self?.refreshFromDefaults()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.transcriptionReady
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handleTranscriptionReady()
            }
        }
    }

    deinit {
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.transcriptionReady)
    }

    /// Read current state from App Group UserDefaults.
    private func refreshFromDefaults() {
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            dictationStatus = status
            updateStatusMessage(for: status)
        }
    }

    /// Handle transcription ready notification: read the result.
    private func handleTranscriptionReady() {
        refreshFromDefaults()

        if let transcription = defaults.string(forKey: SharedKeys.lastTranscription) {
            lastTranscription = transcription
            statusMessage = "Transcription received"
            DictusLogger.keyboard.info("Received transcription: \(transcription)")

            // Auto-clear status message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.statusMessage = nil
            }
        } else {
            // Retry after 100ms — mitigates UserDefaults race condition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if let transcription = self?.defaults.string(forKey: SharedKeys.lastTranscription) {
                    self?.lastTranscription = transcription
                    self?.statusMessage = "Transcription received"
                }
            }
        }
    }

    private func updateStatusMessage(for status: DictationStatus) {
        switch status {
        case .idle:
            statusMessage = nil
        case .requested:
            statusMessage = "Opening Dictus..."
        case .recording:
            statusMessage = "Recording in Dictus..."
        case .transcribing:
            statusMessage = "Transcribing..."
        case .ready:
            statusMessage = "Transcription ready"
        case .failed:
            statusMessage = "Dictation failed — try again"
            // Auto-dismiss error after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.dictationStatus == .failed {
                    self?.statusMessage = nil
                }
            }
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    /// Called just before the Link opens dictus://dictate.
    func markRequested() {
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        dictationStatus = .requested
        updateStatusMessage(for: .requested)
    }
}
```

**Files:**
- `DictusKeyboard/KeyboardState.swift` — Cross-process state observer

**Done when:**
- `KeyboardState` correctly reads status and transcription from App Group
- Darwin notification triggers update within milliseconds of DictusApp writing
</task>

<task id="1.2.5" title="Create MicButtonDisabled reusable component" estimated_effort="S">
**What:** Create the `MicButtonDisabled` view component that shows when Full Access is off, explaining how to enable it. This is a self-contained component used by Plan 1.3's `KeyboardRootView`.
**Why:** SwiftUI `Link` is the only iOS 16-18 compatible, App Store-safe way to open a URL from a keyboard extension. When Full Access is off, we need a clear explanation. Separating this into its own component keeps Plan 1.2 focused on cross-process logic, while Plan 1.3 owns the final KeyboardRootView composition.

**Note:** Plan 1.2 does NOT modify `KeyboardRootView.swift`. Plan 1.3 owns `KeyboardRootView.swift` and composes all components (including `KeyboardState`, `MicButtonDisabled`, `StatusBar`, `TranscriptionStub`) into the final view. This avoids merge conflicts since both plans run in wave 2.

**How:**
1. Create `DictusKeyboard/Views/MicButtonDisabled.swift`:

```swift
// DictusKeyboard/Views/MicButtonDisabled.swift
import SwiftUI

/// Mic button shown when Full Access is not enabled.
/// Shows a popover explaining why Full Access is needed.
struct MicButtonDisabled: View {
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundColor(.gray)
                .padding(12)
                .background(Color.gray.opacity(0.15))
                .clipShape(Circle())
        }
        .popover(isPresented: $showExplanation) {
            VStack(spacing: 8) {
                Text("Accès complet requis")
                    .font(.headline)
                Text("Active l'Accès complet dans Réglages > Claviers > Dictus pour utiliser la dictée.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Link("Ouvrir Réglages", destination: URL(string: "app-settings:")!)
                    .font(.caption.bold())
            }
            .padding()
            .frame(width: 250)
        }
    }
}
```

**Files:**
- `DictusKeyboard/Views/MicButtonDisabled.swift` — Disabled mic button with Full Access explanation

**Done when:**
- Component compiles independently
- Tapping shows explanation popover with Settings link
</task>

<task id="1.2.6" title="Integrate KeyboardState into KeyboardViewController" estimated_effort="S">
**What:** Wire up `KeyboardState` initialization and cleanup in `KeyboardViewController`, ensuring Darwin notification observers are properly managed across the keyboard lifecycle.
**Why:** The keyboard extension can be created and destroyed multiple times as the user switches keyboards. Darwin notification observers must be cleaned up to prevent leaks and duplicate callbacks.
**How:**
1. Update `DictusKeyboard/KeyboardViewController.swift` to pass state through:

```swift
class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        #if DEBUG
        let result = AppGroupDiagnostic.run()
        DictusLogger.keyboard.debug(
            "Diagnostic: canWrite=\(result.canWrite) canRead=\(result.canRead)"
        )
        #endif

        let rootView = KeyboardRootView(controller: self)
        let hosting = UIHostingController(rootView: rootView)
        self.hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Darwin observers cleaned up by KeyboardState deinit
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Future: react to cursor position changes, return key type, etc.
    }
}
```

Note: `KeyboardState` is created as a `@StateObject` inside `KeyboardRootView`, so its lifecycle is tied to the SwiftUI view. When the hosting controller is deallocated, `KeyboardState.deinit` runs and removes Darwin observers.

**Files:**
- `DictusKeyboard/KeyboardViewController.swift` — Lifecycle management

**Done when:**
- No Darwin notification observer leaks across keyboard show/hide cycles
- Console shows clean lifecycle logs
</task>

</tasks>

## Verification
- [ ] Opening `dictus://dictate` in Safari launches DictusApp and triggers dictation stub
- [ ] DictusApp console shows: "Dictation started via URL scheme" followed by status transitions
- [ ] DictusApp UI shows recording -> transcribing -> ready state sequence
- [ ] `KeyboardState` receives Darwin notification and reads transcription from App Group (verified via logs)
- [ ] iOS shows "< [Previous App]" back button in status bar when DictusApp is active (no `dictus://return` needed)
- [ ] Cancelling a dictation in progress (starting a new one) resets cleanly
- [ ] Round-trip works on physical iPhone (manual test)
- [ ] Note: Full keyboard integration (mic button, status bar display) is verified in Plan 1.3
