// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via UnifiedAudioEngine + transcription via TranscriptionService.
import Foundation
import Combine
import AVFoundation
import UIKit
import DictusCore
import WhisperKit

/// Manages the dictation lifecycle in the main app.
/// Phase 3.1: Observes keyboard stop/cancel signals via Darwin notifications,
/// forwards waveform energy to App Group for keyboard visualization.
///
/// WHY this class is @MainActor and uses static let shared:
/// - @MainActor ensures all @Published property updates happen on the main thread (required by SwiftUI)
/// - Singleton pattern because there's only ever one dictation session active at a time,
///   and multiple views need to observe the same coordinator (ContentView, RecordingView)
@MainActor
class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    // MARK: - Published State

    @Published var status: DictationStatus = .idle

    /// The last transcription, and only that. Nil on every failure by construction —
    /// `startDictation` resets it and nothing but a successful transcription assigns it —
    /// so it is not, and must not be read as, a failure channel (#320). What went wrong
    /// lives in `DictationErrorChannel`.
    @Published var lastResult: String?

    /// Forwarded from UnifiedAudioEngine for waveform visualization in RecordingView.
    @Published var bufferEnergy: [Float] = []

    /// Forwarded from UnifiedAudioEngine for elapsed time display in RecordingView.
    @Published var bufferSeconds: Double = 0

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private let audioEngine = UnifiedAudioEngine()
    private let transcriptionService = TranscriptionService()

    /// Whether the audio engine is currently running.
    /// Used by DictusApp to detect "warm but engine-dead" state after Power button stop.
    var isEngineRunning: Bool { audioEngine.isEngineRunning }

    /// Timeout watchdog for whichever post-recording stage is running.
    ///
    /// WHY one timer for two stages (#267): they are mutually exclusive and the
    /// failure it catches is the same one -- a stage that never hands over, leaving
    /// the keyboard's overlay up with nothing behind it. What differs is only how
    /// long is too long, which `stageWatchdogTimeout(for:)` answers.
    ///
    /// The status it was armed for is captured by the timer's own closure, which
    /// re-checks it before firing -- a stage that has handed over to the next one
    /// must not be torn down by the previous one's timer.
    private var stageWatchdog: Timer?

    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private var dictationTask: Task<Void, Never>?

    /// Fires ~1.5s into a recording to prewarm the Apple FM polish model (#141).
    /// Held so it can be cancelled if the user stops before it fires. See
    /// `schedulePolishPrewarm()`.
    private var polishPrewarmTask: Task<Void, Never>?

    /// Which dictation the app is currently in. Moves when one starts and when one
    /// is abandoned -- see `DictationSessionGeneration` for why both matter.
    private var sessionGeneration = DictationSessionGeneration()

    /// The generation delayed UI closures capture (issue #60). RecordingView's
    /// dismiss and onboarding auto-advance bail out when it has moved on, so a
    /// stale reset can never tear down a fresh recording.
    var dictationGeneration: Int { sessionGeneration.current }

    /// Set when cold start dictation is deferred because the app is .inactive.
    ///
    /// Cleared by whichever of its two consumers gets there first: the
    /// `didBecomeActive` retry, or `resolvePendingColdStartOnBackground()` when the
    /// app leaves the foreground without ever having become active (#311). The
    /// second one is not an optimisation -- it is the only exit that always exists.
    /// `didBecomeActive` is an event the user can withhold simply by swiping back
    /// fast enough, and four of twelve deliberately fast dictations did exactly that.
    ///
    /// Not `private` only because the second consumer lives in `ColdStartResolution.swift`
    /// and `private` is file-scoped. Still single-writer.
    var pendingColdStartDictation = false

    /// Background execution assertion held across the resolution of a parked cold
    /// start (#311). `.invalid` when none is held. Managed entirely from
    /// `ColdStartResolution.swift`, which is why it is not `private`.
    ///
    /// WHY this is the only such assertion in the app: every other path either runs in
    /// the foreground, or runs while the audio engine is already capturing and
    /// `UIBackgroundModes: audio` grants the runtime. This one runs from the
    /// `.background` scene transition, so the process is on its way to suspension, and
    /// the runtime it needs is the runtime it is trying to earn -- the audio mode
    /// grants nothing until `startRecording()` has succeeded, which is the far side of
    /// the window. Without an assertion that window is covered only by iOS's default
    /// post-background grace, which is a behaviour and not a contract. A suspension
    /// inside it would leave the flag cleared, no engine started and nothing reported:
    /// the exact silence this whole change exists to make impossible, with a log line
    /// to prove we had thought about it.
    var coldStartAssertion: UIBackgroundTaskIdentifier = .invalid

    /// Task that resolves when WhisperKit is fully loaded.
    /// WHY: Both init() pre-load and startDictation() call ensureEngineReady().
    /// If startDictation() arrives while pre-load is still running, it must AWAIT
    /// the ongoing init instead of starting a duplicate one. This Task acts as
    /// a concurrency lock — the first caller creates it, subsequent callers await it.
    private var initTask: Task<Void, Error>?

    /// Re-entry flag for stopDictation. Prevents the 3+ concurrent transcribe()
    /// calls observed in #144 when a user taps stop multiple times during a model
    /// swap (turbo load). Set synchronously on entry, cleared in the Task's defer.
    private var isTranscribingInFlight = false

    /// Timestamp of last waveform write to App Group.
    /// Used to throttle writes to ~5Hz (every 200ms) to avoid overwhelming UserDefaults
    /// with high-frequency updates from the audio engine's energy callback.
    private var lastWaveformWriteDate = Date.distantPast

    /// Combine subscriptions forwarding UnifiedAudioEngine's published values to coordinator.
    private var energyCancellable: AnyCancellable?
    private var secondsCancellable: AnyCancellable?

    private init() {
        // Forward UnifiedAudioEngine's energy levels and seconds to coordinator.
        // NOTE: App Group forwarding for the keyboard is handled directly from
        // the audio thread in UnifiedAudioEngine's processBuffer.
        energyCancellable = audioEngine.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                guard let self else { return }
                self.bufferEnergy = energy
                // Only forward to Dynamic Island when user is actively recording
                guard self.audioEngine.isRecording else { return }
                LiveActivityManager.shared.updateWaveform(levels: energy)
            }
        secondsCancellable = audioEngine.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.bufferSeconds = seconds
            }

        // Observe keyboard-initiated stop/cancel signals via Darwin notifications.
        observeKeyboardSignals()

        // Clear stale transcription left over from a previous crash or missed pickup.
        // 5-minute threshold: if the keyboard didn't read it by now, it never will.
        if let ts = defaults.object(forKey: SharedKeys.lastTranscriptionTimestamp) as? Double,
           Date().timeIntervalSince1970 - ts > 300 {
            defaults.removeObject(forKey: SharedKeys.lastTranscription)
            defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
            defaults.synchronize()
        }

        // Audit the shared dictation state before anything reads it (issue #261).
        reconcileOrphanedDictationState()

        // Phase 37 instrumentation: snapshot device capabilities once per app launch
        // so the log stream has a stable anchor for per-device gating analysis.
        let snapshot = DeviceCapabilities.current()
        PersistentLog.log(.deviceCapabilitySnapshot(
            model: snapshot.deviceModelIdentifier,
            ramGB: snapshot.physicalMemoryGB,
            availableMemoryMB: snapshot.availableMemoryMB,
            thermalState: snapshot.thermalState.logLabel
        ))

        // Pre-load WhisperKit + audio session eagerly on app launch.
        // WHY: The first recording via URL scheme takes 4-5s if we load lazily.
        // By loading in init(), the model is ready when the keyboard triggers dictation.
        //
        // WHY configure audio session BEFORE the Task:
        // iOS forbids AVAudioSession.setActive(true) from background. The async Task
        // may not run until after the app is backgrounded. By configuring synchronously
        // in init(), we guarantee the session is active while still in the foreground.
        try? audioEngine.configureAudioSession()

        Task {
            let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
            guard modelReady else {
                self.setModelLoadState(.idle, reason: "init-preload-no-model")
                return
            }

            self.setModelLoadState(.loading, reason: "init-preload")
            do {
                try await ensureEngineReady()
                PersistentLog.log(.engineWarmUpAttempt(context: "init-preload"))
                try audioEngine.warmUp()
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                self.setModelLoadState(.ready, reason: "init-preload-success")
            } catch {
                PersistentLog.log(.engineWarmUpFailed(context: "init-preload", error: error.localizedDescription))
                self.setModelLoadState(.idle, reason: "init-preload-failed")
            }
        }

        // Stop audio engine when user taps Power button in Dynamic Island.
        // WHY here (not in LiveActivityManager):
        // The audio engine is owned by DictationCoordinator.
        // StopStandbyIntent posts this notification because it can't reference coordinator
        // directly (the intent file is compiled into DictusWidgets too).
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DictusStopStandbyRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Sync LiveActivityManager state — the intent already ended the activity
                // but the manager doesn't know. Without this, currentActivity stays non-nil
                // and ensureActivityAlive() is a no-op on next dictation (#50).
                LiveActivityManager.shared.stopStandbyActivity()

                // Stop any active recording first
                if self.status == .recording {
                    self.cancelDictation()
                }
                // Kill the audio engine — removes the orange mic indicator
                if self.audioEngine.isEngineRunning {
                    self.audioEngine.deactivateSession()
                }
                PersistentLog.log(.engineWarmUpFailed(context: "standby-power-off", error: "user stopped standby"))
            }
        }

        // Cancel any in-flight dictation when the audio session is interrupted
        // (phone call, Siri, etc.) or media services are reset. UnifiedAudioEngine
        // already tore down the engine; we just need to clean up the dictation
        // pipeline state and notify the keyboard that the recording failed
        // (issue #106).
        NotificationCenter.default.addObserver(
            forName: .dictusAudioSessionInterrupted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAudioInterruptionDuringDictation()
            }
        }

        // WHY observe didBecomeActive (not willEnterForeground):
        // willEnterForeground fires while the audio session is still interrupted.
        // didBecomeActive fires AFTER the app is fully active and the audio session
        // interruption has ended — the audio engine can safely start at this point.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // `sessionConfigured` used to be a hardcoded `true` here, so
                // every `sessionConfigured=true` in a device log was a literal
                // rather than a measurement — including the one quoted as
                // evidence in #293. Both fields are now read from the engine.
                PersistentLog.log(.engineStateSnapshot(
                    engineRunning: self.audioEngine.isEngineRunning,
                    isRecording: self.audioEngine.isRecording,
                    hasWhisperKit: self.whisperKit != nil,
                    sessionConfigured: self.audioEngine.sessionConfigured,
                    allowsHaptics: self.audioEngine.allowsHapticsDuringRecording,
                    context: "didBecomeActive"
                ))

                // Wall-clock backstop for Phase B's idle-release timer (issue #106).
                // If iOS suspended the main queue while we were backgrounded, the
                // asyncAfter scheduled in scheduleIdleRelease may fire late. On
                // foreground transition we have a reliable runloop again — this
                // call releases the warm state if the idle interval already
                // expired during the suspension. Must happen BEFORE warmUp below,
                // otherwise we'd warm an engine that should be released.
                self.audioEngine.enforceIdleReleaseIfDue()

                // Recover DI if it was lost (Activity.request fails from background on cold start).
                // Must happen BEFORE pendingColdStartDictation so transitionToRecording finds an activity.
                LiveActivityManager.shared.ensureActivityAlive()

                // Retry deferred cold start dictation now that app is fully active.
                // WHY here: URL scheme launches fire handleIncomingURL at .inactive state,
                // where engine.start() fails. startDictation sets pendingColdStartDictation
                // and returns. Now that we're .active, retry the full startDictation flow.
                //
                // This stays the primary path — it is the one that runs from a fully
                // active app with a recovered audio session. The background path added
                // in #311 is the fallback for when this event never arrives.
                if self.pendingColdStartDictation {
                    self.pendingColdStartDictation = false
                    // Only retry if keyboard is still waiting (watchdog hasn't reset to idle)
                    let keyboardStatus = self.defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil"
                    PersistentLog.log(.coldStartRetry(keyboardStatus: keyboardStatus))
                    if keyboardStatus == DictationStatus.requested.rawValue {
                        self.startDictation(fromURL: true)
                    }
                    return
                }

                guard !self.audioEngine.isEngineRunning else {
                    PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive-already-running"))
                    return
                }
                let modelReady = self.defaults.bool(forKey: SharedKeys.modelReady)
                guard modelReady else {
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive", error: "modelReady=false"))
                    return
                }

                do {
                    try self.audioEngine.configureAudioSession()
                    PersistentLog.log(.engineWarmUpAttempt(context: "didBecomeActive"))
                    self.setModelLoadState(.loading, reason: "didBecomeActive-warmup")
                    try await self.ensureEngineReady()
                    try self.audioEngine.warmUp()
                    PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive"))
                    self.setModelLoadState(.ready, reason: "didBecomeActive-success")
                } catch {
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive", error: error.localizedDescription))
                    self.setModelLoadState(.idle, reason: "didBecomeActive-failed")
                }
            }
        }
    }

    /// Schedule a prewarm of the Apple FM polish model partway into a recording (#141).
    ///
    /// Apple recommends calling `prewarm()` at least one second before
    /// `respond()`, "when interaction is imminent". The start of a recording is
    /// exactly that signal: we know polish will run in a few seconds, and the
    /// recording itself provides the lead time. Firing at ~1.5s also aligns with
    /// the polish engine's <2s skip gate — if we're still recording at 1.5s the
    /// clip will almost certainly cross 2s and actually be polished, so warming
    /// is not wasted on flash dictations.
    ///
    /// The `status == .recording` guard drops the prewarm if the user already
    /// stopped. `PolishCoordinator.prewarm()` is itself a no-op when the toggle
    /// is off, so we don't load the model into memory for nothing.
    private func schedulePolishPrewarm() {
        polishPrewarmTask?.cancel()
        polishPrewarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.status == .recording else { return }
            PolishCoordinator.shared.prewarm()
        }
    }

    // MARK: - Public API

    /// Start the recording pipeline.
    /// Called from URL scheme (first time) or Darwin notification (subsequent times).
    ///
    /// Two paths:
    /// - WARM START: engine already running → purge idle samples + startRecording()
    /// - COLD START: engine not running → startRecording() starts it (<100ms) + load model in parallel
    ///
    /// - Parameters:
    ///   - fromURL: If true, the app was opened via URL scheme from the keyboard.
    ///   - allowInactiveStart: Skip the cold-start defer below and attempt the start
    ///     from whatever state the app is in. Set only by
    ///     `resolvePendingColdStartOnBackground()`, which is the last chance a parked
    ///     start gets (#311) — deferring a second time there would park it forever.
    func startDictation(fromURL: Bool = false, allowInactiveStart: Bool = false) {
        // Clear previous recording state before starting new recording.
        // WHY here (not in stopDictation): DI tap and lockscreen paths call
        // startDictation directly without going through stopDictation first.
        // The old result must be cleared regardless of entry path so
        // RecordingView never shows a stale transcription card.
        lastResult = nil
        // Same argument, one process further out (#320): the previous attempt's failure
        // reason is stale the moment a new attempt begins, and this is the only event
        // that makes it so. Clearing here — rather than when a surface reads it — is
        // what lets both the keyboard and the app read it, in either order.
        DictationErrorChannel.clear()
        bufferEnergy = []
        bufferSeconds = 0
        // Cancel any polish still running from the previous dictation (#141).
        PolishCoordinator.shared.cancelInflight()
        polishPrewarmTask?.cancel()
        PersistentLog.log(.statusChanged(from: status.rawValue, to: "clearing-for-new", source: "startDictation-reset"))

        // Guard against duplicate calls while actively recording or transcribing.
        // The predicate moved to DictusCore in #311 so the stranded-cold-start path
        // can ask the same question before it calls in, instead of restating this
        // list and drifting from it.
        guard ColdStartResolutionPolicy.canStartNewDictation(from: status) else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Ignoring duplicate startDictation — already \(self.status.rawValue, privacy: .public)")
            }
            return
        }

        // New session supersedes any pending delayed reset (issue #60) and any
        // outstanding work from the previous one (#267).
        sessionGeneration.beginSession()

        // WHY this early return (only for Darwin notification path, NOT URL scheme):
        // iOS forbids starting an audio engine from background. If the engine isn't
        // running and we're in background (Darwin notification from keyboard), attempting
        // to start will fail. The keyboard's fallback opens the URL scheme after 500ms.
        let appState = UIApplication.shared.applicationState
        if !fromURL && appState != .active && !audioEngine.isEngineRunning {
            PersistentLog.log(.dictationDeferred(reason: "no engine running, appState=\(appState.rawValue)"))
            return
        }

        PersistentLog.log(.dictationStarted(fromURL: fromURL, appState: "\(appState.rawValue)", engineRunning: audioEngine.isEngineRunning))

        // Check if a model is downloaded and ready.
        // Force a cross-process sync before reading — right after a URL-scheme wake
        // the App Group defaults can return a stale `false`, producing a bogus
        // "no model downloaded" error on the first attempt (observed in #102).
        defaults.synchronize()
        let modelReady = defaults.bool(forKey: SharedKeys.modelReady)
        guard modelReady else {
            PersistentLog.log(.dictationFailed(error: "No model downloaded"))
            // Localised since #249 — this sibling of the model-availability failure
            // reached the keyboard banner in English regardless of device language.
            handleError(String(localized: "No model downloaded. Open Dictus to download a model."))
            return
        }

        // Refuse new dictation if an explicit model swap is in flight.
        // Issue #144: tapping the mic during a turbo load caused the keyboard to
        // queue dispatches that all collapsed into 3+ concurrent transcribe()
        // calls when the load resolved. Reading the App Group state lets us short-
        // circuit cleanly — the keyboard's overlay UI surfaces the wait to the user.
        //
        // Issue #167: URL-scheme cold-start launches arrive while the init-preload
        // is still loading the model. Failing here would route first-use dictation
        // into `failed` state. Skip the guard for fromURL=true and let the existing
        // cold-start defer at line ~368 park the request as `pendingColdStartDictation`
        // — the retry's `ensureEngineReady` awaits the in-flight initTask via its lock.
        let currentLoadState = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        if currentLoadState == ModelLoadState.loading.rawValue && !fromURL {
            PersistentLog.log(.dictationDeferred(reason: "model load in flight (state=loading)"))
            // Keep the keyboard request pending. KeyboardState re-reads the
            // shared state before its fallback URL and opens the prepare-only
            // flow instead of showing a refusal message.
            return
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        // Play start sound BEFORE configuring the audio session.
        // WHY before: Once the audio session is configured with .playAndRecord,
        // AudioServicesPlaySystemSound may be suppressed.
        SoundFeedbackService.playRecordStart()

        // Configure audio session NOW while we're in the foreground.
        try? audioEngine.configureAudioSession()

        // The session these start paths belong to. `ensureMicrophonePermission` is
        // an await even when permission is already granted, so a cancel queued on
        // the main actor can land between here and the first write below (#267).
        let session = sessionGeneration.current

        if audioEngine.isEngineRunning {
            // WARM START: engine already running → purge + record (instant)
            dictationTask = Task {
                do {
                    let hasPermission = try await audioEngine.ensureMicrophonePermission()
                    guard hasPermission else {
                        guard mayReport(session, "permission denial") else { return }
                        handleError("Microphone permission denied")
                        return
                    }
                    // Before `startRecording`, not merely before the status write:
                    // a cancelled start that reached the engine would leave the mic
                    // capturing for a dictation the user called off -- the orphaned
                    // engine of #60, arrived at from the other end.
                    guard mayReport(session, "warm start") else { return }
                    updateStatus(.recording)
                    LiveActivityManager.shared.transitionToRecording()
                    try audioEngine.startRecording()
                    PersistentLog.log(.audioEngineStarted)
                    schedulePolishPrewarm()
                    await verifyAudioFlow()
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Warm start: \(error.localizedDescription)"))
                    guard mayReport(session, "warm start failure") else { return }
                    handleError(error.localizedDescription)
                }
            }
        } else {
            // COLD START: engine not running → start engine + record + load model in parallel
            //
            // WHY defer when not .active:
            // URL scheme launches fire handleIncomingURL while app is still .inactive.
            // AVAudioEngine.start() fails with AUIOClient_StartIO error from non-active state.
            // Deferring to didBecomeActive guarantees the app is fully active.
            //
            // WHY the flag can override it (#311): `allowInactiveStart` is set only by
            // the background-transition path, where `.active` is no longer coming. A
            // second defer there would re-park the request with nothing left to unpark
            // it, which is the bug this whole change is about.
            if appState != .active && !allowInactiveStart {
                pendingColdStartDictation = true
                PersistentLog.log(.dictationDeferred(
                    reason: "cold start deferred to didBecomeActive, appState=\(appState.rawValue)"))
                return
            }

            dictationTask = Task {
                // Backstop for the background assertion a last-chance start holds
                // (#311). The two outcomes release it themselves, each at the earliest
                // moment it is safe to; this catches the exits that are neither -- a
                // permission denial, and the `mayReport` guards that drop an abandoned
                // session. A no-op when no assertion is held, which is every other call.
                defer { self.endColdStartAssertion(reason: "task-exit") }
                do {
                    let hasPermission = try await audioEngine.ensureMicrophonePermission()
                    guard hasPermission else {
                        guard mayReport(session, "permission denial") else { return }
                        handleError("Microphone permission denied")
                        return
                    }
                    guard mayReport(session, "cold start") else { return }
                    try audioEngine.startRecording()
                    updateStatus(.recording)
                    LiveActivityManager.shared.transitionToRecording()
                    PersistentLog.log(.audioEngineStarted)
                    // The engine is capturing, so `UIBackgroundModes: audio` keeps the
                    // process alive on its own now. Released here rather than at the end
                    // of the task so the model load below, which can run for tens of
                    // seconds, does not sit on an assertion it no longer needs.
                    endColdStartAssertion(reason: "engine-started")
                    schedulePolishPrewarm()
                    await verifyAudioFlow()

                    // Load the transcription model in parallel while recording
                    self.setModelLoadState(.loading, reason: "cold-start-load")
                    try await ensureEngineReady()
                    let loadedName = self.currentModelName ?? "unknown"
                    PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
                    self.setModelLoadState(.ready, reason: "cold-start-success")
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Cold start engine load: \(error.localizedDescription)"))
                    // A last-chance start (#311) fails for a reason the user can do
                    // nothing about and cannot read: the #73 AUIOClient_StartIO failure
                    // reaches `localizedDescription` as a bare CoreAudio error number.
                    // The raw text stays in the log line above, where it belongs; the
                    // keyboard banner gets the one action that works.
                    let message = allowInactiveStart
                        ? self.strandedColdStartMessage
                        : error.localizedDescription
                    // The model load runs inside this task and takes seconds on a
                    // cold start, so this is the widest window in the app for a
                    // cancel to arrive mid-flight. `setModelLoadState` stays ungated
                    // on purpose: it describes the model, which outlives any one
                    // dictation, and the next session needs it to be accurate.
                    self.setModelLoadState(.idle, reason: "cold-start-failed")
                    guard self.mayReport(session, "cold start failure") else { return }
                    self.handleError(message)
                    // The keyboard has been told. Released here so the assertion ends on
                    // a reported failure exactly as it does on a started engine.
                    self.endColdStartAssertion(reason: "failure-reported")
                }
            }
        }
    }

    /// Tell the keyboard that a parked cold start will not run.
    ///
    /// WHY `handleError` and not a bespoke channel: the keyboard's status message is an
    /// in-process property of `KeyboardState`; nothing the app writes reaches it directly.
    /// `DictationErrorChannel` plus a `.failed` status is the app's actual channel —
    /// `KeyboardState.refreshFromDefaults` picks the error up and shows it for three
    /// seconds, and `.failed` does not own the keyboard area, so the "Démarrage…"
    /// overlay drops on the same write. The keyboard clears its own toolbar line when
    /// the three seconds are up; the stored reason stays until the next dictation (#320).
    ///
    /// The wording asks for a second tap rather than explaining the race: by the time
    /// this is read the user is in their host app looking at a stuck keyboard, and what
    /// they need is the one action that works.
    func reportStrandedColdStart() {
        PersistentLog.log(.dictationFailed(error: "cold start stranded: app left the foreground before it could run"))
        handleError(strandedColdStartMessage)
    }

    /// What the keyboard says when a cold start could not run. Shared by the two ways
    /// that happens — no attempt was possible, or the attempt threw — because from the
    /// user's side they are the same event and deserve the same sentence.
    private var strandedColdStartMessage: String {
        String(localized: "Dictation could not start. Tap the microphone again.")
    }

    /// Called when user taps the stop button.
    /// Stops recording and starts transcription using the already-loaded model.
    ///
    /// Single path: collectSamples() (keeps engine alive) → transcribe → done.
    /// No more branching between AudioRecorder and RawAudioCapture.

    /// Minimum audio duration required for transcription (in seconds).
    /// WHY 0.5s: WhisperKit handles clips ≥0.5s reliably for short words (oui, non, ok).
    /// Below 0.5s, it tends to hallucinate (invent words not spoken).
    /// Previous value was 1.0s (Parakeet requirement), but Parakeet is no longer used
    /// in the dictation pipeline — only WhisperKit via keyboard.
    private let minimumRecordingDuration: TimeInterval = 0.5

    func stopDictation() {
        // Issue #144 re-entry guard: refuse if a transcription is already in flight.
        // Without this, tapping stop multiple times during a long model swap (e.g.
        // turbo load) spawned 3+ concurrent transcribe() calls that cancelled each
        // other with Swift.CancellationError. The flag is set synchronously here
        // (before the async Task) so a second stopDictation() can never slip past.
        guard !isTranscribingInFlight else {
            PersistentLog.log(.dictationDeferred(reason: "stop ignored — transcription already in flight"))
            return
        }
        isTranscribingInFlight = true

        dictationTask?.cancel()
        // The recording is ending; the prewarm (if it hasn't fired) is moot.
        polishPrewarmTask?.cancel()

        // The session this run belongs to. Every write it makes below is gated on
        // still being that session (#267) -- see `mayReport`.
        let session = sessionGeneration.current

        dictationTask = Task {
            defer { self.isTranscribingInFlight = false }
            do {
                let samples = audioEngine.collectSamples()

                guard !samples.isEmpty else {
                    guard mayReport(session, "empty recording") else { return }
                    handleError("No audio recorded")
                    return
                }

                let audioDuration = Double(samples.count) / 16000.0

                guard audioDuration >= minimumRecordingDuration else {
                    PersistentLog.log(.recordingTooShort(durationMs: Int(audioDuration * 1000)))
                    guard mayReport(session, "short recording") else { return }
                    handleError("Recording too short")
                    return
                }

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording stopped. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", audioDuration), privacy: .public)s")
                }

                updateStatus(.transcribing)
                LiveActivityManager.shared.transitionToTranscribing()
                // Arm watchdog: if DI fails to leave .recording, force recovery after 10s.
                // If transitionToTranscribing succeeded, the watchdog's guard exits harmlessly.
                LiveActivityManager.shared.startRecordingWatchdog()
                SoundFeedbackService.playRecordStop()

                try await ensureEngineReady()

                // One language-policy snapshot per dictation (#226): mode,
                // keyboard language, engine, and model are captured HERE and
                // propagated through STT, polish, and finalization. Without
                // the snapshot, each stage would re-read App Group state and a
                // keyboard-toolbar language change while transcription runs
                // could make Whisper transcribe in one language and polish in
                // another. The policy is also engine-aware: with Parakeet
                // active the setting is Whisper-only-effective, so every mode
                // resolves to the historical follow behavior.
                let languagePolicy = TranscriptionLanguagePolicy.snapshot()

                let rawText = try await transcriptionService.transcribe(
                    audioSamples: samples,
                    languagePolicy: languagePolicy
                )

                // Polish layer (#141) — passes raw through when toggle off, when language
                // detection skips, when the engine throws/cancels, or when the guardrail rejects.
                //
                // The status moves to `.processing` from inside the call rather than
                // before it (#267): every one of those pass-through paths returns in
                // about a millisecond, and announcing a stage for them would flash a
                // label and a new animation for a single frame. `onEngineWillRun`
                // fires only once an engine worth waiting for is about to run.
                let text = await PolishCoordinator.shared.polish(
                    raw: rawText,
                    languagePolicy: languagePolicy,
                    recordingDuration: audioDuration,
                    // Gated like every other write this task makes: the callback
                    // fires from inside `polish`, which a cancel does not interrupt,
                    // so an abandoned dictation would otherwise reopen the keyboard
                    // overlay on "Traitement..." and drive the Live Activity into a
                    // stage it had already left (#267).
                    onEngineWillRun: { [weak self] in
                        guard let self, self.mayReport(session, "processing stage") else { return }
                        self.updateStatus(.processing)
                        LiveActivityManager.shared.transitionToProcessing()
                    }
                )

                // Append trailing separator so chained dictations don't stick together.
                // Whisper Auto-detect mode (#226) inserts the transcription as-is: the
                // output language is unknown, and coercing Western punctuation/spacing
                // onto e.g. Chinese ("你好。" + ". ") would corrupt the text. Follow and
                // explicit modes — and Parakeet in every mode — keep the historical
                // separator behavior unchanged.
                let finalText: String
                if languagePolicy.insertsTranscriptionAsIs {
                    finalText = text
                } else if let last = text.last, ".!?…".contains(last) {
                    finalText = text + " "
                } else {
                    finalText = text + ". "
                }

                // The gate that matters most. Everything below is irreversible from
                // the user's point of view: it writes the transcription to the App
                // Group and posts `transcriptionReady`, which is what makes the
                // keyboard type it into their document. A dictation the user
                // cancelled must not insert text a few seconds later (#267).
                guard mayReport(session, "transcription result") else { return }

                // Write result to App Group
                lastResult = finalText
                status = .ready
                defaults.set(finalText, forKey: SharedKeys.lastTranscription)
                defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
                defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
                defaults.synchronize()

                DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
                LiveActivityManager.shared.endWithResult(preview: finalText)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Transcription complete: \(finalText, privacy: .private)")
                }

                cleanupRecordingKeys()
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                }
                // A cancelled task lands here, and so does one that failed for its
                // own reasons after the session ended. Either way the failure
                // belongs to a dictation that is over: writing `.failed` re-presents
                // the recording screen the user just dismissed (#267).
                guard mayReport(session, "transcription failure") else { return }
                handleError(error.localizedDescription)
            }
        }
    }

    /// Cancel the current dictation without transcribing.
    /// Called when the keyboard sends a cancel signal via Darwin notification.
    func cancelDictation() {
        // FIRST, before anything is cancelled: from here on, the transcription task
        // is working for a session that no longer exists and may not report (#267).
        // `Task.cancel()` below is only a request -- neither WhisperKit nor Apple FM
        // promises to return promptly -- so the task can still finish seconds from
        // now, and this is what makes its outcome land nowhere.
        sessionGeneration.abandonSession()
        dictationTask?.cancel()
        dictationTask = nil
        // Reset the transcribe re-entry flag so the next stop/cancel cycle can proceed.
        isTranscribingInFlight = false
        stopStageWatchdog()

        // Discard samples but keep engine alive for next recording
        _ = audioEngine.collectSamples()

        // Reset all state
        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()
        SoundFeedbackService.playRecordCancel()
        // Return Dynamic Island to standby (cancel = no transcription, go back to "On")
        Task { await LiveActivityManager.shared.returnToStandby() }
        // `returnToStandby` only comes back from .recording/.ready/.failed, and the
        // recording watchdog below only unsticks .recording -- so a dictation
        // abandoned inside a post-recording stage had no path home at all, and the
        // pill stayed on that stage and rejected the next dictation (#267 review).
        // The two calls are mutually exclusive by their own guards, so the order
        // between them does not matter.
        LiveActivityManager.shared.recoverFromAbandonedStage()
        // Arm watchdog: safety net if returnToStandby's guard rejects.
        LiveActivityManager.shared.startRecordingWatchdog()
        updateStatus(.idle)

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation cancelled by keyboard")
        }
    }

    /// Reset status to idle (e.g., after user returns to keyboard).
    ///
    /// Issue #60: a UI-only reset while the pipeline is active orphans the audio
    /// engine (keeps capturing) and the Live Activity (stuck on REC), so an active
    /// session must go through the real teardown instead.
    ///
    /// WHY the shared predicate and not a list of cases spelled out here (#267):
    /// this asks "is a dictation in flight", which is the exact question
    /// `isActive` answers over an exhaustive switch. A hand-written list is a list
    /// the next status case can be left out of, silently, and this one guards a
    /// teardown -- the same shape of omission #260 and #261 were made of.
    func resetStatus() {
        if DictationSessionLivenessPolicy.isActive(status) {
            cancelDictation()
            return
        }
        updateStatus(.idle)
        // Keep lastResult so HomeView can display the last transcription card.
    }

    /// Handle an audio session interruption that fired while dictation was active.
    ///
    /// UnifiedAudioEngine has already stopped the engine and posted the in-process
    /// notification. We only need to clean up the dictation pipeline: cancel the
    /// in-flight task, drop accumulated samples, write a "failed" status to App
    /// Group so the keyboard's overlay closes, and notify the user via the Live
    /// Activity (LiveActivityManager handles its own end via the same notification).
    /// Issue #106.
    private func handleAudioInterruptionDuringDictation() {
        // Same predicate as `resetStatus` and for the same reason (#267).
        let wasActive = DictationSessionLivenessPolicy.isActive(status)
        guard wasActive else {
            // Engine died while idle — nothing to roll back. The standby DI is
            // dismissed by LiveActivityManager via the same notification.
            return
        }

        // Same reasoning as `cancelDictation`: this teardown ends the session, so
        // the task must not report into it afterwards (#267). The `.failed` written
        // below is this handler speaking, not the task, and is not gated.
        sessionGeneration.abandonSession()
        dictationTask?.cancel()
        dictationTask = nil
        isTranscribingInFlight = false
        stopStageWatchdog()

        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()

        // updateStatus(.failed) handles both the App Group write and the Darwin
        // statusChanged post — no manual duplication needed (issue #106 review).
        updateStatus(.failed)

        if #available(iOS 14.0, *) {
            DictusLogger.app.warning("Dictation cancelled by audio session interruption")
        }
    }

    // MARK: - Private Helpers

    /// Register Darwin notification observers for keyboard stop/cancel signals.
    private func observeKeyboardSignals() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.stopRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let requested = self.defaults.bool(forKey: SharedKeys.stopRequested)
                if requested {
                    self.defaults.set(false, forKey: SharedKeys.stopRequested)
                    self.defaults.synchronize()
                    self.stopDictation()
                }
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.cancelRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let requested = self.defaults.bool(forKey: SharedKeys.cancelRequested)
                if requested {
                    self.defaults.set(false, forKey: SharedKeys.cancelRequested)
                    self.defaults.synchronize()
                    self.cancelDictation()
                }
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let appState = UIApplication.shared.applicationState
                PersistentLog.log(.engineDarwinStartReceived(
                    appState: "\(appState.rawValue)",
                    engineRunning: self.audioEngine.isEngineRunning
                ))
                self.startDictation()
            }
        }
    }

    /// Forward waveform energy data to App Group for the keyboard extension to display.
    /// Throttled to ~5Hz (every 200ms) to avoid overwhelming UserDefaults.
    private func forwardWaveformToAppGroup(energy: [Float]) {
        guard status == .recording else { return }

        let now = Date()
        guard now.timeIntervalSince(lastWaveformWriteDate) >= 0.2 else { return }
        lastWaveformWriteDate = now

        let cappedEnergy = Array(energy.suffix(30))
        if let data = try? JSONEncoder().encode(cappedEnergy) {
            defaults.set(data, forKey: SharedKeys.waveformEnergy)
        }
        defaults.set(bufferSeconds, forKey: SharedKeys.recordingElapsedSeconds)
        defaults.synchronize()

        DarwinNotificationCenter.post(DarwinNotificationName.waveformUpdate)
    }

    /// Clear a dictation the previous process never finished (issue #261).
    ///
    /// The invariant this restores: `dictationStatus` describes an active dictation,
    /// but no live coordinator owns a session for it. That is trivially decidable
    /// here — this method runs from `init`, so the process has just started and owns
    /// no session by construction. Nothing else audited the key, which is why an app
    /// terminated mid-recording left `recording` behind for the keyboard to restore
    /// an overlay from.
    ///
    /// WHY `.requested` is excluded: the keyboard writes it moments before opening
    /// `dictus://dictate`, i.e. moments before launching this very process. Clearing
    /// it here would break every cold-start dictation — including the retry in
    /// `didBecomeActive`, which proceeds only while the stored status is still
    /// `requested`.
    ///
    /// WHY it writes `.idle` and no `lastError`: this audit is hygiene, not speech.
    /// The first version wrote `.failed` plus a localised error so the keyboard's
    /// failure path would show it, which had two problems. By the time the app
    /// relaunches the moment has passed — the keyboard reconciles in-process, within
    /// seconds, and that is the surface that tells the user. And `failed` has no
    /// expiry in the App Group: `KeyboardState.refreshFromDefaults` adopts a stored
    /// `failed` and shows the stored reason whenever the extension is next loaded,
    /// however old it is, until a new dictation clears it (#320). That is pre-existing
    /// behaviour, but writing `failed` here on every reconciliation would have made a
    /// stale error message a routine sight.
    ///
    /// WHY it does NOT go through `updateStatus`: this process is not failing
    /// anything. It is auditing state a dead one left behind, and `status` is
    /// correctly `.idle` here.
    private func reconcileOrphanedDictationState() {
        // WHY the cases are spelled out here and not asked of `isActive` (#267):
        // this list is deliberately narrower. `.requested` is active but is written
        // by the keyboard moments before it launches this app, so reconciling it at
        // launch would kill every cold-start dictation. `.processing` belongs with
        // `.recording` and `.transcribing`: the app that wrote it is the app that
        // just died, so a launch finding it is finding a corpse.
        guard let raw = defaults.string(forKey: SharedKeys.dictationStatus),
              let stored = DictationStatus(rawValue: raw),
              stored == .recording || stored == .transcribing || stored == .processing else { return }

        PersistentLog.log(.dictationStateReconciled(
            source: "app-launch",
            staleStatus: raw,
            heartbeatAgeMs: -1
        ))
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
        // Clears the heartbeat, the waveform keys and the pending stop/cancel flags
        // the dead process never got to clean up, and synchronizes. Dropping the
        // heartbeat matters most: one that outlives its session is what the keyboard
        // would otherwise judge the *next* session by (#261).
        cleanupRecordingKeys()
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Clean up recording-related App Group keys after recording completes or is cancelled.
    private func cleanupRecordingKeys() {
        // NOTE: Do NOT clear lastTranscription here — the keyboard extension reads it
        // asynchronously via Darwin notification. Clearing it here would race with the
        // keyboard and delete the transcription before it can be inserted.
        // Stale transcriptions are cleaned up on app launch (5-min threshold in init).
        defaults.removeObject(forKey: SharedKeys.waveformEnergy)
        defaults.removeObject(forKey: SharedKeys.recordingElapsedSeconds)
        defaults.removeObject(forKey: SharedKeys.recordingHeartbeat)
        defaults.set(false, forKey: SharedKeys.stopRequested)
        defaults.set(false, forKey: SharedKeys.cancelRequested)
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        defaults.synchronize()
    }

    /// Reads the list of downloaded model identifiers from App Group UserDefaults.
    private func readDownloadedModels() -> [String] {
        guard let data = defaults.data(forKey: SharedKeys.downloadedModels),
              let models = try? JSONDecoder().decode([String].self, from: data) else {
            if let active = defaults.string(forKey: SharedKeys.activeModel) {
                return [active]
            }
            return []
        }
        return models
    }

    /// Whether the transcription task started under `session` may still report.
    ///
    /// A dictation that was abandoned -- cancelled, watchdog-reset, interrupted --
    /// moves the generation, so work started before it silently stops here instead
    /// of writing status, inserting text or driving the Live Activity into a session
    /// that no longer exists (#267).
    ///
    /// WHY it logs rather than returning quietly: a dropped outcome is invisible
    /// otherwise, and the device log is how this class of bug gets diagnosed here.
    /// The signature to look for afterwards is the absence of rejected Live Activity
    /// transitions following a clean abandon.
    ///
    /// ### What is deliberately NOT gated, and why
    ///
    /// Every `await` in a session-owned task is a place a cancel can land, but not
    /// every continuation past one publishes session state. These were each checked
    /// rather than gated by reflex:
    ///
    /// - `verifyAudioFlow()` already opens with `guard status == .recording`, and an
    ///   abandoned session is `.idle` by then. Its engine restart is unreachable
    ///   after a cancel.
    /// - `setModelLoadState(...)` describes the *model*, which outlives any one
    ///   dictation. Suppressing it would leave the next session reading a load state
    ///   that never happened.
    /// - `schedulePolishPrewarm()` warms a model and publishes nothing.
    /// - The stage watchdog re-checks `self.status` against the status it was armed
    ///   for before it fires.
    /// - `pendingColdStartDictation` is retried from `didBecomeActive` only when the
    ///   App Group still reads `.requested`; a cancel writes `.idle` first, so the
    ///   deferred start does not resurrect.
    private func mayReport(_ session: Int, _ what: String) -> Bool {
        guard sessionGeneration.mayReport(from: session) else {
            PersistentLog.log(.dictationDeferred(
                reason: "abandoned session dropped \(what) (gen \(session) != \(sessionGeneration.current))"
            ))
            return false
        }
        return true
    }

    // MARK: - Stage Watchdog

    /// How long a post-recording stage may run before it is declared stuck.
    /// Nil for statuses no stage watchdog covers.
    ///
    /// WHY 30s for transcription: WhisperKit transcription of a typical dictation
    /// (<60s audio) should complete in under 10s even on older devices. 30s provides
    /// generous margin while still catching genuinely stuck transcriptions.
    ///
    /// WHY 60s for the LLM stage (#267) and not the same 30s: generation time scales
    /// with the output, which is exactly why this stage was split out, and the cost
    /// of firing early is higher here than during transcription -- the transcript
    /// already exists and the recovery below throws it away with the rest of the
    /// session. The number is a last-resort unfreeze, not a latency budget.
    private func stageWatchdogTimeout(for status: DictationStatus) -> TimeInterval? {
        switch status {
        case .transcribing:
            return 30
        case .processing:
            return 60
        case .idle, .requested, .recording, .ready, .failed:
            return nil
        }
    }

    /// Log source for a fired stage watchdog. `appTranscription` is unchanged from
    /// before #267 so log lines written by older builds keep meaning what they meant.
    private func stageWatchdogSource(for status: DictationStatus) -> String {
        status == .processing ? "appProcessing" : "appTranscription"
    }

    private func startStageWatchdog(for status: DictationStatus) {
        stopStageWatchdog()
        guard let timeout = stageWatchdogTimeout(for: status) else { return }
        stageWatchdog = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.status == status else { return }
                PersistentLog.log(.watchdogReset(
                    source: self.stageWatchdogSource(for: status),
                    staleState: status.rawValue
                ))
                self.cancelDictation()
            }
        }
    }

    private func stopStageWatchdog() {
        stageWatchdog?.invalidate()
        stageWatchdog = nil
    }

    /// Write dictation status to App Group so the keyboard can observe it.
    private func updateStatus(_ newStatus: DictationStatus) {
        // Invariant (issue #60): entering .idle while the engine is still capturing
        // means some path skipped the teardown. Stop capture (engine stays warm per
        // #106), force the Live Activity out of .recording, and log the violation so
        // any future recurrence of this class is one log line, not a silent
        // background recording.
        if newStatus == .idle && audioEngine.isRecording {
            PersistentLog.log(.idleInvariantViolation(
                from: status.rawValue,
                engineRunning: audioEngine.isEngineRunning
            ))
            if #available(iOS 14.0, *) {
                DictusLogger.app.fault("Invariant violation: entering .idle while engine is recording — forcing teardown")
            }
            _ = audioEngine.collectSamples()
            Task { await LiveActivityManager.shared.returnToStandby() }
            LiveActivityManager.shared.startRecordingWatchdog()
        }

        let oldStatus = status
        PersistentLog.log(.statusChanged(from: oldStatus.rawValue, to: newStatus.rawValue, source: "coordinator"))
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()

        // Re-arm on every stage the watchdog covers, disarm on everything else.
        // The `.transcribing -> .processing` hand-over is the case that makes the
        // second branch matter: leaving the transcription timer armed would let it
        // fire 30s into a stage it knows nothing about (#267).
        if stageWatchdogTimeout(for: newStatus) != nil {
            startStageWatchdog(for: newStatus)
        } else if stageWatchdogTimeout(for: oldStatus) != nil {
            stopStageWatchdog()
        }

        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Verify audio samples are actually being captured after startRecording.
    /// Detects "zombie engine" state where engine.isRunning but tap receives no buffers.
    /// If 0 samples after 2s, force-restarts the engine and retries once.
    private func verifyAudioFlow() async {
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch { return } // Task cancelled (user stopped recording)

        guard status == .recording else { return }

        let sampleCount = audioEngine.currentSampleCount
        if sampleCount > 0 { return } // Healthy — samples flowing

        PersistentLog.log(.dictationFailed(error: "Zombie engine: 0 samples after 2s, force-restarting"))

        // Force restart: stop engine, reconfigure, restart
        audioEngine.forceRestart()
        do {
            try audioEngine.startRecording()
        } catch {
            handleError("Micro indisponible. Relancez l'application.")
            return
        }

        // Check again after restart
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch { return }

        guard status == .recording else { return }

        if audioEngine.currentSampleCount == 0 {
            handleError("Micro indisponible. Relancez l'application.")
        } else {
            PersistentLog.log(.engineWarmUpSuccess(context: "zombie-recovery"))
        }
    }

    /// Handle errors by updating status and writing error to App Group.
    ///
    /// The message goes to `DictationErrorChannel`, which both the keyboard's toolbar
    /// and the app's own failure screen read (#320). Neither consumes it: it stays put
    /// until the next dictation starts, so a user who reads it on one surface and then
    /// opens the other is told the same thing twice rather than something else.
    private func handleError(_ message: String) {
        DictationErrorChannel.record(message)
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        defaults.synchronize()
        updateStatus(.failed)
        LiveActivityManager.shared.endWithFailure()
        // Arm watchdog: safety net if endWithFailure's transition guard rejects.
        LiveActivityManager.shared.startRecordingWatchdog()
    }

    // MARK: - Model load orchestration (issue #144)

    /// Read the current persisted model load state from the App Group.
    /// SwiftUI views read this through NotificationCenter posts emitted by
    /// `setModelLoadState` (see `Notification.Name.dictusModelLoadStateChanged`).
    var modelLoadState: ModelLoadState {
        let raw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        return ModelLoadState(rawValue: raw) ?? .idle
    }

    /// Update the tri-state load flag, persist it to the App Group so the keyboard
    /// can gate mic taps, and broadcast a notification so any in-app overlay can react.
    /// Must be called on the main actor (the class is @MainActor).
    func setModelLoadState(_ newState: ModelLoadState, reason: String) {
        let oldRaw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        guard oldRaw != newState.rawValue else { return }
        defaults.set(newState.rawValue, forKey: SharedKeys.modelLoadState)
        defaults.synchronize()
        PersistentLog.log(.modelLoadStateChanged(from: oldRaw, to: newState.rawValue, reason: reason))
        NotificationCenter.default.post(
            name: .dictusModelLoadStateChanged,
            object: nil,
            userInfo: ["state": newState.rawValue, "reason": reason]
        )
    }

    /// Eagerly load the active model into RAM. Called from `ModelManager.selectModel`
    /// after a model swap so the user does not have to wait for the first mic tap to
    /// trigger the lazy load (issue #144 — turbo swap took 1-3 minutes which collapsed
    /// into a cancellation storm without this proactive path).
    ///
    /// Safe to call repeatedly: the underlying `initTask` lock dedupes concurrent loads.
    func preloadActiveModel() {
        Task {
            self.setModelLoadState(.loading, reason: "selectModel-proactive")
            do {
                try await ensureEngineReady()
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                self.setModelLoadState(.ready, reason: "selectModel-proactive-success")
            } catch {
                PersistentLog.log(.engineWarmUpFailed(
                    context: "selectModel-proactive",
                    error: error.localizedDescription
                ))
                self.setModelLoadState(.idle, reason: "selectModel-proactive-failed")
            }
        }
    }
}

