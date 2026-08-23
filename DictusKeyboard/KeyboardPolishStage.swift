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
        clearLocalProcessingStage()
        refreshFromDefaults()
    }

    /// Drop the stage when this keyboard is no longer in the document the generation
    /// belongs to (#361, device finding on `eae6c68`).
    ///
    /// `KeyboardState` is one singleton for the whole extension process, and the
    /// process follows the user from host app to host app. So a generation started in
    /// Messages survived a switch to another app, `refreshFromDefaults` short-circuited
    /// on the stage this process was still holding, and the polish overlay opened over
    /// a text field the insertion was then refused for:
    ///
    /// ```text
    /// KeyboardState BDD7111B refreshSkippedDuringPolish status=processing
    /// showsOverlayChanged isShowing=true status=processing
    /// polishInsertionRefused reason=different-document ageMs=7778
    /// ```
    ///
    /// Decision 7 refused the insertion; nothing refused the stage. The wait it draws
    /// is a lie the moment the answer is known, and the bound on it is the generation
    /// rather than anything in our control — #357 Q4 measured one resuming after
    /// forty-three minutes.
    ///
    /// Same reasoning decision 15 already applies to a superseded call: release at the
    /// moment the answer is known, not when the call returns.
    @MainActor
    func releasePolishStageIfFieldChanged() {
        guard KeyboardPolishCoordinator.shared.releaseIfFieldChanged() else { return }
        // Cleared without refreshing: this runs inside `registerControllerAppearance`,
        // which refreshes immediately afterwards. Refreshing here would re-enter it.
        clearLocalProcessingStage()
    }

    /// Forget the stage without re-reading the App Group. For callers that are about
    /// to refresh anyway.
    func clearLocalProcessingStage() {
        holdsLocalProcessingStage = false
    }

    /// Whether `stored` must not be drawn right now, and the side effect that implies.
    ///
    /// The rule itself is `KeyboardHandoffStage` in DictusCore, where it is tested
    /// against every status pair. What cannot live in a pure function is the second
    /// half of the decision: **a hold has to stop the app-liveness watchdog.** That
    /// watchdog judges DictusApp's heartbeat, and the app drops the heartbeat the
    /// moment it hands the dictation over — so left armed it reconciles a perfectly
    /// healthy dictation into "Recording interrupted" at five seconds, one second
    /// before a typical generation returns. There is nothing left for it to watch:
    /// the work is in this process now.
    func holdsHandoffStage(against stored: DictationStatus) -> Bool {
        guard !KeyboardHandoffStage.adopts(
            stored: stored,
            drawing: dictationStatus,
            handoffOutstanding: handoffIsOutstanding
        ) else { return false }
        stopWatchdog()
        logProbe("handoffStageHeld", details: "stored=\(stored.rawValue) \(sessionDetails())")
        return true
    }

    /// Whether a raw transcription is still this keyboard's to finish (#361).
    ///
    /// True from the moment DictusApp writes the hand-off until the keyboard has
    /// typed it or refused to: first the policy blob beside the unclaimed raw, then
    /// the pending record while the generation runs. Both are needed — the window
    /// between them is one main-queue turn wide, and a `.ready` adopted inside it is
    /// the same flash.
    var handoffIsOutstanding: Bool {
        AppGroup.defaults.data(forKey: SharedKeys.lastTranscriptionPolicy) != nil
            || PendingDictationChannel.current != nil
    }

    /// Decide what a transcription DictusApp just published is, and act on it.
    ///
    /// A hand-off carries the policy snapshot the keyboard needs to polish with; a
    /// dictation finished inside the app does not, and its text is already complete.
    /// That path predates #361 — the app has always broadcast its own results and a
    /// keyboard on screen has always typed them — and re-running the pipeline over it
    /// put app-origin events into the `<KBD>` half of the debug ring, which is the one
    /// thing the writer marker exists to keep clean.
    @MainActor
    func takeTranscription(_ transcription: String) {
        guard handoffIsOutstanding else {
            PersistentLog.log(.polishHandoff(
                step: "claimed", outcome: "not-a-handoff", chars: transcription.count
            ))
            insertDictation(transcription)
            return
        }
        KeyboardPolishCoordinator.shared.handle(raw: transcription)
    }
}
