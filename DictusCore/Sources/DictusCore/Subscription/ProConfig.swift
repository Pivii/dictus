// DictusCore/Sources/DictusCore/Subscription/ProConfig.swift
// Compile-time configuration for Pro subscription and beta state.
import Foundation

/// Configuration for Pro subscription behavior.
///
/// WHY a simple Bool instead of runtime detection:
/// A simple isBeta flag -- flip to false and ship an update.
/// Runtime TestFlight detection via appStoreReceiptURL path checking is
/// fragile across iOS versions; a compile-time constant is reliable.
public enum ProConfig {
    /// Beta period flag ("isBetaPeriod" in issue #55): while true, every
    /// ProFeature is unlocked for everyone.
    ///
    /// Flip to `false` for the App Store release that enables the paywall.
    /// If TestFlight builds must stay free after that flip, wire a TESTFLIGHT
    /// Active Compilation Condition in Xcode build settings first -- it does
    /// NOT exist today, so a bare `#if TESTFLIGHT` would silently never fire.
    public static let isBeta = true

    /// Effective beta state — respects the debug "Force Free Tier" toggle.
    /// Use this instead of `isBeta` in UI code to allow testing the paid flow.
    /// In Release builds, this is identical to `isBeta` (the #if DEBUG block is stripped).
    public static var effectiveBeta: Bool {
        #if DEBUG
        if AppGroup.defaults.bool(forKey: SharedKeys.debugForceFreeTier) {
            return false
        }
        #endif
        return isBeta
    }
}
