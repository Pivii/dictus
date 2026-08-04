// DictusCore/Sources/DictusCore/DictationSessionGeneration.swift
// Which dictation a piece of in-flight work belongs to, and when it stops being
// allowed to speak for it.

import Foundation

/// Identifies the dictation that in-flight work belongs to.
///
/// A dictation's transcription and polish run in a `Task` that outlives the
/// decisions made about the dictation itself. The task can only be *asked* to stop
/// -- `Task.cancel()` is cooperative, and neither WhisperKit nor Apple Foundation
/// Models promises to return promptly -- so it can still be running seconds after
/// the session it belongs to has been declared over. When it finishes, it must not
/// report.
///
/// ### The failure this exists for (#267 device session, 2026-08-04)
///
/// Cancelling during transcription produced, within the same second:
///
/// ```
/// liveActivityTransition from=transcribing to=standby-abandoned
/// statusChanged from=transcribing to=idle
/// statusChanged from=idle to=failed          <- the abandoned task, reporting
/// ```
///
/// The teardown was correct and the view closed; then the still-running task threw,
/// wrote `failed`, and the recording screen came back for about half a second. Six
/// Live Activity transitions were rejected in the same window (`standby->failed`,
/// `standby->ready`), the state machine correctly refusing writes from a session
/// that was over. The `standby->ready` ones are the alarming half: on that path the
/// task had *succeeded*, and a success write also inserts text into the user's
/// document.
///
/// ### Why the pre-existing guard did not cover it
///
/// `DictationCoordinator` already had a generation counter from #60, but it was
/// incremented in exactly one place -- `startDictation()` -- so it answered "did a
/// **newer** session start", which is supersession, not abandonment. Nothing starts
/// when a dictation is abandoned. And the transcription task never captured the
/// counter at all, so even a superseding start would not have stopped these writes.
/// Two gaps, one of them in the concept.
///
/// This type closes the concept: the generation moves for **both** reasons a
/// session can stop being the current one, and the two reasons are named here
/// rather than left as increments spread across a 1200-line coordinator.
///
/// Lives in DictusCore because `DictationCoordinator` is in DictusApp, which has no
/// test bundle. Same reasoning as `KeyboardAreaMode` and `LiveActivityStateMachine`.
public struct DictationSessionGeneration: Equatable, Sendable {

    /// The generation work started now would belong to.
    public private(set) var current: Int

    public init(current: Int = 0) {
        self.current = current
    }

    /// A new dictation is starting. Work from the previous one stops being current.
    public mutating func beginSession() {
        current += 1
    }

    /// The current dictation is over with no successor: cancelled by the user, or
    /// torn down by a watchdog or an audio interruption.
    ///
    /// WHY this is not the same call as `beginSession` even though both advance the
    /// counter: they are two different reasons, and a reader asking "when does work
    /// stop being allowed to report" has to be able to find both. Collapsing them
    /// into one `invalidate()` is how the abandonment case went missing the first
    /// time.
    public mutating func abandonSession() {
        current += 1
    }

    /// Whether work that started under `generation` may still report its outcome --
    /// write status, insert text, or drive the Live Activity.
    ///
    /// Fails closed by construction: work only reports while its generation is
    /// still the current one, so any future reason to end a session invalidates
    /// outstanding work as soon as it advances the counter.
    public func mayReport(from generation: Int) -> Bool {
        generation == current
    }
}
