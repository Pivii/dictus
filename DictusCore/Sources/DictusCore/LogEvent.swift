// DictusCore/Sources/DictusCore/LogEvent.swift
// Structured logging API with privacy-safe typed events.
// Callers log via enum cases with typed parameters -- no free-text strings.

import Foundation

// MARK: - LogLevel

/// Log severity levels for structured logging.
/// 4 levels: debug (internal details), info (normal operations),
/// warning (recoverable issues), error (failures).
public enum LogLevel: String, CaseIterable, Sendable {
    case debug, info, warning, error

    /// Level name padded to 7 characters for aligned log output.
    public var paddedName: String {
        rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)
    }
}

// MARK: - Subsystem

/// App subsystems that produce log events.
/// Each subsystem groups related events for filtering and analysis.
public enum Subsystem: String, CaseIterable, Sendable {
    case dictation, audio, transcription, model, keyboard, lifecycle
}

// MARK: - LogEvent

/// Typed log events with structured parameters.
///
/// WHY an enum instead of free-text logging:
/// Privacy by construction -- callers cannot pass arbitrary strings that might
/// contain transcription text or keystrokes. Each case defines exactly what
/// data can be logged. The `keyboardTextInserted` case intentionally has NO
/// content parameter.
///
/// Error string parameters accept framework error descriptions (WhisperKit, Parakeet,
/// AVAudioSession) which are safe to log per user decision.
public enum LogEvent: Sendable {
    // MARK: Dictation
    case dictationStarted(fromURL: Bool, appState: String, engineRunning: Bool)
    case dictationCompleted(durationMs: Int)
    case dictationFailed(error: String)
    case dictationDeferred(reason: String)

    // MARK: Audio
    case audioEngineStarted
    case audioEngineStopped
    case audioSessionConfigured(category: String)
    case audioSessionFailed(error: String)

    // MARK: Transcription
    case transcriptionStarted(modelName: String)
    case transcriptionCompleted(durationMs: Int, wordCount: Int)
    case transcriptionFailed(error: String)

    // MARK: Model
    case modelDownloadStarted(name: String, sizeMB: Int)
    case modelDownloadCompleted(name: String)
    case modelDownloadFailed(name: String, error: String)
    case modelSelected(name: String)
    case modelCompilationStarted(name: String)
    case modelCompilationCompleted(name: String, durationMs: Int)

    // MARK: Keyboard
    case keyboardDidAppear
    case keyboardDidDisappear
    case keyboardMicTapped
    case keyboardTextInserted  // No content parameter -- privacy by design

    // MARK: Lifecycle
    case appLaunched(version: String)
    case appDidBecomeActive
    case appWillResignActive
    case appDidEnterBackground
    case appWhisperKitLoaded(modelName: String)

    // MARK: - Computed Properties

    /// The subsystem this event belongs to, derived from the case.
    public var subsystem: Subsystem {
        switch self {
        case .dictationStarted, .dictationCompleted, .dictationFailed, .dictationDeferred:
            return .dictation
        case .audioEngineStarted, .audioEngineStopped, .audioSessionConfigured, .audioSessionFailed:
            return .audio
        case .transcriptionStarted, .transcriptionCompleted, .transcriptionFailed:
            return .transcription
        case .modelDownloadStarted, .modelDownloadCompleted, .modelDownloadFailed,
             .modelSelected, .modelCompilationStarted, .modelCompilationCompleted:
            return .model
        case .keyboardDidAppear, .keyboardDidDisappear, .keyboardMicTapped, .keyboardTextInserted:
            return .keyboard
        case .appLaunched, .appDidBecomeActive, .appWillResignActive,
             .appDidEnterBackground, .appWhisperKitLoaded:
            return .lifecycle
        }
    }

    /// Log level derived from the event type.
    /// Failures = error, deferred/warnings = warning, starts/completes = info,
    /// stops/internal state = debug.
    public var level: LogLevel {
        switch self {
        // Errors
        case .dictationFailed, .audioSessionFailed, .transcriptionFailed,
             .modelDownloadFailed:
            return .error

        // Warnings
        case .dictationDeferred:
            return .warning

        // Info (normal operations: starts, completes, selections, configs)
        case .dictationStarted, .dictationCompleted,
             .audioEngineStarted, .audioSessionConfigured,
             .transcriptionStarted, .transcriptionCompleted,
             .modelDownloadStarted, .modelDownloadCompleted,
             .modelSelected, .modelCompilationStarted, .modelCompilationCompleted,
             .keyboardDidAppear, .keyboardMicTapped,
             .appLaunched, .appWhisperKitLoaded:
            return .info

        // Debug (internal state transitions)
        case .audioEngineStopped,
             .keyboardDidDisappear, .keyboardTextInserted,
             .appDidBecomeActive, .appWillResignActive, .appDidEnterBackground:
            return .debug
        }
    }

