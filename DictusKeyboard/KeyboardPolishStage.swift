// DictusKeyboard/KeyboardPolishStage.swift
// The `.processing` stage, held on the keyboard's own authority (issue #361).
import Foundation
import DictusCore

/// Since #361 the keyboard runs the polish engine, so it also owns the stage that
/// describes the wait. It sets `.processing` locally, with no round trip: this process
/// draws the overlay, so there is nobody to ask, and it is faster than what it
/// replaces rather than slower (decision 6).
///
/// WHY this is a file of its own: `KeyboardState` sits at SwiftLint's length budget,
/// and these two methods are one concern with one caller. `holdsLocalProcessingStage`
/// stays a stored property over there — extensions cannot hold one — and carries a
/// note saying why it is not `private`.
extension KeyboardState {

    /// Draw the LLM stage.
    ///
    /// Called from inside the polish call, once a model is really about to run: every
    /// gate that can skip it — the toggle, the duration gate, the gibberish gate, a
    /// passthrough backend, the #315 availability gate — has been cleared by then, so
    /// the stage marks a wait that is really happening rather than one that might
    /// (#267). Announcing it for the pass-through paths, which return in about a
    /// millisecond, would flash a label and a new animation for a single frame.
    func beginLocalProcessingStage() {
        holdsLocalProcessingStage = true
        dictationStatus = .processing
    }

    /// Release the stage with no insertion behind it — the generation was refused by
    /// decision 7's identity check, or superseded.
    ///
    /// Re-reads the App Group, which is the authority again from here: it says `ready`
    /// if the app is still holding that, or `idle` if its 10 s watchdog has already
    /// brought the dictation home. Either way the overlay comes down, which is the
    /// point — nothing is coming to fill it.
    func endLocalProcessingStage() {
        guard holdsLocalProcessingStage else { return }
        holdsLocalProcessingStage = false
        refreshFromDefaults()
    }
}
