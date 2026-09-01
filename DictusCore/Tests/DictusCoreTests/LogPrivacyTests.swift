// DictusCore/Tests/DictusCoreTests/LogPrivacyTests.swift
// Tests that no LogEvent formatted output leaks sensitive data.
import XCTest
@testable import DictusCore

final class LogPrivacyTests: XCTestCase {

    /// All possible LogEvent instances for exhaustive testing.
    private var allEvents: [LogEvent] {
        [
            .dictationStarted(fromURL: true, appState: "active", engineRunning: true),
            .dictationCompleted(durationMs: 3000),
            .dictationFailed(error: "timeout"),
            .dictationDeferred(reason: "engineNotReady"),
            .audioEngineStarted,
            .audioEngineStopped,
            .audioSessionConfigured(category: "playAndRecord"),
            .audioSessionFailed(error: "configError"),
            .transcriptionStarted(modelName: "base"),
            .transcriptionCompleted(durationMs: 2500, wordCount: 42),
            .transcriptionFailed(error: "modelNotLoaded"),
            .modelDownloadStarted(name: "large-v3", sizeMB: 1500),
            .modelDownloadCompleted(name: "large-v3"),
            .modelDownloadFailed(name: "large-v3", error: "networkTimeout"),
            // Background transfer (#449). The chunk line is the one to watch: it carries
            // a CDN host, and the signed query string that host serves must never travel
            // with it.
            .modelDownloadResumed(
                name: "parakeet-tdt-0.6b-v3",
                path: "Encoder.mlmodelc/weights/weight.bin",
                offsetMB: 96,
                totalMB: 445,
                source: "relaunch"
            ),
            .modelDownloadRangeRejected(
                name: "parakeet-tdt-0.6b-v3",
                path: "Encoder.mlmodelc/weights/weight.bin",
                statusCode: 200,
                reason: "http200-range-ignored"
            ),
            .modelDownloadChunk(
                name: "parakeet-tdt-0.6b-v3",
                path: "Encoder.mlmodelc/weights/weight.bin",
                index: 3,
                count: 14,
                statusCode: 206,
                host: "us.aws.cdn.hf.co",
                validated: true
            ),
            .modelDownloadIntegrityFailed(
                name: "parakeet-tdt-0.6b-v3",
                path: "Encoder.mlmodelc/weights/weight.bin",
                reason: "sha256 mismatch"
            ),
            .modelDownloadSessionRestored(tasks: 0, models: 1),
            .modelSelected(name: "base"),
            .modelCompilationStarted(name: "base"),
            .modelCompilationCompleted(name: "base", durationMs: 5000),
            .keyboardDidAppear,
            .keyboardDidDisappear,
            .keyboardMicTapped,
            .keyboardTextInserted,
            .keyRepeatStarted,
            .keyRepeatStopped(ticks: 12, reason: "touch"),
            .appLaunched(version: "1.2"),
            .appDidBecomeActive,
            .appWillResignActive,
            .appDidEnterBackground,
            .appWhisperKitLoaded(modelName: "base"),
        ]
    }

    func testNoFormattedOutputContainsSensitivePatterns() {
        // Sensitive patterns that should NEVER appear in log output
        // These represent the kinds of data the privacy requirement (LOG-02) forbids
        let sensitivePatterns = [
            "transcription=",   // No raw transcription text
            "keystroke=",       // No keystroke data
            "audioContent=",    // No audio content
            "userText=",        // No user text
            "inputText=",       // No input text
        ]

        for event in allEvents {
            let formatted = event.formatted()
            for pattern in sensitivePatterns {
                XCTAssertFalse(
                    formatted.contains(pattern),
                    "Event \(formatted) contains sensitive pattern '\(pattern)'"
                )
            }
        }
    }

    func testKeyboardTextInsertedHasNoAssociatedValues() {
        // keyboardTextInserted must have NO content parameter
        // We verify by checking its formatted output has no key=value pairs after the event name
        let event = LogEvent.keyboardTextInserted
        let formatted = event.formatted()
        // Extract everything after "keyboardTextInserted"
        if let range = formatted.range(of: "keyboardTextInserted") {
            let afterEventName = String(formatted[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(afterEventName.isEmpty, "keyboardTextInserted should have no parameters, got: '\(afterEventName)'")
        } else {
            XCTFail("Expected 'keyboardTextInserted' in formatted output")
        }
    }

    func testErrorParametersOnlyAcceptFrameworkErrorDescriptions() {
        // Verify that error events use the "error" parameter key
        // (framework errors like WhisperKit/Parakeet are OK per user decision)
        let errorEvents: [LogEvent] = [
            .dictationFailed(error: "WhisperKit.TranscriptionError"),
            .audioSessionFailed(error: "AVAudioSession.ErrorCode"),
            .transcriptionFailed(error: "Parakeet.ModelError"),
            .modelDownloadFailed(name: "base", error: "URLSession.networkTimeout"),
        ]

        for event in errorEvents {
            let formatted = event.formatted()
            // Error parameter should be present as error=something
            XCTAssertTrue(formatted.contains("error="), "Error event should contain error= parameter: \(formatted)")
        }
    }
}
