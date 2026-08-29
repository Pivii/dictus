// DictusCore/Sources/DictusCore/PremiumFlags.swift
import Foundation

/// Compile-time visibility flags for premium UI (issue #236).
///
/// WHY a compile-time constant instead of remote config:
/// No Pro feature exists yet (#79) and App Store Connect setup is pending (#215),
/// so the paywall would render with empty prices. A single `static let` is enough
/// to hide every entry point (Home banner, Settings Pro section, locked rows, the
/// keyboard panel's Pro pill) while keeping all subscription code compiled and
/// intact.
///
/// WHY it lives in DictusCore rather than beside `SubscriptionManager`:
/// entry points exist in both DictusApp and DictusKeyboard. It started as an
/// `internal` constant in the app target, which the keyboard extension cannot
/// see — so the panel added in #241 shipped a Pro pill that ignored the flag
/// entirely. One flag gating two targets belongs in the shared framework.
///
/// Re-enable: flip `paywallVisible` to `true` in the PR that ships the first
/// real Pro feature, once #215 (ASC setup) is done. See #79/#215/#216.
///
/// WHY an enum with no cases: a caseless enum can never be instantiated,
/// making it a pure namespace for static constants (common Swift pattern).
public enum PremiumFlags {
    /// Controls whether users can see and reach the paywall.
    /// `false` = the app looks like there is no subscription at all.
    ///
    /// TEST BRANCH ONLY — flipped to `true` here and NOT FOR MERGE. #279 is the
    /// issue that owns turning this on for real, and its preconditions are not met:
    /// #215 has not created the subscription in App Store Connect, so the paywall
    /// will show a loading error rather than prices. It is `true` on this branch
    /// because every Pro *surface* is gated behind it — the Pro Features toggles in
    /// Settings (`SettingsView` 132 and 315) and the upgrade row in the fan
    /// (`KeyboardSmartModeFan` 270) — so #423 and #404 cannot be exercised with it
    /// off, whatever the entitlement says.
    public static let paywallVisible = true

    /// Last day of the lifetime founder window, or `nil` while it is not
    /// scheduled (#350).
    ///
    /// The window runs one month from the App Store release that ships the
    /// first real Pro feature (#79). That release has no date yet, so none can
    /// be written here. While this is `nil` the lifetime row shows its price
    /// and its scope sentence and **no founder line at all** — a promotional
    /// claim with a missing date is worse than no claim.
    ///
    /// WHY it governs copy only: the price comes from StoreKit, so the App
    /// Store Connect price change at the end of the window is what moves
    /// 79,99 € to 149,99 €. Setting this constant announces the deadline; it
    /// does not enforce it. Both have to be done on the same day.
    ///
    /// To open the window, give it the **last day the offer stands**:
    /// `DateComponents(calendar: .current, year: 2026, month: 9, day: 12).date`
    ///
    /// That expression is midnight at the *start* of 12 September, while the
    /// offer runs to the end of that day. Nothing should compare against this
    /// value directly — `LifetimeFounderWindow.announcedEnd()` owns that
    /// boundary, and reading the constant raw retires the line a day early.
    public static let lifetimeFounderOfferEnd: Date? = nil
}
