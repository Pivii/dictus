// DictusCore/Sources/DictusCore/ProcessingWaveform.swift
// Bar heights for the LLM-processing animation. Pure math -- no view, no timer.

import Foundation

/// The travelling-peak ("cylon") sweep the recording overlay renders while the
/// LLM stage runs (#267).
///
/// WHY a third animation and not a second speed of the transcription sine: the
/// two waits have to read as different *families*, not as the same wave running
/// slower -- a user who cannot tell them apart learns nothing from the change.
/// A localized bump scanning back and forth is discontinuous where the sine is
/// continuous, so the difference survives a glance at a 30 pt-tall waveform.
/// Ported from Dictus Desktop, which arrived at this shape after several
/// iterations (`src/overlay/RecordingOverlay.tsx`).
///
/// WHY the crest matches the transcription sine's (0.7) while the baseline does
/// not (0.05 against ~0.2): same visual vocabulary, different motion. The bars
/// far from the peak must genuinely drop -- a localized peak sitting on the
/// sine's wave-trough height stops reading as localized.
///
/// WHY it lives in DictusCore and not next to the view in DictusKeyboard: the
/// keyboard extension target has no test bundle, so anything only reachable from
/// there is unprovable. Same reasoning as `KeyboardAreaMode` and
/// `LiveActivityStateMachine`.
///
/// WHY there is no outro here, unlike the desktop original: on desktop the
/// overlay is its own window and can spend 700 ms easing the peak back to centre
/// before it fades. On iOS the overlay *is* the keyboard area, and it gives way
/// the instant the transcription is inserted -- an outro would hold the keys
/// hostage for the exact moment the user is waiting on.
public enum ProcessingWaveform {

    /// Bars in the overlay's waveform. Matches `KeyboardWaveformView`.
    public static let barCount = 30

    /// How many bars either side of the peak still rise above the baseline.
    /// At 10 of 30 bars the bump is wide enough to be read as one shape and
    /// narrow enough to leave a clearly flat remainder.
    public static let halfWidth: Double = 10

    /// Height of a bar the peak does not reach. Close to the recording
    /// waveform's silent floor, deliberately (see the type's doc comment).
    public static let baseline: Float = 0.05

    /// Height of the bar under the centre of the peak. Same value as the
    /// transcription sine's crest.
    public static let crest: Float = 0.7

    /// Sweeps per second. One cycle carries the peak right and back again, so a
    /// single edge-to-edge crossing takes half of it.
    ///
    /// WHY 0.5 Hz, and why the number is set by contrast rather than in the
    /// abstract (device feedback, 2026-08-04): the transcription sine advances its
    /// phase by 0.5 per second, so its pattern crosses the row in 2.00 s. At the
    /// 0.7 Hz this first shipped with, the peak crossed in 0.71 s -- 2.8x faster,
    /// which read as rushed rather than as a different tempo. At 0.5 Hz a crossing
    /// takes exactly 1.00 s, twice the sine's speed. The tempo contrast is
    /// deliberate and stays; it was the ratio that was wrong.
    ///
    /// The floor under this number is the shortest stage worth animating: measured
    /// LLM stages ran 1 s and 3 s, and at 0.5 Hz even the 1 s one shows a whole
    /// crossing rather than a twitch.
    public static let phaseRate: Double = 0.5

    /// Where the peak sits, in bar units, at `phase` (in cycles).
    ///
    /// The sine gives the ends-of-travel their natural slow-down: the peak
    /// decelerates into each edge and accelerates out of it, which is what makes
    /// the motion read as a scan rather than a bouncing ball.
    public static func peakPosition(phase: Double) -> Double {
        Double(barCount - 1) * (1 + sin(2 * .pi * phase)) / 2
    }

    /// Bar heights with the peak centred on `peakPosition`.
    ///
    /// The falloff is a raised cosine, so the bump has no corner at its apex and
    /// meets the baseline tangentially at `halfWidth`.
    public static func levels(peakPosition: Double) -> [Float] {
        (0..<barCount).map { level(at: $0, peakPosition: peakPosition) }
    }

    /// Bar heights at `phase` (in cycles).
    public static func levels(phase: Double) -> [Float] {
        levels(peakPosition: peakPosition(phase: phase))
    }

