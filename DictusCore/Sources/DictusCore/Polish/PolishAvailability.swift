// DictusCore/Sources/DictusCore/Polish/PolishAvailability.swift
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

/// Whether Apple Foundation Models can run in *this* process, right now.
///
/// WHY this lives in DictusCore since #361: the keyboard extension is the process
/// that calls the engine for keyboard dictations, so it has to resolve the engine
/// the same way the app does. The answer is per device and per Apple Intelligence
/// configuration rather than per process, but the read has to be available on both
/// sides of the App Group.
///
/// The Settings-facing half of this question — whether to draw the toggle row at
/// all — stays in DictusApp: it is UI policy, and it is gated by the app target's
/// `DICTUS_POLISH_DEBUG_VISIBLE` build flag, which a framework cannot see.
public enum PolishAvailability {

    /// Detailed availability state for the current device + OS + Apple
    /// Intelligence configuration.
    public static var state: PolishAvailabilityState {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
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
}
