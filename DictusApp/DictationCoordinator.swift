// DictusApp/DictationCoordinator.swift
import Foundation
import Combine
import DictusCore

/// Manages the dictation lifecycle in the main app.
/// Phase 1: stub implementation that simulates recording + transcription.
/// Phase 2: replace stubs with real AVAudioEngine + WhisperKit.
@MainActor
class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    @Published var status: DictationStatus = .idle
    @Published var lastResult: String?

    private let defaults = AppGroup.defaults

    private init() {}

    private var dictationTask: Task<Void, Never>?

    /// Called when the app receives dictus://dictate URL.
    func startDictation() {
        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation started via URL scheme")
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        // Update shared status so keyboard can track progress
        updateStatus(.recording)

        // Simulate recording delay (1.5 seconds)
        dictationTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                // Task was cancelled — clean up
                updateStatus(.idle)
                return
            }
            updateStatus(.transcribing)

            do {
                // Simulate transcription delay (1 second)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                updateStatus(.idle)
                return
            }

            // Write stub result to App Group
            let stubResult = "Bonjour, ceci est un test de dictée."
            writeTranscription(stubResult)
            updateStatus(.ready)

            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Stub transcription written: \(stubResult)")
            }
        }
    }

    /// Write dictation status to App Group so the keyboard can observe it.
    private func updateStatus(_ newStatus: DictationStatus) {
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()

        // Signal keyboard that status changed
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Write transcription result to App Group and signal the keyboard.
    private func writeTranscription(_ text: String) {
        lastResult = text
        defaults.set(text, forKey: SharedKeys.lastTranscription)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.synchronize()

        // Signal keyboard that transcription is ready
        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
    }

    /// Reset status to idle (e.g., after user returns to keyboard).
    func resetStatus() {
        updateStatus(.idle)
        lastResult = nil
    }
}
