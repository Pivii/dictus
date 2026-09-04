// DictusCore/Sources/DictusCore/Polish/SmartModeDiscovery.swift
// Whether the toolbar still teaches the long-press gesture (issue #79).
import Foundation

/// The discovery hint's policy: when "Long-press for Smart Modes" is worth the
/// centre slot.
///
/// #79 gives the hint priority 5 and argues it costs nothing, "because it only
/// renders when there are no suggestions to show". True of the slot; not true of the
/// user. A permanent instruction for a gesture you perform daily is the kind of copy
/// people stop reading and then resent, so this adds the two conditions the issue
/// does not state.
public enum SmartModeDiscovery {

    private static var defaults: UserDefaults { AppGroup.defaults }

    /// Whether the user has ever armed a mode through the fan.
    public static var hasUsedGesture: Bool {
        defaults.bool(forKey: SharedKeys.smartModeGestureUsed)
    }

    /// Record a completed gesture. Idempotent, and never undone.
    public static func noteGestureUsed() {
        guard !hasUsedGesture else { return }
        defaults.set(true, forKey: SharedKeys.smartModeGestureUsed)
        defaults.synchronize()
    }

    /// Whether the hint should be offered the centre slot.
    ///
    /// Three subtractions from "always":
    ///
    /// - **Once the gesture has been used, the hint retires.** It taught what it had
    ///   to teach. Nothing brings it back, including unpinning every mode: the user
    ///   knows the gesture is there, and the empty fan is a better teacher than a
    ///   line of text about it.
    /// - **On a device that cannot run Smart Modes at all, it never appears.** Apple
    ///   Foundation Models needs an iPhone 15 Pro or later on iOS 26 and Dictus
    ///   supports iOS 17 up, so most of the installed base is in this state
    ///   permanently. Teaching them a gesture whose every outcome is a disabled row
    ///   and an explanation is worse than silence — and #79 already decided where
    ///   that population is told the truth about the feature, which is the paywall
    ///   and the App Store listing, not the toolbar.
    ///
    /// - **A gesture that opens nothing is not worth teaching.** `fanIsReachable` is
    ///   `SmartModeSurface.fanEntryPoint != .hidden`: while the paywall is hidden, a
    ///   non-subscriber's long press does not open the fan at all (#460), and a line
    ///   inviting them to perform it would be an instruction with no outcome.
    ///
    /// That last one is **not** the subtraction #404 left open. That question — should
    /// the hint point a non-subscriber at a fan whose only offer is an advertisement —
    /// is about a fan they can still open, and it stays open. This one is about a
    /// gesture that does nothing at all, which is not a question.
    ///
    /// Deliberately NOT subtracted: whether the user is subscribed. A non-subscriber
    /// on a capable device is exactly who this feature is for sale to, and the fan
    /// is where they meet it. What the fan says to them is #392's.
    ///
    /// Neither parameter carries a default, and the zero-argument convenience that
    /// used to sit below this was removed with the second one: a hint policy that
    /// answers on one of its two inputs is what #460 found in the fan.
    public static func offersHint(deviceCanRunModes: Bool, fanIsReachable: Bool) -> Bool {
        deviceCanRunModes && fanIsReachable && !hasUsedGesture
    }
}
