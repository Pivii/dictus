// DictusCore/Sources/DictusCore/WarmInference.swift
// The discarded inference that makes a loaded model actually ready (#426).
//
// WHY this exists at all: `WhisperKitConfig(prewarm: true, load: true)` compiles the
// model and loads its weights, and nothing more. On Apple silicon the Neural Engine
// does its per-shape specialization at the FIRST inference, not at load, so the first
// `transcribe()` pays it however long the weights have been resident. Measured on an
// iPhone 15 Pro Max: 5 476 ms for the first transcription after a model switch against
// 1 343 ms for a later one on comparable audio, twenty-two seconds after the load had
// reported itself ready.
//
// The fix is to run one inference on generated audio and throw the result away, inside
// the load, so the cost lands in a window the user already reads as preparation.
//
// NOT TO BE CONFUSED with `UnifiedAudioEngine.warmUp()` (#106), which warms the AUDIO
// engine — a different subsystem with a similar name. Everything here says "warm
// inference" for that reason, and nothing here should ever be renamed to "warm up".
import Foundation

/// The audio a warm inference runs on.
///
/// Silence, not speech: shape specialization is per tensor shape, and the values in the
/// buffer cannot change the shapes the engine compiles for. What the values could
/// change is how long the decoder runs, and silence is the cheapest answer to that.
public enum WarmInferenceAudio {

    /// Both engines consume 16 kHz mono, as does the whole dictation pipeline.
    public static let sampleRate = 16_000

    /// TWO SECONDS, AND NOT LESS. This number has two independent floors under it and
    /// clears both:
    ///
    /// 1. **WhisperKit skips short buffers entirely.** `TranscribeTask.run` loops
    ///    `while seek < seekClipEnd - windowPadding`, where `windowPadding` is
    ///    `DecodingOptions.windowClipTime` (default 1.0 s) times the sample rate. A
    ///    buffer of one second or less runs *zero* encoder passes, so it would warm
    ///    nothing at all while still logging a success. Nothing in the API says so.
    /// 2. **Parakeet refuses anything under a second.** FluidAudio's own floor, which
    ///    `ParakeetEngine.transcribe` restates rather than discovering.
    ///
    /// Above those floors the length is free: WhisperKit pads whatever it gets to a
    /// fixed 480 000-sample (30 s) window before the mel spectrogram, so a 2 s buffer
    /// and a 30 s one specialize identically.
    public static let durationSeconds = 2.0

    /// Number of samples in a warm-inference buffer.
    public static var sampleCount: Int { Int(durationSeconds * Double(sampleRate)) }

    /// A buffer of digital silence, ready to hand to an engine's `transcribe`.
    public static func silence() -> [Float] {
        [Float](repeating: 0, count: sampleCount)
    }
}

/// Remembers which model this process has already run a warm inference on.
///
/// WHY a ledger rather than trusting the call site: the warm inference is invoked from
/// inside the engine-load task, which already only runs on a genuine load — so the
/// ledger is not what makes the rule true. It is what makes the rule *stated* and
/// testable off-device, where a Core ML load cannot be exercised at all. It is also the
/// gate: if a future call site runs a warm inference somewhere the load dedupe does not
/// cover, this is what stops it from repeating.
///
/// ONE SLOT ON PURPOSE. Dictus holds exactly one speech engine at a time, and switching
/// away from a model and back builds a fresh, cold instance of it. A set of every model
/// ever warmed would remember a warmth that no longer exists.
public struct WarmInferenceLedger {

    /// The model the live engine was warmed for, or nil when none is.
    private var warmedModel: String?

    public init() {}

    /// The model currently recorded as warm. Diagnostic; the decision is `claim`.
    public var warmModel: String? { warmedModel }

    /// Take the right to run a warm inference for `modelIdentifier`.
    ///
    /// - Returns: `true` the first time it is asked for a given model, `false` while
    ///   that same model is still the warm one. A repeated foregrounding of a loaded
    ///   model must never buy a second throwaway inference: the latency win is felt
    ///   once and the battery cost would be paid every time the user comes back.
    public mutating func claim(_ modelIdentifier: String) -> Bool {
        guard warmedModel != modelIdentifier else { return false }
        warmedModel = modelIdentifier
        return true
    }

    /// Forget that `modelIdentifier` is warm.
    ///
    /// Called when the inference did not actually happen — it threw, or the load that
    /// asked for it was discarded before its engine was published. Recording a model as
    /// warm when it is not would make the next load of it skip the one thing this whole
    /// file exists to do.
    ///
    /// The identity check is the same idiom as `clearInitTask(ifStillCurrent:)`: a
    /// mismatched release is a no-op rather than a way to clear somebody else's claim.
    public mutating func release(ifMatches modelIdentifier: String) {
        if warmedModel == modelIdentifier { warmedModel = nil }
    }
}
