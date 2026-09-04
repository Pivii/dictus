// DictusApp/DictationCoordinator+ModelLoad.swift
// The launch preload's deadline, and giving up on a load that will not finish (#428).
//
// WHY a file of its own: DictationCoordinator.swift sits at the file-length budget that
// issue #146 calibrated against it, and that budget exists to catch exactly this — the
// file growing again. Everything here reaches the coordinator through two named seams
// (`loadActiveModelIntoMemory`, `configureAudioSessionForWarmUp`) plus the load epoch
// and the init lock, so moving it out did not mean opening up the coordinator's
// private state wholesale.
import Foundation
import DictusCore
import WhisperKit

/// Where a path logs `engineWarmUpAttempt`, which is not the same for all of them.
enum WarmUpAttemptPosition {
    /// Before the model load. The only marker a hang on this path leaves in the log.
    case beforeModelLoad
    /// Immediately before the audio warm-up, where the launch path has always put it.
    case beforeAudioWarmUp
}

/// One-shot latch deciding which of a launch preload's two arms gets to publish.
///
/// The load and its deadline race, the first to finish wins, and the loser writes
/// nothing. Kept separate from `modelLoadEpoch` deliberately (second review, finding 5):
/// settling a race is a per-run question and must not move shared state that other loads
/// read to decide whether they were abandoned.
@MainActor
final class LaunchPreloadOutcome {
    private var isSettled = false

    /// Returns `true` to exactly one caller, ever.
    func settle() -> Bool {
        if isSettled { return false }
        isSettled = true
        return true
    }
}

extension DictationCoordinator {

