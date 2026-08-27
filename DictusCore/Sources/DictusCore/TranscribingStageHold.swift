// DictusCore/Sources/DictusCore/TranscribingStageHold.swift
// The display floor under the transcription stage. Pure decision -- no view, no
// timer: each surface owns its timer, this owns the rule.

import Foundation

/// Keeps `.transcribing` on screen long enough to be read, when another stage
/// follows it (#309).
///
/// WHY this exists: `.transcribing` is announced the instant transcription starts,
/// and the UI can never know how long it will last -- the duration only exists once
/// the work is done. With Parakeet that is 154-395 ms measured on device, so the
/// stage is entered and left inside a quarter of a second: a label and an animation
/// for a handful of frames, which is not information, it is an artefact. That is the
/// same verdict #267 reached from the other side when it gated `.processing`, except
/// that gate is *predictive* -- `onEngineWillRun` knows before the engine runs
/// whether the wait is worth announcing. Nothing here can know that, so the rule is
/// duration-based instead.
///
/// WHY it delays nothing the user is waiting for: transcription, the LLM stage and
/// the write to the App Group all start at exactly the instants they did before.
/// Only what is *drawn* is held back, and only while a stage that does last has
/// already begun behind it. The added latency is zero in every case, which is what
/// separates this from the unconditional dwell the issue body proposed and this
/// design rejects.
///
/// WHY it lives in DictusCore rather than next to either surface: the keyboard
/// extension target has no test bundle, so anything only reachable from there is
/// unprovable. Same reasoning as `ProcessingWaveform`, `KeyboardAreaMode` and
/// `LiveActivityStateMachine`. Both surfaces -- the keyboard overlay and DictusApp's
/// `RecordingView` -- run this same rule so they cannot disagree about what they are
/// showing within the same second.
///
/// WHY a surface recreated mid-hold is right to skip the stage: iOS rebuilds the
/// keyboard extension constantly (~9 instances per dictation, #281). A new instance
/// reads `.processing` from the App Group and draws it immediately, having never seen
/// `.transcribing`. That is correct and must not be "fixed": there is no flash to
/// suppress, because the stage that would have flashed was never on screen. Nothing
/// here ever synthesises a state to fill such a gap -- the hold can only delay a
/// transition *away from* a stage that is genuinely being drawn.
public struct TranscribingStageHold: Equatable {

    /// The shortest `.transcribing` may stay on screen when a stage follows it.
    ///
    /// WHY a constant of its own, and not `DictationCoordinator.minimumRecordingDuration`
    /// (same 0.5 today): that one is an audio floor -- below half a second of speech
    /// WhisperKit hallucinates. This one is a display floor. They answer different
    /// questions and changing one must not move the other.
    ///
    /// WHY 500 ms. The lower bound is legibility: perceiving a state change takes
    /// ~300-400 ms and reading a one-word label in a single fixation ~250 ms. The upper
    /// bound binds harder -- the hold must not eat a significant share of the stage it
    /// delays, and the shortest polish stage measured is 1 s. A 2 s hold (one full
    /// crossing of the transcription sine, which advances its phase by 0.5 per second
    /// and so crosses the row in 2.00 s) would cover a short polish stage entirely and
    /// leave "Transcription..." on screen for all of it -- the #267 defect reproduced
    /// in miniature. So: no full crossing. The usable band is 350-600 ms and 500 ms
    /// sits well inside it.
    ///
    /// The sine only completes a quarter of its crossing in 500 ms, and that is
    /// acceptable: unlike the travelling peak, whose motion is legible only if it
    /// actually travels, the sine is continuous. It has no start and no end of travel,
    /// so a quarter of the pattern already reads as "a wave advancing". The
    /// whole-crossing argument in `ProcessingWaveform.phaseRate` belongs to the other
    /// animation.
    ///
    /// If it proves short or long in use, it is a number to change, not a design to redo.
    public static let minimumDisplayDuration: TimeInterval = 0.5

    /// What a surface should do with a status it has just been handed.
    public enum Outcome: Equatable {
        /// Nothing to do. The surface is already drawing this status, or has already
        /// decided to.
        case unchanged
        /// Put this status on screen now, and cancel any pending hold.
        case draw(DictationStatus)
        /// Keep drawing the current status, and draw this one after the interval.
        /// The surface arms its own timer and calls `release(now:)` when it fires.
        case hold(DictationStatus, for: TimeInterval)
    }

