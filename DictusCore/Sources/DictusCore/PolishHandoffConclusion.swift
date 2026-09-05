// DictusCore/Sources/DictusCore/PolishHandoffConclusion.swift
// What DictusApp's own status becomes when a keyboard hand-off ends (#467).

import Foundation

/// Whether the end of a keyboard hand-off returns DictusApp to `.idle`.
///
/// WHY THIS EXISTS: since #361 a keyboard dictation ends in the extension, and DictusApp
/// learns of it through `polishDidFinish`. Until #467 the app's own `status` was left at
/// the `.ready` it wrote when it handed the raw over, and `MainTabView` mounts
/// `RecordingView` for every status but `.idle` — so every later visit to DictusApp
/// landed on the recording overlay, covering the home screen and its correct card.
/// Measured on device 2026-09-04: `polishHandoff step=finished` at 14:01:50 with no
/// `→ idle` after it, and the next dictation two seconds later still clearing a `.ready`.
///
/// WHY IT IS A RULE AND NOT AN `if` AT THE CALL SITE: a hand-off has two endings — the
/// keyboard reporting in, and the watchdog concluding it never will — and they have to
/// agree about what they leave behind. The predicate was already written out at the
/// watchdog; #467 gave it a second caller.
///
/// THE CLASSIFICATION, which is the part with content: only `.ready` is a status this
/// process wrote *about the hand-off* and can therefore take back. `.failed` is a
/// sentence the user still has to read and outlives the dictation that produced it, and
/// the four live statuses belong to a dictation that has replaced this one — clearing
/// either would be the class of bug #260 and #261 are made of, arrived at from the app's
/// side. The switch is exhaustive so a status added later has to be classified rather
/// than silently swallowed (#267).
public enum PolishHandoffConclusion {

    /// - Parameter status: the coordinator's status at the moment the hand-off concluded.
    /// - Returns: whether that status should be replaced by `.idle`.
    public static func returnsToIdle(from status: DictationStatus) -> Bool {
        switch status {
        case .ready:
            return true
        case .idle, .requested, .recording, .transcribing, .processing, .failed:
            return false
        }
    }
}
