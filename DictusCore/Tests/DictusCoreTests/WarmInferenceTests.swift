// DictusCore/Tests/DictusCoreTests/WarmInferenceTests.swift
// The two rules the discarded inference stands on (#426).
//
// Neither of them can be checked where the warm inference actually runs: that path
// needs a compiled Core ML model on a Neural Engine, and this suite runs on the Mac
// with neither. What it can check is the policy the app asks before running one, and
// the shape of the buffer it runs on — which is where the trap is. A buffer of one
// second or less makes WhisperKit skip its decode window entirely, so the warm
// inference would report a cheerful success having specialized nothing.
import XCTest
@testable import DictusCore

final class WarmInferenceLedgerTests: XCTestCase {

    /// The whole point: one throwaway inference per load, and no more.
    func testFirstClaimSucceedsAndTheSecondDoesNot() {
        var ledger = WarmInferenceLedger()
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
        XCTAssertFalse(ledger.claim("openai_whisper-small"))
        XCTAssertFalse(ledger.claim("openai_whisper-small"))
    }

    /// A foreground return finds the model already loaded and asks again. It must not
    /// buy a second inference: the latency win is felt once, the battery cost would be
    /// paid every time the user comes back to the app.
    func testRepeatForegroundingOfTheWarmModelClaimsNothing() {
        var ledger = WarmInferenceLedger()
        XCTAssertTrue(ledger.claim("openai_whisper-large-v3-v20240930_turbo_632MB"))
        for _ in 0..<5 {
            XCTAssertFalse(ledger.claim("openai_whisper-large-v3-v20240930_turbo_632MB"))
        }
        XCTAssertEqual(ledger.warmModel, "openai_whisper-large-v3-v20240930_turbo_632MB")
    }

    /// Switching models builds a new engine, and a new engine is cold.
    func testSwitchingModelClaims() {
        var ledger = WarmInferenceLedger()
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
        XCTAssertTrue(ledger.claim("openai_whisper-medium"))
        XCTAssertEqual(ledger.warmModel, "openai_whisper-medium")
    }

    /// And switching BACK claims again. The single slot is the point: Dictus holds one
    /// engine, so returning to a model means loading a fresh, cold instance of it, not
    /// recovering the one that was warm before.
    func testReturningToAPreviouslyWarmModelClaimsAgain() {
        var ledger = WarmInferenceLedger()
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
        XCTAssertTrue(ledger.claim("openai_whisper-medium"))
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
    }

    /// An inference that threw, or a load discarded before its engine was published,
    /// leaves a model that is not warm. Recording it as warm would make the next load
    /// of it skip the only thing this mechanism does.
    func testReleaseLetsTheModelBeClaimedAgain() {
        var ledger = WarmInferenceLedger()
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
        ledger.release(ifMatches: "openai_whisper-small")
        XCTAssertNil(ledger.warmModel)
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
    }

    /// A release naming a different model is a no-op, not a way to clear somebody
    /// else's claim — same identity rule as `clearInitTask(ifStillCurrent:)`.
    func testReleaseOfAnotherModelIsANoOp() {
        var ledger = WarmInferenceLedger()
        XCTAssertTrue(ledger.claim("openai_whisper-small"))
        ledger.release(ifMatches: "openai_whisper-medium")
        XCTAssertEqual(ledger.warmModel, "openai_whisper-small")
        XCTAssertFalse(ledger.claim("openai_whisper-small"))
    }

    func testAFreshLedgerHoldsNothing() {
        let ledger = WarmInferenceLedger()
        XCTAssertNil(ledger.warmModel)
    }
}

final class WarmInferenceAudioTests: XCTestCase {

    /// THE TRAP THIS SUITE EXISTS FOR. WhisperKit's decode loop is
    /// `while seek < seekClipEnd - windowPadding`, and `windowPadding` is
    /// `DecodingOptions.windowClipTime` (1.0 s by default) times the sample rate. A
    /// buffer at or below that clip runs zero encoder passes: the warm inference would
    /// return without error, log a duration, and have specialized nothing.
    func testBufferIsLongerThanWhisperKitsWindowClip() {
        let whisperKitDefaultWindowClipSamples = WarmInferenceAudio.sampleRate
        XCTAssertGreaterThan(WarmInferenceAudio.sampleCount, whisperKitDefaultWindowClipSamples)
    }

    /// Parakeet's own floor, declared by FluidAudio and restated in `ParakeetEngine`.
    /// One buffer has to clear both engines' floors, because one constant serves both.
    func testBufferClearsParakeetsOneSecondFloor() {
        XCTAssertGreaterThanOrEqual(WarmInferenceAudio.sampleCount, WarmInferenceAudio.sampleRate)
    }

    func testSampleCountMatchesTheDeclaredDuration() {
        XCTAssertEqual(WarmInferenceAudio.sampleCount, 32_000)
        XCTAssertEqual(WarmInferenceAudio.silence().count, WarmInferenceAudio.sampleCount)
    }

    /// Silence, and nothing but. Shape specialization is per tensor shape, so the values
    /// buy nothing — but a non-zero buffer would let the decoder hallucinate its way
    /// through a long token loop for no gain.
    func testBufferIsSilent() {
        XCTAssertTrue(WarmInferenceAudio.silence().allSatisfy { $0 == 0 })
    }
}
