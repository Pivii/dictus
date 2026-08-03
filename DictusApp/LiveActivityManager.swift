// DictusApp/LiveActivityManager.swift
// Manages the Dictus Live Activity lifecycle (Dynamic Island + Lock Screen).
import ActivityKit
import Foundation
import UIKit
import DictusCore

/// Manages Live Activity lifecycle for Dynamic Island and Lock Screen display.
///
/// WHY singleton (@MainActor + static let shared):
/// Only one Live Activity should exist at a time. DictationCoordinator and DictusApp
/// both need to call methods on the same instance. @MainActor ensures thread safety
/// for ActivityKit calls which must happen on the main thread.
///
/// WHY the standby pattern:
/// Unlike typical Live Activities that start/end with a task, Dictus keeps a persistent
/// "standby" Live Activity while the app runs in background. This gives the user
/// permanent access to the Dynamic Island for quick recording. The activity transitions
/// between phases (.standby -> .recording -> .transcribing -> .ready -> .standby)
/// without being destroyed. Only the Power button or app termination ends it.
@MainActor
class LiveActivityManager {
    static let shared = LiveActivityManager()

    // MARK: - State Machine

    /// Internal state machine for Live Activity lifecycle.
    /// WHY separate from DictusLiveActivityAttributes.Phase: This tracks the manager's own state,
    /// including .idle (no activity exists). DictusLiveActivityAttributes.Phase is the ActivityKit
    /// display state sent to the widget. The state machine prevents Dynamic Island
    /// desync after chaining multiple recordings (#42).
    private enum LiveActivityPhase: String {
        case idle       // No activity exists
        case standby    // Activity exists, waiting for user
        case recording  // Active recording
        case transcribing // Processing audio
        case processing // Running the LLM stage on the transcript (#267)
        case ready      // Showing result (auto-dismiss pending)
        case failed     // Showing error (auto-dismiss pending)
    }

    /// Returns true if transitioning from the current phase to `target` is valid.
    /// Invalid transitions are logged and rejected -- callers check the return value.
    /// WHY: Without validation, concurrent Activity.update() calls arrive out of order
    /// and autoDismissTask from previous recordings can fire mid-recording (#42).
    private func validateTransition(to target: LiveActivityPhase) -> Bool {
        // Delegate validation to the extracted state machine in DictusCore.
        // WHY keep both: The state machine provides unit-testable validation logic.
        // The private enum stays as the canonical internal state. We map to the
        // shared Phase type for validation, then sync if accepted.
        let smTarget = mapToStateMachinePhase(target)
        var copy = stateMachine
        if copy.transition(to: smTarget) {
            stateMachine = copy
            return true
        } else {
            // During a no-activity dictation cycle (standby bootstrap failed from
            // .idle), every downstream sink is rejected from .idle by design.
            // One bootstrapUnavailable entry already names the cause -- persisting
            // each rejection would only flood exports (#233). Rejections while an
            // activity exists keep logging: those are the #42 desync diagnostics.
            guard stateMachine.shouldLogRejection else {
                DictusLogger.app.debug("LiveActivity: suppressed rejection \(self.currentPhase.rawValue, privacy: .public) -> \(target.rawValue, privacy: .public) (no-activity cycle)")
                return false
            }
            DictusLogger.app.warning("LiveActivity: rejected transition \(self.currentPhase.rawValue, privacy: .public) -> \(target.rawValue, privacy: .public)")
            PersistentLog.log(.liveActivityFailed(context: "rejectedTransition", error: "\(currentPhase.rawValue)->\(target.rawValue)"))
            return false
        }
    }

