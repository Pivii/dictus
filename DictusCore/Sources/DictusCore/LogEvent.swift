// DictusCore/Sources/DictusCore/LogEvent.swift
// Structured logging API with privacy-safe typed events.
// Callers log via enum cases with typed parameters -- no free-text strings.

import Foundation

// MARK: - LogLevel

/// Log severity levels for structured logging.
/// 4 levels: debug (internal details), info (normal operations),
/// warning (recoverable issues), error (failures).
public enum LogLevel: String, CaseIterable, Sendable {
    case debug, info, warning, error

    /// Level name padded to 7 characters for aligned log output.
    public var paddedName: String {
        rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)
    }
}

// MARK: - Subsystem

/// App subsystems that produce log events.
/// Each subsystem groups related events for filtering and analysis.
public enum Subsystem: String, CaseIterable, Sendable {
    case dictation, audio, transcription, model, keyboard, lifecycle
}

// MARK: - LogEvent

/// Typed log events with structured parameters.
///
/// WHY an enum instead of free-text logging:
/// Privacy by construction -- callers cannot pass arbitrary strings that might
/// contain transcription text or keystrokes. Each case defines exactly what
/// data can be logged. The `keyboardTextInserted` case intentionally has NO
/// content parameter.
///
/// Error string parameters accept framework error descriptions (WhisperKit, Parakeet,
/// AVAudioSession) which are safe to log per user decision.
public enum LogEvent: Sendable {
    // MARK: Dictation
    case dictationStarted(fromURL: Bool, appState: String, engineRunning: Bool)
    case dictationCompleted(durationMs: Int)
    case dictationFailed(error: String)
    case dictationDeferred(reason: String)
    /// Issue #261: an active dictation status was found in the App Group with no
    /// live process behind it, and was cleared. `heartbeatAgeMs` is -1 when the
    /// heartbeat key was absent, which is how the app-side launch audit reports it
    /// (a fresh process owns no session by construction, so it needs no heartbeat
    /// to reach its verdict).
    case dictationStateReconciled(source: String, staleStatus: String, heartbeatAgeMs: Int)

    // MARK: Audio
    case audioEngineStarted
    case audioEngineStopped
    case audioSessionConfigured(category: String)
    case audioSessionFailed(error: String)
    case audioInterruptionBegan(reason: String)
    case audioInterruptionEnded(shouldResume: Bool, restored: Bool)
    case audioRouteChanged(reason: String, details: String)
    case audioMediaServicesReset
    case warmStateReleased(idleSeconds: Int)
    case warmStateRestored(context: String)

    // MARK: Transcription
    case transcriptionStarted(modelName: String)
    case transcriptionCompleted(durationMs: Int, wordCount: Int)
    case transcriptionFailed(error: String)
    case recordingTooShort(durationMs: Int)
    case transcriptionPerformance(modelName: String, audioDurationMs: Int, transcriptionDurationMs: Int, peakMemoryMB: Int)

    // MARK: Model
    case modelDownloadStarted(name: String, sizeMB: Int)
    case modelDownloadCompleted(name: String)
    case modelDownloadFailed(name: String, error: String)
    case modelSelected(name: String)
    case modelCompilationStarted(name: String)
    case modelCompilationCompleted(name: String, durationMs: Int)
    case modelDeleted(name: String, engine: String)
    case modelDeleteFailed(name: String, error: String)
    case modelPrewarmStarted(name: String)
    case modelCleanupPerformed(name: String, reason: String)
    case modelPrewarmPeakMemory(modelName: String, peakMB: Int)
    case modelPrewarmTimeout(name: String, timeoutSeconds: Int)
    case modelLoadStateChanged(from: String, to: String, reason: String)
    case modelDownloadProgress(name: String, percent: Int, mbDownloaded: Int, mbTotal: Int)
    case modelDownloadStalled(name: String, path: String, timeoutSeconds: Int, attempt: Int)

    // MARK: Keyboard
    case keyboardDidAppear
    case keyboardDidDisappear
    case keyboardMicTapped
    case keyboardTextInserted  // No content parameter -- privacy by design

    // MARK: Keyboard status message (#261)
    /// The toolbar message was assigned. `reason` names what asked for it.
    case dictationMessageSet(reason: String, owner: String, visible: Bool)
    /// A live view put that message on screen. One line per view that rendered it,
    /// which is the whole point: iOS keeps several controllers alive, and whether
    /// the one the user is looking at was among them is exactly the open question.
    case dictationMessageDisplayed(rootView: String, controller: String, owner: String, visible: Bool)
    /// The message ended. `displayedCount` is how many views had reported rendering
    /// it over its life, so a single line answers whether anybody could have read it.
    case dictationMessageCleared(reason: String, displayedCount: Int)

