// DictusCore/Sources/DictusCore/Subscription/ProStatusManager.swift
// Lightweight Pro status manager for App Group cross-process sync.
import Foundation
import SwiftUI

/// Manages Pro subscription status in App Group UserDefaults.
///
/// WHY ObservableObject with @Published:
/// SwiftUI views observe this to reactively show/hide Pro UI elements.
/// When SubscriptionManager (in DictusApp) calls setProActive(),
/// the @Published property triggers UI refresh across all observing views.
///
/// WHY separate from SubscriptionManager:
/// ProStatusManager lives in DictusCore (shared framework) so both the
/// main app AND the keyboard extension can read Pro status. SubscriptionManager
/// lives in DictusApp only (StoreKit is too heavy for the ~50MB keyboard extension).
///
/// Pro status is driven entirely by StoreKit entitlements: no entitlement
/// means free tier. Testing uses Apple's standard paths — the local
/// StoreKitConfig.storekit in development, and the free sandbox environment
/// on TestFlight.
@MainActor
public final class ProStatusManager: ObservableObject {
    @Published public private(set) var isProActive: Bool

    public init() {
        // Runs at every app launch (DictusApp.init), which is what makes the
        // seeding idempotent and always ahead of the first read.
        ProStatusManager.seedFeatureTogglesIfNeeded()

        // Through the static rather than reading the key directly, so the app's own
        // observed value and every `FeatureGate` answer come from one expression (#460).
        self.isProActive = ProStatusManager.isProActiveStatic
    }

    /// Writes the per-feature Pro toggles into the App Group the first time, so that
    /// the keyboard extension and the app read the same answer (issue #401).
    ///
    /// WHY a write and not `register(defaults:)`, which is what this replaced:
    /// registration is per-process and never hits disk. DictusApp runs this init and
    /// read `true` for an un-toggled feature; the keyboard extension never runs it and
    /// read `false`. Same key, two processes, two answers -- a subscriber who never
    /// opened the Settings toggle got a locked Smart Mode fan while Settings showed it
    /// on. The App Group is the source of truth both sides already assume it is, so
    /// the value has to actually be in it.
    ///
    /// WHY `object(forKey:) == nil` and not an unconditional write: seed, never
    /// assign. `SubscriptionManager.updateProStatus()` runs on every launch, so an
    /// unconditional write would silently switch a feature back on for a user who
    /// deliberately turned it off. `bool(forKey:)` cannot tell "never set" from "set
    /// to false"; `object(forKey:)` can.
    ///
    /// WHY no `register(defaults:)` survives alongside it: a registered value makes
    /// `object(forKey:)` return non-nil, which would disarm the guard above and leave
    /// the keys unpersisted all over again.
    ///
    /// Seeding is deliberately not conditioned on Pro being active: `FeatureGate`
    /// checks `isProActive` first, so a stored `true` grants a free user nothing --
    /// it is only the on-by-default state waiting for the day they subscribe, which
    /// is exactly what the registration used to express.
    nonisolated public static func seedFeatureTogglesIfNeeded() {
        let defaults = AppGroup.defaults
        let unseeded = ProFeature.allCases.filter {
            defaults.object(forKey: $0.settingsKey) == nil
        }
        guard !unseeded.isEmpty else { return }

        unseeded.forEach { defaults.set(true, forKey: $0.settingsKey) }
        // Same reason as setProActive below: the reader is another process.
        defaults.synchronize()
    }

    /// Called by SubscriptionManager after transaction updates (DictusApp only).
    ///
    /// WHY write to App Group AND update @Published:
    /// App Group write makes it visible to keyboard extension on next read.
    /// @Published update triggers immediate SwiftUI refresh in the main app.
    public func setProActive(_ active: Bool) {
        AppGroup.defaults.set(active, forKey: SharedKeys.proActive)
        AppGroup.defaults.synchronize()
        // Re-read rather than assign `active` (#460 review). The stored value is what
        // was just written; the *entitlement* is what `isProActiveStatic` answers, and
        // since #460 those two can differ under the debug override. Assigning `active`
        // here made `SubscriptionManager.updateProStatus()` — which runs at every
        // launch and calls `setProActive(false)` with no subscription — publish false
        // while `FeatureGate` and the keyboard both said true. One expression decides
        // entitlement or the two processes disagree, which is the whole of #401.
        refreshFromAppGroup()
    }

    /// Re-read entitlement from the shared state, without writing anything.
    ///
    /// The published property is a cache of `isProActiveStatic`, and a cache needs an
    /// invalidation. Anything that changes an *input* to that answer without going
    /// through `setProActive` calls this: today that is the debug override's switch
    /// in Settings (#460), which must not write `SharedKeys.proActive` — a forced
    /// entitlement that persisted into the real key would outlive the switch being
    /// turned off, and would be indistinguishable from a genuine subscription.
    public func refreshFromAppGroup() {
        isProActive = ProStatusManager.isProActiveStatic
    }

    /// Lightweight static read for keyboard extension (no StoreKit, no ObservableObject).
    ///
    /// WHY static: The keyboard extension doesn't need reactive updates --
    /// it reads Pro status once at viewDidLoad/viewWillAppear. A static method
    /// avoids instantiating an ObservableObject in the memory-constrained extension.
    ///
    /// **This is the one place entitlement is decided** (#460). `FeatureGate.isProActive`,
    /// the keyboard's toolbar and this class's own published property all come through
    /// here, which is what makes a single debug override possible instead of one force
    /// path per surface.
    nonisolated public static var isProActiveStatic: Bool {
        #if DEBUG
        // Compiled out of Release entirely, along with the flag and its key. See
        // `PremiumFlags.debugProEntitlementForced` for why it has to exist at all: #460
        // hides the Smart Mode surface from everyone, the maintainer included, and the
        // feature is still being built.
        if PremiumFlags.debugProEntitlementForced { return true }
        #endif
        return AppGroup.defaults.bool(forKey: SharedKeys.proActive)
    }
}
