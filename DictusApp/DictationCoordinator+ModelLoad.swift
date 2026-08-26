// DictusApp/DictationCoordinator+ModelLoad.swift
// Giving up on a model load that will not finish (#428).
//
// WHY a file of its own: DictationCoordinator.swift sits at the file-length budget that
// issue #146 calibrated against it, and that budget exists to catch exactly this — the
// file growing again. Everything here reaches the coordinator through named seams
// (`releaseEngineInitLock`) plus the load epoch, so moving it out did not mean opening
// up the coordinator's private state.
import Foundation
import DictusCore

extension DictationCoordinator {

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
}
