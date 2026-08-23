// DictusCore/Sources/DictusCore/DictationOrigin.swift
import Foundation

/// Who asked for a dictation, and therefore who finishes it (#361 decision 4).
///
/// Both origins run the same `PolishPipeline`; what differs is the process that
/// runs it. A keyboard dictation is polished by the keyboard extension, which is in
/// the foreground at exactly the moment the model runs — the whole point of #361. A
/// dictation started inside DictusApp is already foreground and has never had that
/// problem, so it keeps polishing in place.
///
/// WHY it has to be carried rather than derived: `startDictation()` is reached from
/// the keyboard's Darwin notification and from the app's own record button through
/// the same signature, and `stopDictation()` cannot tell them apart afterwards.
/// `UIApplication.applicationState` is the closest available proxy and is not one —
/// it describes when the user stopped, not who started.
public enum DictationOrigin: String, Codable, Sendable {
    /// Requested by the keyboard extension, over Darwin or the `dictus://dictate`
    /// URL. The result is typed into a host app's text field.
    case keyboard
    /// Started inside DictusApp. The result is shown in the app.
    case app
}
