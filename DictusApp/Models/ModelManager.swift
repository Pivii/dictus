// DictusApp/Models/ModelManager.swift
// Manages the WhisperKit model lifecycle: download, select, delete, state tracking.
import Foundation
import Combine
import DictusCore
import WhisperKit
import FluidAudio

/// Represents the current state of a model in the download/preparation lifecycle.
///
/// WHY an enum with associated value for error:
/// Swift enums with associated values let us attach context (the error message)
/// directly to the state, instead of needing a separate error property. This makes
/// state handling exhaustive via switch — the compiler ensures every state is handled.
enum ModelState: Equatable {
    case notDownloaded
    case downloading
    case prewarming
    case ready
    case error(String)
}

/// Manages WhisperKit model download, selection, deletion, and App Group persistence.
///
/// WHY @MainActor:
/// All @Published properties are observed by SwiftUI views on the main thread.
/// @MainActor guarantees all mutations happen on main, preventing data races.
///
/// WHY ObservableObject:
/// SwiftUI's @StateObject/@EnvironmentObject require ObservableObject conformance
/// to automatically re-render views when @Published properties change.
@MainActor
class ModelManager: ObservableObject {

    // MARK: - Published State

    /// Identifiers of models currently downloaded on device.
    @Published var downloadedModels: [String] = []

    /// The currently selected model identifier for transcription.
    @Published var activeModel: String?

    /// Per-model download progress (0.0 to 1.0). Only populated during active downloads.
    @Published var downloadProgress: [String: Float] = [:]

    /// Per-model lifecycle state. Updated as models move through download/prewarm/ready.
    @Published var modelStates: [String: ModelState] = [:]

    // MARK: - Private

    private let defaults = AppGroup.defaults

    /// Serial prewarm lock — only one CoreML compilation at a time.
    /// The Neural Engine cannot handle multiple models compiling simultaneously
    /// (causes ANE "E5 bundle" errors). Downloads are parallel, prewarms are serial.
    private var isPrewarming = false

    /// Directory inside the App Group container where model files are stored.
    /// Using the shared container means the keyboard extension could also access
    /// models here in the future (though currently only the app downloads them).
    private var modelsDirectory: URL? {
        AppGroup.containerURL?.appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - Init

    init() {
        loadState()
        // Initialize states for all known models (including deprecated Tiny/Base so
        // already-downloaded deprecated models still get their state set to .ready).
        for model in ModelInfo.allIncludingDeprecated {
            if downloadedModels.contains(model.identifier) {
                modelStates[model.identifier] = .ready
            } else {
                modelStates[model.identifier] = .notDownloaded
            }
        }
    }

    // MARK: - Public API

    /// Reads persisted model state from App Group UserDefaults.
    ///
    /// WHY JSON for downloadedModels:
    /// UserDefaults can store arrays natively, but using JSON (Data) is more
    /// explicit and avoids type-casting issues. We store a JSON-encoded [String].
    func loadState() {
        if let data = defaults.data(forKey: SharedKeys.downloadedModels),
           let models = try? JSONDecoder().decode([String].self, from: data) {
            downloadedModels = models
        }
        activeModel = defaults.string(forKey: SharedKeys.activeModel)
    }

    /// Downloads a model variant, prewarms it, and updates state.
    ///
    /// WHY engine-aware download:
    /// WhisperKit and Parakeet use completely different download pipelines.
    /// WhisperKit downloads from HuggingFace via WhisperKit.download().
    /// Parakeet downloads via FluidAudio's AsrModels.downloadAndLoad().
    /// This method routes to the correct pipeline based on the model's engine.
    ///
    /// WHY foreground download (not background session):
    /// Background URLSession adds significant complexity (delegate callbacks, session
    /// restoration, app lifecycle handling). For v1, foreground download with visible
    /// progress is simpler and sufficient. Users will have the app open during download.
    func downloadModel(_ identifier: String) async throws {
        // Check if this is a Parakeet model and route accordingly
        let modelInfo = ModelInfo.forIdentifier(identifier)
        if modelInfo?.engine == .parakeet {
            try await downloadParakeetModel(identifier)
            return
        }

        try await downloadWhisperKitModel(identifier)
    }

    /// Download a WhisperKit model variant from HuggingFace.
    ///
    /// WHY prewarm after download:
    /// WhisperKit models need Core ML compilation on first use. Prewarming does this
    /// compilation immediately after download, so the first transcription is fast.
    /// Without prewarming, the first transcription would have a ~10-30s delay.
    private func downloadWhisperKitModel(_ identifier: String) async throws {
        guard let modelsDir = modelsDirectory else {
            throw ModelManagerError.noContainer
        }

        // Create the models directory if it doesn't exist
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.0
        PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: 0))

