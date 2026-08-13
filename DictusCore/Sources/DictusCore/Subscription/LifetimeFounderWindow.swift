// DictusCore/Sources/DictusCore/Subscription/LifetimeFounderWindow.swift
// Whether the lifetime founder offer may still be announced.
import Foundation

/// Decides whether the founder-window line may still be shown (#350).
///
/// WHY this is not just a nil check on `PremiumFlags.lifetimeFounderOfferEnd`:
/// the constant is compiled into a build, and builds outlive the window. The
/// price rises to 79,99 € in App Store Connect on the announced day, but a user
/// who has not updated keeps running the build that announced the offer — so
/// the row would read "79,99 €" with "Offre fondateur jusqu'au 12 septembre
/// 2026" underneath it, promising a price that is already gone, on a date
/// already past. The date has to be checked against the clock, not only
/// against nil.
///
/// WHY an enum with no cases: a caseless enum can never be instantiated,
/// making it a pure namespace for static functions (common Swift pattern).
public enum LifetimeFounderWindow {

    /// The date to announce, or `nil` when there is nothing to announce —
    /// either the window was never scheduled or it has closed.
    ///
    /// The window covers the **whole** of the named day: "jusqu'au 12
    /// septembre" is a promise the offer is still there on 12 September.
    /// `PremiumFlags.lifetimeFounderOfferEnd` holds the start of that day, so
    /// the comparison runs against the start of the day after it — comparing
    /// against the constant itself would retire the line a full day early.
    ///
    /// - Parameters:
    ///   - end: the configured last day; defaults to the shipped constant.
    ///   - now: injectable for tests.
    ///   - calendar: injectable for tests. Day arithmetic goes through the
    ///     calendar rather than adding 86 400 seconds, so a day that is not
    ///     24 hours long (a daylight-saving change) still resolves correctly.
    public static func announcedEnd(
        end: Date? = PremiumFlags.lifetimeFounderOfferEnd,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let end else { return nil }
        guard let dayAfterEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: end)
        ) else { return nil }
        return now < dayAfterEnd ? end : nil
    }
}