    // MARK: User dictionary (#307)
    // Every payload here is an Int, and that is the point: these cases *cannot*
    // carry a learned word. The words themselves live in AutocorrectDebugLog,
    // which does not exist in a Release binary. See that file's header for the
    // split.
    /// A word entered the personal dictionary. `learnedCount` is the size of the
    /// dictionary after the write, so a reader can watch it grow and see where it
    /// stops.
    case userDictionaryWordLearned(learnedCount: Int)
    /// The cap overflowed and entries were dropped (#304). `removed` is how many
    /// this write took out, `learnedCount` the size it settled at.
    case userDictionaryEvicted(removed: Int, learnedCount: Int, cap: Int)
    /// The dictionary was cleared, and how many words that cost.
    case userDictionaryReset(clearedCount: Int)
    /// Entries written before recency existed were stamped on load (#304).
    /// `stamped` is the legacy cohort, `droppedStamps` the timestamps whose word
    /// was no longer learned. This is the line that answers "did the update keep
    /// this install's vocabulary" — the #304 criterion no log could settle.
    case userDictionaryMigrated(stamped: Int, droppedStamps: Int, learnedCount: Int)
    /// Entries unused for `days` were discarded on load (#287). Below the cap this
    /// is the only thing that ever removes an entry, so it is the line that says
    /// a dictionary is being kept honest over time.
    case userDictionaryStaleDiscarded(removed: Int, learnedCount: Int, days: Int)
    /// The one-shot prune of entries the base dictionary already knew (#287).
    /// `removed` is what this install was carrying for nothing; the words
    /// themselves are in the debug log.
    case userDictionaryPruned(removed: Int, learnedCount: Int)

    // MARK: Animation
    case overlayShown(status: String)
    case overlayHidden(status: String)
    case statusChanged(from: String, to: String, source: String)
    case watchdogReset(source: String, staleState: String)
    /// Issue #60: a path tried to enter .idle while the engine was still capturing.
    case idleInvariantViolation(from: String, engineRunning: Bool)
    case rapidTapRejected

    // MARK: Engine Diagnostics (temporary — remove after debug)
    case engineWarmUpAttempt(context: String)
    case engineWarmUpSuccess(context: String)
    case engineWarmUpFailed(context: String, error: String)
    case engineStateSnapshot(engineRunning: Bool, isRecording: Bool, hasWhisperKit: Bool, sessionConfigured: Bool, context: String)
    case engineCollectResult(sampleCount: Int, engineRunning: Bool)
    case engineDarwinStartReceived(appState: String, engineRunning: Bool)

    // MARK: Waveform Diagnostics
    case waveformAppeared(refreshID: Int, isProcessing: Bool, energyCount: Int, killedState: Bool)
    case waveformDisappeared(refreshID: Int, renderTick: Int)
    /// `maxGapMs` is the worst interval between two display-link callbacks since the
    /// previous heartbeat. It is the frame-cadence evidence #314 asks for, carried by a
    /// line that is already emitted every ~2 s: a per-frame event would be the wrong
    /// trade against a log that is capped at 1 MB and deduplicated (#255).
    case waveformHeartbeat(renderTick: Int, avgLevel: Float, energyCount: Int, maxGapMs: Int)
    case waveformStall(gapMs: Int, renderTick: Int, energyCount: Int)
    case waveformRefreshIDChanged(oldID: Int, newID: Int, status: String)
    case waveformEnergyTransition(fromCount: Int, toCount: Int, status: String)
    case waveformTimelineNotFiring(renderTick: Int, energyCount: Int)
    case diagnosticProbe(component: String, instanceID: String, action: String, details: String)

    // MARK: Overlay Diagnostics
    case overlayBodyEvaluated(status: String, showsOverlay: Bool, energyCount: Int)
    case overlayTimerStarted
    case overlayTimerStopped
    case overlayRecreated(reason: String, status: String)

    // MARK: Onboarding
    case onboardingScenePhaseChanged(phase: String)
    case onboardingKeyboardCheckStarted(modeCount: Int)
    case onboardingKeyboardDetected(identifier: String)
    case onboardingKeyboardNotFound(modeCount: Int)
    case onboardingKeyboardCheckSkipped(reason: String)
    case onboardingKeyboardRetry
    case onboardingDictusKeyboardActivated
    case onboardingGlobeTutorialTextDetected
    case onboardingGlobeTutorialSkipped

    // MARK: Live Activity
    case liveActivityStarted(id: String)
    case liveActivityTransition(from: String, to: String)
    case liveActivityFailed(context: String, error: String)
    case liveActivityEnded(reason: String)
    /// A standby start/recovery attempt returned without creating a new activity.
    /// WHY the two booleans: When the Dynamic Island silently never appears, the
    /// exported log must show BOTH the in-app toggle and the iOS-level
    /// ActivityAuthorizationInfo().areActivitiesEnabled value to tell the causes
    /// apart (issue #233 — the system toggle was the only fully silent path).
    /// WHY activityState: both booleans can read true while the activity the
    /// manager is holding has already been ended by the system. Without the
    /// activity's real state, that failure looks identical to a healthy skip in
    /// an exported log, which is how #257 went unnoticed for 8 hours. nil means
    /// the manager held no activity at all.
    case liveActivityStandbySkipped(reason: String, isEnabled: Bool, activitiesEnabled: Bool, activityState: LiveActivityLiveness?)

