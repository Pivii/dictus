// DictusApp/Polish/PolishAvailability.swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Gates the Settings polish toggle. Round 1 supports Apple Foundation Models only —
/// the toggle is hidden on devices where it's unavailable (Apple Intelligence off,
/// pre-iOS 26, or non-A17 Pro / non-M-series hardware).
///
/// The Debug build flag `DICTUS_POLISH_DEBUG_VISIBLE` forces the toggle visible so
/// development on non-FM devices is still possible (engine falls back to passthrough).
public enum PolishAvailability {

    /// True only when Apple Foundation Models is actually usable on this device.
    public static var isAppleFMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            case .unavailable:
                return false
            @unknown default:
                return false
            }
        }
        #endif
        return false
    }

    /// True when the Settings toggle should be rendered.
    /// Hidden on incapable devices unless the debug-visible flag is set.
    public static var isToggleVisible: Bool {
        #if DICTUS_POLISH_DEBUG_VISIBLE
        return true
        #else
        return isAppleFMAvailable
        #endif
    }
}
