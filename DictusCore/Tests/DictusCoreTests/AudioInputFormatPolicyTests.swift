import XCTest
@testable import DictusCore

/// Coverage for the input-format decision behind the dead-input-node fix (issue #123).
///
/// These tests exist because `UnifiedAudioEngine.startEngine` cannot be unit-tested:
/// it is `@MainActor`, owns a live `AVAudioEngine` and lives in the DictusApp target.
/// The three-way decision below is the whole substance of the fix, so it is the part
/// worth pinning down — especially since the failure it addresses cannot be reproduced
/// on demand on a device.
final class AudioInputFormatPolicyTests: XCTestCase {

    // MARK: - proceed

    func testHealthyFormatProceeds() {
        // 48 kHz mono is what the built-in mic reports on every device Dictus runs on.
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 1, sampleRate: 48000, hasRebuiltEngine: false),
            .proceed
        )
    }

    func testHealthyFormatProceedsAfterARebuild() {
        // The point of the rebuild: the new node reports a usable format and recording
        // goes ahead. Before #123 there was no path from a dead format to this outcome
        // short of the user force-quitting the app.
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 1, sampleRate: 48000, hasRebuiltEngine: true),
            .proceed
        )
    }

    // MARK: - rebuild

    func testMeasuredDeadFormatAsksForARebuild() {
        // The exact signature captured on device: `invalid hwFormat: sr=0.0 ch=2`.
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 2, sampleRate: 0, hasRebuiltEngine: false),
            .rebuildEngine
        )
    }

    func testZeroChannelsAsksForARebuild() {
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 0, sampleRate: 48000, hasRebuiltEngine: false),
            .rebuildEngine
        )
    }

    func testFullyEmptyFormatAsksForARebuild() {
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 0, sampleRate: 0, hasRebuiltEngine: false),
            .rebuildEngine
        )
    }

    func testNaNSampleRateIsTreatedAsDead() {
        // No capture has produced one, but it is representable and it must not slip
        // through `> 0` into an AVAudioConverter.
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 1, sampleRate: .nan, hasRebuiltEngine: false),
            .rebuildEngine
        )
    }

    // MARK: - fail

    func testDeadSampleRateAfterTheRebuildFails() {
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 2, sampleRate: 0, hasRebuiltEngine: true),
            .fail(.zeroSampleRate)
        )
    }

    func testZeroChannelsAfterTheRebuildFails() {
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 0, sampleRate: 48000, hasRebuiltEngine: true),
            .fail(.zeroChannelCount)
        )
    }

    func testFullyEmptyFormatAfterTheRebuildNamesTheChannels() {
        // Both halves are missing; the channel count is the one reported, because it is
        // the more fundamental absence.
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 0, sampleRate: 0, hasRebuiltEngine: true),
            .fail(.zeroChannelCount)
        )
    }

    func testNaNSampleRateAfterTheRebuildFails() {
        XCTAssertEqual(
            AudioInputFormatPolicy.decide(channelCount: 1, sampleRate: .nan, hasRebuiltEngine: true),
            .fail(.zeroSampleRate)
        )
    }

    // MARK: - the loop terminates

    func testAtMostOneRebuildIsEverAsked() {
        // The guarantee the call site depends on: feed the decision back to itself with
        // `hasRebuiltEngine` set from the previous answer and it must reach a terminal
        // outcome, never a second `.rebuildEngine`.
        var hasRebuilt = false
        var decisions: [AudioInputFormatDecision] = []
        for _ in 0..<5 {
            let decision = AudioInputFormatPolicy.decide(
                channelCount: 2, sampleRate: 0, hasRebuiltEngine: hasRebuilt
            )
            decisions.append(decision)
            if decision == .rebuildEngine { hasRebuilt = true }
        }
        XCTAssertEqual(decisions.filter { $0 == .rebuildEngine }.count, 1)
        XCTAssertEqual(decisions.last, .fail(.zeroSampleRate))
    }
}