    // MARK: Cold Start Diagnostics
    case coldStartURLReceived(isColdStart: Bool, isEngineDead: Bool, hasBeenActive: Bool)
    case coldStartFlagSet(active: Bool, context: String)
    case coldStartRetry(keyboardStatus: String)
    case coldStartDarwinFallback(elapsedMs: Int, status: String)
    /// A cold start was still parked when the app left the foreground, so
    /// `didBecomeActive` was never going to arrive (#311). `action` is the
    /// `ColdStartResolution` that was applied — `dropped`, `report` or `retry` —
    /// or `expired`, which is the background assertion running out with the
    /// request still unresolved. This is the line that makes the failure
    /// self-diagnosing: before it, a stranded dictation left no trace at all
    /// beyond a `dictationDeferred` followed by silence.
    case coldStartStranded(keyboardStatus: String, action: String)

    // MARK: Subscription
    case subscriptionError(action: String, error: String)

    // MARK: Log Management
    case logExportCompleted(durationMs: Int, sizeBytes: Int)

    // MARK: Lifecycle
    case appLaunched(version: String)
    case appDidBecomeActive
    case appWillResignActive
    case appDidEnterBackground
    case appWhisperKitLoaded(modelName: String)
    case deviceCapabilitySnapshot(model: String, ramGB: Int, availableMemoryMB: Int, thermalState: String)

    // MARK: Polish
    /// Issue #315: the polish engine threw. `reason` is the slug the engine gave
    /// its own failure (`PolishFailureReason`) — "rateLimited", "concurrentRequests",
    /// or "other:<Type>" for an error no engine recognised.
    ///
    /// WHY it belongs in this log and not only in the polish debug export: the
    /// export answers "how often, and which reason", but not "what else was the
    /// app doing". A failure that arrives in 4 ms has to be readable against the
    /// dictation timeline right next to it — status transitions, holds, the
    /// insertion — and only this log has all of them on one page.
    case polishEngineFailed(reason: String, engine: String, mode: String, engineMs: Int)

    /// Issue #315: polish stopped calling its engine for the rest of this process,
    /// after `consecutiveRefusals` `rateLimited` results in a row.
    ///
    /// Emitted once, on the transition. Every dictation after it records
    /// `outcome = engineUnavailable` in the polish debug export, so the count of
    /// what a single outage cost is already answerable there; a line per skipped
    /// call here would only repeat it. What this log has that the export does not
    /// is everything else the app was doing, which is what says whether the user
    /// was told and what the keyboard was showing at the time.
    case polishEngineUnavailable(engine: String, reason: String, consecutiveRefusals: Int)

    // MARK: - Computed Properties

    /// The subsystem this event belongs to, derived from the case.
    public var subsystem: Subsystem {
        switch self {
        case .dictationStarted, .dictationCompleted, .dictationFailed, .dictationDeferred,
             .dictationStateReconciled:
            return .dictation
        case .audioEngineStarted, .audioEngineStopped, .audioSessionConfigured, .audioSessionFailed,
             .audioInterruptionBegan, .audioInterruptionEnded, .audioRouteChanged,
             .audioMediaServicesReset, .warmStateReleased, .warmStateRestored:
            return .audio
        case .transcriptionStarted, .transcriptionCompleted, .transcriptionFailed, .recordingTooShort,
             .transcriptionPerformance:
            return .transcription
        case .modelDownloadStarted, .modelDownloadCompleted, .modelDownloadFailed,
             .modelSelected, .modelCompilationStarted, .modelCompilationCompleted,
             .modelDeleted, .modelDeleteFailed, .modelPrewarmStarted, .modelCleanupPerformed,
             .modelPrewarmPeakMemory, .modelPrewarmTimeout, .modelLoadStateChanged,
             .modelDownloadProgress, .modelDownloadStalled:
            return .model
        case .keyboardDidAppear, .keyboardDidDisappear, .keyboardMicTapped, .keyboardTextInserted,
             .overlayShown, .overlayHidden, .rapidTapRejected,
             .dictationMessageSet, .dictationMessageDisplayed, .dictationMessageCleared,
             .waveformAppeared, .waveformDisappeared, .waveformHeartbeat, .waveformStall,
             .waveformRefreshIDChanged, .waveformEnergyTransition, .waveformTimelineNotFiring,
             .overlayBodyEvaluated, .overlayTimerStarted, .overlayTimerStopped, .overlayRecreated,
             .diagnosticProbe,
             .userDictionaryWordLearned, .userDictionaryEvicted, .userDictionaryReset,
             .userDictionaryMigrated, .userDictionaryStaleDiscarded, .userDictionaryPruned:
            return .keyboard
        case .statusChanged, .watchdogReset, .idleInvariantViolation:
            return .dictation
        case .engineWarmUpAttempt, .engineWarmUpSuccess, .engineWarmUpFailed,
             .engineStateSnapshot, .engineCollectResult, .engineDarwinStartReceived:
            return .audio
        case .onboardingScenePhaseChanged, .onboardingKeyboardCheckStarted,
             .onboardingKeyboardDetected, .onboardingKeyboardNotFound,
             .onboardingKeyboardCheckSkipped, .onboardingKeyboardRetry,
             .onboardingDictusKeyboardActivated, .onboardingGlobeTutorialTextDetected,
             .onboardingGlobeTutorialSkipped:
            return .lifecycle
        case .coldStartURLReceived, .coldStartFlagSet, .coldStartRetry, .coldStartDarwinFallback,
             .coldStartStranded:
            return .lifecycle
        case .logExportCompleted:
            return .lifecycle
        case .subscriptionError:
            return .lifecycle
        case .liveActivityStarted, .liveActivityTransition, .liveActivityFailed, .liveActivityEnded,
             .liveActivityStandbySkipped:
            return .lifecycle
        case .appLaunched, .appDidBecomeActive, .appWillResignActive,
             .appDidEnterBackground, .appWhisperKitLoaded, .deviceCapabilitySnapshot:
            return .lifecycle
        // Polish is the stage after the STT result and before the App Group
        // write, so it reads with the transcription stream rather than as a
        // subsystem of its own (#315).
        case .polishEngineFailed, .polishEngineUnavailable:
            return .transcription
        }
    }

