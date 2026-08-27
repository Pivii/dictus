// DictusApp/Audio/DictationFailureMessage.swift
// The one place a thrown error becomes a sentence a user can read (#313).
import Foundation
import DictusCore

/// An error that carries two different texts: one written for the person holding the
/// phone, one written for whoever reads the log afterwards.
///
/// WHY the split is a protocol rather than a convention (#313):
/// `LocalizedError` has exactly one text slot, and every consumer reaches it through
/// `error.localizedDescription`. So the log line and the error banner were being served
/// by the same string, and whichever audience it was written for, it was wrong for the
/// other one. What actually shipped was the developer's version: an Austrian tester was
/// shown `Micro indisponible (Failed to create tap due to format mismatch, <AVAudioFormat
/// 0x1172f1220: 1 ch, 48000 Hz, Float32>)` (#417), and a mistimed mic tap produced
/// `Transcription failed: Parakeet: Invalid audio data provided. Must be at least 1 second
/// of 16kHz audio.` (#313, 2026-08-08).
///
/// `SpeechModelError` solved this for itself in #249. This is that solution named, so the
/// next error type inherits it instead of rediscovering it.
///
/// The rule, in one line: **`errorDescription` is the only thing a user may see, and
/// `diagnosticDescription` is the only thing that may name a component, a format or an
/// exception.**
protocol DiagnosableError: LocalizedError {
    /// English technical detail for `PersistentLog`. Never shown to the user.
    var diagnosticDescription: String { get }
}

/// Turns a thrown `Error` into the two texts a failure needs.
///
/// WHY a funnel and not `error.localizedDescription` at each `catch` (#313):
/// the catch sites in `DictationCoordinator` are the widest in the app — anything
/// WhisperKit, FluidAudio, Core ML, AVFoundation or CoreAudio raises passes through them.
/// `localizedDescription` on those is developer English at best and a bare CoreAudio error
/// number at worst (#311). A `catch` cannot know what it caught, so the decision of what to
/// say is made here, once: a type of ours speaks for itself, and everything else gets a
/// written sentence.
///
/// It also owns the sentences that more than one call site needs, so the same failure
/// cannot end up phrased two ways.
enum DictationFailureMessage {

    // MARK: - The shared sentences

    /// Nothing was captured, or nothing was understood. **Not a fault** (#313, 2026-08-25).
    ///
    /// WHY one sentence for what used to be five messages: stopping the mic a beat too
    /// early, a moment of silence, Parakeet's one-second floor, an empty transcription and
    /// a recording the model returned nothing for are the same event from the user's side.
    /// Nothing was captured; tap again. Presenting them as failures told the user the app
    /// was broken when nothing was. The wording and the treatment are SuperWhisper's,
    /// measured on device by the maintainer.
    static var noWordsDetected: String {
        String(localized: "No words detected",
               comment: "Shown when a dictation produced no text: nothing was captured, or nothing was understood. Not an error — the app is working, there was simply nothing to transcribe (issue #313).")
    }

    /// The microphone was refused, or never granted. Shared by the engine's own error and
    /// by the two coordinator paths that see the refusal as a `false` rather than a throw.
    static var microphonePermissionDenied: String {
        String(localized: "Dictus needs microphone access. Turn it on in iPhone Settings.",
               comment: "Shown when microphone permission is denied or has not been granted (issue #313).")
    }

    /// The engine is alive but delivering nothing, and restarting it in place did not help.
    /// A new process is the only remedy that works, so it is the only one offered.
    static var microphoneStoppedResponding: String {
        String(localized: "The microphone stopped responding. Close Dictus and open it again.",
               comment: "Shown when the audio engine reports running but captures no samples, and a forced restart does not recover it (issue #313).")
    }

    /// What a failure says when we cannot name it. Names no cause — asserting one we have
    /// not established is the mistake #320 was opened for — and offers the one action that
    /// is always available.
    static var unexplainedFailure: String {
        String(localized: "The dictation failed. Tap the microphone to try again.",
               comment: "Shown when a dictation fails for a reason the app cannot name. Deliberately names no cause (issues #313, #320).")
    }

    // MARK: - Resolution

    /// The sentence shown on whichever surface the user is on.
    ///
    /// An error of ours answers for itself. Anything else gets `unexplainedFailure`: the
    /// raw text is not withheld, it goes to `diagnostic(for:)` and into the log line.
    static func userFacing(for error: Error) -> String {
        guard let diagnosable = error as? DiagnosableError,
              let sentence = diagnosable.errorDescription else {
            return unexplainedFailure
        }
        return sentence
    }

    /// English technical detail for the log. Never shown to the user.
    ///
    /// Falls back to `localizedDescription` for a foreign error because that is what those
    /// log lines carried before this type existed, and it is the readable form for an
    /// `NSError`. The point of the funnel is what leaves the log, not what enters it.
    static func diagnostic(for error: Error) -> String {
        guard let diagnosable = error as? DiagnosableError else {
            return error.localizedDescription
        }
        return diagnosable.diagnosticDescription
    }
}