// MARK: - Speech engine initialization

/// Engine initialization lives in its own extension so the coordinator class body
/// stays within the SwiftLint `type_body_length` budget. These methods are still
/// file-private members of the coordinator and touch the same stored properties.
@MainActor
private extension DictationCoordinator {
    /// Initialize the appropriate STT engine based on the active model.
    ///
    /// WHY engine-aware:
    /// The user can select either a WhisperKit or Parakeet model. This method
    /// checks the active model's engine type and initializes the correct engine.
    ///
    /// Falls back to the active model from App Group, then to "openai_whisper-small".
    func ensureEngineReady(preferredModel: String? = nil) async throws {
        let modelName = preferredModel
            ?? defaults.string(forKey: SharedKeys.activeModel)
            ?? "openai_whisper-small"

        let modelInfo = ModelInfo.forIdentifier(modelName)
        let engine = modelInfo?.engine ?? .whisperKit

        switch engine {
        case .parakeet:
            try await ensureParakeetReady(modelName: modelName)
        case .whisperKit:
            try await ensureWhisperKitEngineReady(modelName: modelName)
        }
    }

    /// Initialize WhisperKit with the preferred model if not already loaded.
    ///
    /// Loads strictly from the local model repository (issue #249). This path used to
    /// build its config from the model name with `download: true` and no
    /// `modelFolder`, so WhisperKit resolved the identifier against the Hugging Face
    /// hub — every Whisper model was unusable without connectivity, and a hub outage
    /// or airplane mode failed dictation with WhisperKit's untranslated
    /// "Model not found…" message. Downloading stays the model manager's job.
    func ensureWhisperKitEngineReady(modelName: String) async throws {
        if whisperKit != nil, currentModelName == modelName {
            return
        }

        if let existingTask = initTask {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Engine init already in progress — awaiting existing task")
            }
            // The in-flight task rethrows its raw error to every awaiting caller, so
            // localise here too (issue #249) — a cold start that piggybacks on the
            // launch preload takes this branch.
            do {
                try await existingTask.value
            } catch {
                throw SpeechModelError.engineLoadFailed(identifier: modelName, underlying: error)
            }
            return
        }