    /// Map internal LiveActivityPhase to the shared state machine Phase.
    private func mapToStateMachinePhase(_ phase: LiveActivityPhase) -> LiveActivityStateMachine.Phase {
        switch phase {
        case .idle: return .idle
        case .standby: return .standby
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .processing: return .processing
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    /// Force-sync the state machine to match a direct currentPhase assignment.
    /// WHY force (not transition): Direct assignments happen in recovery/bootstrap paths
    /// where the state machine's transition rules may reject the change.
    private func syncStateMachine(to phase: LiveActivityPhase) {
        stateMachine.forcePhase(mapToStateMachinePhase(phase))
    }

    /// Maps DictusLiveActivityAttributes.Phase (ActivityKit display) to LiveActivityPhase (internal state machine).
    private func mapContentPhase(_ phase: DictusLiveActivityAttributes.Phase) -> LiveActivityPhase {
        switch phase {
        case .standby: return .standby
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .processing: return .processing
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    /// Current Live Activity instance. nil if no activity is running.
    private var currentActivity: Activity<DictusLiveActivityAttributes>?

    /// Tracks the current phase via a formal state machine with validated transitions.
    /// WHY: Even if DictationCoordinator guards its sinks, this provides a second
    /// barrier -- updateWaveform() is a no-op unless we're actually recording.
    /// WHY LiveActivityPhase (not DictusLiveActivityAttributes.Phase): Adds .idle state and transition
    /// validation to prevent DI desync after chaining recordings (#42).
    private var currentPhase: LiveActivityPhase = .idle

    /// Extracted state machine for transition validation (lives in DictusCore for unit testing).
    /// WHY a separate struct: The transition rules are pure logic with no ActivityKit dependency.
    /// Keeping them in DictusCore enables unit testing all valid/invalid paths.
    private var stateMachine = LiveActivityStateMachine()

    /// Post-recording watchdog: forces DI back to standby if stuck on .recording.
    /// WHY "post-recording": This does NOT run during recording. It starts only AFTER
    /// DictationCoordinator signals recording has ended (stop or cancel). If the DI
    /// successfully transitions away from .recording, the guard exits harmlessly.
    private var recordingWatchdog: Task<Void, Never>?

    /// Timestamp of last waveform update. Used to throttle to 1Hz.
    private var lastWaveformUpdate = Date.distantPast

    /// iOS auto-removes the activity if no update arrives within this interval.
    /// 30s clears ghosts after force-quit. Waveform updates (1Hz) and phase
    /// transitions keep refreshing it during normal use.
    private let staleInterval: TimeInterval = 30

    /// Whether the user has enabled Live Activity in Settings.
    /// WHY UserDefaults read (not @AppStorage): LiveActivityManager is not a SwiftUI view.
    private var isEnabled: Bool {
        UserDefaults(suiteName: AppGroup.identifier)?.bool(forKey: SharedKeys.liveActivityEnabled) ?? true
    }

    /// Task for auto-dismiss after result/failure display.
    private var autoDismissTask: Task<Void, Never>?

    private init() {
        // End all Live Activities when the app is terminated (force-quit from app switcher).
        // WHY: Without this, the DI stays visible for up to 8 hours after a force-quit.
        // willTerminate fires reliably when the user swipes up in the app switcher.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.endAllActivitiesSync()
        }

        // End the Live Activity when the audio session is interrupted (phone call,
        // Siri, etc.) or media services were reset. The DI must NOT keep showing
        // a "ready to dictate" indicator while the underlying audio engine is dead;
        // the user perceives this as broken — they tap and get a cold start instead
        // of the warm dictation the DI implied (issue #106).
        NotificationCenter.default.addObserver(
            forName: .dictusAudioSessionInterrupted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endActivityForAudioInterruption()
            }
        }

        // Dismiss the standby DI when the warm-state engine is released after the
        // idle timeout (issue #106 Phase B). A standby pill suggests the next
        // dictation is instant — but the engine is asleep, so it would be a cold
        // start. End the activity so the UI matches reality.
        NotificationCenter.default.addObserver(
            forName: .dictusWarmStateReleased,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endActivityForWarmStateRelease()
            }
        }
    }

    /// Tear down the Live Activity because the audio session was interrupted.
    /// Force-syncs internal state before issuing the async `activity.end` so a
    /// concurrent `transitionToRecording` can't resurrect the dead activity.
    func endActivityForAudioInterruption() {
        guard let activity = currentActivity else {
            // No activity to end, but reset state in case it was leaked.
            currentPhase = .idle
            syncStateMachine(to: .idle)
            return
        }

        autoDismissTask?.cancel()
        autoDismissTask = nil
        cancelRecordingWatchdog()

        currentActivity = nil
        currentPhase = .idle
        syncStateMachine(to: .idle)
        PersistentLog.log(.liveActivityEnded(reason: "audioInterrupted"))

        Task {
            let finalState = DictusLiveActivityAttributes.ContentState(phase: .failed)
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            DictusLogger.app.info("Live Activity ended -- audio session interrupted")
        }
    }

    /// Tear down the Live Activity because the warm-state engine was released.
    /// The DI is dismissed gracefully (.standby final state, not .failed) since
    /// nothing actually went wrong — the app simply went idle (issue #106).
    func endActivityForWarmStateRelease() {
        guard let activity = currentActivity else {
            currentPhase = .idle
            syncStateMachine(to: .idle)
            return
        }

        autoDismissTask?.cancel()
        autoDismissTask = nil
        cancelRecordingWatchdog()

        currentActivity = nil
        currentPhase = .idle
        syncStateMachine(to: .idle)
        PersistentLog.log(.liveActivityEnded(reason: "warmStateReleased"))

        Task {
            let finalState = DictusLiveActivityAttributes.ContentState(phase: .standby)
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            DictusLogger.app.info("Live Activity ended -- warm state released after idle timeout")
        }
    }

    // MARK: - Standby Mode

    /// Outcome of a standby start attempt.
    /// WHY a return value: `transitionToRecording()` needs the concrete reason a
    /// bootstrap could not produce an activity so it can persist a single
    /// `bootstrapUnavailable` entry with that reason (issue #233). Every case maps
    /// to exactly one return path of `startStandbyActivity()`.
    enum StandbyStartOutcome {
        case created                    // New activity requested successfully
        case alreadyStandby             // Activity exists and is already in standby
        case alreadyRunning             // Activity exists in a non-standby phase
        case orphanRecovered            // Adopted an existing system activity
        case disabledInApp              // In-app Live Activity toggle is off
        case systemActivitiesDisabled   // iOS Settings per-app toggle is off
        case requestFailed(String)      // Activity.request threw

        /// True when an activity exists after the call (bootstrap can proceed).
        var activityAvailable: Bool {
            switch self {
            case .created, .alreadyStandby, .alreadyRunning, .orphanRecovered:
                return true
            case .disabledInApp, .systemActivitiesDisabled, .requestFailed:
                return false
            }
        }

        /// Greppable reason token for PersistentLog entries.
        var reason: String {
            switch self {
            case .created: return "created"
            case .alreadyStandby: return "alreadyStandby"
            case .alreadyRunning: return "alreadyRunning"
            case .orphanRecovered: return "orphanRecovered"
            case .disabledInApp: return "disabledInApp"
            case .systemActivitiesDisabled: return "systemActivitiesDisabled"
            case .requestFailed(let error): return "requestFailed: \(error)"
            }
        }
    }

    /// Persist a standby-skip outcome to the exportable log.
    /// WHY a helper: every silent return path must produce a greppable entry with
    /// both enablement booleans (#233); centralizing keeps the call sites compact.
    /// WHY it reads `currentLiveness` by default: every existing call site skips
    /// *because of* the activity the manager already holds, so the state that
    /// explains the skip is that activity's own. Only the dead-activity path
    /// passes a state explicitly, because it has just cleared the reference (#257).
    private func logStandbySkipped(reason: String, isEnabled: Bool, activitiesEnabled: Bool,
                                   activityState: LiveActivityLiveness? = nil) {
        PersistentLog.log(.liveActivityStandbySkipped(
            reason: reason,
            isEnabled: isEnabled,
            activitiesEnabled: activitiesEnabled,
            activityState: activityState ?? currentLiveness
        ))
    }

    /// Start a Live Activity in standby mode.
    /// Called when the app enters background -- gives the user a persistent
    /// Dynamic Island indicator that Dictus is ready to record.
    ///
    /// WHY check areActivitiesEnabled:
    /// The user can disable Live Activities in Settings. Attempting to create
    /// one when disabled throws an error. Checking first avoids log noise.
    /// WHY synchronous (not async):
    /// Called from onChange(scenePhase: .background). If wrapped in Task { await },
    /// the Task is deferred -- by the time it runs, iOS considers the app fully
    /// backgrounded and Activity.request() fails with "Target is not foreground".
    /// Synchronous execution ensures the activity is created during the transition.
    /// Zombie cleanup is handled separately by cleanupStaleActivities() at app init.
    ///
    /// WHY every return path persists a PersistentLog entry:
    /// The #233 failure signature was a recovery attempt followed by silence --
    /// an early return that only hit the OS logger, which is not part of the
    /// user-exportable log. Exported logs must always show which path returned.
    @discardableResult
    func startStandbyActivity() -> StandbyStartOutcome {
        guard isEnabled else {
            DictusLogger.app.info("Live Activity disabled by user preference -- skipping")
            logStandbySkipped(reason: "disabledInApp", isEnabled: false,
                              activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled)
            return .disabledInApp
        }

        // Drop a dead reference BEFORE the fast paths below. WHY first: an activity
        // the system ended still satisfies `currentActivity != nil`, so the
        // alreadyStandby short-circuit would report a corpse as healthy standby on
        // every background transition and the pill would never be recreated (#257).
        discardActivityIfNotLive(context: "startStandby")

        // Allow transition from idle->standby or if already standby (no-op)
        // WHY: Prevents creating duplicate activities when app re-enters background
        if currentPhase == .standby && currentActivity != nil {
            DictusLogger.app.info("Live Activity already in standby -- skipping")
            logStandbySkipped(reason: "alreadyStandby", isEnabled: true,
                              activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled)
            return .alreadyStandby
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DictusLogger.app.info("Live Activities disabled by user -- skipping")
            // Prime suspect of #233: the iOS Settings per-app toggle. This was the
            // only fully silent path -- it MUST name areActivitiesEnabled=false.
            logStandbySkipped(reason: "systemActivitiesDisabled", isEnabled: true, activitiesEnabled: false)
            return .systemActivitiesDisabled
        }

        // Sync currentActivity reference (may be stale after intent or force-quit)
        if let current = currentActivity,
           !Activity<DictusLiveActivityAttributes>.activities.contains(where: { $0.id == current.id }) {
            DictusLogger.app.info("currentActivity stale (killed by intent or force-quit) -- clearing")
            PersistentLog.log(.liveActivityFailed(context: "startStandby-staleRef", error: "activity \(current.id) gone from system"))
            currentActivity = nil
            currentPhase = .idle
            syncStateMachine(to: .idle)
        }

        // Guard against duplicates at the system level, not just our in-memory reference.
        // WHY: After crash/force-quit, currentActivity is nil but old activities persist
        // in ActivityKit. cleanupStaleActivities() runs async in init() and may not have
        // finished yet. Checking the system list prevents creating a second activity.
        let systemActivities = adoptableSystemActivities()
        if currentActivity == nil, let existing = systemActivities.first {
            // Recover orphaned activity instead of creating a new one
            currentActivity = existing
            currentPhase = mapContentPhase(existing.content.state.phase)
            syncStateMachine(to: currentPhase)
            DictusLogger.app.info("Recovered orphaned Live Activity: \(existing.id, privacy: .public)")
            PersistentLog.log(.liveActivityStarted(id: "orphan-recovered:\(existing.id)"))
            // End any extras beyond the first (shouldn't happen, but defense in depth)
            for activity in systemActivities.dropFirst() {
                Task {
                    await activity.end(
                        .init(state: .init(phase: .standby), staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                    DictusLogger.app.info("Ended duplicate Live Activity: \(activity.id, privacy: .public)")
                }
            }
            return .orphanRecovered
        }

        // Don't create duplicate activities
        guard currentActivity == nil else {
            DictusLogger.app.info("Live Activity already running -- skipping startStandby")
            logStandbySkipped(reason: "alreadyRunning", isEnabled: true, activitiesEnabled: true)
            return .alreadyRunning
        }

        let attributes = DictusLiveActivityAttributes()
        let state = DictusLiveActivityAttributes.ContentState(phase: .standby)
        // staleDate: if app is killed without willTerminate firing, iOS auto-removes
        // the DI after this interval. 30s is short enough to clear ghosts quickly (#84).
        let staleDate = Date().addingTimeInterval(staleInterval)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: staleDate),
                pushType: nil
            )
            currentActivity = activity
            currentPhase = .standby
            syncStateMachine(to: .standby)
            DictusLogger.app.info("Live Activity started in standby (id: \(activity.id, privacy: .public))")
            PersistentLog.log(.liveActivityStarted(id: activity.id))
            return .created
        } catch {
            DictusLogger.app.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
            PersistentLog.log(.liveActivityFailed(context: "startStandby", error: error.localizedDescription))
            return .requestFailed(error.localizedDescription)
        }
    }

