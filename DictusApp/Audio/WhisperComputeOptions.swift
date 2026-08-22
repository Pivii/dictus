// DictusApp/Audio/WhisperComputeOptions.swift
// Translates DictusCore's compute policy into WhisperKit's ModelComputeOptions.
import DictusCore
import WhisperKit

/// The single place where the device's audio-encoder compute policy becomes a
/// WhisperKit type (issue #370).
///
/// WHY one helper instead of four inline expressions:
/// Dictus initialises WhisperKit at four sites (DictationCoordinator, ModelManager,
/// TranscriptionService, WhisperKitEngine). A copy of the rule at each one is a copy
/// that can drift, and the one that drifts is the one that silently puts an iPhone 11
/// back on the Neural Engine. All four call `current()`.
///
/// WHY it can return nil rather than always building an options object:
/// `WhisperKitConfig.computeOptions` is optional and every site passes nothing today.
/// Returning nil off the A12/A13 path is what makes "every other device is unchanged"
/// exact rather than approximate — WhisperKit receives the same nil it receives now,
/// so no default can be accidentally restated wrongly here.
enum WhisperComputeOptions {

    /// Compute options for the current device, or nil to keep WhisperKit's own default.
    static func current() -> ModelComputeOptions? {
        options(for: DeviceCapabilities.current().audioEncoderComputePolicy)
    }

    /// Pure mapping, split out so it can be reasoned about without reading the device.
    static func options(for policy: DeviceCapabilities.AudioEncoderComputePolicy) -> ModelComputeOptions? {
        switch policy {
        case .whisperKitDefault:
            return nil
        case .cpuAndGPU:
            // Only the audio encoder moves. mel, textDecoder and prefill keep
            // ModelComputeOptions' own defaults, which are the values WhisperKit
            // would have used anyway.
            return ModelComputeOptions(audioEncoderCompute: .cpuAndGPU)
        }
    }
}
