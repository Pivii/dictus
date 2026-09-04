// DictusCore/Sources/DictusCore/Subscription/ProFeature.swift
// Pro feature definitions and centralized gating logic.
import Foundation

/// Enum listing all features gated behind the Pro subscription.
///
/// WHY an enum with CaseIterable:
/// CaseIterable lets us iterate all Pro features in Settings to build
/// the "Pro Features" section dynamically. Each case carries its display
/// metadata (name, icon, settings key) so the UI never hardcodes feature info.
public enum ProFeature: String, CaseIterable {
    case smartMode
    case history
    case vocabulary

    /// Human-readable name for Settings rows and paywall cards.
    public var displayName: String {
        switch self {
        case .smartMode: return "Smart Mode"
        case .history: return "History"
        case .vocabulary: return "Vocabulary"
        }
    }

    /// SF Symbol name for the feature icon.
    public var icon: String {
        switch self {
        case .smartMode: return "sparkles"
        case .history: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .vocabulary: return "character.book.closed"
        }
    }

    /// Description shown on paywall feature cards.
    public var paywallDescription: String {
        switch self {
        case .smartMode: return "Reformulate your text with on-device AI"
        case .history: return "Search and export all your transcriptions"
        case .vocabulary: return "Teach Dictus your technical terms"
        }
    }

    /// Localized description shown on paywall feature cards (French).
    public var paywallDescriptionFR: String {
        switch self {
        case .smartMode: return "Reformulez vos textes avec une IA embarqu\u{00E9}e"
        case .history: return "Recherchez et exportez toutes vos transcriptions"
        case .vocabulary: return "Apprenez \u{00E0} Dictus vos termes techniques"
        }
    }

    /// App Group UserDefaults key for per-feature enable/disable toggle.
    public var settingsKey: String {
        switch self {
        case .smartMode: return SharedKeys.smartModeEnabled
        case .history: return SharedKeys.historyEnabled
        case .vocabulary: return SharedKeys.vocabularyEnabled
        }
    }

    // MARK: - Device capability (#79)

    /// Whether this feature needs Apple Foundation Models, and therefore an
    /// iPhone 15 Pro or later on iOS 26.
    ///
    /// Dictus supports iOS 17 and up, so **most of the installed base cannot run
    /// Smart Mode**, and #268 closed the only alternative backend `wontfix`. Refusing
    /// to sell Pro on those devices would amputate the market to protect one feature;
    /// selling it while advertising that feature is worse than that — it is a
    /// misleading-metadata rejection waiting to happen, and the App Review device on
    /// #207 was an iPad Air.
    ///
    /// So Pro is sold to everyone and the paywall tells the truth per device.
    public var requiresAppleIntelligence: Bool {
        switch self {
        case .smartMode: return true
        case .history, .vocabulary: return false
        }
    }

    /// Whether this iPhone could deliver the feature if the user configured it for
    /// it — hardware and OS only, not whether Apple Intelligence is switched on.
    ///
    /// The distinction matters on a paywall: an iPhone 15 Pro with Apple Intelligence
    /// off is a device where Smart Mode works after one trip to Settings, and saying
    /// "your iPhone does not support this" to that user would be false.
    public var isSupportedByThisDevice: Bool {
        guard requiresAppleIntelligence else { return true }
        return SmartModeAvailability.deviceIsCapable
    }

    /// The line a card carries when the device cannot deliver the feature, or nil
    /// when it can.
    ///
    /// English, like every other string on this type, and for the same stated reason:
    /// DictusCore ships no string catalog. The paywall owns its translation.
    public var unsupportedNotice: String? {
        isSupportedByThisDevice ? nil : "Requires Apple Intelligence (iPhone 15 Pro or later, iOS 26)"
    }
}

/// Centralized feature gating -- checks Pro status + per-feature toggle.
///
/// WHY a struct with static methods instead of a protocol:
/// FeatureGate is purely a query object with no state. Static methods
/// keep the call site clean: `FeatureGate.isAvailable(.smartMode)`.
/// No need for dependency injection here -- it reads directly from App Group.
public struct FeatureGate {
    /// Check if a specific Pro feature is available.
    /// Returns true only when Pro is active AND the feature is individually enabled.
    public static func isAvailable(_ feature: ProFeature) -> Bool {
        guard isProActive else { return false }
        return isEnabled(feature)
    }

    /// The per-feature toggle alone, with no subscription check.
    ///
    /// WHY this is exposed separately from `isAvailable` (#423): the two halves of
    /// that `&&` describe two different people. Someone without Pro is being sold
    /// something; a subscriber who switched Smart Modes off in Settings has said
    /// what they want, and telling them the feature "is part of Dictus Pro" is
    /// false. `SmartModeEntitlement` is the type that keeps them apart, and this is
    /// what it reads to do it.
    ///
    /// Seeded to `true` at first launch by `ProStatusManager.seedFeatureTogglesIfNeeded`,
    /// so "never touched the toggle" reads as on rather than off.
    public static func isEnabled(_ feature: ProFeature) -> Bool {
        AppGroup.defaults.bool(forKey: feature.settingsKey)
    }

    /// Check if Pro subscription is active (beta OR paid).
    /// Use this for UI gating that doesn't depend on individual feature toggles.
    public static var isProActive: Bool {
        ProStatusManager.isProActiveStatic
    }

    /// Keyboard-specific feature gate -- call from DictusKeyboard to check
    /// if a Pro feature should be shown on the keyboard UI.
    ///
    /// WHY a separate method from isAvailable:
    /// The keyboard extension will call this in Phase 33 when adding Smart Mode
    /// button etc. It has identical logic to isAvailable() now, but provides
    /// a semantic entry point for keyboard-specific gating. If keyboard gating
    /// logic ever diverges (e.g., different defaults), only this method changes.
    ///
    /// In Phase 30, no Pro UI exists on the keyboard yet, so this is a skeleton
    /// that Phase 33 will consume when the Smart Mode button is added.
    public static func isKeyboardFeatureAvailable(_ feature: ProFeature) -> Bool {
        guard isProActive else { return false }
        return AppGroup.defaults.bool(forKey: feature.settingsKey)
    }
}