    /// Stop the standby Live Activity entirely.
    /// Called when user taps Power button in expanded Dynamic Island view.
    func stopStandbyActivity() {
        guard let activity = currentActivity else { return }

        autoDismissTask?.cancel()
        autoDismissTask = nil

        currentActivity = nil
        currentPhase = .idle  // Update BEFORE async work to prevent races (#49)
        syncStateMachine(to: .idle)
        PersistentLog.log(.liveActivityEnded(reason: "powerButton"))
        Task {
            let finalState = DictusLiveActivityAttributes.ContentState(phase: .standby)
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            DictusLogger.app.info("Live Activity stopped by user (Power button)")
        }
    }

    // MARK: - Recording Mode

    /// Transition from standby to recording.
    /// Called when DictationCoordinator starts recording.
    func transitionToRecording() {
        guard isEnabled else { return }

        // Cancel any stale watchdog from a previous recording cycle.
        // WHY at the very start: If the user starts a new recording while a watchdog
        // from the previous cycle is still ticking, the watchdog must NOT fire mid-recording.
        cancelRecordingWatchdog()

        // Drop a dead reference so the auto-bootstrap below can actually fire.
        // WHY here and not only in ensureActivityAlive(): a keyboard dictation never
        // foregrounds the app, and didBecomeActive is ensureActivityAlive()'s only
        // caller. Without this, a system-ended activity keeps currentPhase on
        // .standby, the bootstrap is skipped, and every update() below is dropped
        // silently -- the user dictates and no Dynamic Island ever appears (#257).
        discardActivityIfNotLive(context: "transitionToRecording")

        // Auto-bootstrap: if no activity exists, create standby first.
        // WHY BEFORE validateTransition: idle→recording is invalid, but idle→standby→recording
        // is the valid path. Without this, the guard rejects and the fallback at line 228
        // (which also calls startStandbyActivity) is UNREACHABLE after the guard returns.
        if currentPhase == .idle {
            PersistentLog.log(.liveActivityTransition(from: "idle", to: "recording-bootstrap"))
            let outcome = startStandbyActivity()
            // If bootstrap failed (e.g., app is background, or Live Activities are
            // disabled at the system level), dictation continues without a DI --
            // ensureActivityAlive() will retry on didBecomeActive.
            // ONE bootstrapUnavailable entry carries the concrete reason for this
            // cycle; the downstream sinks (transcribing, ready) would otherwise each
            // add a rejectedTransition entry from .idle with zero information (#233).
            if !outcome.activityAvailable {
                PersistentLog.log(.liveActivityFailed(context: "bootstrapUnavailable", error: outcome.reason))
                stateMachine.beginNoActivityCycle()
                return
            }
        }

        // WHY: State machine guard prevents DI desync from concurrent transitions (#42)
        guard validateTransition(to: .recording) else { return }

        // Cancel any pending auto-return from a previous dictation's ready/failed state.
        // WHY AFTER validation (not before): If state is .failed and validation rejects,
        // we must NOT cancel the autoDismissTask — it's the only path back to .standby.
        // Cancelling before validation destroyed the recovery path (#15.2).
        autoDismissTask?.cancel()
        autoDismissTask = nil

        guard let activity = currentActivity else {
            // If no activity exists (e.g., app was in foreground), create one then transition.
            // WHY only delayed path: startStandbyActivity() is synchronous but the activity
            // needs a moment before it can accept updates. The delayed updateToRecording()
            // is the ONLY update path — no duplicate immediate Task (#49).
            let outcome = startStandbyActivity()
            if !outcome.activityAvailable {
                PersistentLog.log(.liveActivityFailed(context: "bootstrap-fallback", error: outcome.reason))
            }
            currentPhase = .recording  // Lock state immediately to prevent races (#49)
            syncStateMachine(to: .recording)
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                await updateToRecording()
            }
            return
        }

