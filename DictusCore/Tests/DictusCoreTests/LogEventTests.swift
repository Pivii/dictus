// DictusCore/Tests/DictusCoreTests/LogEventTests.swift
// Tests for LogEvent level and subsystem mapping.
import XCTest
@testable import DictusCore

final class LogEventTests: XCTestCase {

    // MARK: - LogLevel cases

    func testLogLevelHasExactly4Cases() {
        XCTAssertEqual(LogLevel.allCases.count, 4)
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, "debug")
        XCTAssertEqual(LogLevel.info.rawValue, "info")
        XCTAssertEqual(LogLevel.warning.rawValue, "warning")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
    }

    func testLogLevelPaddedName() {
        // All padded names should be 7 chars for alignment
        XCTAssertEqual(LogLevel.debug.paddedName, "DEBUG  ")
        XCTAssertEqual(LogLevel.info.paddedName, "INFO   ")
        XCTAssertEqual(LogLevel.warning.paddedName, "WARNING")
        XCTAssertEqual(LogLevel.error.paddedName, "ERROR  ")
    }

    // MARK: - Subsystem cases

    func testSubsystemHasExactly6Cases() {
        XCTAssertEqual(Subsystem.allCases.count, 6)
    }

    func testSubsystemRawValues() {
        XCTAssertEqual(Subsystem.dictation.rawValue, "dictation")
        XCTAssertEqual(Subsystem.audio.rawValue, "audio")
        XCTAssertEqual(Subsystem.transcription.rawValue, "transcription")
        XCTAssertEqual(Subsystem.model.rawValue, "model")
        XCTAssertEqual(Subsystem.keyboard.rawValue, "keyboard")
        XCTAssertEqual(Subsystem.lifecycle.rawValue, "lifecycle")
    }

    // MARK: - Dictation events

    func testDictationStartedIsInfoDictation() {
        let event = LogEvent.dictationStarted(fromURL: true, appState: "active", engineRunning: true)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .dictation)
    }

    func testDictationCompletedIsInfoDictation() {
        let event = LogEvent.dictationCompleted(durationMs: 3000)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .dictation)
    }

    func testDictationFailedIsErrorDictation() {
        let event = LogEvent.dictationFailed(error: "timeout")
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.subsystem, .dictation)
    }

    func testDictationDeferredIsWarningDictation() {
        let event = LogEvent.dictationDeferred(reason: "engineNotReady")
        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.subsystem, .dictation)
    }

    func testDictationStateReconciledIsWarningDictation() {
        let event = LogEvent.dictationStateReconciled(
            source: "keyboard-refresh",
            staleStatus: "recording",
            heartbeatAgeMs: 23_000
        )
        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.subsystem, .dictation)
    }

    func testDictationStateReconciledIsGreppableWithItsEvidence() {
        // Issue #261 acceptance criterion 4: the exported log must carry an explicit
        // event for the reconciliation, so this failure is self-diagnosing without a
        // rebuild — the same rationale as `localModelResolved` for #249. The name and
        // the heartbeat age are what a reader greps for, so both are pinned here.
        let event = LogEvent.dictationStateReconciled(
            source: "keyboard-watchdog",
            staleStatus: "recording",
            heartbeatAgeMs: 23_000
        )
        XCTAssertEqual(event.name, "dictationStateReconciled")
        XCTAssertEqual(
            event.message,
            "source=keyboard-watchdog staleStatus=recording heartbeatAgeMs=23000"
        )
    }

    func testDictationStateReconciledReportsAnAbsentHeartbeatAsMinusOne() {
        // The app-side launch audit reaches its verdict from the fact that a fresh
        // process owns no session, so it has no heartbeat to report.
        let event = LogEvent.dictationStateReconciled(
            source: "app-launch",
            staleStatus: "transcribing",
            heartbeatAgeMs: -1
        )
        XCTAssertEqual(event.message, "source=app-launch staleStatus=transcribing heartbeatAgeMs=-1")
    }

    // MARK: - Stranded cold start (#311)

    func testColdStartStrandedIsAWarningWithItsResolution() {
        // #311's regression grep pivots on this name, and on `action` telling the
        // reader which of the three outcomes the parked start actually got. It is a
        // warning because a parked start reaching this point is a user-visible
        // request that nearly went nowhere.
        let event = LogEvent.coldStartStranded(keyboardStatus: "requested", action: "retry")
        XCTAssertEqual(event.name, "coldStartStranded")
        XCTAssertEqual(event.message, "keyboardStatus=requested action=retry")
        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.subsystem, .lifecycle)
    }

    func testColdStartStrandedCarriesTheStatusTheKeyboardWasShowing() {
        // A `dropped` line has to say what the stored status had become, because
        // that is the whole reason nothing was done about it.
        let event = LogEvent.coldStartStranded(keyboardStatus: "idle", action: "dropped")
        XCTAssertEqual(event.message, "keyboardStatus=idle action=dropped")
    }

    func testColdStartStrandedReportsAnExpiredAssertion() {
        // `expired` is the fourth vocabulary value and the only one that is not a
        // `ColdStartResolution`: the background assertion ran out with the request
        // still unresolved, which is a stranded start by definition.
        let event = LogEvent.coldStartStranded(keyboardStatus: "requested", action: "expired")
        XCTAssertEqual(event.message, "keyboardStatus=requested action=expired")
        XCTAssertEqual(event.level, .warning)
    }

    // MARK: - Keyboard status message trail (#261)

    func testDictationMessageSetIsGreppableWithItsOwner() {
        // The device test script tells the maintainer to grep these exact names, so
        // the names and the field order are a contract, not an implementation detail.
        let event = LogEvent.dictationMessageSet(reason: "reconciled-keyboard-refresh", owner: "9DF73D57", visible: true)
        XCTAssertEqual(event.name, "dictationMessageSet")
        XCTAssertEqual(event.message, "reason=reconciled-keyboard-refresh owner=9DF73D57 visible=true")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    func testDictationMessageDisplayedCarriesBothIdentities() {
        // `rootView` and `controller` against `owner` is what tests the hypothesis
        // that a message renders into a tree the user is not looking at.
        let event = LogEvent.dictationMessageDisplayed(
            rootView: "D67967A0",
            controller: "9DF73D57",
            owner: "9DF73D57",
            visible: true
        )
        XCTAssertEqual(event.name, "dictationMessageDisplayed")
        XCTAssertEqual(event.message, "rootView=D67967A0 controller=9DF73D57 owner=9DF73D57 visible=true")
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    func testDictationMessageClearedWarnsWhenNobodyRenderedIt() {
        // The whole point of counting: `displayedCount=0` is "the user was never
        // told", and it is findable by level as well as by reading the number.
        let unseen = LogEvent.dictationMessageCleared(reason: "reconciled-timeout", displayedCount: 0)
        XCTAssertEqual(unseen.name, "dictationMessageCleared")
        XCTAssertEqual(unseen.message, "reason=reconciled-timeout displayedCount=0")
        XCTAssertEqual(unseen.level, .warning)

        let seen = LogEvent.dictationMessageCleared(reason: "reconciled-timeout", displayedCount: 2)
        XCTAssertEqual(seen.level, .info)
    }

    // MARK: - Audio events

    func testAudioEngineStartedIsInfoAudio() {
        let event = LogEvent.audioEngineStarted
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .audio)
    }

    func testAudioEngineStoppedIsDebugAudio() {
        let event = LogEvent.audioEngineStopped
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .audio)
    }

    func testAudioSessionConfiguredIsInfoAudio() {
        let event = LogEvent.audioSessionConfigured(category: "playAndRecord")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .audio)
    }

    func testAudioSessionFailedIsErrorAudio() {
        let event = LogEvent.audioSessionFailed(error: "configError")
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.subsystem, .audio)
    }

    // MARK: - Transcription events

    func testTranscriptionStartedIsInfoTranscription() {
        let event = LogEvent.transcriptionStarted(modelName: "base")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .transcription)
    }

    func testTranscriptionCompletedIsInfoTranscription() {
        let event = LogEvent.transcriptionCompleted(durationMs: 2500, wordCount: 42)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .transcription)
    }

    func testTranscriptionFailedIsErrorTranscription() {
        let event = LogEvent.transcriptionFailed(error: "modelNotLoaded")
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.subsystem, .transcription)
    }

    // MARK: - Model events

    func testModelDownloadStartedIsInfoModel() {
        let event = LogEvent.modelDownloadStarted(name: "large-v3", sizeMB: 1500)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .model)
    }

    func testModelDownloadCompletedIsInfoModel() {
        let event = LogEvent.modelDownloadCompleted(name: "large-v3")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .model)
    }

    func testModelDownloadFailedIsErrorModel() {
        let event = LogEvent.modelDownloadFailed(name: "large-v3", error: "networkTimeout")
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.subsystem, .model)
    }

    func testModelSelectedIsInfoModel() {
        let event = LogEvent.modelSelected(name: "base")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .model)
    }

    func testModelCompilationStartedIsInfoModel() {
        let event = LogEvent.modelCompilationStarted(name: "base")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .model)
    }

    func testModelCompilationCompletedIsInfoModel() {
        let event = LogEvent.modelCompilationCompleted(name: "base", durationMs: 5000)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .model)
    }

    // MARK: - Keyboard events

    func testKeyboardDidAppearIsInfoKeyboard() {
        let event = LogEvent.keyboardDidAppear
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    func testKeyboardDidDisappearIsDebugKeyboard() {
        let event = LogEvent.keyboardDidDisappear
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    func testKeyboardMicTappedIsInfoKeyboard() {
        let event = LogEvent.keyboardMicTapped
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    func testKeyboardTextInsertedIsDebugKeyboard() {
        let event = LogEvent.keyboardTextInserted
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    // MARK: - Waveform frame cadence (#314)

    /// The issue asks for frame-gap evidence at a finer grain than the 500 ms
    /// `waveformStall` threshold: 50-100 ms is already enough to make a 60 Hz
    /// animation feel bad, and none of it was visible in a log. The heartbeat is
    /// where that evidence rides, because it is emitted every ~2 s and the log is
    /// capped and deduplicated (#255) -- a per-frame event was not an option.
    func testWaveformHeartbeatCarriesTheWorstFrameGapOfItsWindow() {
        let event = LogEvent.waveformHeartbeat(
            renderTick: 1200, avgLevel: 0.42, energyCount: 40, maxGapMs: 83
        )
        XCTAssertEqual(event.name, "waveformHeartbeat")
        XCTAssertEqual(
            event.message,
            "renderTick=1200 avgLevel=0.420 energyCount=40 maxGapMs=83"
        )
    }

    /// A window with no frame worth reporting still says so, rather than dropping the
    /// field: a reader comparing two heartbeats needs the healthy one to be readable
    /// as healthy, not as missing.
    func testWaveformHeartbeatReportsASmoothWindowAsZero() {
        let event = LogEvent.waveformHeartbeat(
            renderTick: 60, avgLevel: 0, energyCount: 0, maxGapMs: 0
        )
        XCTAssertEqual(event.message, "renderTick=60 avgLevel=0.000 energyCount=0 maxGapMs=0")
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .keyboard)
    }

    // MARK: - Lifecycle events

    func testAppLaunchedIsInfoLifecycle() {
        let event = LogEvent.appLaunched(version: "1.2")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .lifecycle)
    }

    func testAppDidBecomeActiveIsDebugLifecycle() {
        let event = LogEvent.appDidBecomeActive
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .lifecycle)
    }

    func testAppWillResignActiveIsDebugLifecycle() {
        let event = LogEvent.appWillResignActive
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .lifecycle)
    }

    func testAppDidEnterBackgroundIsDebugLifecycle() {
        let event = LogEvent.appDidEnterBackground
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .lifecycle)
    }

    func testWhisperKitLoadedIsInfoLifecycle() {
        let event = LogEvent.appWhisperKitLoaded(modelName: "base")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .lifecycle)
    }

    // MARK: - User dictionary events (#307)

    func testUserDictionaryWordLearnedIsDebugKeyboard() {
        let event = LogEvent.userDictionaryWordLearned(learnedCount: 42)
        XCTAssertEqual(event.level, .debug)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.message, "learnedCount=42")
    }

    func testUserDictionaryEvictedIsInfoKeyboard() {
        let event = LogEvent.userDictionaryEvicted(removed: 3, learnedCount: 1000, cap: 1000)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.message, "removed=3 learnedCount=1000 cap=1000")
    }

    func testUserDictionaryResetIsInfoKeyboard() {
        let event = LogEvent.userDictionaryReset(clearedCount: 17)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.message, "clearedCount=17")
    }

    func testUserDictionaryMigratedIsInfoKeyboard() {
        let event = LogEvent.userDictionaryMigrated(stamped: 12, droppedStamps: 2, learnedCount: 30)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.message, "stamped=12 droppedStamps=2 learnedCount=30")
    }

    func testUserDictionaryStaleDiscardedIsInfoKeyboard() {
        let event = LogEvent.userDictionaryStaleDiscarded(removed: 4, learnedCount: 26, days: 300)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.message, "removed=4 learnedCount=26 days=300")
    }

    func testUserDictionaryPrunedIsInfoKeyboard() {
        let event = LogEvent.userDictionaryPruned(removed: 20, learnedCount: 2)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.subsystem, .keyboard)
        XCTAssertEqual(event.message, "removed=20 learnedCount=2")
    }

    /// The privacy guarantee these events rest on is that none of them can carry
    /// a word at all: every associated value is an `Int`, so the formatted line
    /// is digits and fixed keys and nothing else. A future parameter of type
    /// `String` would break this test before it could reach an export.
    func testUserDictionaryEventsCannotCarryText() {
        let events: [LogEvent] = [
            .userDictionaryWordLearned(learnedCount: 42),
            .userDictionaryEvicted(removed: 3, learnedCount: 1000, cap: 1000),
            .userDictionaryReset(clearedCount: 17),
            .userDictionaryMigrated(stamped: 12, droppedStamps: 2, learnedCount: 30),
            .userDictionaryStaleDiscarded(removed: 4, learnedCount: 26, days: 300),
            .userDictionaryPruned(removed: 20, learnedCount: 2)
        ]
        let allowed = CharacterSet(charactersIn: "0123456789= ")
            .union(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        for event in events {
            XCTAssertNil(
                event.message.rangeOfCharacter(from: allowed.inverted),
                "\(event.name) formats something other than plain key=integer pairs"
            )
            // The parameter values themselves are digits only.
            let values = event.message.split(separator: " ").map { $0.split(separator: "=")[1] }
            for value in values {
                XCTAssertTrue(
                    value.allSatisfy(\.isNumber),
                    "\(event.name) has a non-numeric value \"\(value)\""
                )
            }
        }
    }

    // MARK: - Formatted output

    func testFormattedOutputContainsLevelSubsystemAndEventName() {
        let event = LogEvent.dictationStarted(fromURL: true, appState: "active", engineRunning: false)
        let formatted = event.formatted()
        // Should contain ISO8601 timestamp pattern, level, subsystem, event params
        XCTAssertTrue(formatted.contains("INFO"))
        XCTAssertTrue(formatted.contains("[dictation]"))
        XCTAssertTrue(formatted.contains("dictationStarted"))
        XCTAssertTrue(formatted.contains("fromURL=true"))
        XCTAssertTrue(formatted.contains("appState=active"))
        XCTAssertTrue(formatted.contains("engineRunning=false"))
    }

    func testFormattedOutputContainsISO8601Timestamp() {
        let event = LogEvent.audioEngineStarted
        let formatted = event.formatted()
        // ISO8601 timestamps look like [2026-03-11T14:23:01Z]
        let timestampPattern = #"\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]"#
        XCTAssertNotNil(formatted.range(of: timestampPattern, options: .regularExpression))
    }

    func testFormattedOutputForEventWithNoParams() {
        let event = LogEvent.keyboardTextInserted
        let formatted = event.formatted()
        XCTAssertTrue(formatted.contains("DEBUG"))
        XCTAssertTrue(formatted.contains("[keyboard]"))
        XCTAssertTrue(formatted.contains("keyboardTextInserted"))
    }
}
