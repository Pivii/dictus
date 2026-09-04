// DictusCore/Sources/DictusCore/ModelLoadState.swift
import Foundation

/// Tri-state lifecycle for the active transcription model.
/// Written to App Group UserDefaults under `SharedKeys.modelLoadState` so the
/// keyboard extension can refuse mic taps while the app is busy loading the
/// model into RAM (issue #144 — fixes the cascade of `Swift.CancellationError`
/// when a user taps the mic during a turbo model swap).
public enum ModelLoadState: String, Codable {
    /// No load in flight. `modelReady` reflects whether a model is on disk.
    case idle
    /// WhisperKit/Parakeet is being loaded into RAM (or compiling/downloading).
    /// Mic taps from the keyboard MUST be refused while in this state.
    case loading
    /// Active model is loaded in RAM and ready to transcribe.
    case ready
}

public extension ModelLoadState {
    /// Reset a persisted `loading` that no live process can be responsible for.
    ///
    /// THE INVARIANT: a process that has just started cannot have a load in flight.
    /// `loading` describes a WhisperKit/Parakeet init running *inside a process*;
    /// nothing about it survives that process. So a `loading` read at launch, before
    /// this launch has started anything, is always a claim left behind by a previous
    /// process that was force-quit, jetsammed or crashed mid-compile.
    ///
    /// WHY this has to exist (issue #428): the value is persisted in the App Group and
    /// nothing ever cleared it. The keyboard reads it to decide whether to open Dictus
    /// with `intent=prepare`, and that intent makes `MainTabView` replace the whole tab
    /// bar with the preparation screen. One interrupted Turbo compile therefore locked
    /// the user out of Settings, out of the model list, and out of any way to choose a
    /// different model — on that launch and on every launch after it.
    ///
    /// WHY `ready` is deliberately left alone even though it is just as stale: it is
    /// also a claim about RAM this process does not have, but believing it costs at
    /// most one lazy load on the next dictation. Believing `loading` costs the whole
    /// app. Only the value that can lock the user out is corrected here.
    ///
    /// - Returns: whether a stale value was actually found and reset, so the caller
    ///   can log the correction rather than log on every launch.
    @discardableResult
    static func clearStaleLoadingState(in defaults: UserDefaults) -> Bool {
        guard defaults.string(forKey: SharedKeys.modelLoadState) == ModelLoadState.loading.rawValue else {
            return false
        }
        defaults.set(ModelLoadState.idle.rawValue, forKey: SharedKeys.modelLoadState)
        defaults.synchronize()
        return true
    }

    /// What a dictation that failed writes to this flag.
    ///
    /// THE RULE, and it is the one this whole type is built on: the flag describes the
    /// MODEL, not the dictation. A dictation is one session and it fails for its own
    /// reasons; the engine it was waiting for either is in RAM afterwards or is not,
    /// and that fact outlives the session. So a failed dictation may only write `.idle`
    /// when nothing is loaded. When an engine for the active model is published,
    /// `.idle` is a false statement about RAM, and both readers act on it: the loading
    /// overlay (issue #144) and the keyboard's cold-start routing (issue #262).
    ///
    /// WHY THIS BECAME REACHABLE (issue #427): before the prewarm deadline was made
    /// detachable, a load the app had given up on could not come back. It can now — it
    /// lands, publishes its engine and writes `.ready` — and the very cancellation that
    /// abandoning it produced fails the cold-start dictation that was waiting on it.
    /// Measured on device 2026-08-30, in the same second: `init-preload-late-success`
    /// setting `.ready`, then `cold-start-failed` setting `.idle` over the top of it,
    /// with the engine loaded and running.
    ///
    /// It also fixes a quieter case that was always there: a dictation failing before
    /// its model load (a microphone denial, an audio engine that will not start) used
    /// to write `.idle` over a model that had been warm since the previous dictation.
    ///
    /// A nil `activeModel` returns `.idle` whatever is published, for the reason issue
    /// #433 gave `isModelReady` the same shape: a downloaded model nobody has elected
    /// is not a model this app can dictate with.
    ///
    /// - Parameters:
    ///   - publishedModel: the identifier whose engine is currently in RAM, or nil.
    ///   - activeModel: the identifier the app would dictate with, or nil.
    static func afterFailedDictation(publishedModel: String?, activeModel: String?) -> ModelLoadState {
        guard let publishedModel, let activeModel, publishedModel == activeModel else {
            return .idle
        }
        return .ready
    }
}
