// DictusCore/Sources/DictusCore/DeviceCapabilities.swift
// Device capability snapshot used for per-device model gating (Phase 37, issue #104).

import Foundation

/// A snapshot of device characteristics used to decide which speech models
/// can safely run on the current device.
///
/// WHY a struct with public init instead of static helpers:
/// Tests for `ModelInfo.isSupported(on:)` need to inject synthetic capabilities
/// (iPhone 12 / 15 Pro Max / 17 Pro) without running on that hardware. Making
/// every field injectable keeps the gating logic pure and unit-testable.
public struct DeviceCapabilities: Sendable, Equatable {

    /// Total physical RAM in gigabytes (rounded down).
    public let physicalMemoryGB: Int

    /// Remaining jetsam headroom in megabytes at the moment the snapshot was taken.
    /// Measured via `os_proc_available_memory()` — this is the memory the app can
    /// allocate before iOS kills it with a jetsam event.
    public let availableMemoryMB: Int

    /// Hardware model identifier from `sysctl` (e.g. "iPhone16,2" = iPhone 15 Pro Max).
    /// On simulator this is the host-reported value (e.g. "arm64") or the simulated
    /// device via `SIMULATOR_MODEL_IDENTIFIER` env var.
    public let deviceModelIdentifier: String

    /// Current thermal state — throttling under `.serious` or `.critical` will
    /// degrade transcription latency significantly.
    public let thermalState: ProcessInfo.ThermalState

    public init(
        physicalMemoryGB: Int,
        availableMemoryMB: Int,
        deviceModelIdentifier: String,
        thermalState: ProcessInfo.ThermalState
    ) {
        self.physicalMemoryGB = physicalMemoryGB
        self.availableMemoryMB = availableMemoryMB
        self.deviceModelIdentifier = deviceModelIdentifier
        self.thermalState = thermalState
    }

    /// Reads the current device's capabilities at call time. Not cached — calling
    /// it twice produces fresh readings (available memory + thermal state drift).
    public static func current() -> DeviceCapabilities {
        DeviceCapabilities(
            physicalMemoryGB: readPhysicalMemoryGB(),
            availableMemoryMB: readAvailableMemoryMB(),
            deviceModelIdentifier: readDeviceModelIdentifier(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    /// Whether this device is an A12- or A13-class iPhone (iPhone XS/XR through
    /// iPhone 11 and iPhone SE 2nd gen).
    ///
    /// WHY a hardware-family test and not a RAM test:
    /// These devices ship 3-4 GB, the same tier as the A14 iPhone 12 family, so RAM
    /// alone cannot tell them apart. Argmax's WhisperKit Core ML support matrix draws
    /// the line on the chip, not the memory: A12/A13 list only Tiny and Base, while
    /// A14 adds Small. Recommending or offering Small here traps the app in Core ML
    /// optimization during onboarding and can jetsam it (issue #362).
    ///
    /// WHY it lives on DeviceCapabilities rather than ModelInfo:
    /// This type states facts about the hardware; ModelInfo decides what those facts
    /// mean for the catalog. Keeping the prefix list here gives the recommendation
    /// rule and the per-device gate one shared definition instead of two copies.
    ///
    /// Source of truth: https://huggingface.co/argmaxinc/whisperkit-coreml/raw/main/config.json
    public var isA12OrA13iPhone: Bool {
        deviceModelIdentifier.hasPrefix("iPhone11,") || deviceModelIdentifier.hasPrefix("iPhone12,")
    }

    /// Number of concurrent decoding workers WhisperKit should use for parallel
    /// chunk processing. Scales with physical RAM tier and de-rates under thermal
    /// pressure. Tiers match Apple's marketed iPhone RAM lineup (6/8/12 GB).
    ///
    /// Used as `DecodingOptions.concurrentWorkerCount` — higher = more parallelism
    /// but more peak memory + heat. Conservative on low-RAM devices and when the
    /// SoC is already throttling.
    public var recommendedConcurrentWorkerCount: Int {
        let base: Int
        switch physicalMemoryGB {
        case 12...:
            base = 8   // iPhone 17 Pro / 18 Pro and beyond
        case 8...:
            base = 6   // iPhone 15 Pro / 16 Pro / Pro Max class
        default:
            base = 4   // 6 GB devices (turbo gating floor) and older
        }
        switch thermalState {
        case .serious, .critical:
            return max(2, base / 2)
        default:
            return base
        }
    }

    // MARK: - Private readers

    private static func readPhysicalMemoryGB() -> Int {
        // Use ceiling, not nearest-rounding, to report the marketed RAM tier.
        //
        // Real-device observation on iPhone 15 Pro Max (8 GB marketed):
        // ProcessInfo.physicalMemory returns ~7.47 GB because the kernel and
        // secure enclave reserve ~530 MB. Nearest-rounding gives 7, floor
        // gives 7, only ceiling produces the 8 that Turbo gating relies on.
        //
        // Safe across the iPhone lineup because Apple's RAM tiers are spaced
        // by whole GB (4/6/8/12) — ceiling can only push a reading up to the
        // next integer, never past the next marketed tier:
        //   - 3.8 GB (iPhone 12 mini, 4 GB marketed) → ceil = 4 ✓
        //   - 5.9 GB (iPhone 13 Pro, 6 GB marketed) → ceil = 6 ✓
        //   - 7.47 GB (iPhone 15 Pro Max, 8 GB marketed) → ceil = 8 ✓
        //   - 11.3 GB (iPhone 17 Pro, 12 GB marketed) → ceil = 12 ✓
        let bytes = Double(ProcessInfo.processInfo.physicalMemory)
        return Int((bytes / 1_073_741_824.0).rounded(.up))
    }

    private static func readAvailableMemoryMB() -> Int {
        // `os_proc_available_memory()` is iOS 13+. Returns jetsam headroom in bytes.
        // Returns 0 if the process has no jetsam limit (rare, mostly simulator).
        // macOS has no jetsam equivalent and this path only matters on-device;
        // the macOS build exists solely for the polish eval harness.
        #if os(iOS)
        let bytes = os_proc_available_memory()
        return Int(bytes / 1_048_576)
        #else
        return 0
        #endif
    }

    private static func readDeviceModelIdentifier() -> String {
        // Simulator reports host arch via sysctl; prefer SIMULATOR_MODEL_IDENTIFIER
        // when present so we see the simulated device.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier
    }
}

// MARK: - Thermal state log formatting

public extension ProcessInfo.ThermalState {
    /// Human-readable label used in log output.
    var logLabel: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