        // Fail fast, before any task is created, when the model is not on disk.
        // `SharedKeys.modelReady` only reflects App Group bookkeeping; this checks
        // the files WhisperKit will actually read.
        guard let modelFolder = WhisperModelRepository.installedModelFolderURL(for: modelName) else {
            let error = SpeechModelError.modelNotInstalled(identifier: modelName)
            PersistentLog.log(.diagnosticProbe(
                component: "WhisperKitLoad",
                instanceID: modelName,
                action: "localModelMissing",
                details: error.diagnosticDescription
            ))
            throw error
        }

        PersistentLog.log(.diagnosticProbe(
            component: "WhisperKitLoad",
            instanceID: modelName,
            action: "localModelResolved",
            details: "folder=\(modelFolder.lastPathComponent) download=false tokenizerCache=\(WhisperModelRepository.cachedTokenizerRepositoryNames().joined(separator: "|"))"
        ))

        let task = Task<Void, Error> {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Initializing WhisperKit with model: \(modelName, privacy: .public)")
            }

            let config = WhisperKitConfig(
                model: modelName,
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )

            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.currentModelName = modelName

            // Share with TranscriptionService only — UnifiedAudioEngine doesn't need WhisperKit
            transcriptionService.prepare(whisperKit: kit)

            let whisperKitEngine = WhisperKitEngine()
            whisperKitEngine.setWhisperKit(kit)
            transcriptionService.prepare(engine: whisperKitEngine)

