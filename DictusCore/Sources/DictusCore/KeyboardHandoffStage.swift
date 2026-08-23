// DictusCore/Sources/DictusCore/KeyboardHandoffStage.swift
// Whether the keyboard may draw a status DictusApp wrote, while the keyboard owns
// the rest of the dictation (issue #361). Pure decision -- no view, no App Group.

import Foundation

/// Keeps the keyboard from drawing the end of a dictation that is not over, and from
/// drawing the middle of one it cannot finish here.
///
/// ### The frame this exists to suppress
///
/// Since #361 DictusApp finishes its half of a keyboard dictation by writing
/// `.ready` and posting `transcriptionReady`. It is telling the truth about itself:
/// the transcription IS ready. But the dictation is not over — the keyboard still has
/// to polish and type it — and the keyboard used to adopt that `.ready` anyway,
/// between `.transcribing` and its own `.processing`. Device capture on
/// 2026-08-23 (`eae6c68`), on every dictation in the run:
///
/// ```text
/// hostingSet_idle      old=276.0 new=52.0  status=ready
/// RecordingOverlay 2433F841 onDisappear    status=transcribing
/// hostingSet_recording old=52.0 new=276.0  status=processing
/// RecordingOverlay F316D939 onAppear       <-- a different instance
/// ```
///
/// The keyboard collapsed to typing height and expanded again inside one status hop,
/// destroying and rebuilding the overlay. That is a visible flash, and it cost the
/// transcription stage as well: `TranscribingStageHold` only holds when *another
/// stage* follows, and `.ready` is terminal, so the #309 floor never armed and a
/// 154-395 ms Parakeet transcription was drawn for a handful of frames.
///
/// ### And the frame that has to be let through
///
/// `KeyboardState` is one singleton for the whole extension process, and the process
/// follows the user from host app to host app. Holding on "a hand-off is outstanding"
/// alone therefore kept the overlay up in a stranger's document, drawing a wait for
/// text that would never be typed there (`eae6c68`, second finding of the same run).
///
/// So the hold is scoped to the document the dictation came from. That is the same
/// identity `PendingDictation.mayInsert(into:)` decides insertion by, asked one stage
/// earlier — and asking it here rather than acting on it is what keeps the two apart.
/// **Dropping the overlay must never cost the dictation.** The first attempt at this
/// cancelled the generation and cleared the record when the field changed, and on
/// device (`1bed468`) it fired 1.25 s after the claim, on a controller iOS rebuilt
/// while the user was still in transit to the home screen. He came straight back to
/// the same field and nothing arrived — neither the polished text nor the raw. The
/// issue's own principle is that a dictation degrades to raw insertion, never to
/// nothing.
///
/// The follow-up run (`c5c226c`) confirmed this rule behaves: the generation ran its
/// full 4,860 ms and the identity check decided at insertion time. It also showed the
/// identity check itself is coarser than decision 7 assumed — see
/// `PendingDictation.documentIdentifier`. That does not change anything here: this
/// rule decides what is drawn, and its correctness does not depend on how the identity
/// question is answered.
///
/// ### Why the rule is not "ignore .ready"
///
/// `.ready` is a real end for a dictation started inside DictusApp, and for one this
/// keyboard has already typed. What makes it a hand-off instead of an end is that
/// **the raw text is still waiting to be dealt with** — the caller establishes that
/// and passes it in, so this stays a pure function.
///
/// A hold implies one thing at the call site that is not expressible here: the
/// keyboard's app-liveness watchdog must be stopped. It exists to catch DictusApp
/// dying while the keyboard waits on it, and once the keyboard owns the tail there is
/// nothing to watch — the work is in this process, and the app has already dropped
/// the heartbeat that watchdog judges by. Left armed, it would reconcile a perfectly
/// healthy dictation into "Recording interrupted" at five seconds, one second before
/// a typical generation returns.
public enum KeyboardHandoffStage {