    /// Load the active model at launch, under a deadline the app actually honours.
    ///
    /// WHY a deadline at all (issue #428): this path used to `await ensureEngineReady()`
    /// naked. When the compile never returned, `modelLoadState` stayed "loading" for the
    /// life of the process and was persisted that way for every process after it, which
    /// is what locked a device out of its own app after one interrupted Turbo compile.
    ///
    /// The deadline comes from the catalogue, per model, not from a constant here:
    /// `ModelInfo.preloadDeadlineSeconds(for:)` reads the same budget the download path
    /// uses, so Turbo gets 300s and everything else 120s (issue #406), and there is only
    /// ever one number per model to keep true. Those numbers are sized against a
    /// variant's FIRST compile on a device, which runs into the minutes; a load that
    /// finds a warm Core ML cache takes seconds.
    ///
    /// The measurement that matters most here is the one taken through this very path:
    /// on 2026-08-27 a cold launch preload of turbo_632MB took 202s and COMPLETED. This
    /// deadline is not guarding against a compile that never returns — it is guarding
    /// against the app having no way to know the difference.
    func runLaunchPreload() async {
        let modelName = defaults.string(forKey: SharedKeys.activeModel) ?? "openai_whisper-small"
        let deadlineSeconds = ModelInfo.preloadDeadlineSeconds(for: modelName)
        let outcome = LaunchPreloadOutcome()

        // `outcome` settles the race between THIS preload's two arms. It knows nothing
        // about loads started later, so the epoch is checked as well before either arm
        // writes: a user who escapes at 45s and picks another model owns the shared
        // state from that moment, and this preload must not write over it when its
        // compile finally lands (third review, finding A).
        let epoch = modelLoadEpoch

        setModelLoadState(.loading, reason: "init-preload")

        // The deadline arm. An independent task, NOT a child in a task group, and that
        // is the entire point.
        //
        // WHY AN INDEPENDENT TASK: because the alternative was measured and does not
        // work. Racing a sleep against the compile inside a throwing task group cannot
        // bound anything — a task group cannot return until every child has finished, so
        // the deadline error surfaces only once the compile it was meant to bound has
        // completed anyway, and `cancelAll()` does not help because cancellation is a
        // request and a Core ML compile checks no flag and offers no suspension point at
        // which it could notice one. The maintainer's device log has it firing in the
        // wild exactly this way: `modelPrewarmTimeout timeout=5s`, logged 212 seconds
        // after the compile it names started.
        //
        // This path was written this way from the start (issue #428). Issue #427 then
        // moved the download path onto the same shape, so `withPrewarmTimeout` now
        // arbitrates between two independent tasks too, and the two paths no longer
        // disagree about what a budget means. What follows below is the reasoning both
        // of them rest on.
        //
        // So this deadline interrupts nothing, and no deadline can. The compile keeps
        // running and keeps burning CPU until it finishes on its own. What expiry buys
        // is the only thing ever available: the app stops *waiting*. `modelLoadState`
        // goes back to idle, the keyboard stops refusing mic taps, and the preparation
        // screen stops covering the app.
        let deadlineArm = Task { @MainActor [weak self] in
            try await Task.sleep(nanoseconds: UInt64(deadlineSeconds) * 1_000_000_000)
            guard let self, !self.loadWasAbandoned(since: epoch), outcome.settle() else { return }
            // Giving up IS what moves the epoch — nothing else does.
            self.modelLoadEpoch += 1
            // Remember what we gave up on, so returning to the foreground does not
            // quietly start the same compile again (finding 3).
            self.abandonedModel = modelName
            self.setModelLoadState(.idle, reason: ModelPreparationOutcome.deadlineExpiredReason)
            PersistentLog.log(.diagnosticProbe(
                component: "ModelPreload",
                instanceID: modelName,
                action: "deadlineExpired",
                details: "seconds=\(deadlineSeconds) compileStillRunning=true"
            ))
        }

        // The load arm. The same work as before; the only new thing is that it has to
        // claim the outcome before publishing it, because the deadline may have won.
        do {
            let loadedName = try await loadActiveModelIntoMemory(
                context: "init-preload",
                attemptLog: .beforeAudioWarmUp
            )
            PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
            deadlineArm.cancel()

            // The epoch moved, but that does not by itself mean somebody else owns the
            // state (fourth review, finding 5). It moves when a load is ABANDONED, and
            // an abandoned load whose model is still the active one publishes its engine
            // anyway — `shouldPublishLoad` decided that, and it is the fix that stopped
            // the deadline throwing away working dictations. So this branch was logging
            // `supersededByNewerLoad` when nothing had superseded anything, and leaving
            // `modelLoadState` at `.idle` with a live engine behind it until some later
            // foreground warm-up happened to heal it. The log's reader is an agent, and
            // that line was simply false.
            //
            // What the engine actually did is the thing to report, and if it published,
            // the state must say so.
            if loadWasAbandoned(since: epoch) {
                let enginePublished = loadedName == modelName
                PersistentLog.log(.diagnosticProbe(
                    component: "ModelPreload",
                    instanceID: modelName,
                    action: enginePublished ? "publishedAfterAbandon" : "discardedAfterAbandon",
                    details: "loadedModel=\(loadedName) activeModel=\(defaults.string(forKey: SharedKeys.activeModel) ?? "nil")"
                ))
                guard enginePublished else { return }
                // The deadline can land between the engine being published and
                // `warmUp()` returning, which means `abandonedModel` was set AFTER
                // `clearAbandonedModel` already ran for this load. Publishing `.ready`
                // while the model is still marked abandoned makes every later foreground
                // warm-up skip work that is perfectly valid, for a model that is loaded
                // and running. Clear it here too: this is the branch that knows the
                // engine survived. (CodeRabbit, against 809a63f.)
                clearAbandonedModel(ifMatches: modelName)
                setModelLoadState(.ready, reason: "init-preload-late-success")
                return
            }
            guard outcome.settle() else {
                // Reachable only in the narrow window where the load published its
                // engine and the deadline claimed the outcome immediately afterwards.
                // A load abandoned any earlier than that throws instead and lands in
                // the catch below, which is why this line no longer has to guess
                // whether an engine survived: it reports the name the load actually
                // published (finding 6 — the details here used to be hardcoded, and
                // were false on the very path they described).
                PersistentLog.log(.diagnosticProbe(
                    component: "ModelPreload",
                    instanceID: modelName,
                    action: "completedAfterDeadline",
                    details: "loadedModel=\(loadedName) state=idle"
                ))
                return
            }
            setModelLoadState(.ready, reason: "init-preload-success")
        } catch {
            PersistentLog.log(.engineWarmUpFailed(
                context: "init-preload",
                error: DictationFailureMessage.diagnostic(for: error)
            ))
            deadlineArm.cancel()
            guard !loadWasAbandoned(since: epoch), outcome.settle() else { return }
            setModelLoadState(.idle, reason: "init-preload-failed")
        }
    }

