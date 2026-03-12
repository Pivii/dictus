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

    /// Watchdog timer that periodically checks for stale active states.
    /// WHY: If the app crashes or a Darwin notification is lost, the keyboard
    /// could get stuck showing the recording overlay forever. The watchdog
    /// detects this by checking if waveform data has stopped updating for 5s
    /// while status is still .recording or .transcribing.
    private var watchdogTimer: Timer?

    /// Tracks when waveform energy was last refreshed from App Group.
    /// Used by the watchdog to detect stale states (no updates for 5s).
    private var lastWaveformUpdate: Date = Date()

    /// When set, the watchdog uses a longer threshold (15s) to account for
    /// the app→keyboard transition during cold start. The app needs time to
    /// stabilize audio recording and start posting waveform updates.
    /// Cleared automatically when recording ends (status becomes idle).
    private var coldStartGraceEnd: Date?


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
        stopWatchdog()
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.transcriptionReady)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.waveformUpdate)
    }

    // MARK: - Watchdog

    /// Prevents re-entrant calls to forceResetToIdle().
    /// WHY: forceResetToIdle posts a statusChanged notification, which triggers
    /// refreshFromDefaults on the next run loop. If the watchdog timer fires
    /// again before that run loop pass (e.g., stacked timer events), a second
    /// forceResetToIdle call would post a duplicate notification.
    private var isResettingToIdle = false

    /// Force-reset all dictation state to idle.
    /// Called by the watchdog timer or stale-state detection on keyboard appear.
    /// Writes to App Group so the app side sees the reset too.
    func forceResetToIdle() {
        guard !isResettingToIdle else { return }
        isResettingToIdle = true
        defer { isResettingToIdle = false }

        stopWatchdog()
        dictationStatus = .idle
        waveformEnergy = []
        recordingElapsed = 0
        statusMessage = nil
        // Write to App Group so app side sees the reset
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Start a repeating 1s timer that checks for stale active states.
    /// WHY 5s threshold: Waveform updates arrive at ~5Hz during recording.
    /// If 5 seconds pass without any update while status is still active,
    /// the app has likely crashed or been killed by iOS.
    /// During cold start grace period, uses 15s threshold instead.
    private func startWatchdog() {
        stopWatchdog()
        lastWaveformUpdate = Date()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let activeStates: [DictationStatus] = [.requested, .recording, .transcribing]
            guard activeStates.contains(self.dictationStatus) else {
                self.stopWatchdog()
                return
            }
            // During cold start, the app transitions foreground→background while
            // setting up audio. Waveform data may not flow for ~10s. Use 15s threshold.
            let inGracePeriod = self.coldStartGraceEnd.map { Date() < $0 } ?? false
            let threshold: TimeInterval = inGracePeriod ? 15.0 : 5.0
            if Date().timeIntervalSince(self.lastWaveformUpdate) > threshold {
                // Before resetting, check the audio-thread heartbeat.
                // WHY: In background, iOS throttles the main thread so waveform
                // Darwin notifications may not arrive. But the audio thread keeps
                // writing a heartbeat directly to App Group. If the heartbeat is
                // fresh, the app IS still recording — don't kill the overlay.
                let heartbeat = self.defaults.double(forKey: SharedKeys.recordingHeartbeat)
                if heartbeat > 0, Date().timeIntervalSince1970 - heartbeat < threshold {
                    self.lastWaveformUpdate = Date()
                    return
                }
                PersistentLog.log(.watchdogReset(source: "keyboard", staleState: self.dictationStatus.rawValue))
                self.forceResetToIdle()
            }
        }
    }

    /// Invalidate and nil the watchdog timer.
    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
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
    /// Starts/stops the watchdog timer based on the new status.
    func refreshFromDefaults() {
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            let oldStatus = dictationStatus
            dictationStatus = status

            // Start/restart watchdog on any active state transition, stop when leaving.
            // WHY restart (not just start): transitioning .requested → .recording
            // must reset lastWaveformUpdate. Without this, the watchdog fires
            // immediately because it still has the timestamp from markRequested().
            let activeStates: [DictationStatus] = [.requested, .recording, .transcribing]
            if activeStates.contains(status) {
                if !activeStates.contains(oldStatus) || status != oldStatus {
                    startWatchdog()
                }
                // During cold start, the app is transitioning between foreground/background.
                // Waveform data may not flow for several seconds. Activate grace period
                // so the watchdog uses a longer threshold (15s instead of 5s).
                if defaults.bool(forKey: SharedKeys.coldStartActive) {
                    coldStartGraceEnd = Date().addingTimeInterval(15)
                    lastWaveformUpdate = Date()
                }
            } else {
                stopWatchdog()
                coldStartGraceEnd = nil
            }
        }
    }

    /// Read waveform energy and elapsed time from App Group.
    /// Called when DictusApp posts waveformUpdate notification during recording.
    /// Updates lastWaveformUpdate so the watchdog knows data is still flowing.
    private func readWaveformData() {
        // Update watchdog timestamp — data is still flowing from the app
        lastWaveformUpdate = Date()

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
            PersistentLog.log(.keyboardTextInserted)
            HapticFeedback.textInserted()

            // Reset state to idle.
            // WHY explicit stopWatchdog: refreshFromDefaults() above may have read
            // .transcribing from App Group (before .ready propagated), starting the
            // watchdog. Setting dictationStatus = .idle here bypasses refreshFromDefaults
            // so the watchdog wouldn't self-stop until its next 1s tick. Stopping
            // explicitly prevents false-positive watchdog resets.
            stopWatchdog()
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
                    PersistentLog.log(.keyboardTextInserted)
                    HapticFeedback.textInserted()

                    self.stopWatchdog()
                    self.dictationStatus = .idle
                    self.waveformEnergy = []
                    self.recordingElapsed = 0
                    self.statusMessage = nil
                    self.lastTranscription = nil
                }
            }
        }
    }

    /// Timestamp of last mic tap — used for debouncing.
    /// WHY 1.5s debounce: After a recording completes (transcription inserted),
    /// there's a brief window where the overlay hides and the mic button appears.
    /// Accidental double-taps or frustrated rapid-tapping during this transition
    /// cause sub-1-second recordings that Parakeet rejects, triggering a cascade
    /// of errors. 1.5s matches the natural human rhythm between dictation sessions.
    private var lastMicTapDate = Date.distantPast

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
        // Debounce: reject taps within 1.5s of the last tap.
        let now = Date()
        guard now.timeIntervalSince(lastMicTapDate) >= 1.5 else {
            PersistentLog.log(.rapidTapRejected)
            return
        }
        lastMicTapDate = now

        PersistentLog.log(.keyboardMicTapped)
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
                // App didn't respond — not running. Open URL to launch it.
                let url = URL(string: "dictus://dictate?source=keyboard")!
                if let openURL = self.openURL {
                    openURL(url)
                } else {
                    self.openURLFromExtension(url)
                }
            }
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    func markRequested() {
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        dictationStatus = .requested
        startWatchdog()
        HapticFeedback.recordingStarted()
    }
}
