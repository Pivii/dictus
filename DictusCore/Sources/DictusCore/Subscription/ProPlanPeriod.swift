// DictusCore/Sources/DictusCore/Subscription/ProPlanPeriod.swift
// Which period suffix, if any, a Pro plan's price may carry.
import Foundation

/// The renewal unit of a subscription, mirroring StoreKit's
/// `Product.SubscriptionPeriod.Unit`.
///
/// WHY it is mirrored rather than imported: DictusCore is linked by the
/// keyboard extension, which lives under a ~50 MB ceiling and has no business
/// with StoreKit. Only DictusApp links the framework, so the rule that decides
/// the suffix is expressed over these cases and the view maps StoreKit's enum
/// onto them at the one call site.
public enum ProSubscriptionUnit: Equatable {
    case day
    case week
    case month
    case year
    /// A unit StoreKit may add after this was written.
    case unknown
}

/// The period suffix a price may carry, e.g. "39,99 €/an".
public enum ProPlanPeriod: Equatable {
    case monthly
    case yearly
    /// No suffix: a one-off purchase, or a duration Dictus does not sell.
    case unlabelled

    /// Resolves what a price may claim about its own period.
    ///
    /// WHY the length is checked and not only the unit: App Store Connect sells
    /// 2-, 3- and 6-month durations as well as 1-month ones, so a unit of
    /// `.month` alone does not make a price "per month". Labelling a six-month
    /// plan "39,99 €/mois" would not be vague, it would be false — and a false
    /// price is the failure this whole rule exists to prevent (#350).
    ///
    /// Anything else falls to `unlabelled`: the bare price is less informative
    /// than a suffix, and never wrong.
    ///
    /// - Parameters:
    ///   - unit: `nil` when the product has no subscription at all, which is
    ///     what a non-consumable looks like.
    ///   - value: how many of `unit` each renewal spans.
    public static func resolve(unit: ProSubscriptionUnit?, value: Int) -> ProPlanPeriod {
        switch (unit, value) {
        case (.year, 1): return .yearly
        case (.month, 1): return .monthly
        default: return .unlabelled
        }
    }
}