    /// Height of one bar. Kept separate so the view can ask per index without
    /// allocating an array every frame.
    public static func level(at index: Int, peakPosition: Double) -> Float {
        let distance = abs(Double(index) - peakPosition)
        guard distance < halfWidth else { return baseline }
        let bump = 0.5 + 0.5 * cos(.pi * distance / halfWidth)
        return baseline + (crest - baseline) * Float(bump)
    }

    /// The phase whose peak sits at the centre of the row. Where each stage starts,
    /// so the peak enters from the middle and sweeps out rather than appearing
    /// mid-travel.
    ///
    /// WHY zero and not a computed value: `sin(0) == 0` already puts the peak at
    /// `(barCount - 1) / 2`. Naming it stops the phase reset from looking like it
    /// forgot to initialise something.
    public static let centredPhase: Double = 0

    // MARK: - Advancing the phase

    /// Phase per second for the transcription sine (`.sweep`).
    ///
    /// WHY it lives here, next to the travelling peak's rate, when the sine is drawn
    /// by each surface's own `processingEnergy`: the two animations share one phase
    /// variable, and until now this number existed only as a `/ 2.0` written inline in
    /// two display-link callbacks. A rate that is only visible at the point it is
    /// consumed is a rate that drifts apart between surfaces.
    ///
    /// The sine's pattern translates by one full row per unit of phase, so 0.5 is the
    /// 2.00 s crossing that `phaseRate` and `TranscribingStageHold` are both stated
    /// against. The value is unchanged from the inline divisor (#314 is about the
    /// animation running at the speed it was designed for, not about a new speed).
    public static let sweepPhaseRate: Double = 0.5

    /// The most real time a single frame is allowed to advance the phase by.
    ///
    /// WHY a ceiling at all: with the phase advancing by real elapsed time, a gap of
    /// any size advances by that size -- and the gaps that are not dropped frames are
    /// enormous. The keyboard extension is suspended and resumed, the device sleeps,
    /// the display link is left registered across an App Group round trip. Unclamped,
    /// the first frame after such a gap teleports the peak to an arbitrary point of its
    /// travel, which is a worse artefact than the slowdown this fix removes.
    ///
    /// WHY 100 ms. It has to sit above any hitch worth catching up and below any gap
    /// worth abandoning. Six frames at 60 Hz is far more than a stutter costs, so
    /// ordinary jank is still absorbed in full; and it is a fifth of the 500 ms
    /// `waveformStall` threshold, so anything the log calls a stall is always clamped.
    /// At the peak's 0.5 Hz the ceiling caps one frame's travel at 5 % of a cycle,
    /// which cannot read as a jump.
    public static let maxPhaseAdvanceSeconds: Double = 0.1

    /// How far the shared phase moves in `elapsedSeconds` of real time.
    ///
    /// WHY the drivers must not do this themselves (#314): both used to advance the
    /// phase by `CADisplayLink.duration`, the *nominal* interval between refreshes.
    /// That number does not grow when a callback is late and does not account for a
    /// frame that was skipped, so under load -- App Group writes, text insertion,
    /// polish completing on the app side -- the phase fell behind real time by exactly
    /// the frames that were lost, permanently. The animation did not stutter, it ran
    /// slow, which is what was reported. Elapsed time makes a dropped frame *skip*
    /// where the nominal duration made it *slow*.
    ///
    /// Negative elapsed times clamp to zero. Both surfaces feed this from
    /// `CADisplayLink.timestamp`, which is monotonic, but the same guard is what
    /// `TranscribingStageHold` learned to want from a clock that moved backwards, and
    /// a negative advance would run the animation in reverse for a frame.
    public static func phaseAdvance(for animation: WaveformAnimation, elapsedSeconds: Double) -> Double {
        let clamped = min(max(elapsedSeconds, 0), maxPhaseAdvanceSeconds)

        switch animation {
        case .sweep:
            return clamped * sweepPhaseRate
        case .travellingPeak:
            return clamped * phaseRate
        case .micLevels, .still:
            // Neither draws from the phase: the mic levels follow live energy, and a
            // still waveform is not moving at all.
            return 0
        }
    }
}