    /// Warm the engine when the app comes back to the foreground.
    ///
    /// WHY it lives here rather than inline in the `didBecomeActive` observer: what this
    /// decides is no longer "warm up" but "may we start a load the user did not ask
    /// for?", which is a model-load policy question and belongs beside the rest of them.
    func warmUpEngineOnForeground() async {
        guard !isAudioEngineRunning else {
            PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive-already-running"))
            return
        }
        guard defaults.bool(forKey: SharedKeys.modelReady) else {
            PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive", error: "modelReady=false"))
            return
        }

        // Returning to the foreground is not a request to retry a MODEL load the user
        // just walked away from (first review, finding 3). Without this, escaping the
        // preparation screen and then backgrounding the app — the natural thing to do
        // while waiting — restarted the very same compile, wrote `.loading` again, and
        // put the user straight back on the screen they had escaped, 45 seconds reset.
        //
        // WHAT IT MUST NOT SKIP is the audio session (audit finding 2). An earlier
        // version returned before `configureAudioSessionForWarmUp()`, so a stale
        // `abandonedModel` cost audio reconfiguration on every foreground return for the
        // rest of the process. The session is what #123 is about — a stale input node
        // reports `invalid hwFormat: sr=0.0 ch=2` — and it is cheap. Whatever happens to
        // the model, the audio path gets set up.
        let activeModel = defaults.string(forKey: SharedKeys.activeModel)
        let modelWasAbandoned = abandonedModel != nil && abandonedModel == activeModel

        let epoch = modelLoadEpoch
        do {
            try configureAudioSessionForWarmUp()

            if modelWasAbandoned {
                PersistentLog.log(.diagnosticProbe(
                    component: "ModelPreload",
                    instanceID: abandonedModel ?? "unknown",
                    action: "warmUpSkippedAfterAbandon",
                    details: "context=didBecomeActive audioSessionConfigured=true"
                ))
                return
            }

            setModelLoadState(.loading, reason: "didBecomeActive-warmup")
            _ = try await loadActiveModelIntoMemory(
                context: "didBecomeActive",
                attemptLog: .beforeModelLoad
            )
            PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive"))
            // Claim before publishing, as the launch preload does: this warm-up can be
            // abandoned mid-flight too, and `.ready` would then announce an engine that
            // was discarded before it was installed (finding 5).
            guard !loadWasAbandoned(since: epoch) else { return }
            setModelLoadState(.ready, reason: "didBecomeActive-success")
        } catch {
            PersistentLog.log(.engineWarmUpFailed(
                context: "didBecomeActive",
                error: DictationFailureMessage.diagnostic(for: error)
            ))
            guard !loadWasAbandoned(since: epoch) else { return }
            setModelLoadState(.idle, reason: "didBecomeActive-failed")
        }
    }

