// DictusKeyboard/KeyboardState.swift
import Foundation
import UIKit
import Combine
import DictusCore

/// Observes cross-process state changes from DictusApp via Darwin notifications.
/// Reads actual data from App Group UserDefaults after each notification.
///
/// Phase 3 additions:
/// - waveformEnergy/recordingElapsed for recording overlay visualization
/// - requestStop()/requestCancel() to send commands back to DictusApp
/// - Auto-insert transcription into active text field via textDocumentProxy
/// - Haptic feedback on recording lifecycle events
class KeyboardState: ObservableObject {
    @Published var dictationStatus: DictationStatus = .idle
    @Published var lastTranscription: String?
    @Published var statusMessage: String?
    @Published var waveformEnergy: [Float] = []
    @Published var recordingElapsed: Double = 0

    /// Reference to the keyboard controller for text insertion.
    /// WHY weak: KeyboardState is owned by KeyboardRootView (via @StateObject),
    /// and the controller owns the hosting view. A strong reference would create
    /// a retain cycle: controller -> view -> state -> controller.
    weak var controller: UIInputViewController?

    /// Closure to open a URL from the keyboard extension.
    /// WHY a closure: KeyboardState is not a SwiftUI View, so it cannot use
    /// @Environment(\.openURL). KeyboardRootView captures its own openURL
    /// environment action and injects it here via .onAppear — same pattern
    /// as the controller reference above.
    var openURL: ((URL) -> Void)?

    /// Opens a URL from the keyboard extension using NSExtensionContext.
    /// WHY extensionContext: This is the Apple-documented API for app extensions
    /// to open URLs. Neither SwiftUI's openURL nor the responder chain work
    /// reliably in keyboard extensions.
    func openURLFromExtension(_ url: URL) {
        controller?.extensionContext?.open(url)
    }

    private let defaults = AppGroup.defaults

