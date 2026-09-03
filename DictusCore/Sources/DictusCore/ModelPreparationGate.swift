import Foundation

/// When a model preparation screen may take the display, and when it may not (#458).
///
/// WHY THIS EXISTS: the preparation screen is raised reactively by three views that all
/// watch the same global `modelLoadState` flag, and none of them asked whether anything
/// else was on screen. A dictation started inside DictusApp on a cold Core ML cache runs
/// `startDictation`'s cold-start branch, which begins recording and *then* writes
/// `modelLoadState = .loading` — so the load flips the flag while the microphone is live.
/// `ModelManagerView`'s `.fullScreenCover` presents at window level, above the
/// `RecordingView` that `MainTabView` puts in its `ZStack`, and the recording screen was
/// replaced mid-sentence for the eleven seconds the load took. Measured on device
/// 2026-08-30 and reproduced in the simulator; see the issue for both logs.
///
/// THE RULE: a preparation screen is never raised while a dictation is not idle, and a
/// preparation withheld that way is never replayed once the dictation ends. Popping the
/// screen when the user has just stopped talking and is watching their transcription
/// arrive is the same lie one beat later.
///
/// WHY THE STATE, when the gate could have been a single `if`: the views raise the screen
/// from `.onChange` *and* from `.onAppear`. `.onChange` alone would need no memory — a
/// load withheld during a dictation does not change again when the dictation ends, so
/// nothing re-fires. `.onAppear` does: switching to the Models tab re-asks the question,
/// and by then the dictation is over and the load is still running. The latch is what
/// makes the two entry points give the same answer.
///
/// Nothing here belongs to the app target — it is a decision about two booleans and a
/// string — so it lives where `swift test` can reach it.
public struct ModelPreparationGate: Equatable, Sendable {

    /// Every preparation refused because a dictation held the display.
    /// Emptied when preparation activity stops altogether, so the *next* one is judged
    /// on its own.
    ///
    /// WHY A SET AND NOT ONE SLOT: `liveActivePrepModel` names a single model, but it can
    /// name a different one from one moment to the next — a download of B while A is
    /// prewarming makes it alternate. A single slot only remembered the last refusal, so
    /// refusing A and then B left A unremembered, and A becoming the live preparation
    /// again after the dictation ended would have been presented: the delayed pop this
    /// type exists to prevent. Nothing distinguishes the two refusals, so nothing should
    /// have to choose between them.
    private var withheldModels: Set<String> = []

    public init() {}

    /// Whether a dictation currently owns what the user is looking at.
    ///
    /// WHY `!= .idle` and not `DictationSessionLivenessPolicy.isActive`: that policy
    /// answers "is some process still driving this dictation", which is false for
    /// `.ready` and `.failed`, and it is what the watchdogs judge staleness with. The
    /// question here is the other one — "is the dictation screen on screen" — and
    /// `MainTabView` already answers it with exactly this comparison: `RecordingView` is
    /// mounted for every status but `.idle`, result and error included.
    public static func dictationOwnsTheDisplay(_ status: DictationStatus) -> Bool {
        status != .idle
    }

    /// The model whose preparation may be raised on screen right now, if any.
    ///
    /// - Parameters:
    ///   - liveModel: the model currently in a user-facing preparation phase — the
    ///     views' `liveActivePrepModel` — or nil when no preparation is in flight.
    ///   - dictationStatus: the dictation status at the instant of the decision.
    ///   - isPresenting: whether a preparation screen is already up. Preserves the
    ///     "don't re-raise what is already raised" guard the call sites carried inline.
    /// - Returns: the identifier to present, or nil to leave the screen alone.
    public mutating func modelToPresent(
        liveModel: String?,
        dictationStatus: DictationStatus,
        isPresenting: Bool
    ) -> String? {
        guard let liveModel else {
            // Nothing is preparing at all. Every refusal is over, and a later preparation
            // is a new event that gets judged on its own merits.
            //
            // WHY this and not "forget a model once it stops being the live one": with
            // two preparations in flight the live one alternates, so forgetting per model
            // would clear a refusal while its load is still running. An empty
            // `liveModel` is the one moment that says all of them are done.
            withheldModels.removeAll()
            return nil
        }
        guard !Self.dictationOwnsTheDisplay(dictationStatus) else {
            // The load runs on regardless — it is only the screen that is refused.
            withheldModels.insert(liveModel)
            return nil
        }
        // The dictation is over and this is still a load it started under.
        guard !withheldModels.contains(liveModel) else { return nil }
        guard !isPresenting else { return nil }
        return liveModel
    }
}
