// DictusCore/Sources/DictusCore/Subscription/ProProductID.swift
// App Store Connect product identifiers for Dictus Pro.
import Foundation

/// The App Store Connect product identifiers Dictus Pro sells (#215).
///
/// WHY these live in DictusCore rather than beside `SubscriptionManager`:
/// an identifier is permanent once the product exists in App Store Connect —
/// a typo cannot be renamed, only abandoned. DictusApp has no test target, so
/// constants declared there are unverifiable; here the DictusCore suite can
/// check them against the local StoreKit configuration the app ships with.
///
/// WHY an enum with no cases: a caseless enum can never be instantiated,
/// making it a pure namespace for static constants (common Swift pattern).
public enum ProProductID {
    /// Auto-renewable subscription, 1 month, no introductory offer.
    public static let monthly = "solutions.pivi.dictus.pro.monthly"

    /// Auto-renewable subscription, 1 year, 7-day free trial.
    public static let yearly = "solutions.pivi.dictus.pro.yearly"

    /// Every identifier `SubscriptionManager` asks StoreKit for.
    ///
    /// WHY a Set: `Product.products(for:)` takes a collection of identifiers
    /// and its result order is unspecified, so nothing downstream may depend
    /// on the declaration order here.
    public static let all: Set<String> = [monthly, yearly]
}