    init() {
        // Read initial state from App Group
        refreshFromDefaults()

        // Observe Darwin notifications for real-time updates
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.statusChanged
        ) { [weak self] in
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

        // Observe waveform updates from DictusApp during recording (~5Hz).
        // DictusApp writes JSON-encoded [Float] to SharedKeys.waveformEnergy
        // and elapsed seconds to SharedKeys.recordingElapsedSeconds, then posts
        // this notification. The keyboard reads the values for the overlay UI.
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.waveformUpdate
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.readWaveformData()
            }
        }
    }

    deinit {
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.transcriptionReady)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.waveformUpdate)
    }

    // MARK: - Recording commands (keyboard -> app)

    /// Request DictusApp to stop recording and begin transcription.
    /// Uses the Darwin notification + Bool flag pattern: write the flag first,
    /// then post the notification so the app reads the flag when it handles the notification.
    func requestStop() {
        defaults.set(true, forKey: SharedKeys.stopRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
        HapticFeedback.recordingStopped()
    }

    /// Request DictusApp to cancel recording and discard audio.
    /// Resets local keyboard state immediately for instant UI feedback,
    /// while the Darwin notification tells the app to clean up its side.
    func requestCancel() {
        defaults.set(true, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.cancelRecording)

        // Reset local state immediately for responsive UI
        dictationStatus = .idle
        waveformEnergy = []
        recordingElapsed = 0
        statusMessage = nil
    }

    // MARK: - State observation

    /// Read current state from App Group UserDefaults.
    private func refreshFromDefaults() {
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            dictationStatus = status
        }
    }

    /// Read waveform energy and elapsed time from App Group.
    /// Called when DictusApp posts waveformUpdate notification during recording.
    private func readWaveformData() {
        // Read elapsed seconds
        recordingElapsed = defaults.double(forKey: SharedKeys.recordingElapsedSeconds)

        // Read waveform energy: JSON-encoded [Float] array
        if let data = defaults.data(forKey: SharedKeys.waveformEnergy) {
            do {
                let energy = try JSONDecoder().decode([Float].self, from: data)
                waveformEnergy = energy
            } catch {
                // JSON decode failure — keep existing waveform data
                if #available(iOS 14.0, *) {
                    DictusLogger.keyboard.warning("Failed to decode waveform energy: \(error)")
                }
            }
        }
    }

    /// Handle transcription ready notification: auto-insert text into active field.
    ///
    /// Phase 3 behavior: instead of displaying transcription in a banner,
    /// insert it directly into the text field via textDocumentProxy.insertText().
    /// This matches the standard iOS dictation UX — user speaks, text appears at cursor.
    private func handleTranscriptionReady() {
        refreshFromDefaults()

        if let transcription = defaults.string(forKey: SharedKeys.lastTranscription),
           !transcription.isEmpty {
            // Clear from UserDefaults BEFORE inserting to prevent duplicate insertions.
            // Darwin notifications can be delivered multiple times (extension lifecycle,
            // multiple statusChanged posts). By clearing first, subsequent calls find
            // nothing to insert.
            defaults.removeObject(forKey: SharedKeys.lastTranscription)
            defaults.synchronize()

            controller?.textDocumentProxy.insertText(transcription)
            HapticFeedback.textInserted()

            if #available(iOS 14.0, *) {
                DictusLogger.keyboard.info("Auto-inserted transcription: \(transcription)")
            }

            // Reset state to idle
            dictationStatus = .idle
            waveformEnergy = []
            recordingElapsed = 0
            statusMessage = nil
            lastTranscription = nil
        } else {
            // Retry after 100ms — mitigates UserDefaults race condition.
            // Darwin notifications are posted immediately after synchronize(),
            // but cross-App-Group propagation can lag on-device.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                if let transcription = self.defaults.string(forKey: SharedKeys.lastTranscription),
                   !transcription.isEmpty {
                    self.defaults.removeObject(forKey: SharedKeys.lastTranscription)
                    self.defaults.synchronize()

                    self.controller?.textDocumentProxy.insertText(transcription)
                    HapticFeedback.textInserted()

                    self.dictationStatus = .idle
                    self.waveformEnergy = []
                    self.recordingElapsed = 0
                    self.statusMessage = nil
                    self.lastTranscription = nil
                }
            }
        }
    }

    /// Start recording: set local state, then signal DictusApp.
    ///
    /// WHY the keyboard doesn't record directly:
    /// WhisperKit requires loading ML models (~50-200MB) which exceeds the keyboard
    /// extension's ~50MB memory limit. The actual recording runs in DictusApp.
    ///
    /// Flow (Wispr Flow-inspired):
    /// 1. Set local state to .requested (recording overlay appears immediately)
    /// 2. Post startRecording Darwin notification (app records in background if alive)
    /// 3. If app doesn't respond in 500ms → fall back to URL scheme (opens app)
    ///
    /// This means: after the first launch, subsequent recordings happen without
    /// switching apps. The user stays in their current app the entire time.
    func startRecording() {
        markRequested()

        // Try background recording first — if app is alive, it will handle this
        // notification and start recording without coming to the foreground.
        DarwinNotificationCenter.post(DarwinNotificationName.startRecording)

        // Fallback: if app didn't respond (not running), open URL to launch it.
        // We check after 500ms whether status progressed past .requested.
        // If the app handled the notification, status will be .recording by now.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if self.dictationStatus == .requested {
                // Save the host app's bundle ID so DictusApp can return to it.
                // WHY here (not earlier): We only need this for the URL fallback path
                // (cold start). When the app handles via Darwin notification, the user
                // never leaves their current app.
                self.saveHostBundleID()

                // App didn't respond — not running. Open URL to launch it.
                let url = URL(string: "dictus://dictate")!
                if let openURL = self.openURL {
                    openURL(url)
                } else {
                    self.openURLFromExtension(url)
                }
            }
        }
    }

    /// Save the host app's bundle ID to App Group for auto-return.
    ///
    /// WHY this technique: UIInputViewController doesn't expose the host bundle ID
    /// publicly. We try multiple known locations for this private property via KVC.
    /// This is the same approach used by other published App Store apps (Wispr Flow,
    /// SuperWhisper) for auto-return functionality.
    ///
    /// WHY multiple attempts: The _hostBundleID property location varies across iOS
    /// versions and view controller hierarchies. We try the most common locations.
    private func saveHostBundleID() {
        var bundleID: String?

        // Attempt 1: directly on the UIInputViewController
        bundleID = controller?.value(forKey: "_hostBundleID") as? String

        // Attempt 2: on the parent view controller
        if bundleID == nil {
            bundleID = controller?.parent?.value(forKey: "_hostBundleID") as? String
        }

        // Attempt 3: via the host's bundle identifier in the extension context
        // WHY: On some iOS versions, extensionContext exposes host info differently
        if bundleID == nil {
            bundleID = controller?.extensionContext?.value(forKey: "_hostBundleIdentifier") as? String
        }

        if let id = bundleID, !id.isEmpty {
            defaults.set(id, forKey: SharedKeys.hostBundleID)
            defaults.synchronize()
            PersistentLog.log("Keyboard: saved hostBundleID=\(id)")
        } else {
            PersistentLog.log("Keyboard: could not retrieve hostBundleID")
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    func markRequested() {
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        dictationStatus = .requested
        HapticFeedback.recordingStarted()
    }
}
