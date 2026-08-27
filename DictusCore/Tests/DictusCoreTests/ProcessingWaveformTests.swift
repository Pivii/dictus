// DictusCore/Tests/DictusCoreTests/ProcessingWaveformTests.swift
// The shape and the travel of the LLM-stage animation (#267).

import XCTest
@testable import DictusCore

/// Coverage for the travelling-peak sweep.
///
/// These tests exist because the animation itself is unreachable from a test: it
/// lives behind a `CADisplayLink` in `DictusKeyboard`, a target with no test
/// bundle, inside a keyboard extension a simulator cannot even enable. What can be
/// pinned is the arithmetic that decides every bar's height, and that is where the
/// property the issue asks for lives -- "reads as a different family from the
/// transcription sine" is, concretely, "localized peak" against "continuous wave".
final class ProcessingWaveformTests: XCTestCase {

    private var barCount: Int { ProcessingWaveform.barCount }
    private var centre: Double { Double(ProcessingWaveform.barCount - 1) / 2 }

    // MARK: - The shape is a localized peak

    func testTheBarUnderThePeakIsAtTheCrest() {
        let levels = ProcessingWaveform.levels(peakPosition: 0)
        XCTAssertEqual(levels[0], ProcessingWaveform.crest, accuracy: 0.0001)
    }

    func testBarsBeyondTheHalfWidthSitAtTheBaseline() {
        let levels = ProcessingWaveform.levels(peakPosition: 0)
        let firstOutside = Int(ProcessingWaveform.halfWidth)
        for index in firstOutside..<barCount {
            XCTAssertEqual(
                levels[index], ProcessingWaveform.baseline, accuracy: 0.0001,
                "bar \(index) is \(ProcessingWaveform.halfWidth) or more from the peak"
            )
        }
    }

    /// The defining difference from the transcription sine, stated as the issue
    /// states it: one is a localized peak, the other a continuous wave. Concretely,
    /// at every instant the peak leaves a large run of bars sitting at exactly the
    /// same floor, which a sine never does -- it is somewhere on its curve
    /// everywhere. This is the property that survives a glance at a 120 pt-tall
    /// waveform, and the reason the two states can be told apart at all.
    func testThePeakAlwaysLeavesAFlatRunThatTheTranscriptionSweepNeverHas() {
        for step in 0..<20 {
            let phase = Double(step) / 20

            let peakLevels = ProcessingWaveform.levels(phase: phase)
            let flatUnderPeak = peakLevels.filter { abs($0 - ProcessingWaveform.baseline) < 0.0001 }.count
            XCTAssertGreaterThanOrEqual(
                flatUnderPeak, barCount / 3,
                "phase \(phase): only \(flatUnderPeak) of \(barCount) bars are at the floor"
            )

            let sweepLevels = (0..<barCount).map { transcriptionSweepLevel(at: $0, phase: phase) }
            let sweepFloor = sweepLevels.min() ?? 0
            let flatUnderSweep = sweepLevels.filter { abs($0 - sweepFloor) < 0.0001 }.count
            XCTAssertLessThanOrEqual(
                flatUnderSweep, 2,
                "phase \(phase): the sine is supposed to have no flat run, it has \(flatUnderSweep)"
            )
        }
    }

