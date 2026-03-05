// DictusKeyboard/KeyboardState.swift
import Foundation
import Combine
import DictusCore

/// Observes cross-process state changes from DictusApp via Darwin notifications.
/// Reads actual data from App Group UserDefaults after each notification.
class KeyboardState: ObservableObject {
    @Published var dictationStatus: DictationStatus = .idle
    @Published var lastTranscription: String?
    @Published var statusMessage: String?

    private let defaults = AppGroup.defaults

    init() {
        // Read initial state from App Group
        refreshFromDefaults()

        // Observe Darwin notifications for real-time updates
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.statusChanged
        ) { [weak self] in
            // Darwin callbacks are on arbitrary threads — dispatch to main
            DispatchQueue.main.async {
                self?.refreshFromDefaults()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.transcriptionReady
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handleTranscriptionReady()
            }
        }
    }

    deinit {
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.transcriptionReady)
    }

    /// Read current state from App Group UserDefaults.
    /// When status is .ready, also reads lastTranscription — belt-and-suspenders
    /// fix so the keyboard picks up the transcription even if only the statusChanged
    /// notification fires (the transcriptionReady notification also reads it).
    private func refreshFromDefaults() {
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            dictationStatus = status
            updateStatusMessage(for: status)

            if status == .ready {
                lastTranscription = defaults.string(forKey: SharedKeys.lastTranscription)
            }
        }
    }

    /// Handle transcription ready notification: read the result.
    private func handleTranscriptionReady() {
        refreshFromDefaults()

        if let transcription = defaults.string(forKey: SharedKeys.lastTranscription) {
            lastTranscription = transcription
            statusMessage = "Transcription received"
            if #available(iOS 14.0, *) {
                DictusLogger.keyboard.info("Received transcription: \(transcription)")
            }

            // Auto-clear status message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.statusMessage = nil
            }
        } else {
            // Retry after 100ms — mitigates UserDefaults race condition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if let transcription = self?.defaults.string(forKey: SharedKeys.lastTranscription) {
                    self?.lastTranscription = transcription
                    self?.statusMessage = "Transcription received"
                }
            }
        }
    }

    private func updateStatusMessage(for status: DictationStatus) {
        switch status {
        case .idle:
            statusMessage = nil
        case .requested:
            statusMessage = "Opening Dictus..."
        case .recording:
            statusMessage = "Recording in Dictus..."
        case .transcribing:
            statusMessage = "Transcribing..."
        case .ready:
            statusMessage = "Transcription ready"
        case .failed:
            statusMessage = "Dictation failed — try again"
            // Auto-dismiss error after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.dictationStatus == .failed {
                    self?.statusMessage = nil
                }
            }
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    /// Called just before the Link opens dictus://dictate.
    func markRequested() {
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        dictationStatus = .requested
        updateStatusMessage(for: .requested)
    }
}