    /// Wait for the Neural Engine to be free of any Core ML compile, then take it.
    ///
    /// Balanced by `releaseNeuralEngine(from:)`, and every caller must balance it —
    /// `defer` is the only safe way to do that, because the work in between can throw.
    ///
    /// WHY POLLING: it is the idiom `ModelManager` already used for the same job, it
    /// composes with `@MainActor` without a continuation, and the thing being waited on
    /// takes minutes. A 500ms granularity costs nothing against a 200s compile.
    ///
    /// The check and the take are not separated by a suspension point, so no two callers
    /// can leave this function holding the engine at once.
    ///
    /// `try await` ON THE SLEEP, NEVER `try?`. This is measured, not argued: `Task.sleep`
    /// throws the instant its task is cancelled, so swallowing that error stops the
    /// waiting and turns this poll into a spin — 105,533 iterations in the first second
    /// after cancellation, against 3 in 1.2s while healthy, on the main actor, for as
    /// long as the holder holds it. A first Turbo compile holds it for about 200s. It is
    /// not a deadlock and other main-actor work still interleaves; it simply burns the
    /// main actor, the battery and the thermal budget for the length of a compile.
    /// `develop` never had this — its version of this wait used `try await`.
    func acquireNeuralEngine(for holder: String) async throws {
        if let current = neuralEngineHolder, current != holder {
            PersistentLog.log(.diagnosticProbe(
                component: "NeuralEngine",
                instanceID: holder,
                action: "queuedBehindCompile",
                details: "heldBy=\(current)"
            ))
        }
        // The deferral covers THIS wait and nothing else (CodeRabbit, on the fix for
        // fourth-review finding 2). It is raised only when somebody else already holds
        // the gate, and it comes down when this loop ends — which is the moment the
        // caller takes the hardware and starts being responsible for its own progress.
        let deferralIsOurs = isInsideEngineLoadForDictation && neuralEngineHolder != nil
        if deferralIsOurs { isWaitingForNeuralEngine = true }
        defer { if deferralIsOurs { isWaitingForNeuralEngine = false } }

        while neuralEngineHolder != nil {
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        // A waiter cancelled while the engine was free — or on the same turn it came
        // free — must not go on to take it. The work it was queued for is gone, and the
        // compile it would start cannot be cancelled once begun: it would hold the
        // engine, and make the next real load queue behind a dictation the user stopped.
        try Task.checkCancellation()
        neuralEngineHolder = holder
    }

    /// What the model load flag must say once a dictation has failed (issue #427).
    ///
    /// The rule itself is `ModelLoadState.afterFailedDictation`, in DictusCore where it
    /// is unit-tested. This is the half that needs the coordinator: the identifier whose
    /// engine is actually in RAM is the caller's to supply, because it is `private` to
    /// `DictationCoordinator.swift`, and the active model comes from the App Group.
    ///
    /// - Parameter published: the model whose engine is loaded right now, or nil.
    func modelLoadStateAfterFailedDictation(published: String?) -> ModelLoadState {
        ModelLoadState.afterFailedDictation(
            publishedModel: published,
            activeModel: defaults.string(forKey: SharedKeys.activeModel)
        )
    }

    /// Give the Neural Engine back, if this holder still has it.
    ///
    /// The identity check makes a mismatched release a no-op rather than a way to hand
    /// somebody else's compile away — the same reasoning as `clearInitTask(ifStillCurrent:)`.
    func releaseNeuralEngine(from holder: String) {
        if neuralEngineHolder == holder { neuralEngineHolder = nil }
    }

    /// Wait until no engine init is in flight, and report whether the one that finished
    /// has already done this caller's work.
    ///
    /// WHY WAIT rather than take the lock away (issue #428 review, finding 2): the
    /// Neural Engine cannot compile two models at once. `ModelManager` serialises its
    /// own prewarms for exactly that reason — simultaneous compiles produce the "E5
    /// bundle" failure — and `ensureEngineReady` is not covered by that lock. An
    /// abandoned compile cannot be stopped, so the only safe thing a later caller can do
    /// is queue behind it. An earlier version of the escape cleared the lock instead,
    /// which meant "choose another model after escaping" started a second compile on
    /// top of the first: a lockout traded for a hardware-level failure.
    ///
    /// DO NOT "IMPROVE" THIS BY CLEARING THE LOCK AGAIN. The trade was made deliberately
    /// and it is not close. Waiting costs a bounded, measured delay: a cold Turbo compile
    /// completed in 202s on the affected device, so the worst case is a couple of minutes
    /// before the next model starts loading. Clearing the lock costs an E5-class failure
    /// that nobody in this repo has ever reproduced on purpose — which also means nobody
    /// could debug it if a user hit it. A bounded wait beats an unbounded unknown.
    ///
    /// WHY A LOOP: `await` is a suspension point, and another caller may have installed
    /// a lock of its own while this one was parked. Going straight to the compile after
    /// a single wait would be the double compile this exists to prevent.
    ///
    /// - Returns: `true` when the caller can return immediately because the load that
    ///   just finished was the one it wanted.
    func awaitInFlightEngineInit(
        modelName: String,
        component: String,
        isAlreadyLoaded: () -> Bool
    ) async throws -> Bool {
        while let inFlight = initTask {
            let isCurrentGeneration = initTaskEpoch == modelLoadEpoch
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Engine init already in progress — awaiting existing task")
            }
            do {
                try await inFlight.value
                // Only a load of the current generation can have loaded our model: an
                // abandoned one discarded its engine rather than publishing it.
                if isCurrentGeneration, isAlreadyLoaded() {
                    return true
                }
            } catch {
                // A load the app is still waiting for rethrows to every awaiter, so it
                // is localised here too (issue #249) — a cold start that piggybacks on
                // the launch preload takes this branch. An abandoned load's failure is
                // not this caller's failure: it is noted and stepped over.
                if isCurrentGeneration {
                    throw Self.loadFailure(for: modelName, from: error)
                }
                PersistentLog.log(.diagnosticProbe(
                    component: component,
                    instanceID: modelName,
                    action: "waitedOutAbandonedLoad",
                    details: "reason=\(Self.loadFailure(for: modelName, from: error).diagnosticDescription)"
                ))
            }
            clearInitTask(ifStillCurrent: inFlight)
        }
        return false
    }

