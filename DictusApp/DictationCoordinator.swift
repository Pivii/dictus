// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via AudioRecorder + transcription via TranscriptionService.
import Foundation
import Combine
import AVFoundation
import DictusCore
import WhisperKit

/// Manages the dictation lifecycle in the main app.
/// Phase 2: Real WhisperKit recording + transcription pipeline.
///
/// WHY this class is @MainActor and uses static let shared:
/// - @MainActor ensures all @Published property updates happen on the main thread (required by SwiftUI)
/// - Singleton pattern because there's only ever one dictation session active at a time,
///   and multiple views need to observe the same coordinator (ContentView, RecordingView)
@MainActor
class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    // MARK: - Published State

    @Published var status: DictationStatus = .idle
    @Published var lastResult: String?

    /// Forwarded from AudioRecorder for waveform visualization in RecordingView.
    @Published var bufferEnergy: [Float] = []

    /// Forwarded from AudioRecorder for elapsed time display in RecordingView.
    @Published var bufferSeconds: Double = 0

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private var whisperKit: WhisperKit?
    private var dictationTask: Task<Void, Never>?

    /// Combine subscription forwarding AudioRecorder's published values to coordinator.
    ///
    /// WHY Combine sink instead of direct observation:
    /// AudioRecorder is a separate ObservableObject. We need to forward its @Published
    /// properties to DictationCoordinator's @Published properties so RecordingView can
    /// observe a single source of truth (the coordinator).
    private var energyCancellable: AnyCancellable?
    private var secondsCancellable: AnyCancellable?

    private init() {
        // Forward AudioRecorder's energy levels and seconds to coordinator
        energyCancellable = audioRecorder.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                self?.bufferEnergy = energy
            }
        secondsCancellable = audioRecorder.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.bufferSeconds = seconds
            }
    }

    // MARK: - Public API

    /// Called when the app receives dictus://dictate URL.
    /// Starts the full recording pipeline.
    func startDictation() {
        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation started via URL scheme")
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()

        dictationTask = Task {
            do {
                // Step 1: Check microphone permission
                let hasPermission = try await audioRecorder.ensureMicrophonePermission()
                guard hasPermission else {
                    handleError("Microphone permission denied")
                    return
                }

                // Step 2: Initialize WhisperKit if not already ready
                try await ensureWhisperKitReady()

                // Step 3: Start recording
                updateStatus(.recording)
                try audioRecorder.startRecording()

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording started successfully")
                }
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Failed to start dictation: \(error.localizedDescription)")
                }
                handleError(error.localizedDescription)
            }
        }
    }

    /// Called when user taps the stop button.
    /// Stops recording and starts transcription.
    func stopDictation() {
        dictationTask?.cancel()

        dictationTask = Task {
            do {
                // Step 1: Stop recording and get audio samples
                let samples = audioRecorder.stopRecording()

                guard !samples.isEmpty else {
                    handleError("No audio recorded")
                    return
                }

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording stopped. Samples: \(samples.count), Duration: \(String(format: "%.1f", Double(samples.count) / Double(WhisperKit.sampleRate)))s")
                }

                // Step 2: Transcribe
                updateStatus(.transcribing)
                let text = try await transcriptionService.transcribe(audioSamples: samples)

                // Step 3: Write result to App Group
                // IMPORTANT: Write both lastTranscription AND status to UserDefaults
                // BEFORE posting any Darwin notifications. This prevents a race condition
                // where the keyboard reads UserDefaults between two separate notifications
                // and sees status=ready but lastTranscription is still nil.
                lastResult = text
                status = .ready
                defaults.set(text, forKey: SharedKeys.lastTranscription)
                defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
                defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
                defaults.synchronize()

                // Post notifications after ALL writes are complete
                DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Transcription complete: \(text)")
                }

                // Step 4: Brief delay for checkmark flash before returning to idle
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if status == .ready {
                    updateStatus(.idle)
                }
            } catch {
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Transcription failed: \(error.localizedDescription)")
                }
                handleError(error.localizedDescription)
            }
        }
    }

    /// Reset status to idle (e.g., after user returns to keyboard).
    func resetStatus() {
        updateStatus(.idle)
        lastResult = nil
    }

    // MARK: - Private Helpers

    /// Initialize WhisperKit with the default model if not already loaded.
    ///
    /// WHY we hardcode "openai_whisper-tiny" as the fallback model:
    /// Plan 2.3 will add Model Manager with user-selectable models. For now,
    /// we use the smallest model as a safe default. It's ~40 MB and works on all devices.
    private func ensureWhisperKitReady() async throws {
        guard whisperKit == nil else { return }

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Initializing WhisperKit...")
        }

        // Check if user has a preferred model from App Group, fallback to tiny
        let modelName = defaults.string(forKey: "dictus.activeModel") ?? "openai_whisper-tiny"

        let config = WhisperKitConfig(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )

        let kit = try await WhisperKit(config)
        self.whisperKit = kit

        // Share the instance with AudioRecorder and TranscriptionService
        audioRecorder.prepare(whisperKit: kit)
        transcriptionService.prepare(whisperKit: kit)

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("WhisperKit ready with model: \(modelName)")
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

    /// Handle errors by updating status and writing error to App Group.
    private func handleError(_ message: String) {
        defaults.set(message, forKey: SharedKeys.lastError)
        defaults.synchronize()
        updateStatus(.failed)
    }
}