    /// Event name as it appears in the log line (matches the enum case name).
    public var name: String {
        switch self {
        case .dictationStarted: return "dictationStarted"
        case .dictationCompleted: return "dictationCompleted"
        case .dictationFailed: return "dictationFailed"
        case .dictationDeferred: return "dictationDeferred"
        case .audioEngineStarted: return "audioEngineStarted"
        case .audioEngineStopped: return "audioEngineStopped"
        case .audioSessionConfigured: return "audioSessionConfigured"
        case .audioSessionFailed: return "audioSessionFailed"
        case .transcriptionStarted: return "transcriptionStarted"
        case .transcriptionCompleted: return "transcriptionCompleted"
        case .transcriptionFailed: return "transcriptionFailed"
        case .modelDownloadStarted: return "modelDownloadStarted"
        case .modelDownloadCompleted: return "modelDownloadCompleted"
        case .modelDownloadFailed: return "modelDownloadFailed"
        case .modelSelected: return "modelSelected"
        case .modelCompilationStarted: return "modelCompilationStarted"
        case .modelCompilationCompleted: return "modelCompilationCompleted"
        case .keyboardDidAppear: return "keyboardDidAppear"
        case .keyboardDidDisappear: return "keyboardDidDisappear"
        case .keyboardMicTapped: return "keyboardMicTapped"
        case .keyboardTextInserted: return "keyboardTextInserted"
        case .appLaunched: return "appLaunched"
        case .appDidBecomeActive: return "appDidBecomeActive"
        case .appWillResignActive: return "appWillResignActive"
        case .appDidEnterBackground: return "appDidEnterBackground"
        case .appWhisperKitLoaded: return "appWhisperKitLoaded"
        }
    }

    /// Formatted key=value parameters from associated values.
    /// Returns empty string for events with no associated values.
    public var message: String {
        switch self {
        // Dictation
        case .dictationStarted(let fromURL, let appState, let engineRunning):
            return "fromURL=\(fromURL) appState=\(appState) engineRunning=\(engineRunning)"
        case .dictationCompleted(let durationMs):
            return "duration=\(durationMs)ms"
        case .dictationFailed(let error):
            return "error=\(error)"
        case .dictationDeferred(let reason):
            return "reason=\(reason)"

        // Audio
        case .audioEngineStarted, .audioEngineStopped:
            return ""
        case .audioSessionConfigured(let category):
            return "category=\(category)"
        case .audioSessionFailed(let error):
            return "error=\(error)"

        // Transcription
        case .transcriptionStarted(let modelName):
            return "model=\(modelName)"
        case .transcriptionCompleted(let durationMs, let wordCount):
            return "duration=\(durationMs)ms words=\(wordCount)"
        case .transcriptionFailed(let error):
            return "error=\(error)"

        // Model
        case .modelDownloadStarted(let name, let sizeMB):
            return "name=\(name) size=\(sizeMB)MB"
        case .modelDownloadCompleted(let name):
            return "name=\(name)"
        case .modelDownloadFailed(let name, let error):
            return "name=\(name) error=\(error)"
        case .modelSelected(let name):
            return "name=\(name)"
        case .modelCompilationStarted(let name):
            return "name=\(name)"
        case .modelCompilationCompleted(let name, let durationMs):
            return "name=\(name) duration=\(durationMs)ms"

        // Keyboard (no content parameters -- privacy)
        case .keyboardDidAppear, .keyboardDidDisappear,
             .keyboardMicTapped, .keyboardTextInserted:
            return ""

        // Lifecycle
        case .appLaunched(let version):
            return "version=\(version)"
        case .appDidBecomeActive, .appWillResignActive, .appDidEnterBackground:
            return ""
        case .appWhisperKitLoaded(let modelName):
            return "model=\(modelName)"
        }
    }

    // MARK: - Formatting

    /// Static ISO8601 formatter -- reused across all calls to avoid allocation overhead.
    /// WHY static: ISO8601DateFormatter is expensive to create. Creating one per log call
    /// causes measurable performance overhead (research pitfall 3).
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Produces the full formatted log line.
    /// Format: `[ISO8601timestamp] LEVEL  [subsystem] eventName param=value ...`
    public func formatted() -> String {
        let timestamp = Self.isoFormatter.string(from: Date())
        let params = message
        if params.isEmpty {
            return "[\(timestamp)] \(level.paddedName) [\(subsystem.rawValue)] \(name)"
        }
        return "[\(timestamp)] \(level.paddedName) [\(subsystem.rawValue)] \(name) \(params)"
    }
}