        do {
            // Download model files from HuggingFace via WhisperKit's built-in downloader.
            // The progressCallback closure is called repeatedly with a Progress object,
            // letting us update the UI with download percentage.
            let modelFolder = try await WhisperKit.download(
                variant: identifier,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress[identifier] = Float(progress.fractionCompleted)
                    }
                }
            )

            PersistentLog.log(.modelDownloadCompleted(name: identifier))

            // Prewarm: compile Core ML model for this device's Neural Engine/GPU.
            // Serialized — only one model compiles at a time. Multiple simultaneous
            // CoreML compilations crash the ANE with "E5 bundle" errors.
            //
            // WHY transition state BEFORE removing progress:
            // If we remove downloadProgress first while state is still .downloading,
            // ModelCardView's .downloading case reads progress ?? 0 = 0%, showing a
            // stuck-at-zero bar. Setting .prewarming first eliminates this gap.
            modelStates[identifier] = .prewarming
            downloadProgress.removeValue(forKey: identifier)

            // Wait for any other prewarm to finish (poll on MainActor is safe)
            while isPrewarming {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }

            isPrewarming = true
            defer { isPrewarming = false }

            PersistentLog.log(.modelCompilationStarted(name: identifier))

            let config = WhisperKitConfig(
                model: identifier,
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            _ = try await WhisperKit(config)

            // Update state
            if !downloadedModels.contains(identifier) {
                downloadedModels.append(identifier)
            }

            // First model downloaded becomes active automatically
            if activeModel == nil {
                activeModel = identifier
            }

            modelStates[identifier] = .ready
            persistState()

            PersistentLog.log(.modelCompilationCompleted(name: identifier, durationMs: 0))
        } catch {
            modelStates[identifier] = .error(error.localizedDescription)
            downloadProgress.removeValue(forKey: identifier)

            // Clean up partially downloaded/corrupted model files so retry starts fresh.
            // ANE compilation failures (E5 bundle errors) leave behind unusable cached files
            // that prevent re-download from working correctly.
            cleanupModelFiles(identifier)

            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Download a Parakeet model via FluidAudio SDK (iOS 17+ only).
    ///
    /// WHY a separate method:
    /// FluidAudio's download + CoreML compilation is handled by a single call
    /// (AsrModels.downloadAndLoad). There's no separate progress callback —
    /// the download/compile is atomic. This is simpler than WhisperKit's
    /// two-step download + prewarm, but means no progress bar during download.
    ///
    /// Since Dictus now targets iOS 17, no availability guard is needed.
    /// FluidAudio is always available.
    private func downloadParakeetModel(_ identifier: String) async throws {
        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.0
        PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: 0))

        do {
            // Wait for any WhisperKit prewarm to finish (ANE conflict avoidance)
            while isPrewarming {
                try await Task.sleep(nanoseconds: 500_000_000)
            }

            isPrewarming = true
            modelStates[identifier] = .prewarming
            defer { isPrewarming = false }

            // FluidAudio handles download + CoreML compilation in one call
            let parakeetEngine = ParakeetEngine()
            try await parakeetEngine.prepare(modelIdentifier: identifier)

            downloadProgress.removeValue(forKey: identifier)

            // Update state
            if !downloadedModels.contains(identifier) {
                downloadedModels.append(identifier)
            }

            if activeModel == nil {
                activeModel = identifier
            }

            modelStates[identifier] = .ready
            persistState()

            PersistentLog.log(.modelDownloadCompleted(name: identifier))
        } catch {
            modelStates[identifier] = .error(error.localizedDescription)
            downloadProgress.removeValue(forKey: identifier)

            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Sets the active model for transcription.
    func selectModel(_ identifier: String) {
        guard downloadedModels.contains(identifier) else { return }
        activeModel = identifier
        persistState()
        PersistentLog.log(.modelSelected(name: identifier))
    }

    /// Deletes a model from disk and updates state.
    ///
    /// WHY guard count > 1:
    /// The app must always have at least one model available for transcription.
    /// Without this guard, the user could delete all models and the keyboard
    /// would have no model to use, resulting in a broken experience.
    func deleteModel(_ identifier: String) throws {
        guard downloadedModels.count > 1 else {
            throw ModelManagerError.cannotDeleteLastModel
        }

        // Remove model files from disk
        if let modelsDir = modelsDirectory {
            let modelPath = modelsDir.appendingPathComponent(identifier)
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
            }
        }

        // Also remove from WhisperKit's default download location
        // WhisperKit.download stores models at Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier}
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let whisperKitDir = docsDir?.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(identifier)") {
            if FileManager.default.fileExists(atPath: whisperKitDir.path) {
                try FileManager.default.removeItem(at: whisperKitDir)
                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Deleted model files at: \(whisperKitDir.path)")
                }
            }
        }

        downloadedModels.removeAll { $0 == identifier }
        modelStates[identifier] = .notDownloaded

        // If deleted model was active, switch to first remaining
        if activeModel == identifier {
            activeModel = downloadedModels.first
        }

        persistState()
    }

    /// Checks if a model is the device-recommended variant.
    ///
    /// WHY delegate to ModelInfo:
    /// The recommendation logic is RAM-based and belongs in the catalog layer
    /// (ModelInfo), not the state manager. This instance method preserves the
    /// call-site signature so views don't need to change.
    func isRecommended(_ identifier: String) -> Bool {
        ModelInfo.isRecommended(identifier)
    }

    /// Cleans up a failed model's files and resets its state to not downloaded.
    /// Called from UI when user wants to free disk space from a failed download.
    func cleanupFailedModel(_ identifier: String) {
        cleanupModelFiles(identifier)
        modelStates[identifier] = .notDownloaded
    }

    /// Removes partially downloaded or corrupted model files from disk.
    /// Called after download/prewarm failure so a retry starts clean.
    private func cleanupModelFiles(_ identifier: String) {
        // Clean from App Group container
        if let modelsDir = modelsDirectory {
            let modelPath = modelsDir.appendingPathComponent(identifier)
            try? FileManager.default.removeItem(at: modelPath)
        }

        // Clean from WhisperKit's default download location
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let whisperKitDir = docsDir?.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(identifier)") {
            try? FileManager.default.removeItem(at: whisperKitDir)
        }

        // Remove from downloaded list if it was added prematurely
        downloadedModels.removeAll { $0 == identifier }
        if activeModel == identifier {
            activeModel = downloadedModels.first
        }
        persistState()
    }

    /// Whether at least one model is downloaded and ready for transcription.
    var isModelReady: Bool {
        !downloadedModels.isEmpty && activeModel != nil
    }

    // MARK: - Private

    /// Persists model state to App Group UserDefaults so the keyboard extension
    /// can read which model is active and whether transcription is available.
    private func persistState() {
        if let data = try? JSONEncoder().encode(downloadedModels) {
            defaults.set(data, forKey: SharedKeys.downloadedModels)
        }
        defaults.set(activeModel, forKey: SharedKeys.activeModel)
        defaults.set(!downloadedModels.isEmpty, forKey: SharedKeys.modelReady)
        defaults.synchronize()
    }
}

/// Errors specific to model management operations.
enum ModelManagerError: Error, LocalizedError {
    case cannotDeleteLastModel
    case noContainer
    case parakeetUnavailable

    var errorDescription: String? {
        switch self {
        case .cannotDeleteLastModel:
            return "Cannot delete the last remaining model"
        case .noContainer:
            return "App Group container not available"
        case .parakeetUnavailable:
            return "Parakeet requires iOS 17+ or FluidAudio is not linked"
        }
    }
}
