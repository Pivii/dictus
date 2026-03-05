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
}