    /// What this keyboard still owes the dictation the App Group is describing.
    public enum Handoff: Equatable, Sendable {
        /// Nothing outstanding: no raw is waiting to be polished or typed.
        case none
        /// A raw is outstanding **and** this keyboard is in the document it came
        /// from, so the wait is one the user is here to see through.
        case here
        /// A raw is outstanding but this keyboard is somewhere else. The generation
        /// keeps running and is left to resolve on its own terms — what must not
        /// happen is drawing its wait over a document that will not receive it.
        ///
        /// Note that "somewhere else" is decided by an identifier scoped to the input
        /// session, so re-presenting the keyboard in the same field lands here too.
        /// That costs the dictation, which is accepted — see
        /// `PendingDictation.documentIdentifier`. What this case must never do is make
        /// it worse by tearing the record down on the way past.
        case elsewhere
    }

    /// Whether a controller may draw a stage this process set on its own authority.
    ///
    /// ### The frame this exists to suppress
    ///
    /// `KeyboardState` is a process-wide singleton and its `dictationStatus` outlives
    /// any one controller, so a freshly mounted `KeyboardRootView` renders whatever the
    /// singleton is holding. Device capture on `a4e7fa7`, three times in three minutes,
    /// on returning to an app where a dictation had been made:
    ///
    /// ```text
    /// KeyboardRootView 2DACE7B5 onAppear  status=processing visible=true
    /// viewWillAppear_entry                status=processing storedStatus=ready
    /// statusChanged from=processing to=ready
    /// ```
    ///
    /// A flash of the polish overlay before the normal keyboard appears. It is this
    /// issue's residue rather than a pre-existing bug: `status=processing
    /// storedStatus=ready` is exactly the state #361 created, because the stage became
    /// keyboard-local while the App Group kept saying `ready`. Before the move both
    /// said the same thing and there was nothing to be stale about.
    ///
    /// ### Why owning the keyboard area is not enough
    ///
    /// `KeyboardRootView` already refuses to draw for a controller that does not own
    /// the area. But ownership can be taken by a path that never reconciles:
    /// `KeyboardState.claimOwnership` deliberately does not call
    /// `refreshFromDefaults`, because it runs inside the area-mode subscription and
    /// refreshing there would re-enter it (#260). So a controller can become the owner,
    /// and draw, having never evaluated `adopts(stored:drawing:handoff:)` above.
    ///
    /// - Parameters:
    ///   - isLocallyOwned: whether the stage was set by this process rather than read
    ///     from the App Group.
    ///   - hasGenerationInFlight: whether a polish call is actually running.
    ///   - reconciledForThisController: whether the state has been read against the App
    ///     Group since this controller took the area.
    public static func drawsLocalStage(isLocallyOwned: Bool,
                                       hasGenerationInFlight: Bool,
                                       reconciledForThisController: Bool) -> Bool {
        // A stage that came from the App Group cannot be stale in this way: whatever
        // wrote it is the authority, and every controller reads the same value. Only a
        // locally-owned one can outlive the facts that justified it. Keeping this case
        // permissive is also what leaves #260's reclaim path working — a controller
        // claiming an ownerless area mid-recording draws immediately, as it must.
        guard isLocallyOwned else { return true }
        // No generation behind it means it is stale by construction, whoever asks.
        guard hasGenerationInFlight else { return false }
        return reconciledForThisController
    }

    /// Whether the keyboard should adopt `stored` as its stage.
    ///
    /// - Parameters:
    ///   - stored: what `SharedKeys.dictationStatus` says.
    ///   - drawing: the stage this keyboard is currently showing.
    ///   - handoff: what this keyboard still owes, and whether it is in the right
    ///     document to owe it.
    public static func adopts(stored: DictationStatus,
                              drawing current: DictationStatus,
                              handoff: Handoff) -> Bool {
        // Somewhere else, or nothing owed: adopting is what takes the overlay down,
        // which is exactly what both cases want.
        guard handoff == .here else { return true }
        // Only `.ready` is held back. `.failed` and `.idle` are real terminations that
        // have to reach the user or the keyboard would keep an overlay up over a
        // dictation that has been cancelled, interrupted or reconciled away — the
        // class of bug #260 and #261 are made of. `.ready` is the only status the
        // hand-off itself produces.
        guard stored == .ready else { return true }
        // And only while this keyboard is mid-dictation. A keyboard sitting at `.idle`
        // draws nothing either way, and holding there would leave it unable to adopt
        // anything for as long as some other surface's hand-off stayed outstanding.
        return !DictationSessionLivenessPolicy.isActive(current)
    }
}
