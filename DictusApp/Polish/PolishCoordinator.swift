// DictusApp/Polish/PolishCoordinator.swift
import Foundation
import DictusCore

/// DictusApp's polish entry point: one `PolishService` for dictations started
/// inside the app, plus the debug ring the settings screen and the JSON export
/// read.
///
/// ### What is left here, and why so little (#361)
///
/// The orchestration this type used to hold — the toggle, the language branch, the
/// duration and gibberish gates, the availability gate, the metrics — moved to
/// `PolishService` in DictusCore, because the keyboard extension now runs the same
/// pipeline for keyboard dictations. One pipeline, two call sites (decision 4).
///
/// What could not move is the app-only half: the ring's memory cache and retention,
/// the export, and the prewarm scheduled from the recording. A keyboard dictation
/// never reaches this object at all.
@MainActor
public final class PolishCoordinator {

    public static let shared = PolishCoordinator()

    private let metricsRing = PolishMetricsRing()
    private let service: PolishService

    private init() {
        // No `onBecameUnavailable`: the #315 notice lives in the keyboard toolbar and
        // describes the keyboard's gate since #361. When an in-app dictation exhausts
        // the app's budget, the user is looking at DictusApp, and telling them through
        // a surface in another process would be both late and wrong.
        self.service = PolishService(sink: metricsRing)
    }

    // MARK: - Public API

    /// Cancel any in-flight polish. Called by `DictationCoordinator.startDictation()`
    /// so a new recording does not pile up behind the previous polish.
    public func cancelInflight() {
        service.cancelInflight()
    }

    /// Warm the Apple FM engine for the user's current target language (#141).
    ///
    /// Only ever called for a dictation started inside the app since #361: a keyboard
    /// dictation is polished in the extension, and warming a session in this process
    /// could not help it — the two hold separate `LanguageModelSession` caches.
    public func prewarm() {
        service.prewarm()
    }

    /// Polish raw STT output for an in-app dictation. See `PolishService.polish`.
    ///
    /// `smartMode` is the mode armed when this dictation started (#79). A dictation
    /// started inside the app honours it exactly as a keyboard one does: the mode is
    /// a parameter of the dictation, not of the process that runs it.
    public func polish(raw: String,
                       languagePolicy: TranscriptionLanguagePolicy,
                       smartMode: SmartMode?,
                       recordingDuration: TimeInterval,
                       onEngineWillRun: (() -> Void)? = nil) async -> PolishOutcome {
        await service.polish(
            raw: raw,
            languagePolicy: languagePolicy,
            smartMode: smartMode,
            recordingDuration: recordingDuration,
            onEngineWillRun: onEngineWillRun
        )
    }

    // MARK: - Debug ring

    /// Recent polish events for the debug screen — both processes' events, read
    /// back off the shared file.
    public func metricsSnapshot() async -> [PolishDebugEntry] {
        await metricsRing.snapshot()
    }

    /// All polish events within the 7-day retention window — used by the JSON export.
    public func metricsAllEntries() async -> [PolishDebugEntry] {
        await metricsRing.allEntries()
    }

    /// Count of persisted events within the 7-day retention window.
    public func metricsStoredCount() async -> Int {
        await metricsRing.storedCount()
    }

    /// Empties the debug ring. Triggered from the debug screen's Clear button.
    public func clearMetricsRing() async {
        await metricsRing.clear()
    }
}