    /// The status currently on screen.
    public private(set) var displayed: DictationStatus

    /// When `displayed` last changed. Only `.transcribing` has a floor, but the anchor
    /// is kept for every status so there is no second rule about when it is valid.
    private var displayedSince: Date

    /// A status decided but not yet drawn, waiting out the floor above.
    public private(set) var pending: DictationStatus?

    public init(displayed: DictationStatus = .idle, since: Date = Date()) {
        self.displayed = displayed
        self.displayedSince = since
    }

    /// Move the drawn stage toward `incoming`.
    public mutating func apply(_ incoming: DictationStatus, now: Date) -> Outcome {
        // Re-affirming what is already on screen, or what has already been decided, is
        // not new information. Both matter in practice: the keyboard re-adopts the
        // stored status on every Darwin refresh and on every keyboard appearance, so
        // the same value is written many times per dictation. Treating those as fresh
        // would restart the floor under a stage already half spent -- and, while a hold
        // is pending, would throw the decision away and strand the overlay on
        // `.transcribing` until the next status arrived.
        guard incoming != displayed, incoming != pending else { return .unchanged }

        guard displayed == .transcribing, Self.isAStageFollowing(incoming) else {
            return commit(incoming, now: now)
        }

        // Clamped at zero so a clock that moved backwards cannot lengthen the hold.
        // `now` is wall-clock on both surfaces, and an NTP correction between the two
        // reads makes this difference negative -- which, unclamped, would flow into
        // the subtraction below and return a hold of the floor *plus* the size of the
        // jump. A one-hour correction would then strand the overlay on
        // "Transcription..." for the rest of the dictation, until the terminal status
        // preempted it. The clamp makes `minimumDisplayDuration` a hard ceiling on
        // what this can ever return, so the worst a backward jump can now cost is one
        // full floor -- the same half-second any ordinary fast transcription gets.
        let shown = max(0, now.timeIntervalSince(displayedSince))
        guard shown < Self.minimumDisplayDuration else {
            // The stage has already been readable for long enough -- Whisper medium
            // transcribes in 2.9-5 s, so on that engine the rule never fires at all.
            return commit(incoming, now: now)
        }

        pending = incoming
        return .hold(incoming, for: Self.minimumDisplayDuration - shown)
    }

    /// The surface's hold timer has elapsed: draw what was waiting.
    ///
    /// `.unchanged` when nothing is pending, which is what a timer that outlived its
    /// decision gets -- a terminal status arriving mid-hold preempts and clears it, and
    /// the stale timer must then draw nothing.
    public mutating func release(now: Date) -> Outcome {
        guard let pending else { return .unchanged }
        return commit(pending, now: now)
    }

    private mutating func commit(_ status: DictationStatus, now: Date) -> Outcome {
        displayed = status
        displayedSince = now
        pending = nil
        return .draw(status)
    }

    /// Whether `next` is another stage of the same dictation, as opposed to its end or
    /// the start of a new one. Only a stage is worth waiting for.
    ///
    /// WHY an exhaustive switch rather than `next == .processing`: a status added later
    /// has to be classified here rather than silently inheriting an answer. That is how
    /// `.processing` reached the watchdog predicate in #267.
    ///
    /// WHY `.requested` and `.recording` are on the immediate side even though they are
    /// not terminal: they belong to the *next* dictation, not to this one. `.requested`
    /// in particular is the one moment in the whole interaction where the user needs
    /// immediate truth -- the keyboard has fired the URL and the mic is about to go
    /// live -- and it is the only place a hold would cost real perceived latency. The
    /// general-sounding formulation "a minimum duration for every stage" is pretty and
    /// false; do not extend this rule to `.requested` as a tidy-up.
    ///
    /// `.processing` needs no floor of its own either: the state that follows it is
    /// always terminal, so a rule keyed on "another stage follows" can never fire for
    /// it. That is correct, and the same judgement as polish-off dictations -- the last
    /// stage before the result is not an artefact, it is speed.
    private static func isAStageFollowing(_ next: DictationStatus) -> Bool {
        switch next {
        case .processing:
            return true
        case .idle, .ready, .failed:
            // Terminal: the interaction is over (or was cancelled). Never waits.
            return false
        case .requested, .recording:
            return false
        case .transcribing:
            // Unreachable -- an incoming equal to `displayed` returned above.
            return false
        }
    }
}