        PersistentLog.log(.liveActivityTransition(from: "standby", to: "recording"))
        currentPhase = .recording  // Update BEFORE async work to prevent races (#49)
        Task {
            let state = DictusLiveActivityAttributes.ContentState(
                phase: .recording,
                recordingStartDate: Date(),
                waveformLevels: [0.3, 0.5, 0.7, 0.5, 0.3]
            )
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(self.staleInterval)))
            DictusLogger.app.info("Live Activity -> recording")
        }
    }

    /// Internal helper to update existing activity to recording after creation.
    private func updateToRecording() async {
        guard let activity = currentActivity else { return }
        let state = DictusLiveActivityAttributes.ContentState(
            phase: .recording,
            recordingStartDate: Date(),
            waveformLevels: [0.3, 0.5, 0.7, 0.5, 0.3]
        )
        await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(staleInterval)))
        // currentPhase already set to .recording by caller before Task (#49)
        DictusLogger.app.info("Live Activity -> recording (delayed)")
    }

    /// Update waveform levels during recording.
    /// Throttled to 1Hz to stay within ActivityKit update budget.
    ///
    /// WHY 1Hz (not 5Hz like App Group writes):
    /// ActivityKit has a stricter update budget than UserDefaults.
    /// Apple recommends no more than ~1 update/second for Live Activities.
    /// The timer auto-updates independently via Text(date, style: .timer).
    ///
    /// WHY downsample 30->5:
    /// DictationCoordinator's bufferEnergy has up to 30 values (one per waveform bar
    /// in the in-app RecordingView). Dynamic Island only shows 5 bars. Averaging
    /// groups of 6 produces smooth, representative levels.
    func updateWaveform(levels: [Float]) {
        guard currentActivity != nil else { return }
        // Defense in depth: only update waveform during active recording
        guard currentPhase == .recording else { return }

        // Throttle to 1Hz
        let now = Date()
        guard now.timeIntervalSince(lastWaveformUpdate) >= 1.0 else { return }
        lastWaveformUpdate = now

        // Downsample to 5 bars
        let downsampled = downsample(levels, to: 5)

        guard let activity = currentActivity else { return }
        Task {
            let state = DictusLiveActivityAttributes.ContentState(
                phase: .recording,
                recordingStartDate: activity.content.state.recordingStartDate,
                waveformLevels: downsampled
            )
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(self.staleInterval)))
        }
    }

    // MARK: - Transcription Mode

    /// Transition from recording to transcribing.
    func transitionToTranscribing() {
        guard isEnabled else { return }

        // WHY: State machine guard prevents DI desync from concurrent transitions (#42)
        guard validateTransition(to: .transcribing) else { return }

        guard let activity = currentActivity else { return }

        PersistentLog.log(.liveActivityTransition(from: "recording", to: "transcribing"))
        currentPhase = .transcribing  // Update BEFORE async work to prevent races (#49)
        Task {
            let state = DictusLiveActivityAttributes.ContentState(
                phase: .transcribing,
                waveformLevels: [0.3, 0.5, 0.4, 0.5, 0.3]
            )
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(self.staleInterval)))
            DictusLogger.app.info("Live Activity -> transcribing")
        }
    }

    /// Transition from transcribing to the LLM stage (#267).
    ///
    /// Called from inside `PolishCoordinator`'s engine callback, so it fires only
    /// when a model is really about to run -- most dictations never reach it and go
    /// straight from `.transcribing` to `.ready`, which the state machine allows.
    func transitionToProcessing() {
        guard isEnabled else { return }

        guard validateTransition(to: .processing) else { return }

        guard let activity = currentActivity else { return }

        PersistentLog.log(.liveActivityTransition(from: "transcribing", to: "processing"))
        currentPhase = .processing  // Update BEFORE async work to prevent races (#49)
        Task {
            let state = DictusLiveActivityAttributes.ContentState(
                phase: .processing,
                waveformLevels: [0.2, 0.5, 0.8, 0.5, 0.2]
            )
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(self.staleInterval)))
            DictusLogger.app.info("Live Activity -> processing")
        }
    }

    /// Show transcription result, then return to standby after 1 second.
    ///
    /// WHY return to standby instead of ending:
    /// The user expects the Dynamic Island to persist as long as the app is alive.
    /// After showing the result briefly, we go back to the "On" standby state
    /// so they can start another recording from the Dynamic Island.
    func endWithResult(preview: String?) {
        guard isEnabled else { return }

        // WHY: State machine guard prevents DI desync from concurrent transitions (#42)
        guard validateTransition(to: .ready) else { return }

        guard let activity = currentActivity else { return }

        autoDismissTask?.cancel()

        // `from` is read off the current phase rather than assumed to be
        // "transcribing": since #267 the result can arrive from either
        // post-recording stage, and a log line that says otherwise would misreport
        // which one the wait was spent in.
        PersistentLog.log(.liveActivityTransition(from: currentPhase.rawValue, to: "ready"))
        currentPhase = .ready  // Update BEFORE async work to prevent races (#49)
        Task {
            let truncatedPreview = preview.map { String($0.prefix(100)) }
            let state = DictusLiveActivityAttributes.ContentState(
                phase: .ready,
                transcriptionPreview: truncatedPreview
            )
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(self.staleInterval)))
            DictusLogger.app.info("Live Activity -> ready")
        }

        // Return to standby after 1 second (fast turnaround for chaining dictations)
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            guard !Task.isCancelled else { return }
            // WHY phase check after sleep: If user started a new recording during the 1s
            // delay, the auto-dismiss must NOT fire -- it would flash DI back to standby
            // mid-recording, causing desync (#42).
            guard currentPhase == .ready else {
                DictusLogger.app.info("Auto-dismiss skipped -- phase changed to \(self.currentPhase.rawValue, privacy: .public)")
                return
            }
            await returnToStandby()
        }
    }

    /// Show failure state, then return to standby after 3 seconds.
    func endWithFailure() {
        guard isEnabled else { return }

        // WHY: State machine guard prevents DI desync from concurrent transitions (#42)
        guard validateTransition(to: .failed) else { return }

        guard let activity = currentActivity else { return }

        autoDismissTask?.cancel()

        PersistentLog.log(.liveActivityTransition(from: "transcribing", to: "failed"))
        currentPhase = .failed  // Update BEFORE async work to prevent races (#49)
        Task {
            let state = DictusLiveActivityAttributes.ContentState(phase: .failed)
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(self.staleInterval)))
            DictusLogger.app.info("Live Activity -> failed")
        }

        // Return to standby after 3 seconds
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            guard !Task.isCancelled else { return }
            // WHY phase check after sleep: If the phase changed during the 3s delay
            // (e.g., user retried), the auto-dismiss must NOT fire (#42).
            guard currentPhase == .failed else {
                DictusLogger.app.info("Auto-dismiss skipped -- phase changed to \(self.currentPhase.rawValue, privacy: .public)")
                return
            }
            await returnToStandby()
        }
    }

    // MARK: - System State Reconciliation

    /// ActivityKit's own view of the activity the manager is holding.
    /// nil when the manager holds no activity.
    private var currentLiveness: LiveActivityLiveness? {
        currentActivity.map { Self.liveness(of: $0) }
    }

    /// Map ActivityKit's `ActivityState` onto the pure value the decision is made from.
    /// WHY `@unknown default`: `ActivityState` is not frozen -- iOS has added cases
    /// since 16.1 and this build must not crash or guess on a future one.
    private static func liveness(of activity: Activity<DictusLiveActivityAttributes>) -> LiveActivityLiveness {
        switch activity.activityState {
        case .active: return .active
        case .stale: return .stale
        case .ended: return .ended
        case .dismissed: return .dismissed
        @unknown default: return .unknown
        }
    }

    /// Drop the held activity when ActivityKit no longer considers it usable.
    /// Returns the state that was observed, or nil when the reference is fine.
    ///
    /// WHY this exists at all (#257): every previous liveness check asked whether the
    /// activity id still appears in `Activity.activities`. It always does -- ActivityKit
    /// ends a Live Activity after 8 hours, and an `.ended` activity stays in that list
    /// until its UI is removed. So the manager kept believing a dead pill was healthy,
    /// the Dynamic Island never came back, and only a reinstall cleared it.
    ///
    /// WHY it calls end() on something already ended: `.ended` still occupies
    /// `Activity.activities`. Ending it with `.immediate` evicts it, so the orphan
    /// adoption in startStandbyActivity() cannot hand the same corpse straight back.
    ///
    /// WHY it does NOT create a replacement: maintainer decision on #257. Recreating
    /// here would open a fresh 8-hour window every time and could loop forever on an
    /// app left open. The next dictation bootstraps a standby activity through
    /// transitionToRecording()'s existing auto-bootstrap path, which needs .idle --
    /// which is exactly the state this leaves behind.
    @discardableResult
    private func discardActivityIfNotLive(context: String) -> LiveActivityLiveness? {
        guard let activity = currentActivity else { return nil }
        let liveness = Self.liveness(of: activity)
        guard liveness.decision == .treatAsAbsent else { return nil }

        autoDismissTask?.cancel()
        autoDismissTask = nil
        cancelRecordingWatchdog()

        currentActivity = nil
        currentPhase = .idle
        syncStateMachine(to: .idle)
        PersistentLog.log(.liveActivityEnded(reason: "\(context)-notLive-\(liveness.rawValue)"))
        DictusLogger.app.info("Live Activity \(liveness.rawValue, privacy: .public) -- clearing dead reference (\(context, privacy: .public))")

        Task {
            await activity.end(
                .init(state: .init(phase: .standby), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        return liveness
    }

    /// Re-push the activity's current content with a fresh staleDate.
    /// WHY not a teardown: a `.stale` activity is still live and still updatable --
    /// only its content is past `staleDate`. Standby sits stale by design (nothing
    /// updates it and staleInterval is 30s), so tearing it down would kill every
    /// standby pill 30 seconds after it appeared. See LiveActivityLiveness.decision.
    private func refreshStaleActivity(_ activity: Activity<DictusLiveActivityAttributes>) {
        Task {
            await activity.update(
                .init(state: activity.content.state, staleDate: Date().addingTimeInterval(self.staleInterval))
            )
            DictusLogger.app.info("Live Activity content refreshed -- was stale")
        }
    }

    /// Live activities from the system list, with any non-live ones ended and excluded.
    /// WHY: `Activity.activities` lists `.ended` activities too. Adopting one as an
    /// "orphan" would hand the manager a dead reference and reproduce #257 through
    /// the bootstrap path instead of the recovery path.
    private func adoptableSystemActivities() -> [Activity<DictusLiveActivityAttributes>] {
        let all = Activity<DictusLiveActivityAttributes>.activities
        for corpse in all where Self.liveness(of: corpse).decision == .treatAsAbsent {
            DictusLogger.app.info("Ending non-live system Live Activity: \(corpse.id, privacy: .public)")
            Task {
                await corpse.end(.init(state: .init(phase: .standby), staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        return all.filter { Self.liveness(of: $0).decision != .treatAsAbsent }
    }

    // MARK: - Recovery

    /// Recreate the Live Activity if it was lost (e.g., Activity.request failed from background).
    /// Safe to call multiple times -- no-op if activity already exists.
    /// WHY: After cold start, Activity.request() silently fails from background.
    /// Calling this on didBecomeActive retries from the foreground where it succeeds.
    func ensureActivityAlive() {
        // WHY every outcome persists a PersistentLog entry: same rationale as
        // startStandbyActivity() -- the #233 signature was a retry attempt whose
        // result was invisible in exported logs. Each exit names what was found.
        guard isEnabled else {
            logStandbySkipped(reason: "ensureAlive-disabledInApp", isEnabled: false,
                              activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled)
            return
        }

        // Detect externally-ended activities (e.g., StopStandbyIntent bypasses manager).
        // WHY: The intent ends the activity via activity.end() but can't call stopStandbyActivity()
        // because LiveActivityManager is DictusApp-only. If DictationCoordinator's observer also
        // missed it, the manager still holds a dead reference. Check the system list as defense in depth.
        if let current = currentActivity,
           !Activity<DictusLiveActivityAttributes>.activities.contains(where: { $0.id == current.id }) {
            PersistentLog.log(.liveActivityFailed(context: "ensureAlive", error: "activity \(current.id) gone from system"))
            currentActivity = nil
            currentPhase = .idle
            syncStateMachine(to: .idle)
        }

        // The check above only catches an activity that LEFT the system list. An
        // activity the system ended is still in it, so ask ActivityKit for the
        // activity's own state before trusting currentPhase (#257).
        if let deadState = discardActivityIfNotLive(context: "ensureAlive") {
            // Deliberately no startStandbyActivity() here -- see discardActivityIfNotLive.
            logStandbySkipped(reason: "ensureAlive-clearedNotLive", isEnabled: true,
                              activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled,
                              activityState: deadState)
            return
        }

        // Still live but its content is out of date: refresh rather than tear down.
        if let activity = currentActivity, Self.liveness(of: activity).decision == .refresh {
            refreshStaleActivity(activity)
            logStandbySkipped(reason: "ensureAlive-refreshed-\(currentPhase.rawValue)", isEnabled: true,
                              activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled)
            return
        }

        guard currentActivity == nil || currentPhase == .idle else {
            // Activity exists, phase is coherent, and ActivityKit reports it .active.
            // WHY that last part matters: this line used to be reachable with a dead
            // activity, which is the entire #257 symptom.
            logStandbySkipped(reason: "ensureAlive-healthy-\(currentPhase.rawValue)", isEnabled: true,
                              activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled)
            return
        }
        PersistentLog.log(.liveActivityTransition(from: currentPhase.rawValue, to: "recovery-standby"))
        // startStandbyActivity() persists its own outcome (created, orphanRecovered,
        // systemActivitiesDisabled, requestFailed, ...) -- no extra entry needed here.
        startStandbyActivity()
    }

    // MARK: - Recording Watchdog

    /// Arm the post-recording watchdog. Called by DictationCoordinator after stop/cancel.
    /// WHY 2s timeout: Normal transition from .recording to .transcribing/.standby takes <1s.
    /// The watchdog ONLY fires if currentPhase is still .recording after the delay — it does
    /// NOT interfere with transcription, result display, or any later phase. If the DI already
    /// moved to .transcribing/.ready/.standby, the guard exits harmlessly.
    /// Previously 10s — reduced to 2s for faster recovery when DI gets stuck (issue #60).
    func startRecordingWatchdog() {
        recordingWatchdog?.cancel()
        recordingWatchdog = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            guard !Task.isCancelled else { return }
            guard currentPhase == .recording else { return }
            // DI is still on .recording but nobody is recording -- force recovery
            PersistentLog.log(.watchdogReset(source: "liveActivity", staleState: "recording"))
            DictusLogger.app.error("Recording watchdog fired -- DI stuck on .recording, forcing standby")
            await returnToStandby()
        }
    }

    /// Cancel the watchdog (new recording started, or DI already transitioned).
    func cancelRecordingWatchdog() {
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
    }

    // MARK: - Utilities

    /// Return to standby state. Called after result/failure auto-dismiss,
    /// and also when a recording is cancelled from the keyboard.
    func returnToStandby() async {
        // WHY: Only return to standby from states that logically precede it.
        // Prevents stale auto-dismiss tasks from overwriting an active recording (#42).
        guard currentPhase == .ready || currentPhase == .failed || currentPhase == .recording else {
            DictusLogger.app.info("returnToStandby skipped -- already \(self.currentPhase.rawValue, privacy: .public)")
            return
        }

        guard let activity = currentActivity else { return }

        PersistentLog.log(.liveActivityTransition(from: currentPhase.rawValue, to: "standby"))
        currentPhase = .standby  // Update BEFORE async work to prevent races (#49)
        syncStateMachine(to: .standby)
        let state = DictusLiveActivityAttributes.ContentState(phase: .standby)
        // Refresh staleDate on each return to standby (#84: 30s clears ghosts after force-quit)
        let staleDate = Date().addingTimeInterval(staleInterval)
        await activity.update(.init(state: state, staleDate: staleDate))
        DictusLogger.app.info("Live Activity -> standby (auto-return)")
    }

    /// Clean up stale Live Activities from previous app launches.
    /// Called at app startup to prevent zombie activities from persisting
    /// after a crash or force-quit.
    ///
    /// WHY this is needed:
    /// If the app crashes or is force-quit, the Live Activity stays visible
    /// on the Dynamic Island until iOS times it out (up to 8 hours).
    /// Cleaning up on launch ensures a fresh state.
    func cleanupStaleActivities() {
        // Capture current session ID BEFORE entering the async Task.
        // WHY: On cold start, transitionToRecording() may create a new Live Activity
        // before this cleanup Task runs. Without this guard, the cleanup would end
        // the freshly created recording activity (race condition).
        let currentSessionActivityID = currentActivity?.id

        Task {
            for activity in Activity<DictusLiveActivityAttributes>.activities {
                if activity.id == currentSessionActivityID { continue }

                await activity.end(
                    .init(
                        state: DictusLiveActivityAttributes.ContentState(phase: .standby),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
                DictusLogger.app.info("Cleaned up stale Live Activity: \(activity.id, privacy: .public)")
            }
            if currentSessionActivityID == nil {
                currentActivity = nil
                currentPhase = .idle
                syncStateMachine(to: .idle)
            }
        }
    }

    /// End all Live Activities during app termination (force-quit).
    /// WHY RunLoop spin: activity.end() is async, but willTerminate gives very limited
    /// time before iOS kills the process. Spawning Task { await } alone doesn't work —
    /// the tasks never execute before the process dies. Running the RunLoop for 500ms
    /// lets the main thread process pending async work, giving the end() calls a chance
    /// to complete. This is the standard pattern for async cleanup during termination.
    private func endAllActivitiesSync() {
        let activities = Activity<DictusLiveActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        let state = DictusLiveActivityAttributes.ContentState(phase: .standby)
        for activity in activities {
            Task {
                await activity.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
        // Give async tasks time to complete before the process is killed
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        currentActivity = nil
        currentPhase = .idle
        syncStateMachine(to: .idle)
        PersistentLog.log(.liveActivityEnded(reason: "appTerminating"))
        DictusLogger.app.info("Ended all Live Activities (app terminating)")
    }

    /// Downsample an array of Float values to the target count by averaging groups.
    private func downsample(_ values: [Float], to count: Int) -> [Float] {
        guard !values.isEmpty else {
            return Array(repeating: 0.3, count: count)
        }

        if values.count <= count {
            // Pad with last value if needed
            var result = values
            let pad = values.last ?? 0.3
            while result.count < count {
                result.append(pad)
            }
            return result
        }

        // Average groups
        let groupSize = values.count / count
        return (0..<count).map { i in
            let start = i * groupSize
            let end = min(start + groupSize, values.count)
            let slice = values[start..<end]
            return slice.reduce(0, +) / Float(slice.count)
        }
    }
}
