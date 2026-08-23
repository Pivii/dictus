// DictusKeyboard/KeyboardPolishStage.swift
// The `.processing` stage, held on the keyboard's own authority (issue #361).
import Foundation
import UIKit
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
        let handoff = outstandingHandoff
        guard !KeyboardHandoffStage.adopts(
            stored: stored,
            drawing: dictationStatus,
            handoff: handoff
        ) else { return false }
        stopWatchdog()
        logProbe(
            "handoffStageHeld",
            details: "stored=\(stored.rawValue) handoff=\(handoff) \(sessionDetails())"
        )
        return true
    }

    /// What this keyboard still owes the current dictation, and whether it is in the
    /// document it owes it to (#361).
    ///
    /// Outstanding from the moment DictusApp writes the hand-off until the keyboard
    /// has typed it or refused to: first the policy blob beside the unclaimed raw,
    /// then the pending record while the generation runs. Both are needed — the window
    /// between them is one main-queue turn wide, and a `.ready` adopted inside it is
    /// the same flash.
    ///
    /// The document is only compared once there is a record to compare against. In the
    /// unclaimed window there is no document on it yet, and the keyboard about to
    /// claim it is this one.
    ///
    /// **This reads nothing from the host unless something is outstanding.** The proxy
    /// read is a synchronous round trip, and this runs on every refresh — including
    /// from `viewWillAppear`, which `KeyboardLifecycleProbe` warns is the critical
    /// path of keyboard presentation.
    var outstandingHandoff: KeyboardHandoffStage.Handoff {
        if let pending = PendingDictationChannel.current {
            return pending.mayInsert(into: currentDocumentIdentifier) ? .here : .elsewhere
        }
        return AppGroup.defaults.data(forKey: SharedKeys.lastTranscriptionPolicy) != nil
            ? .here
            : .none
    }

    /// Whether a raw transcription is still this keyboard's to finish, wherever it is.
    var handoffIsOutstanding: Bool { outstandingHandoff != .none }

    /// The document this keyboard is editing right now, as a string, or nil.
    ///
    /// Goes through the ObjC shim: `documentIdentifier` imports into Swift as a
    /// non-optional `UUID` while the host is free to return nil, and reading it
    /// directly traps before the input session exists. See `TextProxyIdentity.m`.
    var currentDocumentIdentifier: String? {
        guard let proxy = controller?.textDocumentProxy else { return nil }
        return DictusTextProxyIdentity.documentIdentifier(of: proxy)?.uuidString
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
