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
