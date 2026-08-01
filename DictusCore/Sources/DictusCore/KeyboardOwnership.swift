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
/// Before #260 ownership was two independent properties, an optional controller id
/// and a visibility flag, and "nobody owns the keyboard area" had exactly one
/// spelling. That conflated two situations that call for opposite handling:
///
/// - the keyboard was **dismissed** — there is no keyboard on screen, and the next
///   thing to happen is a fresh controller registering from scratch;
/// - the owner was **deallocated mid-dictation while the keyboard stayed on
///   screen** — iOS destroys every live controller before building the successor
///   during an app switch, so for a moment a live recording session has no owner
///   at all.
///
/// In the second case every status change was dropped by the ownership guards and
/// the keyboard stayed in its typing layout while the app recorded behind it,
/// until iOS happened to build another controller — sometimes seconds later,
/// sometimes only after the user went to the app and came back.
///
/// Naming the second case is what makes it fixable: it is the only state from
/// which a live controller may take ownership it never registered for.
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

    /// The owner was deallocated while a dictation still owned the keyboard area,
    /// and no successor has registered yet (#260).
    ///
    /// Reads exactly like `.none` to every consumer — `controllerID` is `nil` and
    /// `isVisible` is `false`, so a dangling marker can never make a dismissed
    /// keyboard look present. What it adds is the licence to reclaim: an attached
    /// controller that finds the area in this state may adopt the session instead
    /// of waiting for iOS to build a replacement.
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
    /// `sessionOwnsKeyboardArea` is `DictationStatus.ownsKeyboardArea` at that
    /// instant, and it is the whole decision: with a dictation in flight the
    /// keyboard is still on screen and a successor is being built, so the area
    /// stays reclaimable; without one, a deallocated owner means the keyboard is
    /// gone and ownership is released outright.
    public func deallocating(
        controllerID: String,
        sessionOwnsKeyboardArea: Bool
    ) -> KeyboardOwnership {
        guard self.controllerID == controllerID else { return self }
        return sessionOwnsKeyboardArea ? .awaitingReclaim(previousControllerID: controllerID) : .none
    }

    /// Ownership after an attached controller claims a reclaimable area, or `nil`
    /// when there is nothing to claim.
    ///
    /// Single-shot by construction: the claim moves the state to `.owned`, so a
    /// second controller reacting to the same event finds nothing reclaimable and
    /// the ordinary ownership guards apply to it again.
    public func reclaiming(controllerID: String) -> KeyboardOwnership? {
        guard isReclaimable else { return nil }
        return .owned(controllerID: controllerID)
    }

    /// Ownership after a dictation status change.
    ///
    /// A reclaimable area is only reclaimable because a session was still in
    /// flight. When that session ends with nobody having claimed it — a keyboard
    /// genuinely dismissed mid-recording, where no successor controller ever
    /// arrives — the marker has nothing left to license and is dropped, so the
    /// state cannot be left dangling for the rest of the process's life.
    public func resolving(sessionOwnsKeyboardArea: Bool) -> KeyboardOwnership {
        guard isReclaimable, !sessionOwnsKeyboardArea else { return self }
        return .none
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
