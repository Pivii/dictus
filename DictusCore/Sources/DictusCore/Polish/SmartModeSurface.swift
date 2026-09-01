// DictusCore/Sources/DictusCore/Polish/SmartModeSurface.swift
// What the keyboard offers for Smart Modes, and what everyone else gets instead.
import Foundation

/// What a long press on the mic opens.
public enum SmartModeFanEntryPoint: Equatable, Sendable {

    /// The fan opens on whatever is pinned or armed, with the reason strip if there
    /// is a reason to show. Every user who is not being sold something lands here,
    /// including the subscriber who switched Smart Modes off (#423).
    case open

    /// The fan opens with its mode rows greyed and a `Dictus Pro` row at the bottom
    /// (#404). The non-subscriber's fan, and the only shape that sells anything.
    case upgrade

    /// Nothing. The long press opens no fan, says nothing and leaves no trace on
    /// screen — as if the gesture had never been wired up.
    case hidden
}

/// The visibility policy for the keyboard's Smart Mode surface (#460).
///
/// ### Why this is a type and not two `if`s in the keyboard
///
/// The same argument `HistoryAvailability` makes, and #460 is the bill for not having
/// made it here first. `PremiumFlags.paywallVisible` was already consulted in the
/// keyboard — by `offersProUpgrade`, which gated the Dictus Pro *row* — and that read
/// looked like the whole of the #236 gate while it was only the part someone happened
/// to need. Lowering the flag removed the one control that led anywhere and left the
/// sentence behind it in place, so the fan went on advertising a product that could
/// not be bought.
///
/// The questions below are pure functions for the reason `SmartModeFanLayout` gives:
/// the keyboard extension has no test bundle, DictusCore does, and this rule has to
/// hold on a surface nobody can screenshot in a review.
///
/// Neither parameter carries a default, for the reason `SmartModeAvailability.armability`
/// gives about its own entitlement parameter: the safe-looking answer is the one that
/// produced the bug. The compiler asks instead.
public enum SmartModeSurface {

    /// What a long press offers, given why modes cannot be armed and whether there is
    /// anything to sell.
    ///
    /// **The only reason that ever hides anything is `.notSubscribed`.** Every other
    /// state is about the device or about a choice the user made, and both of those
    /// are owed a sentence whatever the paywall is doing:
    ///
    /// - **`.switchedOff` is untouched.** That user pays for Smart Modes and turned
    ///   them off themselves. The flag is about not advertising a product that cannot
    ///   be bought; it is not about them, and what #423 built for them stands.
    /// - **A device reason is untouched.** Apple Intelligence being off has nothing to
    ///   do with a subscription, and hiding the fan would replace an actionable
    ///   sentence with silence.
    ///
    /// - Parameter reason: why no mode may be armed, or nil when one may be —
    ///   `SmartModeArmability.reason`.
    /// - Parameter paywallVisible: `PremiumFlags.paywallVisible`.
    public static func fanEntryPoint(reason: SmartModeUnavailableReason?,
                                     paywallVisible: Bool) -> SmartModeFanEntryPoint {
        guard reason == .notSubscribed else { return .open }
        return paywallVisible ? .upgrade : .hidden
    }

    /// Whether a surface may name Dictus Pro for this reason.
    ///
    /// This is the predicate the Dictus Pro row has always been built on, moved here
    /// and given the copy to gate as well. Two conditions, and neither is optional:
    ///
    /// - **`.notSubscribed` and nothing else.** `.notSubscribed` alone — which is what
    ///   a bare `isEntitled` used to collapse to — would sell a subscription to a
    ///   paying subscriber who switched Smart Modes off. `SmartModeEntitlement` is
    ///   what keeps those two people apart (#423).
    /// - **`paywallVisible`.** While the paywall is hidden the product must look like
    ///   it has no subscription at all (#236). A row leading to an unreachable paywall
    ///   is the dead end that gate exists to prevent — and a *sentence* naming a
    ///   product that cannot be bought is the same dead end without even a control to
    ///   press (#460).
    ///
    /// It answers for the fan's Pro row, for the fan's reason line and for the status
    /// message a skipped dictation leaves behind, because those three are one
    /// question: is Dictus Pro on sale to this user today.
    public static func sellsPro(reason: SmartModeUnavailableReason?,
                                paywallVisible: Bool) -> Bool {
        reason == .notSubscribed && paywallVisible
    }

    // There is deliberately **no** zero-argument convenience here (#460 review). One
    // was written and removed unused: it would have resolved both inputs itself, which
    // is the implicit default this issue took out of `SmartModeDiscovery.offersHint`
    // one file over, and it would have hidden a `SystemLanguageModel` availability read
    // behind a property that reads free. Both callers already hold an armability when
    // they ask, and passing it is one line.
}