    /// Log level derived from the event type.
    /// Failures = error, deferred/warnings = warning, starts/completes = info,
    /// stops/internal state = debug.
    public var level: LogLevel {
        switch self {
        // A message nobody rendered is the failure this instrumentation exists to
        // catch (#261), so it is findable by level and not only by reading the count.
        case .dictationMessageCleared(_, let displayedCount):
            return displayedCount == 0 ? .warning : .info

        // Errors
        case .dictationFailed, .audioSessionFailed, .transcriptionFailed,
             .modelDownloadFailed, .modelDeleteFailed,
             .liveActivityFailed, .subscriptionError, .idleInvariantViolation:
            return .error

        // Warnings
        case .dictationDeferred, .dictationStateReconciled,
             .watchdogReset, .engineWarmUpFailed, .recordingTooShort,
             .waveformStall, .waveformTimelineNotFiring,
             .coldStartDarwinFallback, .coldStartStranded, .modelPrewarmTimeout,
             .audioInterruptionBegan, .audioMediaServicesReset,
             .modelDownloadStalled:
            return .warning

        // Info (normal operations: starts, completes, selections, configs)
        case .onboardingKeyboardDetected,
             .onboardingDictusKeyboardActivated, .onboardingGlobeTutorialTextDetected,
             .onboardingGlobeTutorialSkipped,
             .dictationStarted, .dictationCompleted,
             .audioEngineStarted, .audioSessionConfigured,
             .transcriptionStarted, .transcriptionCompleted,
             .modelDownloadStarted, .modelDownloadCompleted, .modelDownloadProgress,
             .modelSelected, .modelCompilationStarted, .modelCompilationCompleted,
             .modelDeleted, .modelPrewarmStarted, .modelCleanupPerformed,
             .modelPrewarmPeakMemory, .modelLoadStateChanged, .transcriptionPerformance,
             .keyboardDidAppear, .keyboardMicTapped,
             .dictationMessageSet, .dictationMessageDisplayed,
             .appLaunched, .appWhisperKitLoaded, .logExportCompleted,
             .deviceCapabilitySnapshot,
             .liveActivityStarted, .liveActivityTransition, .liveActivityEnded,
             .liveActivityStandbySkipped,
             .coldStartURLReceived, .coldStartFlagSet, .coldStartRetry,
             .overlayShown, .overlayHidden, .statusChanged,
             .waveformAppeared, .waveformDisappeared, .waveformRefreshIDChanged,
             .waveformEnergyTransition, .overlayBodyEvaluated, .overlayRecreated,
             .audioInterruptionEnded, .audioRouteChanged,
             .warmStateReleased, .warmStateRestored,
             .userDictionaryEvicted, .userDictionaryReset, .userDictionaryMigrated,
             .userDictionaryStaleDiscarded, .userDictionaryPruned:
            return .info

        // Debug (internal state transitions)
        case .onboardingScenePhaseChanged, .onboardingKeyboardCheckStarted,
             .onboardingKeyboardNotFound, .onboardingKeyboardCheckSkipped,
             .onboardingKeyboardRetry,
             .audioEngineStopped,
             .keyboardDidDisappear, .keyboardTextInserted,
             .appDidBecomeActive, .appWillResignActive, .appDidEnterBackground,
             .rapidTapRejected,
             .engineWarmUpAttempt, .engineWarmUpSuccess,
             .engineStateSnapshot, .engineCollectResult, .engineDarwinStartReceived,
             .waveformHeartbeat, .overlayTimerStarted, .overlayTimerStopped,
             .diagnosticProbe,
             // Debug, not info: one line per newly learned word is the finest grain
             // in this group. The eviction and reset lines are the ones a reader
             // scans for.
             .userDictionaryWordLearned:
            return .debug

        // Warning, not error: the user still gets their text (the deterministic
        // floor), only the polish is lost — but silently, which is the failure
        // worth finding in a log (#315).
        //
        // The same level for the unavailable transition, and for the same reason:
        // an enabled feature has stopped running. It is the more serious of the
        // two — it holds for the rest of the process — but not an error either,
        // because nothing broke and no text was lost.
        case .polishEngineFailed, .polishEngineUnavailable:
            return .warning
        }
    }

