// DictusCore/Sources/DictusCore/LiveActivityLiveness.swift
// Decides whether a Live Activity is still usable, from its system state alone.
// Testable in isolation -- no ActivityKit dependency.

import Foundation

/// ActivityKit's `ActivityState`, mirrored as a plain value.
///
/// WHY mirror it instead of using `ActivityState` directly:
/// ActivityKit is iOS-only, so a rule expressed over `ActivityState` cannot be
/// unit-tested by DictusCore's macOS test target -- and the whole point of #257
/// is that this rule must be verifiable without waiting 8 hours on a device.
/// Mirroring keeps the decision testable; `LiveActivityManager` performs the
/// one-line mapping at the ActivityKit boundary.
///
/// WHY an `unknown` case: `ActivityState` is not frozen. iOS has already added
/// states since 16.1 (`stale` in 16.2, `pending` later), so a build compiled
/// today can observe a state it has no case for.
public enum LiveActivityLiveness: String, Sendable, CaseIterable {
    /// Visible and accepting content updates.
    case active
    /// Visible and still updatable, but its content is past its `staleDate`.
    case stale
    /// Still visible, but ended -- it will never update again.
    case ended
    /// Removed from the screen entirely.
    case dismissed
    /// A state this build does not recognise.
    case unknown

    /// What `LiveActivityManager` should do with an activity in this state.
    public var decision: LiveActivityLivenessDecision {
        switch self {
        case .active:
            return .keep

        // WHY `.stale` is refreshed and NOT treated as absent (the open question
        // on #257): `stale` means the content is out of date, not that the
        // activity is dead -- it is still visible and still accepts updates.
        // Treating it as absent would be actively harmful here, because Dictus
        // sets `staleDate` to just 30 seconds ahead and nothing updates the
        // activity while it sits in standby. A standby pill is therefore `.stale`
        // by design from 30 seconds after it appears, and "stale means dead"
        // would tear down every standby pill half a minute after creating it.
        // Pushing a content update instead clears the stale mark and costs one
        // ActivityKit update per app foreground.
        case .stale:
            return .refresh

        // The states that actually mean "no longer usable". `.ended` is the one
        // behind #257: ActivityKit ends every Live Activity after 8 hours, and an
        // ended activity KEEPS appearing in `Activity.activities` until its UI is
        // removed -- so an id-presence check sees it and calls it healthy forever.
        case .ended, .dismissed:
            return .treatAsAbsent

        // WHY unknown is refreshed rather than ended: an unrecognised state is not
        // evidence of death, and tearing down a live activity is the worse error.
        // An update on a dead activity is a harmless no-op, and the next
        // reconciliation sees `.ended`/`.dismissed` once ActivityKit settles.
        case .unknown:
            return .refresh
        }
    }
}

/// What to do with an activity whose liveness has just been observed.
public enum LiveActivityLivenessDecision: String, Sendable, Equatable {
    /// Live and current -- leave it alone.
    case keep
    /// Live but out of date -- push a content update, do not tear it down.
    case refresh
    /// Not usable any more -- end it, drop the reference, return to idle.
    case treatAsAbsent
}
