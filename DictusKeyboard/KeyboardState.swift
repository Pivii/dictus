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
        didSet {
            syncAreaModeWithStatus()
            // The keyboard's dictation transitions are logged here and nowhere
            // else (#255).
            //
            // They used to be emitted from observers — `statusChanged` from
            // AnimatedMicButton, overlayShown/overlayHidden from
            // KeyboardRootView — i.e. once per live view. iOS keeps ~9 of those
            // alive, so one transition was written ~9 times and a reader counted
            // 9 transitions where 1 happened.
            //
            // The same funnel argument as the area mode above applies: this
            // property is assigned from a dozen places and the observer is the
            // only one none of them can bypass. `refreshFromDefaults` is not:
            // `markRequested` writes `.requested` directly, which is why
            // `idle → requested` was, before this, recorded *only* by the
            // per-instance mic button line.
            //
            // The guard reproduces `.onChange` semantics exactly: didSet also
            // fires on writes that leave the value unchanged, `.onChange` does not.
            if oldValue != dictationStatus {
                PersistentLog.log(.statusChanged(
                    from: oldValue.rawValue,
                    to: dictationStatus.rawValue,
                    source: "keyboardState"
                ))
                if dictationStatus.ownsKeyboardArea {
                    PersistentLog.log(.overlayShown(status: dictationStatus.rawValue))
                } else {
                    PersistentLog.log(.overlayHidden(status: dictationStatus.rawValue))
                }
            }
        }
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

    /// Which controller owns the keyboard area, and whether an ownerless area is
    /// still reclaimable (#260). Single source of truth for the two published
    /// properties below, which are what every consumer actually reads.
    ///
    /// WHY the two properties are kept rather than replaced: `activeControllerID`
    /// and `isKeyboardVisible` are read from SwiftUI (`KeyboardRootView`), from the
    /// view controller's layout guard and from half the device-log probes. Deriving
    /// them here keeps all of that untouched — and keeps them impossible to write
    /// out of step with each other, which is how the two-flag version drifted.
    private(set) var ownership: KeyboardOwnership = .none {
        didSet {
            guard oldValue != ownership else { return }
            activeControllerID = ownership.controllerID
            isKeyboardVisible = ownership.isVisible
            if ownership.isReclaimable {
                nudgeAttachedControllersToReclaim()
            }
        }
    }

    /// Tracks whether the keyboard extension is currently visible on screen.
    ///
    /// Derived from `ownership`: true only while a live controller owns the area.
    /// An owner deallocated mid-dictation leaves this false — the pixels on screen
    /// then belong to a controller nothing can talk to (#260).
    @Published private(set) var isKeyboardVisible: Bool = false

    /// The controller allowed to present the recording overlay, or nil when the
    /// keyboard area has no owner. Derived from `ownership`.
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

    /// Show or hide the hamburger panel (#241). Called by the bar's left slot,
    /// which is the hamburger when closed and the ✕ when open.
    func togglePanelPresentation() {
        presentAreaMode(areaMode == .panel ? .keys : .panel)
    }

    // MARK: - Opening DictusApp from the panel

    /// Open DictusApp from the hamburger panel (#241).
    ///
    /// `intent` travels in the URL so DictusApp can route to a specific screen
    /// later. It has no route for `open` today, so the app simply comes to the
    /// foreground — which is what both the gear and the Pro entry need now.
    ///
    /// Goes through `openDictusURL`, i.e. `extensionContext` first: that is the
    /// documented path for an app extension, and SwiftUI's `openURL` has no
    /// success result and can fail silently in a keyboard extension.
    func openDictusApp(intent: String) {
        guard let url = URL(string: "dictus://open?source=keyboard&intent=\(intent)") else {
            return
        }
        logProbe("openDictusApp", details: "intent=\(intent)")
        openDictusURL(url)
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
            // The statusChanged line this used to emit here now comes from
            // dictationStatus's didSet (#255), which fires for this write and for
            // the ones that never went through this method.
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

            insertTranscription(transcription)
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

                    self.insertTranscription(transcription)
                }
            }
        }
    }

    /// Insert a transcription into the host field and return the keyboard to idle.
    ///
    /// WHY this is a single function called from two places: `handleTranscriptionReady`
    /// has two insertion sites — the direct one and the 100 ms retry that absorbs the
    /// App Group propagation race — and they used to hold two copies of this block.
    /// Anything the keyboard has to remember about an insertion (#266: what it was, so
    /// it can be undone) has to be remembered on both, and the retry path is the one
    /// that loses the race, so a copy that forgets it would fail intermittently and
    /// only on slow devices. One funnel, no copy to forget.
    ///
    /// The App Group key is deliberately NOT read here: the caller clears it before
    /// calling, which is what stops a redelivered Darwin notification from inserting
    /// the same text twice.
    private func insertTranscription(_ transcription: String) {
        controller?.textDocumentProxy.insertText(transcription)
        PersistentLog.log(.keyboardTextInserted)
        HapticFeedback.textInserted()
        onTranscriptionInserted?()

        // Reset state to idle.
        // WHY explicit stopWatchdog: refreshFromDefaults() in the caller may have read
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

        // Offer the undo control for this insertion, and only this one. Armed after
        // the idle reset above because that reset is what ends the dictation session
        // the undo belongs to.
        armDictationUndo(transcription)
    }

    // MARK: - Dictation undo (#266)

    /// The exact string the last dictation inserted, while undoing it is still on
    /// offer. Nil means there is nothing to undo.
    ///
    /// WHY it is held in memory here rather than re-read from the App Group: the
    /// value is removed from shared storage *before* insertion, deliberately, so a
    /// redelivered Darwin notification cannot insert it twice. By the time the user
    /// could ask to undo, the only remaining copy of what was inserted is this one.
    ///
    /// WHY on the shared state object and not on a controller: iOS destroys and
    /// rebuilds `UIInputViewController` instances constantly — around nine per
    /// dictation (#281) — so a record held by a controller would vanish with it.
    /// What that costs is the risk of a record outliving the field it belongs to,
    /// which is what the invalidations below and the tail check exist to prevent.
    private var dictationUndoText: String?

    /// Whether the toolbar should offer the undo control.
    ///
    /// Set only after the insertion has been verified against the live document, so
    /// a host that reports no usable context never shows a control that could not
    /// act (fail closed).
    @Published private(set) var dictationUndoAvailable = false

    /// Expires the offer a few seconds after the insertion.
    private var dictationUndoTimer: Timer?

    /// True while a deletion burst is in flight. Blocks a new dictation from
    /// starting into a field that is still being rewritten.
    private var isUndoingDictation = false

    /// Called after a dictation insertion has been undone, so the controller can
    /// drop suggestions computed from text that no longer exists.
    var onDictationUndone: (() -> Void)?

    /// How long the offer stands.
    ///
    /// WHY 8 seconds: long enough to read a sentence and decide it is wrong, short
    /// enough that the control is gone before the user has moved on and forgotten
    /// what it refers to. The issue asks for "a few seconds"; this is a judgement
    /// call, not a measurement.
    private static let dictationUndoTimeout: TimeInterval = 8

    /// `deleteBackward()` calls issued per main-queue turn.
    ///
    /// WHY chunked at all: every call is an IPC round trip to the host, and a
    /// two-minute dictation is hundreds of them. Issued in one synchronous loop
    /// they block the main thread long enough for a slow host to visibly freeze.
    /// Yielding between chunks lets the host process what it has been given.
    private static let dictationUndoChunkSize = 40

    /// Offer to undo `transcription`, if the document still agrees it was inserted.
    ///
    /// WHY the first check is deferred by one main-queue turn: `insertText` and the
    /// proxy's view of the document are not guaranteed to be in step within the same
    /// turn, and a check that runs too early reads the field as it was *before* the
    /// insertion and refuses. One hop costs a frame nobody sees.
    private func armDictationUndo(_ transcription: String) {
        dictationUndoText = transcription
        dictationUndoAvailable = false
        dictationUndoTimer?.invalidate()
        dictationUndoTimer = Timer.scheduledTimer(
            withTimeInterval: Self.dictationUndoTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.invalidateDictationUndo(reason: "timeout")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.dictationUndoText == transcription else { return }
            switch DictationUndo.verify(
                context: self.controller?.textDocumentProxy.documentContextBeforeInput,
                insertedText: transcription
            ) {
            case .ok(let deleteCount, let verifiedCount, let windowTruncated):
                self.dictationUndoAvailable = true
                self.logProbe(
                    "dictationUndoArmed",
                    details: "deleteCount=\(deleteCount) verified=\(verifiedCount) truncated=\(windowTruncated)"
                )
            case .failed(let reason):
                self.invalidateDictationUndo(reason: "arm-\(reason)")
            }
        }
    }

    /// Re-check the offer against the live document.
    ///
    /// WHY this re-verifies instead of clearing outright: the host reports a text
    /// change for the keyboard's *own* insertion too, so a hook that cleared blindly
    /// would cancel the offer in the same breath as making it — on some hosts, at
    /// some speeds. Re-checking has the behaviour the issue asks for (the offer dies
    /// on the first keystroke, a caret move or a host rewrite) without depending on
    /// which changes a given host chooses to report.
    ///
    /// WHY it stands down until the offer is armed: the change reports triggered by
    /// the insertion itself can arrive before the proxy's context catches up with
    /// it, and a check run against that stale context refuses. Arming already
    /// verifies, one main-queue turn after the insertion, and the user cannot type
    /// inside that turn — so there is nothing for this to protect there.
    ///
    /// WHY only a proven mismatch drops the offer, and not every refusal:
    /// "the field is no longer ours" and "nothing could be read just now" are
    /// different facts, and only the first is evidence. Device capture in Messages
    /// (2026-08-02) showed the second killing a valid offer two seconds after it
    /// was armed: iOS had just swapped controllers, the freshly attached one had
    /// not settled, and its proxy returned no context yet — so `no-context`
    /// invalidated an offer nothing had invalidated. Controller churn is routine
    /// here (#281), so this was not a one-off.
    ///
    /// Keeping the offer alive on an unreadable document costs nothing, because
    /// this is not the check that authorises a deletion: `performDictationUndo`
    /// re-verifies at the instant of the tap and fails closed on exactly these
    /// reasons. The worst case is a button that stays on screen for its few
    /// seconds and refuses when tapped, which is the behaviour a host that lies
    /// about its context earns anyway.
    func revalidateDictationUndo() {
        guard dictationUndoAvailable, let transcription = dictationUndoText else { return }
        if case .failed(let reason) = DictationUndo.verify(
            context: controller?.textDocumentProxy.documentContextBeforeInput,
            insertedText: transcription
        ), Self.provesTheFieldChanged(reason) {
            invalidateDictationUndo(reason: "revalidate-\(reason)")
        }
    }

    /// Whether a `DictationUndo` refusal is evidence that the field stopped being
    /// ours, as opposed to evidence that we could not read it.
    ///
    /// `suffix-mismatch` and `truncated-mismatch` are proof: the document was
    /// legible and what it holds is not what we inserted. `no-context` and
    /// `window-too-short` are absence of proof — a detached or unsettled proxy, a
    /// secure field, a host that reports its context late. `empty-insertion`
    /// cannot occur here, since arming refuses an empty string.
    private static func provesTheFieldChanged(_ reason: String) -> Bool {
        reason == "suffix-mismatch" || reason == "truncated-mismatch"
    }

    /// Drop the offer. The record is destroyed, not merely hidden: a hidden record
    /// is one bug away from deleting text it no longer owns.
    func invalidateDictationUndo(reason: String) {
        guard dictationUndoText != nil else { return }
        dictationUndoText = nil
        dictationUndoAvailable = false
        dictationUndoTimer?.invalidate()
        dictationUndoTimer = nil
        logProbe("dictationUndoInvalidated", details: "reason=\(reason)")
    }

    /// Remove the last dictation insertion from the host field.
    ///
    /// The check runs again here, against the document as it is at this instant.
    /// The one performed when the control appeared proves nothing about now: a host
    /// that rewrites text without reporting it leaves a stale offer on screen, and
    /// this is where that is caught. A refusal deletes nothing.
    func performDictationUndo() {
        guard let transcription = dictationUndoText, !isUndoingDictation else { return }
        guard let proxy = controller?.textDocumentProxy else {
            invalidateDictationUndo(reason: "perform-no-proxy")
            return
        }

        switch DictationUndo.verify(
            context: proxy.documentContextBeforeInput,
            insertedText: transcription
        ) {
        case .failed(let reason):
            HapticFeedback.actionRefused()
            invalidateDictationUndo(reason: "perform-\(reason)")
        case .ok(let deleteCount, let verifiedCount, let windowTruncated):
            logProbe(
                "dictationUndoStarted",
                details: "deleteCount=\(deleteCount) verified=\(verifiedCount) truncated=\(windowTruncated)"
            )
            isUndoingDictation = true
            // The offer is spent the moment it is taken. Clearing first also means
            // a second tap during the burst finds nothing to act on.
            invalidateDictationUndo(reason: "performed")
            deleteInsertedText(
                transcription,
                remaining: deleteCount,
                proven: verifiedCount,
                proxy: proxy
            )
        }
    }

    /// Issue the deletion in chunks, yielding to the main queue between them.
    ///
    /// WHY the remainder is re-proved between chunks: the check that started the
    /// burst could only see as far back as the proxy's window, so on a long
    /// dictation most of what is about to be deleted was never shown to us. As the
    /// deletion eats into the field the window slides back over text that was out
    /// of reach a moment ago, and each chunk pays for the next one by proving the
    /// part it is about to remove is still the tail. What that buys is the one
    /// guarantee this feature is for: no character is deleted that has not been
    /// seen to belong to the insertion.
    ///
    /// `proven` is what makes that literal rather than approximate: it is how many
    /// graphemes the last check actually matched, and no chunk may be longer. A
    /// truncated window proves 24 or more, never all 600, so a fixed chunk size on
    /// its own would step past the proof on the very first pass.
    ///
    /// It cuts the other way too. If a host reports its context late, a chunk can
    /// fail to prove a remainder that is in fact still there, and the undo stops
    /// with text left behind. That is the deliberate side to fail on — leftover
    /// text is visible and can be deleted by hand, text eaten out of the middle of
    /// someone's message is neither. The abort is logged with what was left.
    ///
    /// The proxy is captured once, at the start. iOS can attach a new controller
    /// mid-burst, and `controller` is a shared reference that the new one takes
    /// over; re-reading it each turn would redirect the rest of the deletion at
    /// whatever field that controller is looking at.
    ///
    /// Aborts if a dictation has started in the meantime. `startRecording` refuses
    /// to start one while a burst is in flight, so this is the second line of
    /// defence rather than the first — but the app can also drive the status from
    /// its own side, and a burst that kept deleting into a fresh recording would
    /// eat text this undo never inserted.
    private func deleteInsertedText(
        _ insertedText: String,
        remaining: Int,
        proven: Int,
        proxy: UITextDocumentProxy
    ) {
        guard remaining > 0 else {
            isUndoingDictation = false
            onDictationUndone?()
            logProbe("dictationUndoCompleted")
            return
        }
        guard dictationStatus == .idle, activeSessionID == nil else {
            isUndoingDictation = false
            logProbe(
                "dictationUndoAborted",
                details: "reason=dictation-started remaining=\(remaining) \(sessionDetails())"
            )
            return
        }

        let batch = min(remaining, Self.dictationUndoChunkSize, max(proven, 1))
        for _ in 0..<batch {
            proxy.deleteBackward()
        }
        let left = remaining - batch
        if left > 0 {
            Self.nudgeProxyToRefetchContext(proxy)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard left > 0 else {
                self.deleteInsertedText(insertedText, remaining: 0, proven: 0, proxy: proxy)
                return
            }
            let context = proxy.documentContextBeforeInput
            switch DictationUndo.verify(
                context: context,
                insertedText: String(insertedText.prefix(left))
            ) {
            case .ok(_, let verifiedCount, _):
                self.deleteInsertedText(
                    insertedText,
                    remaining: left,
                    proven: verifiedCount,
                    proxy: proxy
                )
            case .failed(let reason):
                self.isUndoingDictation = false
                // `context` is what decides whether the nudge above works. A refusal
                // with a context far shorter than the chunk just deleted means the
                // host trimmed its cached window instead of refetching, which is the
                // case that cannot be fixed from here (#266 device capture).
                self.logProbe(
                    "dictationUndoAborted",
                    details: "reason=\(reason) remaining=\(left) context=\(context?.count ?? -1)"
                )
            }
        }
    }

    /// Ask the host to refetch the text behind the caret, before we read it again.
    ///
    /// WHY (device capture, 2026-08-02, Notes): a 1077-grapheme undo stopped after
    /// 480 with `window-too-short`. The context window measured 498 when the burst
    /// started and 18 when it stopped — 498 minus the 480 removed. The host had not
    /// been serving a *sliding* window over the document at all; it was serving one
    /// cached window and trimming it as the deletions consumed it. The per-chunk
    /// re-proof assumed the former, so past the first window there was nothing left
    /// to prove the remainder against, and the guard did what it is meant to do.
    ///
    /// A caret movement is the only lever a keyboard extension has here: there is no
    /// API to request more context, but moving the insertion point invalidates what
    /// the proxy holds. One step back and one step forward leaves the caret exactly
    /// where it was, in the same run-loop turn, before the read on the next one.
    ///
    /// Deliberately best-effort. If the host ignores it, or applies only one of the
    /// two steps, the verification on the next turn sees a tail that is not the
    /// remainder and refuses — the burst stops with text left in the field, which is
    /// the direction this feature fails in by design. It cannot make the undo delete
    /// something it has not proved.
    private static func nudgeProxyToRefetchContext(_ proxy: UITextDocumentProxy) {
        proxy.adjustTextPosition(byCharacterOffset: -1)
        proxy.adjustTextPosition(byCharacterOffset: 1)
    }

    // MARK: - Keyboard visibility tracking

    /// Called when a controller becomes the active visible keyboard owner.
    ///
    /// Unconditional: the controller iOS just brought on screen is the keyboard,
    /// whatever came before. This is also what ends an awaiting-reclaim window in
    /// the common case — the successor iOS builds after an app switch simply takes
    /// the area over (#260).
    func registerControllerAppearance(controllerID: String) {
        logProbe(
            "registerControllerAppearance",
            details: "controllerID=\(controllerID) previousOwner=\(activeControllerID ?? "none") ownership=\(ownership.logDescription) wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )
        ownership = ownership.appearing(controllerID: controllerID)

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

        // The keyboard the insertion was made from is going away, so the field it
        // was made into is no longer in front of the user (#266). Only the owner
        // counts here: under churn, instances iOS is about to throw away report
        // disappearing too, and letting one of those drop the record would make the
        // offer vanish at random.
        if ownsVisibility {
            invalidateDictationUndo(reason: "keyboard-dismissed")
        }

        ownership = ownership.disappearing(controllerID: controllerID)
    }

    /// Called when a controller is deallocated (#260).
    ///
    /// WHY this is not `registerControllerDisappearance`: a deallocation is not a
    /// dismissal. Ownership is last-writer-wins on appearance, so under churn the
    /// live keyboard's ownership is routinely overwritten by an instance iOS is
    /// about to throw away — and when the old code let that instance release the
    /// area on its way out, the keyboard the user was looking at was left unable
    /// to present anything, with no path back: its `viewWillAppear` had already
    /// run. That is `activeID=none`, and it lasted seconds.
    ///
    /// The area is marked reclaimable instead. That marker reads as ownerless and
    /// invisible, exactly like the release it replaces, so nothing downstream
    /// changes; what it adds is that a controller still on screen may claim the
    /// area through `claimOwnership`.
    ///
    /// Logs only when ownership actually moves: `deinit` runs on every one of the
    /// ~9 instances a churn cycle destroys, and the ids differ, so an
    /// unconditional line would defeat `PersistentLog`'s duplicate collapsing and
    /// spend the #255 budget on non-events.
    func registerControllerDeallocation(controllerID: String) {
        let next = ownership.deallocating(controllerID: controllerID)
        guard next != ownership else { return }
        logProbe(
            "registerControllerDeallocation",
            details: "controllerID=\(controllerID) ownership=\(ownership.logDescription) next=\(next.logDescription) \(sessionDetails())"
        )
        ownership = next
    }

    /// Let the controller iOS is showing claim an area whose owner was
    /// deallocated (#260).
    ///
    /// `isOnScreen` must come from UIKit window attachment, not from bookkeeping:
    /// it is the only thing separating the live keyboard from the cached instances
    /// iOS never tells to disappear (#128), and both reach this on the same path.
    /// Returns whether the caller now owns the keyboard area.
    ///
    /// WHY this deliberately does NOT call `refreshFromDefaults`: it is called from
    /// inside the area-mode subscription, and refreshing writes `dictationStatus`,
    /// whose `didSet` publishes the mode again — a re-entrant emission while the
    /// first one is still applying its layout. The status is current anyway: the
    /// emission that brought us here came from that very write.
    @discardableResult
    func claimOwnership(controllerID: String, isOnScreen: Bool) -> Bool {
        guard let next = ownership.claiming(controllerID: controllerID, isOnScreen: isOnScreen) else {
            logRefusedClaimOnce(controllerID: controllerID, isOnScreen: isOnScreen)
            return false
        }
        logProbe(
            "claimOwnership",
            details: "controllerID=\(controllerID) previous=\(ownership.logDescription) \(sessionDetails())"
        )
        ownership = next
        return true
    }

    /// The marker a refused claim was last logged against, so the line below is
    /// written once per episode rather than once per controller.
    private var loggedClaimRefusalFor: String?

    /// Record that a reclaimable area went unclaimed because the controller asking
    /// was not on screen (#260).
    ///
    /// This exists to make the fail-closed liveness test falsifiable on device. If
    /// window attachment turns out to be unreliable for a `UIInputViewController`,
    /// the symptom is this line with no `claimedOwnerlessArea` after it — an
    /// explicit signal rather than an absence to be inferred.
    ///
    /// Once per marker: every one of the ~9 cached controllers reacts to the same
    /// emission, and #255 exists because lines that multiply by instance count
    /// make a log unreadable.
    private func logRefusedClaimOnce(controllerID: String, isOnScreen: Bool) {
        guard case .awaitingReclaim(let previous) = ownership,
              loggedClaimRefusalFor != previous else { return }
        loggedClaimRefusalFor = previous
        logProbe(
            "claimRefusedOffScreen",
            details: "controllerID=\(controllerID) previousOwner=\(previous) hasWindow=\(isOnScreen) \(sessionDetails())"
        )
    }

    /// Ask a controller still on screen to look at an area that just became
    /// reclaimable, instead of waiting for the next dictation status change (#260).
    ///
    /// WHY this is needed at all: a controller claims an ownerless area from
    /// `applyAreaMode`, which only runs when the area mode is published — i.e. on a
    /// status write. If the owner is deallocated in the middle of a recording, the
    /// next write is the `transcribing` transition, so the keyboard would sit in
    /// its typing layout for the rest of the utterance.
    ///
    /// Only while a dictation owns the area: `.recording` is the one mode gated on
    /// ownership, so re-publishing anything else would make every attached
    /// controller redo its layout for no possible change.
    ///
    /// WHY asynchronously: this is reached from the outgoing owner's `deinit`,
    /// which then goes on to tear down its hosting controller and view hierarchy.
    /// Applying layout on a *different* controller from inside that stack is the
    /// kind of re-entrancy this file has regressed on before (#142, #128, #166).
    /// One main queue hop puts the work after the deallocation has finished.
    ///
    /// It does nothing when every controller has already been detached — the
    /// subscription is cancelled in `viewDidDisappear`. Nothing can be done for the
    /// keyboard then: there is no live controller left to draw with.
    private func nudgeAttachedControllersToReclaim() {
        guard areaMode == .recording else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.ownership.isReclaimable, self.areaMode == .recording else { return }
            self.logProbe(
                "reclaimNudge",
                details: "ownership=\(self.ownership.logDescription) mode=\(self.areaMode.rawValue) \(self.sessionDetails())"
            )
            self.areaModeSubject.send(self.areaMode)
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
        // An undo burst is still rewriting the field (#266). Starting a dictation
        // now would have the two interleave: the burst deletes on every main-queue
        // turn, and the transcription it would be deleting into is not the one it
        // was verified against. The burst is short; the user taps again.
        //
        // WHY this comes before the debounce: a refused tap must not count as a
        // tap. Charging it to the debounce window would make the mic dead for
        // 1.5 s after a burst that lasted a fraction of that, and the second tap —
        // the one this refusal is telling the user to make — would be the one
        // rejected.
        guard !isUndoingDictation else {
            logProbe("micTapRejectedDuringUndo", details: sessionDetails())
            HapticFeedback.actionRefused()
            return
        }

        // Debounce: reject taps within 1.5s of the last tap.
        let now = Date()
        guard now.timeIntervalSince(lastMicTapDate) >= 1.5 else {
            PersistentLog.log(.rapidTapRejected)
            return
        }
        lastMicTapDate = now

        // A new dictation ends the previous one's undo offer, whatever comes of it.
        invalidateDictationUndo(reason: "new-dictation")

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
                // Force unwrap: the argument is a compile-time literal and a
                // well-formed absolute URL, so the failable initializer cannot
                // return nil. Nothing at runtime can change this string.
                // swiftlint:disable:next force_unwrapping
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
