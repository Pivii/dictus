// DictusCore/Sources/DictusCore/StatusMessageLifetime.swift
// How long the keyboard's toolbar message stays up, and which pending clear is
// allowed to take it down.

import Foundation

/// Identity for the toolbar's status message, so a clear scheduled for one message
/// can never take down the one that replaced it (#342).
///
/// ### The failure this exists for
///
/// Every status message used to schedule an unconditional clear three seconds out:
///
/// ```swift
/// assignStatusMessage(errorMsg, reason: "appError")
/// DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
///     self?.assignStatusMessage(nil, reason: "appError-timeout")
/// }
/// ```
///
/// That closure clears whatever is on the toolbar when it fires, not the message it
/// was scheduled for. Two dictations failing two seconds apart is enough to see it,
/// and two mic taps are enough to produce that -- both attempts fail on "recording
/// too short". The second message inherits the remainder of the first one's timer and
/// dies after a second, observed on device on `1.8.0 (25)`:
///
/// ```
/// [13:42:27Z] KBD dictationMessageCleared reason=replaced displayedCount=3
/// [13:42:27Z] KBD dictationMessageSet reason=appError owner=952A01A2 visible=true
/// [13:42:28Z] KBD dictationMessageCleared reason=appError-timeout displayedCount=0
/// ```
///
/// The cost is not cosmetic. Two failures in a row are rarely the same failure twice:
/// the first is usually the cheap one the user caused, the second the one that needs
/// an action from them ("no model downloaded", "microphone unavailable"). Losing the
/// second loses the informative one. It also manufactures `displayedCount=0`, which
/// #261 defined as the signal that a message was never seen and mapped to `.warning`
/// so an agent reading an exported log can find it -- noise in the one channel built
/// to answer that question (#255).
///
/// ### Why a token rather than a cancellable work item
///
/// Holding the pending `DispatchWorkItem` and cancelling it before scheduling the next
/// one has fewer moving parts, but it only works while every future message source
/// remembers to route through the cancelling funnel. A token is checked by the clear
/// itself, so a message assigned by a site that has never heard of any of this still
/// invalidates the clears that came before it.
///
/// Lives in DictusCore because the keyboard extension has no test bundle, so a rule
/// left there is unprovable. Same reasoning as `TranscribingStageHold`,
/// `DictationSessionGeneration` and `KeyboardAreaMode`.
public struct StatusMessageLifetime: Equatable, Sendable {

    /// How long a status message stays on the toolbar.
    ///
    /// WHY one constant for every message: the two sites that raise one used to carry
    /// their own three seconds, one as a literal and one as a named constant, and they
    /// cross-cleared each other precisely because they were the same length by accident
    /// rather than by construction.
    ///
    /// Whether three seconds is the right number, whether the message should be
    /// dismissible, and whether some failures deserve no message at all, are #313's
    /// questions. This is the place that number lives, not a judgement about it.
    public static let displayDuration: TimeInterval = 3

    /// Token of the message currently holding the toolbar.
    public private(set) var current: Int

    public init(current: Int = 0) {
        self.current = current
    }

    /// A message was assigned. Whatever was on the toolbar before no longer owns it,
    /// and neither does any clear scheduled for it.
    ///
    /// Called for clears as well as for messages: a message taken down early by a
    /// cancel or an insertion invalidates its own pending timeout the same way a
    /// replacement does.
    @discardableResult
    public mutating func advance() -> Int {
        current += 1
        return current
    }

    /// Whether a clear scheduled under `token` may still take the toolbar down.
    ///
    /// Fails closed: a clear only fires while the message it was scheduled for is
    /// still the current one, so any future reason to change the message invalidates
    /// outstanding clears as soon as it advances the token.
    public func mayClear(_ token: Int) -> Bool {
        token == current
    }
}