    /// Release the engine-init lock, but only if it still points at `task`.
    ///
    /// WHY the identity check: an abandoned load eventually completes and runs its own
    /// cleanup. A bare `initTask = nil` there would clear whatever task a *newer* load
    /// had since installed, and the caller after that would see no lock, start a second
    /// init, and put two Core ML compiles on the Neural Engine at once.
    func clearInitTask(ifStillCurrent task: Task<Void, Error>) {
        if initTask == task { initTask = nil }
    }

    /// Wrap a raw engine error for the caller, without flattening an abandonment.
    ///
    /// Everything WhisperKit, FluidAudio and Core ML raise is English and
    /// developer-facing, and `handleError` writes whatever reaches it straight into the
    /// keyboard's banner, so it is localised on the way out (issue #249). An
    /// abandonment is already ours, already localised, and says something different and
    /// more actionable than "the model could not be loaded": nothing is broken, the app
    /// simply stopped waiting, and tapping again works (issue #428).
    static func loadFailure(for modelName: String, from error: Error) -> SpeechModelError {
        if let speechError = error as? SpeechModelError, speechError.isLoadAbandoned {
            return speechError
        }
        return SpeechModelError.engineLoadFailed(identifier: modelName, underlying: error)
    }

    /// Whether a load that has just produced an engine is still the one the app wants.
    ///
    /// TWO questions, and only the second one is about abandonment.
    ///
    /// An engine is wrong to publish when it is for a model the user has since moved
    /// off: doing so would dictate with a model they did not pick and leave
    /// `currentModelName` disagreeing with `activeModel` with nothing to reconcile them.
    /// That is what the epoch was introduced to prevent.
    ///
    /// An engine is NOT wrong to publish merely because the app stopped waiting for it.
    /// Gating on the epoch alone conflated the two and cost a working dictation (second
    /// review, finding 1): a keyboard cold start parks on the launch preload's task by
    /// the #167 rule; the deadline expires at 120s and bumps the epoch; the compile then
    /// SUCCEEDS at 150s and was thrown away, failing the parked recording with
    /// "preparation was interrupted" — a dictation that transcribed normally before this
    /// branch existed. The deadline's job is to free the UI, never to fail a model.
    ///
    /// So a load still carrying the active model publishes, whatever the epoch says.
    func shouldPublishLoad(epoch: Int, component: String, modelName: String) -> Bool {
        if epoch == modelLoadEpoch { return true }

        // The epoch moved on, but that alone does not make this engine the wrong one.
        if modelName == defaults.string(forKey: SharedKeys.activeModel) {
            PersistentLog.log(.diagnosticProbe(
                component: component,
                instanceID: modelName,
                action: "publishedLateLoad",
                details: "epoch=\(epoch) current=\(modelLoadEpoch) stillActiveModel=true"
            ))
            return true
        }

        PersistentLog.log(.diagnosticProbe(
            component: component,
            instanceID: modelName,
            action: "discardedAbandonedLoad",
            details: "epoch=\(epoch) current=\(modelLoadEpoch) activeModel=\(defaults.string(forKey: SharedKeys.activeModel) ?? "nil")"
        ))
        return false
    }

