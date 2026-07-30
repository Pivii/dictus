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
    static let shared = KeyboardState()
    private let instanceID = String(UUID().uuidString.prefix(8))
    private(set) var activeSessionID: String?

    /// WHY didSet and not a sync call at each write site: this property is
    /// assigned from a dozen places (Darwin refresh, mic tap, cancel, watchdog
    /// reset, transcription insert, and both of its retry paths). A property
    /// observer is the only funnel none of them can bypass, so the area mode
    /// below can never drift out of step with the dictation lifecycle.
    @Published var dictationStatus: DictationStatus = .idle {
        didSet { syncAreaModeWithStatus() }
    }

    /// What the keyboard area is presenting: the key grid, a full-area picker or
    /// panel, or the recording overlay. Single source of truth for both the
    /// SwiftUI root view and the UIKit view controller (#271).
    ///
    /// `private(set)`: `.recording` is owned by the dictation lifecycle and every
    /// other transition goes through `presentAreaMode(_:)`, so no caller can put
    /// the two layers into a state the type forbids.
    ///
    /// WHY this is not `@Published`: `@Published` notifies in `willSet`, while the
    /// property still holds the OLD value. KeyboardViewController reacts to a mode
    /// change by forcing `layoutIfNeeded()` — deliberately, so the hosting
    /// constraint is in place before SwiftUI draws (#99, #142). But a forced UIKit
    /// layout makes UIHostingController run its SwiftUI update pass right there,
    /// inside the `willSet`: the body reads the old mode, renders it, and marks
    /// itself clean. A status change survives that, because the next status
    /// (`requested → recording → transcribing`) notifies again and the view
    /// catches up. A one-shot transition does not — opening the emoji picker left
    /// the keyboard area blank, with the hosting view expanded to 268 pt and the
    /// SwiftUI body still on `.keys` (device-log confirmed).
    ///
    /// Notifying from `didSet` instead means every observer — the controller's
    /// sink and SwiftUI alike — reads the value that is actually stored.
    private(set) var areaMode: KeyboardAreaMode = .keys {
        didSet {
            objectWillChange.send()
            areaModeSubject.send(areaMode)
        }
    }

    /// Backs `areaModePublisher`. A subject rather than `@Published`'s projected
    /// publisher for the `didSet` reason above.
    private let areaModeSubject = PassthroughSubject<KeyboardAreaMode, Never>()

    /// Emits the keyboard area mode after every assignment, including assignments
    /// that leave the value unchanged — re-applying the layout on each dictation
    /// status write is how a keyboard returning from suspension re-synchronises.
    ///
    /// Unlike `@Published`, this does not replay the current value on subscribe:
    /// `viewWillAppear` applies `areaMode` explicitly, which covers that.
    var areaModePublisher: AnyPublisher<KeyboardAreaMode, Never> {
        areaModeSubject.eraseToAnyPublisher()
    }

    @Published var lastTranscription: String?
    @Published var statusMessage: String?
    @Published var waveformEnergy: [Float] = []
    @Published var recordingElapsed: Double = 0

    /// Tracks whether the keyboard extension is currently visible on screen.
    @Published private(set) var isKeyboardVisible: Bool = false
    @Published private(set) var activeControllerID: String?

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

    /// Called after transcription text is inserted into the text field.
    /// KeyboardViewController sets this to trigger a SuggestionState update
    /// so the suggestion bar shows completions for the last dictated word.
    var onTranscriptionInserted: (() -> Void)?

    /// Opens a URL from the keyboard extension using NSExtensionContext.
    /// WHY extensionContext: This is the Apple-documented API for app extensions
    /// to open URLs. Neither SwiftUI's openURL nor the responder chain work
    /// reliably in keyboard extensions.
    func openURLFromExtension(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard let extensionContext = controller?.extensionContext else {
            completion(false)
            return
        }
        extensionContext.open(url, completionHandler: completion)
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

    private init() {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: "init",
            details: ""
        ))
        // Read initial state from App Group
        refreshFromDefaults()

        // Observe Darwin notifications for real-time updates
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.statusChanged
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.logProbe("receivedDarwinStatusChanged")
                self?.refreshFromDefaults()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.transcriptionReady
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.logProbe("receivedDarwinTranscriptionReady")
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
        logProbe("deinit")
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
        activeSessionID = nil
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

    // MARK: - Keyboard area presentation

    /// Keeps the presented mode in step with the dictation lifecycle.
    ///
    /// This is where "starting a dictation dismisses the emoji picker" lives: an
    /// explicit transition to `.recording`, rather than the SwiftUI `onChange`
    /// side effect it used to be. Assigned unconditionally — including when the
    /// resolved mode is unchanged — because the layout used to be re-applied on
    /// every status write, and that repetition is load-bearing: it is how a
    /// keyboard returning from suspension re-synchronises its hosting geometry.
    private func syncAreaModeWithStatus() {
        areaMode = KeyboardAreaMode.resolving(status: dictationStatus, current: areaMode)
    }

    /// Present `mode` in the keyboard area.
    ///
    /// `.recording` is rejected: the overlay belongs to the dictation lifecycle
    /// above, so no UI toggle can start or dismiss one. Toggles are likewise
    /// ignored while a dictation owns the area — the key grid is hidden then, so
    /// nothing can reach this in practice, but the invariant holds by
    /// construction instead of by every caller remembering to check.
    func presentAreaMode(_ mode: KeyboardAreaMode) {
        guard mode != .recording, !dictationStatus.ownsKeyboardArea else {
            logProbe(
                "presentAreaModeIgnored",
                details: "requested=\(mode.rawValue) current=\(areaMode.rawValue) status=\(dictationStatus.rawValue)"
            )
            return
        }
        logProbe("presentAreaMode", details: "from=\(areaMode.rawValue) to=\(mode.rawValue)")
        areaMode = mode
    }

    /// Show or hide the emoji picker. Called by the emoji key (through the
    /// controller) and by the picker's own dismiss button.
    func toggleEmojiPresentation() {
        presentAreaMode(areaMode == .emoji ? .keys : .emoji)
    }

    // MARK: - Recording commands (keyboard -> app)

    /// Request DictusApp to stop recording and begin transcription.
    /// Uses the Darwin notification + Bool flag pattern: write the flag first,
    /// then post the notification so the app reads the flag when it handles the notification.
    func requestStop() {
        logProbe("requestStop", details: sessionDetails())
        defaults.set(true, forKey: SharedKeys.stopRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
        HapticFeedback.recordingStopped()
    }

    /// Request DictusApp to cancel recording and discard audio.
    /// Resets local keyboard state immediately for instant UI feedback,
    /// while the Darwin notification tells the app to clean up its side.
    func requestCancel() {
        logProbe("requestCancel", details: sessionDetails())
        defaults.set(true, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.cancelRecording)

        // Reset local state immediately for responsive UI
        dictationStatus = .idle
        waveformEnergy = []
        recordingElapsed = 0
        statusMessage = nil
        activeSessionID = nil
    }

    // MARK: - State observation

    /// Read current state from App Group UserDefaults.
    /// Starts/stops the watchdog timer based on the new status.
    func refreshFromDefaults() {
        logProbe("refreshFromDefaults", details: "storedStatus=\(defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil") visible=\(isKeyboardVisible) \(sessionDetails())")
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            let oldStatus = dictationStatus
            dictationStatus = status

            if oldStatus != status {
                PersistentLog.log(.statusChanged(from: oldStatus.rawValue, to: status.rawValue, source: "keyboardState"))
            }

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
                // Force-read waveform on keyboard reappear to unstick frozen animations.
                // WHY: When the extension is suspended (app in foreground), Darwin
                // notifications are lost. readWaveformData() updates @Published props
                // which forces SwiftUI to re-render the overlay.
                readWaveformData()
            } else {
                stopWatchdog()
                coldStartGraceEnd = nil
                if status == .idle || status == .ready || status == .failed {
                    activeSessionID = nil
                    // Read and display error message from App Group
                    if status == .failed, let errorMsg = defaults.string(forKey: SharedKeys.lastError) {
                        statusMessage = errorMsg
                        defaults.removeObject(forKey: SharedKeys.lastError)
                        defaults.synchronize()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                            self?.statusMessage = nil
                        }
                    }
                }
            }

            // Force SwiftUI re-render when status hasn't changed but we're returning
            // from suspension (e.g., swipe-back during cold start recording).
            // WHY: If oldStatus == status == .recording, SwiftUI skips re-render
            // because no @Published value changed. objectWillChange forces it.
            if isKeyboardVisible && oldStatus == status && activeStates.contains(status) {
                objectWillChange.send()
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
                // Log transitions between empty/populated energy data
                if waveformEnergy.isEmpty != energy.isEmpty {
                    PersistentLog.log(.waveformEnergyTransition(
                        fromCount: waveformEnergy.count,
                        toCount: energy.count,
                        status: dictationStatus.rawValue
                    ))
                }
                waveformEnergy = energy
            } catch {
                // JSON decode failure — keep existing waveform data
                if #available(iOS 14.0, *) {
                    DictusLogger.keyboard.warning("Failed to decode waveform energy: \(error, privacy: .public)")
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
        logProbe("handleTranscriptionReady", details: sessionDetails())
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
            onTranscriptionInserted?()

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
            activeSessionID = nil
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
                    self.onTranscriptionInserted?()

                    self.stopWatchdog()
                    self.dictationStatus = .idle
                    self.waveformEnergy = []
                    self.recordingElapsed = 0
                    self.statusMessage = nil
                    self.lastTranscription = nil
                    self.activeSessionID = nil
                }
            }
        }
    }

    // MARK: - Keyboard visibility tracking

    /// Called when a controller becomes the active visible keyboard owner.
    func registerControllerAppearance(controllerID: String) {
        logProbe(
            "registerControllerAppearance",
            details: "controllerID=\(controllerID) previousOwner=\(activeControllerID ?? "none") wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )
        activeControllerID = controllerID
        isKeyboardVisible = true

        // Refresh state from App Group — picks up status changes that
        // happened while the keyboard extension was suspended.
        refreshFromDefaults()
    }

    /// Called when a controller disappears. Only the current owner may hide the keyboard.
    func registerControllerDisappearance(controllerID: String) {
        let ownsVisibility = activeControllerID == controllerID
        logProbe(
            "registerControllerDisappearance",
            details: "controllerID=\(controllerID) owner=\(activeControllerID ?? "none") ownsVisibility=\(ownsVisibility) wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )

        guard ownsVisibility else { return }

        isKeyboardVisible = false
        activeControllerID = nil
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

        // Issue #262: a model load is now a prepare-only handoff. Opening Dictus
        // lets the app show truthful preparation feedback instead of leaving the
        // user with a refusal message in the keyboard. The app still prevents a
        // recording from starting until the model is ready.
        // We synchronize defaults first because cross-process writes from DictusApp
        // can lag a few ms behind the actual state change.
        if isModelLoading() {
            PersistentLog.log(.keyboardMicTapped)
            deferRecordingForModelPreparation()
            return
        }

        activeSessionID = String(UUID().uuidString.prefix(8))
        logProbe("startRecording", details: sessionDetails())

        PersistentLog.log(.keyboardMicTapped)
        markRequested()

        // The model can begin loading after the first check while this tap is
        // being handed to DictusApp. Re-check immediately before posting the
        // recording request so a model swap cannot race into a recording.
        if isModelLoading() {
            forceResetToIdle()
            deferRecordingForModelPreparation(reason: "model became loading before Darwin handoff")
            return
        }

        // Try background recording first — if app is alive, it will handle this
        // notification and start recording without coming to the foreground.
        DarwinNotificationCenter.post(DarwinNotificationName.startRecording)

        // Fallback: if app didn't respond (not running), open URL to launch it.
        // We check after 500ms whether status progressed past .requested.
        // If the app handled the notification, status will be .recording by now.
        let darwinPostTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let elapsedMs = Int(Date().timeIntervalSince(darwinPostTime) * 1000)
            if self.dictationStatus == .requested {
                if self.isModelLoading() {
                    self.forceResetToIdle()
                    self.deferRecordingForModelPreparation(reason: "model became loading before fallback URL")
                    return
                }
                PersistentLog.log(.coldStartDarwinFallback(
                    elapsedMs: elapsedMs,
                    status: self.dictationStatus.rawValue
                ))
                self.logProbe("fallbackOpenURL", details: self.sessionDetails())
                // App didn't respond — not running. Open URL to launch it.
                let url = URL(string: "dictus://dictate?source=keyboard")!
                self.openDictusURL(url)
            }
        }
    }

    /// Open Dictus without creating a recording request. The user explicitly
    /// starts dictation with a second tap once preparation has completed (#262).
    private func openModelPreparation() {
        guard let url = URL(string: "dictus://dictate?source=keyboard&intent=prepare") else {
            return
        }
        openDictusURL(url)
    }

    /// Re-read the shared state at each handoff boundary because the app can
    /// start a model swap after the keyboard's previous snapshot.
    private func isModelLoading() -> Bool {
        defaults.synchronize()
        let rawState = defaults.string(forKey: SharedKeys.modelLoadState)
            ?? ModelLoadState.idle.rawValue
        return rawState == ModelLoadState.loading.rawValue
    }

    /// Defer recording without leaving a requested state behind in the keyboard.
    private func deferRecordingForModelPreparation(reason: String = "keyboard opened Dictus for model preparation") {
        PersistentLog.log(.dictationDeferred(reason: reason))
        openModelPreparation()
    }

    /// Prefer the extension context because the SwiftUI openURL callback has no
    /// success result and can fail silently in a keyboard extension.
    private func openDictusURL(_ url: URL) {
        if controller?.extensionContext != nil {
            openURLFromExtension(url) { [weak self] succeeded in
                guard !succeeded else { return }
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardState",
                    instanceID: self?.instanceID ?? "unknown",
                    action: "extensionURLFallback",
                    details: "extensionContext.open returned false"
                ))
                DispatchQueue.main.async { [weak self] in
                    self?.openURL?(url)
                }
            }
        } else if let openURL {
            openURL(url)
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    func markRequested() {
        logProbe("markRequested", details: sessionDetails())
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        dictationStatus = .requested
        startWatchdog()
        HapticFeedback.recordingStarted()
    }

    private func sessionDetails() -> String {
        let sessionID = activeSessionID ?? "none"
        return "sessionID=\(sessionID) status=\(dictationStatus.rawValue) energyCount=\(waveformEnergy.count)"
    }

    private func logProbe(_ action: String, details: String = "") {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: action,
            details: details
        ))
    }

    private func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }
}