    /// `KeyboardWaveformDriver.processingEnergy`, duplicated because the driver
    /// lives in the keyboard target this bundle cannot import. Kept to one call
    /// site: the test above, which exists to contrast the two curves.
    private func transcriptionSweepLevel(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    /// Heights fall away monotonically from the peak, which is what makes the shape
    /// read as one bump rather than as noise.
    func testHeightsDecreaseMonotonicallyAwayFromThePeak() {
        let levels = ProcessingWaveform.levels(peakPosition: centre)
        let peakIndex = Int(centre.rounded())
        for index in (peakIndex + 1)..<barCount {
            XCTAssertLessThanOrEqual(levels[index], levels[index - 1], "rising again at bar \(index)")
        }
        for index in stride(from: peakIndex - 1, through: 0, by: -1) {
            XCTAssertLessThanOrEqual(levels[index], levels[index + 1], "rising again at bar \(index)")
        }
    }

    func testEveryLevelStaysBetweenBaselineAndCrest() {
        for step in 0..<40 {
            for level in ProcessingWaveform.levels(phase: Double(step) / 40) {
                XCTAssertGreaterThanOrEqual(level, ProcessingWaveform.baseline)
                XCTAssertLessThanOrEqual(level, ProcessingWaveform.crest)
            }
        }
    }

    /// The issue's reason for reusing the transcription crest: same visual
    /// vocabulary, different motion. `KeyboardWaveformDriver.processingEnergy`
    /// tops out at 0.2 + 0.25 * 2 = 0.7.
    func testTheCrestMatchesTheTranscriptionSweep() {
        XCTAssertEqual(ProcessingWaveform.crest, 0.7, accuracy: 0.0001)
    }

    // MARK: - The peak travels

    func testThePeakSweepsTheFullWidthAndComesBack() {
        var positions: [Double] = []
        for step in 0...100 {
            positions.append(ProcessingWaveform.peakPosition(phase: Double(step) / 100))
        }
        XCTAssertEqual(positions.min() ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(positions.max() ?? -1, Double(barCount - 1), accuracy: 0.01)
        // One cycle ends where it began: the travel is a round trip, not a jump
        // back to the start.
        XCTAssertEqual(positions.first ?? 0, positions.last ?? -1, accuracy: 0.0001)
    }

    func testThePeakIsMovingAtTheStartOfACycle() {
        let start = ProcessingWaveform.peakPosition(phase: 0)
        let shortlyAfter = ProcessingWaveform.peakPosition(phase: 0.01)
        XCTAssertGreaterThan(shortlyAfter, start)
    }

    /// Each stage starts from `centredPhase`, so the peak has to enter from the
    /// middle rather than appear mid-travel against an edge.
    ///
    /// This assertion outlived the reduced-motion fallback it was first written
    /// for: that freeze was removed by maintainer decision after device testing
    /// (see `KeyboardWaveformDriver.needsDisplayLink`). The starting pose is still
    /// worth pinning.
    func testTheStartingPoseIsCentred() {
        XCTAssertEqual(
            ProcessingWaveform.peakPosition(phase: ProcessingWaveform.centredPhase),
            centre,
            accuracy: 0.0001
        )
    }

    /// The tempo is set by contrast with the animation it follows, not in the
    /// abstract. The peak crosses the row in half a cycle; the sine crosses it in
    /// one phase unit. Shipping 0.7 Hz made the peak 2.8x faster than the sine,
    /// which read as rushed on device -- 0.5 Hz makes it exactly twice.
    func testThePeakCrossesTheRowTwiceAsFastAsTheTranscriptionSweep() {
        XCTAssertEqual(peakCrossingSeconds, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transcriptionSweepCrossingSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(
            transcriptionSweepCrossingSeconds / peakCrossingSeconds, 2, accuracy: 0.0001
        )
    }

    /// The shortest LLM stage measured on device ran 1 s. It has to show a whole
    /// crossing, or the animation reads as a twitch and says nothing.
    func testTheShortestMeasuredStageStillShowsAWholeCrossing() {
        XCTAssertLessThanOrEqual(peakCrossingSeconds, 1.0)
    }

    /// Seconds for the peak to travel from one edge to the other: half a cycle,
    /// since a full cycle is out and back.
    private var peakCrossingSeconds: Double {
        1 / (2 * ProcessingWaveform.phaseRate)
    }

    /// Seconds for the transcription sine's pattern to cross the row. Its phase
    /// advances by 0.5 per second and the pattern translates by one full row per unit
    /// of phase.
    private var transcriptionSweepCrossingSeconds: Double {
        1 / ProcessingWaveform.sweepPhaseRate
    }

    // MARK: - The phase advances with real time, not with frames

    private let selfDrivenAnimations: [WaveformAnimation] = [.sweep, .travellingPeak]

    /// The defect #314 reports, stated as a test: the phase has to depend on how much
    /// time passed, not on how many callbacks arrived. Both drivers used to advance it
    /// by `CADisplayLink.duration`, so a run of frames at 120 Hz and the same wall-clock
    /// interval at 60 Hz produced *different* totals -- and a dropped frame, which is
    /// the same shape of discrepancy, cost travel that was never recovered.
    func testTheSameElapsedTimeAdvancesTheSameAmountAtAnyFrameRate() {
        for animation in selfDrivenAnimations {
            let atHighRefreshRate = totalPhase(for: animation, ticks: 20, each: 1.0 / 120)
            let atStandardRefreshRate = totalPhase(for: animation, ticks: 10, each: 1.0 / 60)

            XCTAssertEqual(
                atHighRefreshRate, atStandardRefreshRate, accuracy: 0.000_001,
                "\(animation): 20 frames at 120 Hz and 10 at 60 Hz are the same sixth of a second"
            )
            XCTAssertGreaterThan(atHighRefreshRate, 0, "\(animation): the phase did not move at all")
        }
    }

    /// One long frame is worth exactly the frames it replaced. This is what makes a
    /// dropped frame skip rather than slow: the phase arrives where it would have been
    /// had every frame been delivered.
    func testAFrameThatSwallowedItsNeighboursAdvancesByTheirTotal() {
        for animation in selfDrivenAnimations {
            let fiveFrames = totalPhase(for: animation, ticks: 5, each: 1.0 / 60)
            let oneLateFrame = ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: 5.0 / 60)

            XCTAssertEqual(fiveFrames, oneLateFrame, accuracy: 0.000_001, "\(animation)")
        }
    }

    /// The ceiling is what separates a dropped frame from a suspended extension. A gap
    /// large enough to be a stall must not hand the peak an arbitrary position.
    func testAnElapsedTimeAboveTheCeilingAdvancesByTheCeiling() {
        for animation in selfDrivenAnimations {
            let atTheCeiling = ProcessingWaveform.phaseAdvance(
                for: animation, elapsedSeconds: ProcessingWaveform.maxPhaseAdvanceSeconds
            )

            for elapsed in [ProcessingWaveform.maxPhaseAdvanceSeconds + 0.001, 0.5, 30, 3600] {
                XCTAssertEqual(
                    ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: elapsed),
                    atTheCeiling, accuracy: 0.000_001,
                    "\(animation): \(elapsed) s advanced by more than the ceiling"
                )
            }
        }
    }

    /// Under the ceiling nothing is clamped, or the fix would have traded a slow
    /// animation for one that is slow only under load.
    func testAnOrdinaryFrameIsNotClamped() {
        let ordinaryGaps = [1.0 / 120, 1.0 / 60, 1.0 / 30, ProcessingWaveform.maxPhaseAdvanceSeconds - 0.001]

        for animation in selfDrivenAnimations {
            for elapsed in ordinaryGaps {
                let rate = animation == .sweep ? ProcessingWaveform.sweepPhaseRate : ProcessingWaveform.phaseRate
                XCTAssertEqual(
                    ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: elapsed),
                    elapsed * rate, accuracy: 0.000_001,
                    "\(animation): \(elapsed) s was clamped and should not have been"
                )
            }
        }
    }

