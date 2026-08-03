// DictusCore/Sources/DictusCore/LiveActivityStateMachine.swift
// Extracted state machine for Live Activity phase transitions.
// Testable in isolation -- no ActivityKit dependency.

import Foundation

/// Validates Live Activity phase transitions.
///
/// WHY extracted from LiveActivityManager:
/// The transition rules (which phases can follow which) are pure logic with no
/// ActivityKit dependency. Extracting them into a value type in DictusCore enables
/// unit testing of all valid/invalid paths without needing a running app or simulator.
///
/// WHY a struct (not class):
/// Phase transitions are sequential -- no shared mutable state between callers.
/// A struct with mutating functions makes ownership explicit and prevents accidental
/// aliasing. LiveActivityManager owns a single instance and calls transition(to:).
public struct LiveActivityStateMachine {

    /// Phases of the Live Activity lifecycle.
    /// Maps 1:1 to the private LiveActivityPhase enum in LiveActivityManager.
    public enum Phase: String, Sendable {
        case idle, standby, recording, transcribing, processing, ready, failed
    }

    /// The current phase. Read-only from outside; mutated only via transition(to:) or reset().
    public private(set) var currentPhase: Phase = .idle

    /// True while a dictation cycle runs without any Live Activity available
    /// (standby bootstrap from .idle failed, e.g. Live Activities disabled in
    /// iOS Settings). While set, rejected transitions from .idle are expected —
    /// the whole recording/transcribing/ready pipeline fires with no activity
    /// to drive — so they carry no diagnostic value.
    public private(set) var isInNoActivityCycle: Bool = false

    /// Allowed transitions for each phase.
    /// WHY a stored property (not computed): The map is constant and small (6 entries).
    /// Storing it avoids re-creating the dictionary on every transition call.
    ///
    /// WHY `.idle -> .failed` is allowed (issue #261): a dictation can fail while the
    /// manager sits at `.idle` -- the app relaunches after being terminated
    /// mid-recording, receives the stop the keyboard sent into the void, collects zero
    /// samples and reports a failure. Rejecting that transition left the Dynamic Island
    /// unable to show an error in exactly the situation where the user most needs one,
    /// and produced `liveActivityFailed context=rejectedTransition error=idle->failed`
    /// instead. `endWithFailure()` still returns early when no activity is held, so
    /// allowing this creates no pill out of nothing.
    ///
    /// WHY `.transcribing -> .ready` survives the arrival of `.processing` (#267):
    /// the LLM stage is skipped on most dictations -- the polish toggle is off by
    /// default, the duration gate drops flash clips, and devices without Apple
    /// Foundation Models never reach an engine worth announcing. A pipeline that
    /// went straight from transcription to a result is the common case, not a
    /// degraded one.
    private let validTransitions: [Phase: Set<Phase>] = [
        .idle: [.standby, .failed],
        .standby: [.recording, .idle],
        .recording: [.transcribing, .standby],
        .transcribing: [.processing, .ready, .failed],
        .processing: [.ready, .failed],
        .ready: [.standby, .recording],
        .failed: [.standby, .recording, .idle]
    ]

    public init() {}

    /// Attempt to transition to `target`. Returns true if the transition is valid.
    /// On failure, currentPhase is unchanged.
    @discardableResult
    public mutating func transition(to target: Phase) -> Bool {
        let allowed = validTransitions[currentPhase] ?? []
        guard allowed.contains(target) else { return false }
        currentPhase = target
        // A successful transition means the pipeline is progressing normally,
        // so the no-activity cycle (if any) is over.
        isInNoActivityCycle = false
        return true
    }

    /// Mark the start of a dictation cycle that runs without a Live Activity.
    /// Called by LiveActivityManager when the standby bootstrap from .idle fails.
    public mutating func beginNoActivityCycle() {
        isInNoActivityCycle = true
    }

    /// Explicitly end the no-activity cycle (an activity became available again).
    public mutating func endNoActivityCycle() {
        isInNoActivityCycle = false
    }

    /// Whether a rejected transition is worth persisting to the exported log.
    /// WHY: During a no-activity cycle, every dictation sink still calls the
    /// manager (recording, transcribing, ready) and each call is rejected from
    /// .idle. Persisting each rejection floods exports with redundant entries
    /// (issue #233). Suppression is deliberately narrow: it applies ONLY from
    /// .idle during a declared no-activity cycle — rejections while an activity
    /// exists keep logging, preserving the #42 desync diagnostics.
    public var shouldLogRejection: Bool {
        !(isInNoActivityCycle && currentPhase == .idle)
    }

    /// Returns true if phase is .recording -- used by watchdog logic to decide
    /// if the Dynamic Island is stuck on the recording indicator.
    public var needsWatchdog: Bool {
        currentPhase == .recording
    }

    /// Reset to idle (for teardown/recovery).
    public mutating func reset() {
        currentPhase = .idle
        isInNoActivityCycle = false
    }

    /// Force-set the phase without validation.
    /// WHY: LiveActivityManager has recovery/bootstrap paths that assign currentPhase
    /// directly (e.g., idle after crash, standby after orphan recovery). These bypass
    /// the normal transition rules. forcePhase keeps the state machine in sync.
    public mutating func forcePhase(_ phase: Phase) {
        currentPhase = phase
        // Forcing any non-idle phase means an activity exists (recovery, orphan
        // adoption, bootstrap success) — the no-activity cycle is over. Forcing
        // .idle (teardown) keeps the flag: still no activity to drive.
        if phase != .idle {
            isInNoActivityCycle = false
        }
    }
}