    /// Mark that a dictation is inside the engine load, so `acquireNeuralEngine` knows
    /// a queue wait it is about to enter belongs to one.
    ///
    /// This flag is NOT what the watchdog reads, and the difference is the whole point.
    /// An earlier version raised the watchdog deferral here, around the entire call —
    /// which meant that once a dictation reached this line the watchdog could never act
    /// again, including when the dictation acquired the hardware itself and its OWN
    /// compile hung. That is an unbounded hang with no recovery: the exact shape of the
    /// bug this branch exists to remove, re-created by the fix for it.
    ///
    /// The rule the watchdog needs is narrower: **defer only while ANOTHER holder owns
    /// the gate.** The moment this caller takes it, the work is its own and the watchdog
    /// must be allowed to do its job. So the deferral is raised inside the queue wait
    /// (see `acquireNeuralEngine`) and comes down the instant the gate is taken.
    func waitingForNeuralEngine<T>(_ work: () async throws -> T) async rethrows -> T {
        isInsideEngineLoadForDictation = true
        defer { isInsideEngineLoadForDictation = false }
        return try await work()
    }

    /// Whether a fired stage watchdog should be deferred rather than acted on.
    ///
    /// A stage queued behind a Core ML compile is not a stalled stage. The recording is
    /// captured and safe, the wait ends when the hardware frees, and cancelling here
    /// threw away a dictation the user had already finished speaking (finding 2). The
    /// watchdog is for a stage that will never hand over; this one will.
    ///
    /// STRICTLY WHILE ANOTHER HOLDER OWNS THE GATE. A dictation that has taken the
    /// hardware itself is responsible for its own progress again, and if its compile
    /// hangs the watchdog must be free to act — otherwise deferring here turns a
    /// recoverable failure into an unbounded one, which is what this branch is about.
    func shouldDeferStageWatchdog(for status: DictationStatus) -> Bool {
        guard isWaitingForNeuralEngine else { return false }
        PersistentLog.log(.diagnosticProbe(
            component: "NeuralEngine",
            instanceID: status.rawValue,
            action: "stageWatchdogDeferred",
            details: "waitingForCompile=true recordingPreserved=true"
        ))
        return true
    }

    /// Wrap a freshly loaded `WhisperKit` and warm it, ready to be published (#426).
    ///
    /// A seam rather than three lines at the call site for the reason this whole file
    /// exists: `DictationCoordinator.swift` sits at the file-length budget issue #146
    /// calibrated against it. It also keeps the ordering rule in one place — the engine
    /// is warm before anyone can reach it.
    func warmedWhisperKitEngine(for kit: WhisperKit, modelName: String) async -> WhisperKitEngine {
        let engine = WhisperKitEngine()
        engine.setWhisperKit(kit)
        await runWarmInference(on: engine, modelName: modelName)
        return engine
    }

    /// The Parakeet counterpart: load from the local cache, then warm, then hand back.
    @available(iOS 17.0, *)
    func warmedParakeetEngine(modelName: String) async throws -> ParakeetEngine {
        let engine = ParakeetEngine()
        try await engine.prepare(modelIdentifier: modelName)
        await runWarmInference(on: engine, modelName: modelName)
        return engine
    }

    /// Give up on a load whose engine is not going to be published.
    ///
    /// Clears the warm-inference claim on the way out: nothing in this process is warm
    /// for a model whose engine was discarded, and saying otherwise would make the next
    /// load of it skip the warm inference entirely.
    ///
    /// Returns the error rather than throwing it, so the call site keeps the `throw` in
    /// view. That matters here: a plain `return` from the shared init task reads as a
    /// loaded engine to every caller parked on it (issue #428 review, finding 1).
    func abandonedLoadError(for modelName: String) -> SpeechModelError {
        warmInferenceLedger.release(ifMatches: modelName)
        return SpeechModelError.loadAbandoned(identifier: modelName)
    }

