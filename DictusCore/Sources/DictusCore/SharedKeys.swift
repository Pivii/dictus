// DictusCore/Sources/DictusCore/SharedKeys.swift
import Foundation

/// Centralized UserDefaults keys for App Group shared storage.
/// Using an enum with static properties prevents typo-based bugs.
public enum SharedKeys {
    public static let dictationStatus = "dictus.dictationStatus"
    public static let lastTranscription = "dictus.lastTranscription"
    public static let lastTranscriptionTimestamp = "dictus.lastTranscriptionTimestamp"
    public static let lastError = "dictus.lastError"

    // Model management keys (added for Plan 2.3 transcription pipeline)
    public static let activeModel = "dictus.activeModel"
    public static let modelReady = "dictus.modelReady"
    public static let downloadedModels = "dictus.downloadedModels"

    // Keyboard-App cross-process contracts (added for Plan 3.1)
    /// Current keyboard layout type stored as String ("azerty" or "qwerty")
    public static let keyboardLayout = "dictus.keyboardLayout"
    /// JSON-encoded [Float] waveform energy data written by app during recording
    public static let waveformEnergy = "dictus.waveformEnergy"
    /// Bool flag set by keyboard to request recording stop
    public static let stopRequested = "dictus.stopRequested"
    /// Bool flag set by keyboard to request recording cancellation
    public static let cancelRequested = "dictus.cancelRequested"
    /// Double: elapsed recording seconds, updated at ~5Hz during recording
    public static let recordingElapsedSeconds = "dictus.recordingElapsedSeconds"
}