    /// A clock that moved backwards must not run the animation in reverse for a frame.
    /// Both surfaces feed this from `CADisplayLink.timestamp`, which is monotonic; the
    /// guard is the same one `TranscribingStageHold` needed for its wall clock.
    func testANegativeElapsedTimeDoesNotMoveThePhaseBackwards() {
        for animation in selfDrivenAnimations {
            XCTAssertEqual(
                ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: -1), 0, accuracy: 0.000_001,
                "\(animation)"
            )
        }
    }

    /// The mic levels follow live energy and a still waveform is not moving, so neither
    /// reads the phase. Advancing it under them would leave the next self-driven stage
    /// starting somewhere other than `centredPhase`.
    func testTheAnimationsThatDoNotUseThePhaseDoNotAdvanceIt() {
        for animation in [WaveformAnimation.micLevels, .still] {
            XCTAssertEqual(
                ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: 1.0 / 60), 0,
                "\(animation)"
            )
        }
    }

    /// The peak's tempo, restated through the advance function rather than the constant:
    /// half a cycle -- one edge-to-edge crossing -- takes the second the rate promises.
    func testASecondOfRealTimeCarriesThePeakAcrossTheRow() {
        var phase = ProcessingWaveform.centredPhase
        for _ in 0..<60 {
            phase += ProcessingWaveform.phaseAdvance(for: .travellingPeak, elapsedSeconds: 1.0 / 60)
        }

        XCTAssertEqual(phase, 0.5, accuracy: 0.000_001, "half a cycle in one second")
        XCTAssertEqual(
            ProcessingWaveform.peakPosition(phase: phase), centre, accuracy: 0.000_001,
            "back at the centre, having been to one edge and returned"
        )
    }

    private func totalPhase(for animation: WaveformAnimation, ticks: Int, each elapsed: Double) -> Double {
        (0..<ticks).reduce(0) { total, _ in
            total + ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: elapsed)
        }
    }
}
