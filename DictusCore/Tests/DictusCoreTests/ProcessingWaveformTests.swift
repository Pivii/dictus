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

    /// The reduced-motion fallback freezes the phase rather than flattening the
    /// bars, so the frozen pose has to be the centred one -- a peak parked against
    /// an edge would read as a rendering fault.
    func testTheFrozenReducedMotionPoseIsCentred() {
        XCTAssertEqual(
            ProcessingWaveform.peakPosition(phase: ProcessingWaveform.centredPhase),
            centre,
            accuracy: 0.0001
        )
    }

    /// 0.7 Hz means a round trip in about 1.4 s, so a 3 s wait -- the short end of
    /// today's polish -- shows two full sweeps.
    func testACycleFitsTwiceIntoTheShortestExpectedWait() {
        let cycleSeconds = 1 / ProcessingWaveform.phaseRate
        XCTAssertLessThan(cycleSeconds * 2, 3.0)
    }
}