    /// Event name as it appears in the log line (matches the enum case name).
    public var name: String {
        switch self {
        case .dictationStarted: return "dictationStarted"
        case .dictationCompleted: return "dictationCompleted"
        case .dictationFailed: return "dictationFailed"
        case .dictationDeferred: return "dictationDeferred"
        case .dictationStateReconciled: return "dictationStateReconciled"
        case .audioEngineStarted: return "audioEngineStarted"
        case .audioEngineStopped: return "audioEngineStopped"
        case .audioSessionConfigured: return "audioSessionConfigured"
        case .audioSessionFailed: return "audioSessionFailed"
        case .audioInterruptionBegan: return "audioInterruptionBegan"
        case .audioInterruptionEnded: return "audioInterruptionEnded"
        case .audioRouteChanged: return "audioRouteChanged"
        case .audioMediaServicesReset: return "audioMediaServicesReset"
        case .warmStateReleased: return "warmStateReleased"
        case .warmStateRestored: return "warmStateRestored"
        case .transcriptionStarted: return "transcriptionStarted"
        case .transcriptionCompleted: return "transcriptionCompleted"
        case .transcriptionFailed: return "transcriptionFailed"
        case .recordingTooShort: return "recordingTooShort"
        case .modelDownloadStarted: return "modelDownloadStarted"
        case .modelDownloadCompleted: return "modelDownloadCompleted"
        case .modelDownloadFailed: return "modelDownloadFailed"
        case .modelSelected: return "modelSelected"
        case .modelCompilationStarted: return "modelCompilationStarted"
        case .modelCompilationCompleted: return "modelCompilationCompleted"
        case .modelDeleted: return "modelDeleted"
        case .modelDeleteFailed: return "modelDeleteFailed"
        case .modelPrewarmStarted: return "modelPrewarmStarted"
        case .modelCleanupPerformed: return "modelCleanupPerformed"
        case .keyboardDidAppear: return "keyboardDidAppear"
        case .keyboardDidDisappear: return "keyboardDidDisappear"
        case .keyboardMicTapped: return "keyboardMicTapped"
        case .dictationMessageSet: return "dictationMessageSet"
        case .dictationMessageDisplayed: return "dictationMessageDisplayed"
        case .dictationMessageCleared: return "dictationMessageCleared"
        case .keyboardTextInserted: return "keyboardTextInserted"
        case .engineWarmUpAttempt: return "engineWarmUpAttempt"
        case .engineWarmUpSuccess: return "engineWarmUpSuccess"
        case .engineWarmUpFailed: return "engineWarmUpFailed"
        case .engineStateSnapshot: return "engineStateSnapshot"
        case .engineCollectResult: return "engineCollectResult"
        case .engineDarwinStartReceived: return "engineDarwinStartReceived"
        case .onboardingScenePhaseChanged: return "onboardingScenePhaseChanged"
        case .onboardingKeyboardCheckStarted: return "onboardingKeyboardCheckStarted"
        case .onboardingKeyboardDetected: return "onboardingKeyboardDetected"
        case .onboardingKeyboardNotFound: return "onboardingKeyboardNotFound"
        case .onboardingKeyboardCheckSkipped: return "onboardingKeyboardCheckSkipped"
        case .onboardingKeyboardRetry: return "onboardingKeyboardRetry"
        case .onboardingDictusKeyboardActivated: return "onboardingDictusKeyboardActivated"
        case .onboardingGlobeTutorialTextDetected: return "onboardingGlobeTutorialTextDetected"
        case .onboardingGlobeTutorialSkipped: return "onboardingGlobeTutorialSkipped"
        case .liveActivityStarted: return "liveActivityStarted"
        case .liveActivityTransition: return "liveActivityTransition"
        case .liveActivityFailed: return "liveActivityFailed"
        case .liveActivityEnded: return "liveActivityEnded"
        case .liveActivityStandbySkipped: return "liveActivityStandbySkipped"
        case .appLaunched: return "appLaunched"
        case .appDidBecomeActive: return "appDidBecomeActive"
        case .appWillResignActive: return "appWillResignActive"
        case .appDidEnterBackground: return "appDidEnterBackground"
        case .appWhisperKitLoaded: return "appWhisperKitLoaded"
        case .overlayShown: return "overlayShown"
        case .overlayHidden: return "overlayHidden"
        case .statusChanged: return "statusChanged"
        case .watchdogReset: return "watchdogReset"
        case .idleInvariantViolation: return "idleInvariantViolation"
        case .rapidTapRejected: return "rapidTapRejected"
        case .waveformAppeared: return "waveformAppeared"
        case .waveformDisappeared: return "waveformDisappeared"
        case .waveformHeartbeat: return "waveformHeartbeat"
        case .waveformStall: return "waveformStall"
        case .waveformRefreshIDChanged: return "waveformRefreshIDChanged"
        case .waveformEnergyTransition: return "waveformEnergyTransition"
        case .waveformTimelineNotFiring: return "waveformTimelineNotFiring"
        case .diagnosticProbe: return "diagnosticProbe"
        case .overlayBodyEvaluated: return "overlayBodyEvaluated"
        case .overlayTimerStarted: return "overlayTimerStarted"
        case .overlayTimerStopped: return "overlayTimerStopped"
        case .overlayRecreated: return "overlayRecreated"
        case .coldStartURLReceived: return "coldStartURLReceived"
        case .coldStartFlagSet: return "coldStartFlagSet"
        case .coldStartRetry: return "coldStartRetry"
        case .coldStartDarwinFallback: return "coldStartDarwinFallback"
        case .coldStartStranded: return "coldStartStranded"
        case .subscriptionError: return "subscriptionError"
        case .logExportCompleted: return "logExportCompleted"
        case .transcriptionPerformance: return "transcriptionPerformance"
        case .modelPrewarmPeakMemory: return "modelPrewarmPeakMemory"
        case .modelPrewarmTimeout: return "modelPrewarmTimeout"
        case .deviceCapabilitySnapshot: return "deviceCapabilitySnapshot"
        case .modelLoadStateChanged: return "modelLoadStateChanged"
        case .modelDownloadProgress: return "modelDownloadProgress"
        case .modelDownloadStalled: return "modelDownloadStalled"
        case .polishEngineFailed: return "polishEngineFailed"
        case .polishEngineUnavailable: return "polishEngineUnavailable"
        case .userDictionaryWordLearned: return "userDictionaryWordLearned"
        case .userDictionaryEvicted: return "userDictionaryEvicted"
        case .userDictionaryReset: return "userDictionaryReset"
        case .userDictionaryMigrated: return "userDictionaryMigrated"
        case .userDictionaryStaleDiscarded: return "userDictionaryStaleDiscarded"
        case .userDictionaryPruned: return "userDictionaryPruned"
        }
    }

