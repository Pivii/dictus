import XCTest
@testable import DictusCore

/// Coverage for the converter-reuse decision behind the tap format-mismatch fix (issue #417).
///
/// These tests exist because the code that consumes the decision cannot be unit-tested: it is
/// the body of an `AVAudioEngine` tap callback, on a real-time thread, inside a `@MainActor`
/// class in the DictusApp target. The decision itself is the substance of the fix — the tap
/// now installs with `format: nil` and learns its input format from the buffers — so it is
/// the part worth pinning down.
///
/// The policy is generic over an `Equatable` format so the engine can pass `AVAudioFormat`
/// and keep AVFoundation's own equality. These tests stand in a `Format` of their own, which
/// is the point: what is being asserted is the branching, not `AVAudioFormat.isEqual`.
final class AudioConverterCachePolicyTests: XCTestCase {

    /// Stands in for `AVAudioFormat`. Named after the two fields that actually differ between
    /// the routes Dictus sees — 48 kHz mono built-in mic, 16 kHz mono bluetooth HFP.
    private struct Format: Equatable {
        let sampleRate: Double
        let channels: Int
    }

    private let builtInMic = Format(sampleRate: 48000, channels: 1)
    private let bluetoothHFP = Format(sampleRate: 16000, channels: 1)
    private let stereo = Format(sampleRate: 48000, channels: 2)

    // MARK: - reuse

    func testAConverterForThisFormatIsReused() {
        // The normal case, and the one that has to stay allocation-free: `startEngine`
        // pre-built a converter from the format the node reported, the bus delivers that
        // same format, nothing is built on the audio thread.
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: builtInMic,
                lastUnconvertibleFormat: nil,
                bufferFormat: builtInMic
            ),
            .reuse
        )
    }

    func testAHeldConverterWinsOverAFailureMemoForTheSameFormat() {
        // Cannot arise from the call site — a format that failed to build leaves no
        // converter — but the order of the two checks should not depend on that.
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: builtInMic,
                lastUnconvertibleFormat: builtInMic,
                bufferFormat: builtInMic
            ),
            .reuse
        )
    }

    // MARK: - build

    func testTheFirstBufferBuildsTheConverter() {
        // `startEngine`'s pre-build is best effort: when it returned nil there is nothing
        // held, and the first buffer's own format is the authoritative one.
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: nil,
                lastUnconvertibleFormat: nil,
                bufferFormat: builtInMic
            ),
            .build
        )
    }

    func testAMidRecordingRouteChangeRebuilds() {
        // The second failure this fix closes: before #417 the converter kept converting
        // from 48 kHz after the route moved to a 16 kHz bluetooth headset.
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: builtInMic,
                lastUnconvertibleFormat: nil,
                bufferFormat: bluetoothHFP
            ),
            .build
        )
    }

    func testAChannelCountChangeAloneRebuilds() {
        // Same sample rate, different channel count — still a different converter.
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: builtInMic,
                lastUnconvertibleFormat: nil,
                bufferFormat: stereo
            ),
            .build
        )
    }

    func testAFailureMemoDoesNotBlockADifferentFormat() {
        // The memo is a property of one format, not a latch on the tap: a route that moves
        // away from the unconvertible format must get its converter built.
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: nil,
                lastUnconvertibleFormat: stereo,
                bufferFormat: builtInMic
            ),
            .build
        )
    }

    // MARK: - skip

    func testTheFormatThatAlreadyFailedIsNotRetried() {
        XCTAssertEqual(
            AudioConverterCachePolicy.decide(
                heldInputFormat: nil,
                lastUnconvertibleFormat: stereo,
                bufferFormat: stereo
            ),
            .skipUnconvertibleFormat
        )
    }

    func testAnUnconvertibleFormatIsAttemptedExactlyOnce() {
        // The guarantee the audio thread depends on: buffers arrive at roughly 100 Hz, and
        // only the first of them may attempt an allocation.
        var lastUnconvertible: Format?
        var decisions: [AudioConverterCacheDecision] = []
        for _ in 0..<10 {
            let decision = AudioConverterCachePolicy.decide(
                heldInputFormat: nil,
                lastUnconvertibleFormat: lastUnconvertible,
                bufferFormat: stereo
            )
            decisions.append(decision)
            // Stands in for the call site: the build was attempted and refused.
            if decision == .build { lastUnconvertible = stereo }
        }
        XCTAssertEqual(decisions.filter { $0 == .build }.count, 1)
        XCTAssertEqual(decisions.last, .skipUnconvertibleFormat)
    }

    // MARK: - a settled route stops deciding anything

    func testASettledRouteReusesForever() {
        // The mirror of the test above, on the healthy path: once the converter matches the
        // bus, no later buffer may ask for a build.
        var held: Format? = builtInMic
        var decisions: [AudioConverterCacheDecision] = []
        for _ in 0..<10 {
            let decision = AudioConverterCachePolicy.decide(
                heldInputFormat: held,
                lastUnconvertibleFormat: nil,
                bufferFormat: builtInMic
            )
            decisions.append(decision)
            if decision == .build { held = builtInMic }
        }
        XCTAssertTrue(decisions.allSatisfy { $0 == .reuse })
    }
}
