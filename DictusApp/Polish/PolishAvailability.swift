// DictusApp/Polish/PolishAvailability.swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Specific reasons Apple Foundation Models may be unavailable.
///
/// Round 1 on-device testing surfaced a real UX gap: `appleFMAvailable: false`
/// in the polish ring told us the polish layer fell back to Passthrough but gave
/// no clue *why*. The most common cause is the Siri-vs-iPhone language mismatch
/// (Apple Intelligence refuses to enable when they differ) and surfacing that
/// explicitly is far better than a silent fallback.
public enum PolishAvailabilityState: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case modelNotReady
    case deviceNotEligible
    case osTooOld
    case sdkMissing
    case other(String)
}

/// Gates the Settings polish toggle and surfaces actionable guidance when
/// Apple Foundation Models can't run.
///
/// The Debug build flag `DICTUS_POLISH_DEBUG_VISIBLE` forces the toggle visible
/// regardless of state so development on incapable devices stays possible (the
/// engine falls back to passthrough).
public enum PolishAvailability {

    /// Detailed availability state for the current device + OS + Apple
    /// Intelligence configuration.
    public static var state: PolishAvailabilityState {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(let reason):
                return .other(String(describing: reason))
            @unknown default:
                return .other("unknown")
            }
        } else {
            return .osTooOld
        }
        #else
        return .sdkMissing
        #endif
    }

    /// True only when Apple Foundation Models is actually usable on this device.
    public static var isAppleFMAvailable: Bool {
        state == .available
    }

    /// True when the Settings toggle row should be rendered.
    ///
    /// Visible on devices where Apple FM could become usable after a user fix
    /// (turn on Apple Intelligence, wait for model download). Hidden on devices
    /// where no setup can fix it (old hardware, pre-iOS 26, SDK-less build) so
    /// we don't show a useless toggle in production.
    public static var isToggleVisible: Bool {
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
    public static func canOpenSystemSettings(for state: PolishAvailabilityState) -> Bool {
        state == .appleIntelligenceNotEnabled
    }
}