            if #available(iOS 14.0, *) {
                DictusLogger.app.info("WhisperKit ready with model: \(modelName, privacy: .public)")
            }
        }
        initTask = task

        do {
            try await task.value
            initTask = nil
        } catch {
            initTask = nil
            // Wrap anything WhisperKit or Core ML raises (issue #249). Their messages
            // are English and developer-facing; `handleError` writes whatever reaches
            // it straight into the keyboard's error banner. The raw text stays in the
            // log, the user gets a localised one.
            let wrapped = SpeechModelError.engineLoadFailed(identifier: modelName, underlying: error)
            PersistentLog.log(.diagnosticProbe(
                component: "WhisperKitLoad",
                instanceID: modelName,
                action: "loadFailed",
                details: wrapped.diagnosticDescription
            ))
            throw wrapped
        }
    }

    /// Initialize Parakeet engine (iOS 17+ only).
    ///
    /// Loads strictly from the local FluidAudio cache (issue #252). This path used to call
    /// `AsrModels.downloadAndLoad`, which starts a HuggingFace download when the cache is
    /// absent — during dictation, with no progress and no way to cancel. That is the
    /// asymmetry issue #249 removed for Whisper; downloading stays the model manager's job.
    func ensureParakeetReady(modelName: String) async throws {
        if currentModelName == modelName, whisperKit == nil {
            return
        }

        if #available(iOS 17.0, *) {
            if let existingTask = initTask {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Parakeet init already in progress — awaiting existing task")
                }
                // Same reason as the WhisperKit path (issue #249): the in-flight task
                // rethrows its raw FluidAudio/Core ML error to every awaiting caller.
                do {
                    try await existingTask.value
                } catch {
                    throw SpeechModelError.engineLoadFailed(identifier: modelName, underlying: error)
                }
                return
            }

            // Fail fast, before any task is created, when the cache is absent or partial —
            // mirrors the WhisperKit guard above. `SharedKeys.modelReady` only reflects App
            // Group bookkeeping; this checks the bundles FluidAudio will actually read.
            guard let cacheDirectory = ParakeetEngine.installedModelCacheDirectory() else {
                let error = SpeechModelError.modelNotInstalled(identifier: modelName)
                PersistentLog.log(.diagnosticProbe(
                    component: "ParakeetLoad",
                    instanceID: modelName,
                    action: "localModelMissing",
                    details: error.diagnosticDescription
                ))
                throw error
            }

            PersistentLog.log(.diagnosticProbe(
                component: "ParakeetLoad",
                instanceID: modelName,
                action: "localModelResolved",
                details: "folder=\(cacheDirectory.lastPathComponent) download=false"
            ))

            let task = Task<Void, Error> {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Initializing ParakeetEngine for model: \(modelName, privacy: .public)")
                }

                let parakeetEngine = ParakeetEngine()
                try await parakeetEngine.prepare(modelIdentifier: modelName)

                self.whisperKit = nil
                self.currentModelName = modelName

                transcriptionService.prepare(engine: parakeetEngine)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("ParakeetEngine ready for model: \(modelName, privacy: .public)")
                }
            }
            initTask = task

            do {
                try await task.value
                initTask = nil
            } catch {
                initTask = nil
                // Wrap anything FluidAudio or Core ML raises (issue #249) — those
                // messages are English and developer-facing, and `handleError` writes
                // whatever reaches it into the keyboard's error banner.
                let wrapped = SpeechModelError.engineLoadFailed(identifier: modelName, underlying: error)
                PersistentLog.log(.diagnosticProbe(
                    component: "ParakeetLoad",
                    instanceID: modelName,
                    action: "loadFailed",
                    details: wrapped.diagnosticDescription
                ))
                throw wrapped
            }
        } else {
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("Parakeet not available on iOS 16 — falling back to WhisperKit small")
            }
            try await ensureWhisperKitEngineReady(modelName: "openai_whisper-small")
        }
    }
}
