// DictusApp/Polish/PolishAvailability.swift
import Foundation
import DictusCore

/// The Settings-facing half of Apple FM availability.
///
/// The runtime question — can this process call the engine — moved to DictusCore
/// with #361, because the keyboard extension now asks it too. What stays here is
/// UI policy: whether the toggle row is drawn at all, and whether sending the user
/// to iOS Settings would help. Both are app-only, and the first is gated by the app
/// target's `DICTUS_POLISH_DEBUG_VISIBLE` build flag, which DictusCore cannot see.
public extension PolishAvailability {

    /// True when the Settings polish toggle row should be rendered.
    ///
    /// Visible on devices where Apple FM could become usable after a user fix
    /// (turn on Apple Intelligence, wait for model download). Hidden on devices
    /// where no setup can fix it (old hardware, pre-iOS 26, SDK-less build) so
    /// we don't show a useless toggle in production.
    ///
    /// The Debug build flag `DICTUS_POLISH_DEBUG_VISIBLE` forces it visible
    /// regardless of state so development on incapable devices stays possible (the
    /// engine falls back to passthrough).
    static var isToggleVisible: Bool {
        #if DICTUS_POLISH_DEBUG_VISIBLE
        return true
        #else
        switch state {
        case .available, .appleIntelligenceNotEnabled, .modelNotReady:
            return true
        case .deviceNotEligible, .osTooOld, .sdkMissing, .other:
            return false
        }
        #endif
    }

    /// True when opening iOS Settings is a meaningful next step for the user
    /// to fix the unavailable state.
    static func canOpenSystemSettings(for state: PolishAvailabilityState) -> Bool {
        state == .appleIntelligenceNotEnabled
    }
}