    /// Run the discarded inference that turns a loaded model into a ready one (#426).
    ///
    /// WHY IT NEVER THROWS. A warm inference is an optimisation, and a load that
    /// produced a working engine must not be failed because the optimisation did not
    /// take. If it throws, the engine is published anyway and the first real
    /// transcription pays the specialization exactly as it did before this existed —
    /// the old behaviour, not a broken one. A cancelled load takes this branch too:
    /// `WhisperKit.transcribe` checks cancellation between its stages.
    ///
    /// WHY THE LEDGER RATHER THAN THE CALL SITE. Every caller reaches this from inside
    /// the engine-load task, which only runs on a genuine load, so the once-per-load
    /// rule is already true by construction — `warmUpEngineOnForeground` returns at
    /// `ensureWhisperKitEngineReady`'s "already loaded" guard and never gets here, which
    /// is what stops a repeated foregrounding from buying a throwaway inference every
    /// time the user comes back. The ledger states that rule instead of leaving it
    /// implicit in a control-flow accident, and it is the one piece of this that can be
    /// tested off-device, where no Core ML model can be loaded at all.
    ///
    /// The `ms=` in the completed line is the measurement #426 asks for, and it is also
    /// the only way to tell a real warm inference from one that silently did nothing:
    /// a figure near zero means the buffer never reached the encoder.
    func runWarmInference(on engine: SpeechModelProtocol, modelName: String) async {
        guard warmInferenceLedger.claim(modelName) else {
            PersistentLog.log(.diagnosticProbe(
                component: "WarmInference",
                instanceID: modelName,
                action: "skipped",
                details: "reason=alreadyWarm engine=\(engine.engineName)"
            ))
            return
        }

        let start = Date()
        do {
            try await engine.runWarmInference()
            PersistentLog.log(.diagnosticProbe(
                component: "WarmInference",
                instanceID: modelName,
                action: "completed",
                details: "ms=\(Int(Date().timeIntervalSince(start) * 1000)) engine=\(engine.engineName) samples=\(WarmInferenceAudio.sampleCount)"
            ))
        } catch {
            // Not warm after all, so do not remember it as warm: the next load of this
            // model has to be allowed to try again.
            warmInferenceLedger.release(ifMatches: modelName)
            PersistentLog.log(.diagnosticProbe(
                component: "WarmInference",
                instanceID: modelName,
                action: "failed",
                details: "ms=\(Int(Date().timeIntervalSince(start) * 1000)) engine=\(engine.engineName) error=\(DictationFailureMessage.diagnostic(for: error))"
            ))
        }
    }

    /// Forget that a model was abandoned, once a load of it has actually succeeded.
    ///
    /// WHY it has to be cleared at all (audit finding 2): a load can be abandoned by its
    /// deadline and then finish anyway — which, since the publish gate learned to accept
    /// a load still carrying the active model, is now the COMMON outcome rather than a
    /// rare one. The engine is installed and working, and nothing was reconciling the
    /// memory that said otherwise. It would have gone on suppressing the foreground
    /// warm-up for the rest of the process, for a model that had been ready for minutes.
    func clearAbandonedModel(ifMatches modelName: String) {
        guard abandonedModel == modelName else { return }
        abandonedModel = nil
        PersistentLog.log(.diagnosticProbe(
            component: "ModelPreload",
            instanceID: modelName,
            action: "abandonMemoryCleared",
            details: "reason=loadSucceededAnyway"
        ))
    }

    /// Whether anything abandoned a load since `epoch` was captured.
    ///
    /// Read-only, and that is the point (second review, finding 5). This used to be a
    /// claim that bumped the epoch on its way out, including on the happy path, which
    /// made the epoch mean two things at once: "someone gave up" and "someone finished".
    /// A load created in the window between another load completing and claiming
    /// captured the pre-bump value and was then discarded as abandoned — leaving the
    /// state `.ready` for one model while `currentModelName` held another, and the
    /// preparation screen dismissing on a model that was not loaded.
    ///
    /// The epoch now moves for exactly one reason: a load was abandoned. Deciding which
    /// of two racing arms publishes is a different question, and `LaunchPreloadOutcome`
    /// answers it without touching state other loads read.
    func loadWasAbandoned(since epoch: Int) -> Bool {
        epoch != modelLoadEpoch
    }
}