    /// Formatted key=value parameters from associated values.
    /// Returns empty string for events with no associated values.
    public var message: String {
        switch self {
        // Dictation
        case .dictationStarted(let fromURL, let appState, let engineRunning):
            return "fromURL=\(fromURL) appState=\(appState) engineRunning=\(engineRunning)"
        case .dictationCompleted(let durationMs):
            return "duration=\(durationMs)ms"
        case .dictationFailed(let error):
            return "error=\(error)"
        case .dictationDeferred(let reason):
            return "reason=\(reason)"
        case .dictationStateReconciled(let source, let staleStatus, let heartbeatAgeMs):
            return "source=\(source) staleStatus=\(staleStatus) heartbeatAgeMs=\(heartbeatAgeMs)"

        // Audio
        case .audioEngineStarted, .audioEngineStopped:
            return ""
        case .audioSessionConfigured(let category):
            return "category=\(category)"
        case .audioSessionFailed(let error):
            return "error=\(error)"
        case .audioInterruptionBegan(let reason):
            return "reason=\(reason)"
        case .audioInterruptionEnded(let shouldResume, let restored):
            return "shouldResume=\(shouldResume) restored=\(restored)"
        case .audioRouteChanged(let reason, let details):
            return "reason=\(reason) details=\(details)"
        case .audioMediaServicesReset:
            return ""
        case .warmStateReleased(let idleSeconds):
            return "idleSeconds=\(idleSeconds)"
        case .warmStateRestored(let context):
            return "context=\(context)"

        // Transcription
        case .transcriptionStarted(let modelName):
            return "model=\(modelName)"
        case .transcriptionCompleted(let durationMs, let wordCount):
            return "duration=\(durationMs)ms words=\(wordCount)"
        case .transcriptionFailed(let error):
            return "error=\(error)"
        case .recordingTooShort(let durationMs):
            return "duration=\(durationMs)ms"

        // Model
        case .modelDownloadStarted(let name, let sizeMB):
            return "name=\(name) size=\(sizeMB)MB"
        case .modelDownloadCompleted(let name):
            return "name=\(name)"
        case .modelDownloadFailed(let name, let error):
            return "name=\(name) error=\(error)"
        case .modelSelected(let name):
            return "name=\(name)"
        case .modelCompilationStarted(let name):
            return "name=\(name)"
        case .modelCompilationCompleted(let name, let durationMs):
            return "name=\(name) duration=\(durationMs)ms"
        case .modelDeleted(let name, let engine):
            return "name=\(name) engine=\(engine)"
        case .modelDeleteFailed(let name, let error):
            return "name=\(name) error=\(error)"
        case .modelPrewarmStarted(let name):
            return "name=\(name)"
        case .modelCleanupPerformed(let name, let reason):
            return "name=\(name) reason=\(reason)"
        case .modelLoadStateChanged(let from, let to, let reason):
            return "from=\(from) to=\(to) reason=\(reason)"
        case .modelDownloadProgress(let name, let percent, let mbDownloaded, let mbTotal):
            return "name=\(name) percent=\(percent) downloaded=\(mbDownloaded)MB total=\(mbTotal)MB"
        case .modelDownloadStalled(let name, let path, let timeoutSeconds, let attempt):
            return "name=\(name) path=\(path) timeout=\(timeoutSeconds)s attempt=\(attempt)"

        // Keyboard (no content parameters -- privacy)
        case .keyboardDidAppear, .keyboardDidDisappear,
             .keyboardMicTapped, .keyboardTextInserted:
            return ""

        // Engine Diagnostics
        case .engineWarmUpAttempt(let context):
            return "context=\(context)"
        case .engineWarmUpSuccess(let context):
            return "context=\(context)"
        case .engineWarmUpFailed(let context, let error):
            return "context=\(context) error=\(error)"
        case .engineStateSnapshot(let engineRunning, let isRecording, let hasWhisperKit, let sessionConfigured, let context):
            return "engineRunning=\(engineRunning) isRecording=\(isRecording) hasWhisperKit=\(hasWhisperKit) sessionConfigured=\(sessionConfigured) context=\(context)"
        case .engineCollectResult(let sampleCount, let engineRunning):
            return "sampleCount=\(sampleCount) engineRunning=\(engineRunning)"
        case .engineDarwinStartReceived(let appState, let engineRunning):
            return "appState=\(appState) engineRunning=\(engineRunning)"

        // Onboarding
        case .onboardingScenePhaseChanged(let phase):
            return "phase=\(phase)"
        case .onboardingKeyboardCheckStarted(let modeCount):
            return "modeCount=\(modeCount)"
        case .onboardingKeyboardDetected(let identifier):
            return "identifier=\(identifier)"
        case .onboardingKeyboardNotFound(let modeCount):
            return "modeCount=\(modeCount)"
        case .onboardingKeyboardCheckSkipped(let reason):
            return "reason=\(reason)"
        case .onboardingKeyboardRetry:
            return ""
        case .onboardingDictusKeyboardActivated, .onboardingGlobeTutorialTextDetected,
             .onboardingGlobeTutorialSkipped:
            return ""

        // Live Activity
        case .liveActivityStarted(let id):
            return "id=\(id)"
        case .liveActivityTransition(let from, let to):
            return "from=\(from) to=\(to)"
        case .liveActivityFailed(let context, let error):
            return "context=\(context) error=\(error)"
        case .liveActivityEnded(let reason):
            return "reason=\(reason)"
        case .liveActivityStandbySkipped(let reason, let isEnabled, let activitiesEnabled, let activityState):
            return "reason=\(reason) isEnabled=\(isEnabled) areActivitiesEnabled=\(activitiesEnabled) activityState=\(activityState?.rawValue ?? "none")"

        // Lifecycle
        case .appLaunched(let version):
            return "version=\(version)"
        case .appDidBecomeActive, .appWillResignActive, .appDidEnterBackground:
            return ""
        case .appWhisperKitLoaded(let modelName):
            return "model=\(modelName)"

        // Animation
        case .dictationMessageSet(let reason, let owner, let visible):
            return "reason=\(reason) owner=\(owner) visible=\(visible)"
        case .dictationMessageDisplayed(let rootView, let controller, let owner, let visible):
            return "rootView=\(rootView) controller=\(controller) owner=\(owner) visible=\(visible)"
        case .dictationMessageCleared(let reason, let displayedCount):
            return "reason=\(reason) displayedCount=\(displayedCount)"

        case .overlayShown(let status):
            return "status=\(status)"
        case .overlayHidden(let status):
            return "status=\(status)"
        case .statusChanged(let from, let to, let source):
            return "from=\(from) to=\(to) source=\(source)"
        case .watchdogReset(let source, let staleState):
            return "source=\(source) staleState=\(staleState)"
        case .idleInvariantViolation(let from, let engineRunning):
            return "from=\(from) engineRunning=\(engineRunning)"
        case .rapidTapRejected:
            return ""

        // Waveform Diagnostics
        case .waveformAppeared(let refreshID, let isProcessing, let energyCount, let killedState):
            return "refreshID=\(refreshID) isProcessing=\(isProcessing) energyCount=\(energyCount) killed=\(killedState)"
        case .waveformDisappeared(let refreshID, let renderTick):
            return "refreshID=\(refreshID) renderTick=\(renderTick)"
        case .waveformHeartbeat(let renderTick, let avgLevel, let energyCount, let maxGapMs):
            return "renderTick=\(renderTick) avgLevel=\(String(format: "%.3f", avgLevel)) energyCount=\(energyCount) maxGapMs=\(maxGapMs)"
        case .waveformStall(let gapMs, let renderTick, let energyCount):
            return "gapMs=\(gapMs) renderTick=\(renderTick) energyCount=\(energyCount)"
        case .waveformRefreshIDChanged(let oldID, let newID, let status):
            return "oldID=\(oldID) newID=\(newID) status=\(status)"
        case .waveformEnergyTransition(let fromCount, let toCount, let status):
            return "fromCount=\(fromCount) toCount=\(toCount) status=\(status)"
        case .waveformTimelineNotFiring(let renderTick, let energyCount):
            return "renderTick=\(renderTick) energyCount=\(energyCount)"
        case .diagnosticProbe(let component, let instanceID, let action, let details):
            return "component=\(component) instanceID=\(instanceID) action=\(action) details=\(details)"

        // Overlay Diagnostics
        case .overlayBodyEvaluated(let status, let showsOverlay, let energyCount):
            return "status=\(status) showsOverlay=\(showsOverlay) energyCount=\(energyCount)"
        case .overlayTimerStarted, .overlayTimerStopped:
            return ""
        case .overlayRecreated(let reason, let status):
            return "reason=\(reason) status=\(status)"

        // Cold Start Diagnostics
        case .coldStartURLReceived(let isColdStart, let isEngineDead, let hasBeenActive):
            return "isColdStart=\(isColdStart) isEngineDead=\(isEngineDead) hasBeenActive=\(hasBeenActive)"
        case .coldStartFlagSet(let active, let context):
            return "active=\(active) context=\(context)"
        case .coldStartRetry(let keyboardStatus):
            return "keyboardStatus=\(keyboardStatus)"
        case .coldStartDarwinFallback(let elapsedMs, let status):
            return "elapsedMs=\(elapsedMs) status=\(status)"
        case .coldStartStranded(let keyboardStatus, let action):
            return "keyboardStatus=\(keyboardStatus) action=\(action)"

        // Subscription
        case .subscriptionError(let action, let error):
            return "action=\(action) error=\(error)"

        // Log Management
        case .logExportCompleted(let durationMs, let sizeBytes):
            return "duration=\(durationMs)ms size=\(sizeBytes)bytes"

        // Phase 37 — Turbo retest & device gating telemetry
        case .transcriptionPerformance(let modelName, let audioDurationMs, let transcriptionDurationMs, let peakMemoryMB):
            return "model=\(modelName) audioMs=\(audioDurationMs) transcribeMs=\(transcriptionDurationMs) peakMB=\(peakMemoryMB)"
        case .modelPrewarmPeakMemory(let modelName, let peakMB):
            return "model=\(modelName) peakMB=\(peakMB)"
        case .modelPrewarmTimeout(let name, let timeoutSeconds):
            return "name=\(name) timeout=\(timeoutSeconds)s"
        case .deviceCapabilitySnapshot(let model, let ramGB, let availableMemoryMB, let thermalState):
            return "model=\(model) ramGB=\(ramGB) availableMB=\(availableMemoryMB) thermal=\(thermalState)"

        // User dictionary (#307)
        case .userDictionaryWordLearned(let learnedCount):
            return "learnedCount=\(learnedCount)"
        case .userDictionaryEvicted(let removed, let learnedCount, let cap):
            return "removed=\(removed) learnedCount=\(learnedCount) cap=\(cap)"
        case .userDictionaryReset(let clearedCount):
            return "clearedCount=\(clearedCount)"
        case .userDictionaryMigrated(let stamped, let droppedStamps, let learnedCount):
            return "stamped=\(stamped) droppedStamps=\(droppedStamps) learnedCount=\(learnedCount)"
        case .userDictionaryStaleDiscarded(let removed, let learnedCount, let days):
            return "removed=\(removed) learnedCount=\(learnedCount) days=\(days)"
        case .userDictionaryPruned(let removed, let learnedCount):
            return "removed=\(removed) learnedCount=\(learnedCount)"

        // Polish (#315)
        case .polishEngineFailed(let reason, let engine, let mode, let engineMs):
            return "reason=\(reason) engine=\(engine) mode=\(mode) engineMs=\(engineMs)"
        case .polishEngineUnavailable(let engine, let reason, let consecutiveRefusals):
            return "engine=\(engine) reason=\(reason) consecutiveRefusals=\(consecutiveRefusals)"
        }
    }

