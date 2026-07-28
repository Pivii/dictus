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

/// Single owner of the App Group contract for `ModelLoadState`.
///
/// WHY a store rather than two processes poking UserDefaults directly: since
/// issue #250 the state travels with a transition timestamp, and the keyboard
/// needs that timestamp to tell a load that started moments ago from a
/// `loading` value stranded by a force-quit. Keeping the write and the read in
/// one place is what guarantees the two always agree on the pairing.
///
/// The tri-state semantics themselves are unchanged (#144): `loading` still
/// means "mic taps MUST be refused".
public enum ModelLoadStateStore {

    /// Persist a new state together with the moment it changed.
    /// Callers are expected to have checked that the value actually changed —
    /// re-writing the same state would reset the age of an ongoing load.
    public static func write(_ state: ModelLoadState, to defaults: UserDefaults) {
        defaults.set(state.rawValue, forKey: SharedKeys.modelLoadState)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.modelLoadStateChangedAt)
        defaults.synchronize()
    }

    /// Read the state and, when available, when it was written.
    ///
    /// `changedAt` is nil when no timestamp is stored — a state written by a
    /// build older than #250. Consumers must treat that as "age unknown" and
    /// fall back to their own observation time rather than assuming it is fresh.
    public static func read(from defaults: UserDefaults) -> (state: ModelLoadState, changedAt: Date?) {
        let raw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        let state = ModelLoadState(rawValue: raw) ?? .idle
        let stamp = defaults.double(forKey: SharedKeys.modelLoadStateChangedAt)
        return (state, stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil)
    }
}
