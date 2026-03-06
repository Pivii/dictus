// DictusCore/Sources/DictusCore/SmartModelRouter.swift
import Foundation

/// Routes audio to the appropriate Whisper model based on duration and
/// which models are currently downloaded on-device.
///
/// Strategy:
/// - Audio under 5 seconds -> prefer fast model (tiny/base) for low latency
/// - Audio 5 seconds or longer -> prefer accurate model (small+) for quality
/// - If only one model is downloaded, always use it regardless of duration
public struct SmartModelRouter {

    /// Duration threshold in seconds. Audio shorter than this uses the fast model.
    public static let durationThreshold: TimeInterval = 5.0

    /// Models optimized for speed (low latency on short clips).
    static let fastModels = [
        "openai_whisper-tiny",
        "openai_whisper-base"
    ]

    /// Models optimized for accuracy (better quality on longer audio).
    static let accurateModels = [
        "openai_whisper-small",
        "openai_whisper-medium"
    ]

    /// Selects the best model for the given audio duration from the downloaded models.
    ///
    /// - Parameters:
    ///   - audioDuration: Length of the audio clip in seconds.
    ///   - downloadedModels: WhisperKit identifiers of models available on-device.
    /// - Returns: The identifier of the selected model, or empty string if none available.
    public static func selectModel(
        audioDuration: TimeInterval,
        downloadedModels: [String]
    ) -> String {
        guard !downloadedModels.isEmpty else { return "" }

        // If only one model is downloaded, always use it
        if downloadedModels.count == 1 {
            return downloadedModels[0]
        }

        if audioDuration < durationThreshold {
            // Short audio: prefer fast model
            if let fast = fastModels.first(where: { downloadedModels.contains($0) }) {
                return fast
            }
        } else {
            // Long audio: prefer accurate model
            if let accurate = accurateModels.first(where: { downloadedModels.contains($0) }) {
                return accurate
            }
        }

        // Fallback: first downloaded model
        return downloadedModels[0]
    }
}
