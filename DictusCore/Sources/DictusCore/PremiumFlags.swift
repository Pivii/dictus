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
    public static let paywallVisible = false
}
