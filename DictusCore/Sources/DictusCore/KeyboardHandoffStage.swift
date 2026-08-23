// DictusCore/Sources/DictusCore/KeyboardHandoffStage.swift
// Whether the keyboard may draw a status DictusApp wrote, while the keyboard owns
// the rest of the dictation (issue #361). Pure decision -- no view, no App Group.

import Foundation

/// Keeps the keyboard from drawing the end of a dictation that is not over.
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

    /// Whether the keyboard should adopt `stored` as its stage.
    ///
    /// - Parameters:
    ///   - stored: what `SharedKeys.dictationStatus` says.
    ///   - drawing: the stage this keyboard is currently showing.
    ///   - handoffOutstanding: whether a raw transcription is still this keyboard's to
    ///     finish — claimed and being polished, or written and not yet claimed.
    public static func adopts(stored: DictationStatus,
                              drawing current: DictationStatus,
                              handoffOutstanding: Bool) -> Bool {
        guard handoffOutstanding else { return true }
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
