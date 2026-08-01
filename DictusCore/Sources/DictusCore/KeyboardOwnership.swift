// DictusCore/Sources/DictusCore/KeyboardOwnership.swift
// Which controller owns the keyboard area, and whether an ownerless area is
// still reclaimable (#260).
import Foundation

/// Who owns the keyboard area, from the keyboard extension's point of view.
///
/// iOS creates and destroys `UIInputViewController` instances constantly — around
/// nine of them live at once during a dictation — and only one of them is the
/// keyboard the user is looking at. Ownership is how the extension knows which
/// one that is: the recording overlay is drawn, and the hosting view expanded, by
/// the owner and nobody else (#128, #116).
///
/// Before #260 ownership was two independent properties — an optional controller
/// id and a visibility flag — and once they were emptied there was no way back
/// except a fresh controller registering. That is the bug: a controller that is
/// *not* the keyboard on screen can empty them and leave the one that is unable
/// to present anything.
///
/// It happens because ownership is last-writer-wins on appearance. Under churn the
/// live keyboard's ownership is routinely overwritten by an instance iOS is about
/// to throw away, and when that instance is deallocated it takes the area with it.
/// The live controller is never asked again: its `viewWillAppear` already ran.
/// Every status change is then dropped by the ownership guards and the keyboard
/// stays in its typing layout while the app records behind it — 2.5 s in one
/// capture, four seconds and a manual trip to DictusApp in another.
///
/// The third state below is the way back. It says the last known owner is gone and
/// nothing has registered since, which is the only situation where a controller
/// may take ownership it never registered for — and it may only do so if it can
/// show it is on screen.
///
/// Lives in DictusCore rather than DictusKeyboard so the transitions below are
/// unit-testable — the keyboard extension target has no test bundle. Same
/// reasoning as `KeyboardAreaMode`.
public enum KeyboardOwnership: Equatable, Sendable {
    /// No keyboard on screen. Nothing to draw, nothing to reclaim.
    case none

    /// `controllerID` is the live owner: the one controller allowed to present
    /// the recording overlay and size the keyboard area for it.
    case owned(controllerID: String)

    /// The owner was deallocated and no successor has registered yet (#260).
    ///
    /// Reads exactly like `.none` to every consumer — `controllerID` is `nil` and
    /// `isVisible` is `false` — so relative to releasing ownership outright, which
    /// is what the code did before, this changes nothing anyone can observe. A
    /// dangling marker cannot make a dismissed keyboard look present, and it
    /// cannot leave `isKeyboardVisible` stuck `true`.
    ///
    /// What it adds is a licence: a controller that is still on screen may claim
    /// the area rather than wait for iOS to build a replacement. That is the whole
    /// fix — the state itself is inert.
    case awaitingReclaim(previousControllerID: String)

    /// The owning controller, or `nil` when nobody owns the keyboard area.
    ///
    /// An awaiting-reclaim area deliberately has no owner: the previous one is
    /// deallocated, and a controller comparing its own id against this must not
    /// match a dead instance.
    public var controllerID: String? {
        switch self {
        case .owned(let controllerID):
            return controllerID
        case .none, .awaitingReclaim:
            return nil
        }
    }

    /// Whether a controller is presenting the keyboard on screen.
    ///
    /// False while awaiting reclaim: the pixels the user sees then belong to a
    /// deallocated controller, and nothing can update them until someone owns the
    /// area again.
    public var isVisible: Bool {
        if case .owned = self {
            return true
        }
        return false
    }

    /// Whether an attached controller may take ownership it never registered for.
    public var isReclaimable: Bool {
        if case .awaitingReclaim = self {
            return true
        }
        return false
    }

    /// Ownership after a controller appears.
    ///
    /// Unconditional, and deliberately so: the controller iOS just brought on
    /// screen is the keyboard, whatever the previous state was. This is the path
    /// that closes the awaiting-reclaim window in the common case.
    public func appearing(controllerID: String) -> KeyboardOwnership {
        .owned(controllerID: controllerID)
    }

    /// Ownership after a controller disappears. Only the owner may release it —
    /// a departing non-owner would otherwise take the live keyboard's ownership
    /// away with it, which is the shape of the bug in #260.
    public func disappearing(controllerID: String) -> KeyboardOwnership {
        guard self.controllerID == controllerID else { return self }
        return .none
    }

    /// Ownership after the owning controller is deallocated.
    ///
    /// WHY the dictation status is deliberately NOT consulted here: it says
    /// nothing about whether the keyboard is still on screen. The first capture in
    /// #260 has the owner deallocating a full second *before* the mic is tapped —
    /// the ordinary cold-start shape, controller churn settling and then the user
    /// starting a dictation — with another controller on screen the whole time.
    /// Conditioning the marker on a session being in flight at this instant
    /// therefore misses the dominant case entirely, and an earlier version of this
    /// fix did exactly that.
    ///
    /// A deallocated owner means one thing on its own: the last controller known
    /// to own the area is gone and nothing has registered since. Whether the
    /// keyboard is still on screen is a question only a live controller can
    /// answer, and it answers it in `claiming(controllerID:isOnScreen:)`.
    public func deallocating(controllerID: String) -> KeyboardOwnership {
        guard self.controllerID == controllerID else { return self }
        return .awaitingReclaim(previousControllerID: controllerID)
    }

    /// Ownership after a controller claims a reclaimable area, or `nil` when it
    /// may not have it.
    ///
    /// `isOnScreen` is the whole safety property, and it must be answered by the
    /// caller from UIKit — window attachment, not bookkeeping. Every controller
    /// that can reach this has appeared, been overwritten by a later appearance,
    /// and not been told it disappeared; that description fits the live keyboard
    /// whose ownership a dying controller took with it, and it equally fits the
    /// cached instances iOS never notifies (#128). Only attachment separates them,
    /// and getting it wrong the permissive way would let a stale controller
    /// *acquire* the area instead of merely being skipped — strictly worse than
    /// the bug being fixed. Answer it fail-closed.
    ///
    /// Single-shot by construction: the claim moves the state to `.owned`, so a
    /// second controller reacting to the same event finds nothing reclaimable and
    /// the ordinary ownership guards apply to it again.
    public func claiming(controllerID: String, isOnScreen: Bool) -> KeyboardOwnership? {
        guard isReclaimable, isOnScreen else { return nil }
        return .owned(controllerID: controllerID)
    }

    /// Compact form for device logs: the ownership half of every probe line.
    public var logDescription: String {
        switch self {
        case .none:
            return "none"
        case .owned(let controllerID):
            return "owned(\(controllerID))"
        case .awaitingReclaim(let previousControllerID):
            return "awaitingReclaim(\(previousControllerID))"
        }
    }
}
