// DictusApp/DictationCoordinator+ModelLoad.swift
// The launch preload's deadline, and giving up on a load that will not finish (#428).
//
// WHY a file of its own: DictationCoordinator.swift sits at the file-length budget that
// issue #146 calibrated against it, and that budget exists to catch exactly this — the
// file growing again. Everything here reaches the coordinator through two named seams
// (`loadActiveModelIntoMemory`, `releaseEngineInitLock`) plus the load epoch, so moving
// it out did not mean opening up the coordinator's private state.
import Foundation
import DictusCore

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
        let epoch = modelLoadEpoch

        setModelLoadState(.loading, reason: "init-preload")

        // The deadline arm. An independent task, NOT a child in a task group, and that
        // is the entire point.
        //
        // WHY NOT `withPrewarmTimeout`: issue #427 measured what that primitive actually
        // does. It races a sleep against the compile inside a throwing task group, and a
        // task group cannot return until every child has finished — so the deadline
        // error surfaces only once the compile it was meant to bound has completed
        // anyway. A 5s budget reported failure after 212s. `cancelAll()` does not help
        // either: cancellation is a request, and a Core ML compile checks no flag and
        // offers no suspension point at which it could notice one.
        //
        // That is not only a lab result. The maintainer's device log shows the old
        // guard firing in the wild exactly this way: `modelPrewarmTimeout timeout=5s`
        // logged 212 seconds after the compile it names started, because the group it
        // was racing in could not return until that compile did. A budget that only
        // reports lateness after the fact is worth nothing to the user waiting.
        //
        // So this deadline interrupts nothing, and no deadline can. The compile keeps
        // running and keeps burning CPU until it finishes on its own. What expiry buys
        // is the only thing ever available: the app stops *waiting*. `modelLoadState`
        // goes back to idle, the keyboard stops refusing mic taps, and the preparation
        // screen stops covering the app.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(deadlineSeconds) * 1_000_000_000)
            guard let self, self.claimModelLoadOutcome(epoch: epoch) else { return }
            // Remember what we gave up on, so returning to the foreground does not
            // quietly start the same compile again (finding 3).
            self.abandonedModel = modelName
            self.setModelLoadState(.idle, reason: "init-preload-deadline")
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
            let loadedName = try await loadActiveModelIntoMemory(context: "init-preload")
            PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
            guard claimModelLoadOutcome(epoch: epoch) else {
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
                error: error.localizedDescription
            ))
            guard claimModelLoadOutcome(epoch: epoch) else { return }
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

        // Returning to the foreground is not a request to retry a load the user just
        // walked away from (finding 3). Without this, escaping the preparation screen
        // and then backgrounding the app — the natural thing to do while waiting —
        // restarted the very same compile, wrote `.loading` again, and put the user
        // straight back on the screen they had escaped, with the 45 seconds reset.
        let activeModel = defaults.string(forKey: SharedKeys.activeModel)
        if let abandoned = abandonedModel, abandoned == activeModel {
            PersistentLog.log(.diagnosticProbe(
                component: "ModelPreload",
                instanceID: abandoned,
                action: "warmUpSkippedAfterAbandon",
                details: "context=didBecomeActive"
            ))
            return
        }

        let epoch = modelLoadEpoch
        do {
            try configureAudioSessionForWarmUp()
            setModelLoadState(.loading, reason: "didBecomeActive-warmup")
            _ = try await loadActiveModelIntoMemory(context: "didBecomeActive")
            PersistentLog.log(.engineWarmUpSuccess(context: "didBecomeActive"))
            // Claim before publishing, as the launch preload does: this warm-up can be
            // abandoned mid-flight too, and `.ready` would then announce an engine that
            // was discarded before it was installed (finding 5).
            guard claimModelLoadOutcome(epoch: epoch) else { return }
            setModelLoadState(.ready, reason: "didBecomeActive-success")
        } catch {
            PersistentLog.log(.engineWarmUpFailed(
                context: "didBecomeActive",
                error: error.localizedDescription
            ))
            guard claimModelLoadOutcome(epoch: epoch) else { return }
            setModelLoadState(.idle, reason: "didBecomeActive-failed")
        }
    }

    /// Stop waiting for the model load in flight, at the user's request (issue #428).
    ///
    /// Called when the user takes the escape the preparation screen offers after
    /// `ModelPreparationEscape.revealDelaySeconds`.
    ///
    /// THIS DOES NOT STOP THE COMPILE, and nothing can: a Core ML compile checks no
    /// cancellation flag and offers no suspension point at which it could. The Core ML
    /// work keeps running and keeps burning CPU until it finishes on its own. What this
    /// does is unpick every way that work was holding the app hostage:
    ///   - bumping the epoch makes the abandoned load discard its result instead of
    ///     swapping the engine under whatever model the user picks next, and makes it
    ///     fail its awaiters rather than hand them an engine that was thrown away;
    ///   - `.idle` lets the keyboard accept a mic tap again, and stops the views that
    ///     auto-present the screen from re-covering the one the user just left;
    ///   - remembering the model stops `didBecomeActive` restarting the same compile
    ///     the moment the user backgrounds the app and comes back (finding 3).
    ///
    /// WHAT IT DELIBERATELY DOES NOT DO is take the init lock away. An earlier version
    /// did, and that was worse than the bug it fixed: the abandoned compile keeps
    /// running, the Neural Engine cannot compile two models at once, and a model picked
    /// straight afterwards would have started a second compile on top of it — the "E5
    /// bundle" failure `ModelManager` serialises its own prewarms to avoid (finding 2).
    /// So the next load queues behind the abandoned one instead. The user gets their
    /// app back immediately, which is what this is for; they get their next model when
    /// the hardware is free, which is the most anyone can offer.
    func abandonInFlightModelLoad(reason: String) {
        let modelName = defaults.string(forKey: SharedKeys.activeModel) ?? "unknown"
        modelLoadEpoch += 1
        abandonedModel = modelName
        setModelLoadState(.idle, reason: reason)
        PersistentLog.log(.diagnosticProbe(
            component: "ModelPreload",
            instanceID: modelName,
            action: "abandonedByUser",
            details: "reason=\(reason) compileStillRunning=true nextLoadQueuesBehindIt=true"
        ))
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
    /// A Core ML compile cannot be stopped, so a load may finish minutes after the user
    /// gave up on it and chose another model. Publishing it then would make the app
    /// dictate with a model the user did not pick, and leave `currentModelName`
    /// disagreeing with `activeModel` with nothing to reconcile the two (issue #428).
    func shouldPublishLoad(epoch: Int, component: String, modelName: String) -> Bool {
        if epoch == modelLoadEpoch { return true }
        PersistentLog.log(.diagnosticProbe(
            component: component,
            instanceID: modelName,
            action: "discardedAbandonedLoad",
            details: "epoch=\(epoch) current=\(modelLoadEpoch)"
        ))
        return false
    }

    /// Take ownership of the outcome for `epoch`, or report that someone already has.
    ///
    /// The arbiter of the race above: the load and its deadline both call it, the first
    /// one wins, and the loser writes nothing. Claiming bumps the epoch, so any load
    /// still running against the claimed generation is left unable to publish — which is
    /// exactly what an abandoned load should be.
    func claimModelLoadOutcome(epoch: Int) -> Bool {
        guard epoch == modelLoadEpoch else { return false }
        modelLoadEpoch += 1
        return true
    }
}
