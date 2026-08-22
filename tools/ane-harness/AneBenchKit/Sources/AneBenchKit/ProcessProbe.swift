// tools/ane-harness/Sources/AneBenchKit/ProcessProbe.swift
//
// THROWAWAY — #268 D2. Same readings D1 took, from the same two calls, so the
// two measurements can be laid side by side without a conversion: jetsam
// headroom from `os_proc_available_memory()` (DictusCore's `DeviceCapabilities`)
// and `phys_footprint` (DictusCore's `MemoryFootprint`).
import Foundation
import DictusCore
#if canImport(UIKit)
import UIKit
#endif

public enum ProcessProbe {

    /// Take a labelled reading. `origin` anchors `atSeconds`.
    public static func sample(_ label: String, since origin: Date) async -> ProcessSample {
        let capabilities = DeviceCapabilities.current()
        return ProcessSample(
            label: label,
            atSeconds: Date().timeIntervalSince(origin),
            availableMemoryMB: capabilities.availableMemoryMB,
            footprintMB: MemoryFootprint.residentMB(),
            thermalState: describe(capabilities.thermalState),
            appState: await applicationState()
        )
    }

    /// "background" / "active" / "inactive" on iOS; "n/a" on the Mac, where the
    /// distinction this harness exists to make does not exist.
    public static func applicationState() async -> String {
        #if canImport(UIKit)
        return await MainActor.run {
            switch UIApplication.shared.applicationState {
            case .background: return "background"
            case .inactive: return "inactive"
            case .active: return "active"
            @unknown default: return "unknown"
            }
        }
        #else
        return "n/a"
        #endif
    }

    private static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
