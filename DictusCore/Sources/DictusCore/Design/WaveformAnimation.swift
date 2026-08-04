// DictusCore/Sources/DictusCore/Design/WaveformAnimation.swift
// What a waveform's bars are drawing, for every surface that draws one.

/// Which animation a bar waveform is running.
///
/// WHY a mode and not a set of booleans: the cases are mutually exclusive, and
/// both waveforms in this app used to carry a single `isProcessing` flag that the
/// renderer read to pick between two of them. Adding the LLM stage (#267) as a
/// second boolean would have made "both true" expressible, which is the shape of
/// bug this repo has paid for elsewhere.
///
/// WHY it is shared between `BrandWaveform` (DictusApp) and
/// `KeyboardWaveformDriver` (DictusKeyboard) rather than declared twice: the two
/// draw the same three animations from the same maths, and the moment they stop
/// agreeing on what the vocabulary is, they start disagreeing on what the user
/// sees. `ProcessingWaveform` is the maths; this is the choice of which to run.
public enum WaveformAnimation: Equatable, Sendable {
    /// Bar heights follow the microphone's energy. `DictationStatus.recording`.
    case micLevels
    /// Continuous sine sweep. `DictationStatus.transcribing`.
    case sweep
    /// Travelling peak scanning back and forth. `DictationStatus.processing`.
    case travellingPeak
    /// Nothing is animating -- bars sit where they were left.
    case still

    /// Whether the bars are drawing themselves rather than following the mic.
    ///
    /// The two self-driven animations share a phase, a 4 pt bar floor and a
    /// `waveformAppeared(isProcessing:)` log field whose meaning predates #267.
    public var isSelfDriven: Bool {
        self == .sweep || self == .travellingPeak
    }
}