    // MARK: - Formatting

    /// Static ISO8601 formatter -- reused across all calls to avoid allocation overhead.
    /// WHY static: ISO8601DateFormatter is expensive to create. Creating one per log call
    /// causes measurable performance overhead (research pitfall 3).
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Produces the full formatted log line.
    /// Format: `[ISO8601timestamp] LEVEL  [subsystem] eventName param=value ...`
    public func formatted() -> String {
        "[\(Self.timestamp())] " + payload()
    }

    /// The formatted line without its leading timestamp.
    ///
    /// WHY this is split out of `formatted()` (#255): PersistentLog collapses runs
    /// of identical consecutive lines, and two occurrences of the same event a
    /// second apart differ only by their timestamp. The timestamp-free part is
    /// therefore the comparison key, and it has to be produced by the same code
    /// path that produces the written line so the two can never drift.
    func payload() -> String {
        let src = PersistentLog.source
        let params = message
        if params.isEmpty {
            return "\(level.paddedName) [\(subsystem.rawValue)] <\(src)> \(name)"
        }
        return "\(level.paddedName) [\(subsystem.rawValue)] <\(src)> \(name) \(params)"
    }

    /// ISO8601 timestamp for a log line, taken at the moment of the `log()` call
    /// rather than at the moment of the write — the write is queued.
    static func timestamp(for date: Date = Date()) -> String {
        isoFormatter.string(from: date)
    }
}
