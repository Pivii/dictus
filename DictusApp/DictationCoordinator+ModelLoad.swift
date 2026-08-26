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
            // Release the dedupe lock so a model the user picks next can actually load,
            // instead of awaiting the compile this deadline just gave up on.
            self.releaseEngineInitLock()
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
            let loadedName = try await loadActiveModelIntoMemory()
            PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
            guard claimModelLoadOutcome(epoch: epoch) else {
                // Late, but not wasted: the engine is loaded and the next dictation will
                // use it. The state stays idle, which is true — nothing is in flight any
                // more — and idle is what lets the keyboard accept a mic tap.
                PersistentLog.log(.diagnosticProbe(
                    component: "ModelPreload",
                    instanceID: modelName,
                    action: "completedAfterDeadline",
                    details: "engineLoaded=true state=idle"
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
    ///     swapping the engine under whatever model the user picks next;
    ///   - releasing the init lock means the next `ensureEngineReady` starts a load
    ///     rather than awaiting the hung one, so the user's new choice can arrive;
    ///   - `.idle` lets the keyboard accept a mic tap again, and stops the views that
    ///     auto-present the screen from re-covering the one the user just left.
    func abandonInFlightModelLoad(reason: String) {
        let modelName = defaults.string(forKey: SharedKeys.activeModel) ?? "unknown"
        modelLoadEpoch += 1
        releaseEngineInitLock()
        setModelLoadState(.idle, reason: reason)
        PersistentLog.log(.diagnosticProbe(
            component: "ModelPreload",
            instanceID: modelName,
            action: "abandonedByUser",
            details: "reason=\(reason) compileStillRunning=true"
        ))
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
