// DictusCore/Tests/DictusCoreTests/LogCoverageTests.swift
// Tests that every Subsystem has at least one LogEvent case (LOG-05).
import XCTest
@testable import DictusCore

final class LogCoverageTests: XCTestCase {

    /// All possible LogEvent instances -- must cover every subsystem.
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
            .modelSelected(name: "base"),
            .modelCompilationStarted(name: "base"),
            .modelCompilationCompleted(name: "base", durationMs: 5000),
            .keyboardDidAppear,
            .keyboardDidDisappear,
            .keyboardMicTapped,
            .keyboardTextInserted,
            .coldStartURLReceived(isColdStart: true, isEngineDead: false, hasBeenActive: false),
            .coldStartFlagSet(active: true, context: "handleIncomingURL"),
            .coldStartRetry(keyboardStatus: "requested"),
            .coldStartDarwinFallback(elapsedMs: 510, status: "requested"),
            .coldStartStranded(keyboardStatus: "requested", action: "retry"),
            .logExportCompleted(durationMs: 150, sizeBytes: 50000),
            .subscriptionError(action: "purchase", error: "productNotFound"),
            .appLaunched(version: "1.2"),
            .appDidBecomeActive,
            .appWillResignActive,
            .appDidEnterBackground,
            .appWhisperKitLoaded(modelName: "base"),
        ]
    }

    func testEverySubsystemHasAtLeastOneEvent() {
        let coveredSubsystems = Set(allEvents.map { $0.subsystem })
        for subsystem in Subsystem.allCases {
            XCTAssertTrue(
                coveredSubsystems.contains(subsystem),
                "Subsystem '\(subsystem.rawValue)' has no LogEvent cases"
            )
        }
    }

    func testAllSubsystemsCovered() {
        // Redundant check: the number of unique subsystems from events
        // must equal the total number of Subsystem cases
        let coveredSubsystems = Set(allEvents.map { $0.subsystem })
        XCTAssertEqual(coveredSubsystems.count, Subsystem.allCases.count)
    }
}
