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

/// Byte counters for an in-flight model download, rounded to whole megabytes
/// for display ("22 MB of 483 MB").
struct ModelDownloadBytes: Equatable {
    let downloadedMB: Int
    let totalMB: Int

    init(_ progress: ModelRepoDownloader.Progress) {
        downloadedMB = Int(progress.bytesDownloaded / 1_000_000)
        totalMB = Int(progress.totalBytes / 1_000_000)
    }
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

    /// Per-model byte counters ("22 MB of 483 MB") shown alongside the percentage.
    /// A moving byte counter reads as alive even while the percentage crawls
    /// through a huge weight file (issue #207). Populated for both engines
    /// since issue #210 unified the download pipeline.
    @Published var downloadByteInfo: [String: ModelDownloadBytes] = [:]

    /// Per-model lifecycle state. Updated as models move through download/prewarm/ready.
    @Published var modelStates: [String: ModelState] = [:]

    /// Current load state of the active model in the coordinator (issue #144).
    /// Mirrors `DictationCoordinator.modelLoadState` via App Group + NotificationCenter
    /// so SwiftUI can drive the loading overlay reactively.
    @Published var modelLoadState: ModelLoadState = .idle

    /// Set when the user dismisses the preparation screen by hand (issue #428).
    ///
    /// WHY it has to exist: the escape lands the user on the Models tab, and
    /// `ModelManagerView` auto-presents the very same screen from live state the
    /// moment that tab appears. Without a memory of the user's decision, escaping
    /// would re-cover the screen on the next frame and the way out would be no way
    /// out at all.
    ///
    /// Cleared the moment the user asks for model work again (`downloadModel`,
    /// `selectModel`), because from then on the screen is answering a fresh request
    /// rather than replaying the one they walked away from.
    @Published var preparationDismissedByUser = false

    /// When the current compile-or-load wait began (issue #428 review, findings 3 and 7).
    ///
    /// The escape is offered relative to THIS, not to when a given screen appeared. Two
    /// things used to restart the user's 45 seconds from zero: the screen being
    /// dismissed and re-presented (a keyboard prepare URL arriving, a tab change), and
    /// the preparation context changing mid-wait. Both are invisible to the user, who
    /// only knows they have been waiting a long time and are being asked to wait 45
    /// seconds more.
    ///
    /// Deliberately not set while a download is running: a download is not what the
    /// escape is for (finding 4), so the clock starts when the compile does.
    @Published var preparationWaitStartedAt: Date?

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private var loadStateObserver: NSObjectProtocol?

    /// The serial prewarm lock used to live here, as `isPrewarming`. It now lives on
    /// `DictationCoordinator` (issue #428, second review): the Neural Engine cannot
    /// compile two models at once, and a lock owned by this class covered neither
    /// `ensureEngineReady` — which compiles too and never consulted it — nor the second
    /// `ModelManager` that onboarding builds. One piece of hardware, one lock, on the
    /// singleton that both paths can reach.

    /// Directory inside the App Group container where model files are stored.
    /// Using the shared container means the keyboard extension could also access
    /// models here in the future (though currently only the app downloads them).
    private var modelsDirectory: URL? {
        AppGroup.containerURL?.appendingPathComponent("Models", isDirectory: true)
    }

    /// WhisperKit's on-disk repo directory — the HubApi snapshot layout that
    /// `WhisperKit.download` historically used and that `WhisperKitConfig(modelFolder:)`
    /// expects: `Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier}`.
    /// Single source of truth so download, delete, and cleanup stay path-parallel (issue #210).
    ///
    /// The path itself now lives in `WhisperModelRepository` so the dictation path can
    /// resolve the very same folder and load models without touching the network
    /// (issue #249). This property is kept as the local shorthand for the call sites below.
    private var whisperKitRepoDirectory: URL? {
        WhisperModelRepository.repositoryURL()
    }

    /// Per-model last-logged progress decile, so PersistentLog gets ~10 lines per
    /// download instead of hundreds. Main-actor confined like all other state here.
    private var lastLoggedDeciles: [String: Int] = [:]

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
        // Mirror the coordinator's load state so SwiftUI can react (issue #144).
        // We read the persisted value once for cold-start consistency, then subscribe
        // to subsequent changes posted by `DictationCoordinator.setModelLoadState`.
        if let raw = defaults.string(forKey: SharedKeys.modelLoadState),
           let state = ModelLoadState(rawValue: raw) {
            modelLoadState = state
        }
        loadStateObserver = NotificationCenter.default.addObserver(
            forName: .dictusModelLoadStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?["state"] as? String,
                  let state = ModelLoadState(rawValue: raw) else { return }
            self?.modelLoadState = state
        }
    }

    deinit {
        if let observer = loadStateObserver {
            NotificationCenter.default.removeObserver(observer)
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

        // Resync modelStates with loaded downloadedModels so models downloaded
        // by onboarding's separate ModelManager instance show as .ready here.
        for model in ModelInfo.allIncludingDeprecated
        where downloadedModels.contains(model.identifier) {
            if modelStates[model.identifier] == nil || modelStates[model.identifier] == .notDownloaded {
                modelStates[model.identifier] = .ready
            }
        }
    }

    /// Downloads a model variant, prewarms it, and updates state.
    ///
    /// WHY engine-aware download:
    /// Both engines download their HuggingFace repo via the shared
    /// ModelRepoDownloader (issue #210), but their on-disk layouts and
    /// prewarm/compile pipelines differ (WhisperKitConfig vs FluidAudio's
    /// AsrModels). This method routes to the correct path based on the engine.
    ///
    /// WHY foreground download (not background session):
    /// Background URLSession adds significant complexity (delegate callbacks, session
    /// restoration, app lifecycle handling). For v1, foreground download with visible
    /// progress is simpler and sufficient. Users will have the app open during download.
    func downloadModel(_ identifier: String) async throws {
        // A fresh request: the preparation screen is welcome again (issue #428).
        preparationDismissedByUser = false
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

        guard let repoDir = whisperKitRepoDirectory else {
            throw ModelManagerError.noContainer
        }

        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.0
        lastLoggedDeciles[identifier] = -1
        let catalogSizeMB = Int((ModelInfo.forIdentifier(identifier)?.sizeBytes ?? 0) / 1_000_000)
        PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: catalogSizeMB))

        // Tracks which phase a failure (if any) belongs to. Download-phase failures
        // keep files on disk (every file is complete thanks to atomic per-file
        // moves) so a retry resumes where it left off; a prewarm failure keeps them
        // too when it is the deadline guard firing (issue #405) and only cleans up
        // otherwise, because ANE compilation failures (E5 bundle errors) can leave
        // behind unusable cached files that prevent retry from working.
        // `ModelCleanupPolicy` owns the rule; this flag is one of its two inputs.
        var downloadPhaseCompleted = false

        do {
            // Download the variant's files ourselves instead of WhisperKit.download()
            // (issue #210): HubApi's progress is file-count weighted (a 5 MB config
            // moves the bar as much as a 300 MB weight blob), exposes no byte totals
            // for the MB counter, and has no stall detection or retry. The unified
            // ModelRepoDownloader gives WhisperKit models the same byte-accurate
            // progress, stall handling, and resume as Parakeet (issue #207), and
            // writes the exact on-disk layout WhisperKit already expects.
            let downloader = ModelRepoDownloader(configuration: .whisperKit(variant: identifier))
            try await downloader.download(to: repoDir, modelName: identifier) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress, identifier: identifier)
                }
            }
            let modelFolder = repoDir.appendingPathComponent(identifier, isDirectory: true)

            PersistentLog.log(.modelDownloadCompleted(name: identifier))
            downloadPhaseCompleted = true

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
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Take the Neural Engine. This waits out any compile already running,
            // including one started by `ensureEngineReady` on the dictation path, which
            // the old instance-owned flag could not see (issue #428, second review).
            let engineHolder = "prewarm:\(identifier)"
            try await DictationCoordinator.shared.acquireNeuralEngine(for: engineHolder)
            defer { DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder) }

            PersistentLog.log(.modelCompilationStarted(name: identifier))

            // Phase 37 instrumentation: capture timing + jetsam-headroom delta across prewarm.
            // `peakMB` in the log event stores the delta of available memory (in MB) between
            // pre- and post-prewarm. Positive delta ≈ steady-state memory footprint the model
            // retains after CoreML compilation finishes, which is the signal that matters for
            // per-device gating decisions on memory-constrained devices (e.g. iPhone 15 Pro Max).
            let prewarmStart = Date()
            let availableBeforeMB = DeviceCapabilities.current().availableMemoryMB

            let config = WhisperKitConfig(
                model: identifier,
                modelFolder: modelFolder.path,
                // Issue #370: A12/A13 need the audio encoder off the Neural Engine.
                // This is the site the onboarding hang happens at (prewarm/compile).
                computeOptions: WhisperComputeOptions.current(),
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )

            // Phase 37: guard the CoreML prewarm against indefinite hangs.
            // On iPhone ANE, some WhisperKit model variants fail to compile and the
            // async init never returns (E5 bundle load failure — issue #104,
            // 2026-04-22 iPhone 15 Pro Max).
            //
            // WHY the number comes from the catalogue (issue #406):
            // it used to be a flat 120 written here, justified by the ~17s a Parakeet
            // Encoder compile took on a 15 Pro Max. That was a reading from a different
            // engine, it was never revisited, and it ended up sitting almost exactly on
            // Turbo's own compile time — so a TestFlight tester lost a completed Turbo
            // download to it on 2026-08-25, and the maintainer reproduced it the same
            // day on the smaller variant from issue #408. Raising the global instead
            // would have punished the opposite case: Whisper Small on an unsupported
            // A13 (issue #362) takes far longer than it has any business taking.
            // `ModelInfo.prewarmTimeoutSeconds` lets the two models disagree.
            //
            // WHAT THIS GUARD DOES NOT DO (issue #427): it does not interrupt the
            // compile. `withPrewarmTimeout` races a sleep against `WhisperKit(config)`
            // in a task group, and a task group cannot return until every child has
            // finished — `cancelAll()` is a request, and a Core ML compile neither
            // checks cancellation nor offers a suspension point where it could. So the
            // error is thrown on time and surfaces only once the compile has finished
            // anyway. Measured 2026-08-26: a 5s budget reported failure after 212s, on
            // a compile that had by then completed and warmed the cache.
            //
            // So do not read this budget as protection against a hang. It bounds
            // nothing; it reports, afterwards, that the work took longer than a number.
            // #362 in particular is NOT protected by it, whatever an earlier version of
            // this comment claimed.
            //
            // Whatever this resolves to is the number that reaches the user: it is
            // carried by the thrown `.prewarmTimeout(seconds:)` into both the
            // `.modelPrewarmTimeout` log line and the error text on the model card, so
            // the debug log always states the budget that was actually applied.
            //
            // The fallback covers an identifier the catalogue does not know, which this
            // path should never see — `downloadModel` had to resolve the model to route
            // it here by engine in the first place.
            let prewarmTimeoutSeconds = ModelInfo.forIdentifier(identifier)?.prewarmTimeoutSeconds
                ?? ModelInfo.defaultPrewarmTimeoutSeconds
            do {
                _ = try await withPrewarmTimeout(seconds: prewarmTimeoutSeconds) {
                    try await WhisperKit(config)
                }
            } catch let err as ModelManagerError {
                if case .prewarmTimeout(let s) = err {
                    PersistentLog.log(.modelPrewarmTimeout(name: identifier, timeoutSeconds: s))
                }
                throw err
            }

            let prewarmDurationMs = Int(Date().timeIntervalSince(prewarmStart) * 1000)
            let availableAfterMB = DeviceCapabilities.current().availableMemoryMB
            let consumedMB = max(0, availableBeforeMB - availableAfterMB)

            // Update state
            if !downloadedModels.contains(identifier) {
                downloadedModels.append(identifier)
            }

            // Issue #174: a freshly downloaded model becomes the active one.
            // The user explicitly chose it; without this they had to tap the card
            // a second time, triggering a redundant second RAM load.
            activeModel = identifier

            modelStates[identifier] = .ready
            persistState()

            PersistentLog.log(.modelCompilationCompleted(name: identifier, durationMs: prewarmDurationMs))
            PersistentLog.log(.modelPrewarmPeakMemory(modelName: identifier, peakMB: consumedMB))
            PersistentLog.log(.modelSelected(name: identifier))

            // Hand the Neural Engine back BEFORE kicking off the eager load, not at the
            // end of this scope where the `defer` would do it (audit finding 5). The
            // load below would otherwise spend its first 500ms poll queued behind a lock
            // this scope is about to drop anyway. The `defer` still runs and finds the
            // holder changed, so it is a no-op — that identity check is what makes an
            // early release safe.
            DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)

            // Issue #144: eagerly load the now-active model into the coordinator's
            // RAM-resident WhisperKit instance. The compile above used a throwaway
            // WhisperKit just to populate the Core ML cache.
            DictationCoordinator.shared.preloadActiveModel()
        } catch {
            modelStates[identifier] = .error(error.localizedDescription)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Three failure kinds, one of which deletes anything — see
            // ModelCleanupPolicy for the rule and its reasons:
            //   • download failure → keep (issue #210, same policy as the Parakeet
            //     path): every file on disk is complete, a retry resumes;
            //   • prewarm timeout → keep (issue #405): the payload is intact and only
            //     the Core ML compile ran out of clock, so a retry must resume at the
            //     compile step instead of repaying a 1 GB download;
            //   • any other prewarm failure → clean up: an E5 bundle error (issue
            //     #104) leaves a corrupt Core ML cache that fails identically forever.
            // Since issue #235, tapping the card's "Retry" affordance retries in
            // place; the full reset stays in the overflow menu's "Delete partial
            // download" entry (cleanupFailedModel). When nothing is deleted here the
            // debug log shows .modelPrewarmTimeout with no .modelCleanupPerformed
            // line after it — that pair is what says the bytes were kept.
            let isPrewarmTimeout = (error as? ModelManagerError)?.isPrewarmTimeout ?? false
            if ModelCleanupPolicy.shouldCleanUpFiles(
                downloadPhaseCompleted: downloadPhaseCompleted,
                isPrewarmTimeout: isPrewarmTimeout
            ) {
                cleanupModelFiles(identifier)
            }

            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Download a Parakeet model via the app-side downloader, then compile via FluidAudio.
    ///
    /// WHY a separate method:
    /// WhisperKit and Parakeet use completely different download pipelines and
    /// cache locations. This method downloads the raw model files itself, then
    /// hands off to FluidAudio for CoreML compilation.
    ///
    /// Since Dictus now targets iOS 17, no availability guard is needed.
    /// FluidAudio is always available.
    private func downloadParakeetModel(_ identifier: String) async throws {
        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.0
        lastLoggedDeciles[identifier] = -1
        let catalogSizeMB = Int((ModelInfo.forIdentifier(identifier)?.sizeBytes ?? 0) / 1_000_000)
        PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: catalogSizeMB))

        do {
            // Step 1: Download all raw model files with REAL byte-level progress
            // (issue #207). FluidAudio's DownloadUtils.downloadRepo uses the async
            // URLSession API, which never delivers didWriteData — progress only
            // moved on whole-file completion, and with Encoder's weight.bin being
            // ~92% of the payload the bar froze at ~5% for minutes (App Review
            // rejected 1.7.1(19) as "frozen at 4%"). ModelRepoDownloader downloads
            // the same files into the same cache directory using a delegate-based
            // downloadTask that does deliver byte callbacks.
            let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
            let downloader = ModelRepoDownloader(configuration: .parakeet())
            try await downloader.download(to: cacheDir, modelName: identifier) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress, identifier: identifier)
                }
            }

            // Step 2: take the Neural Engine, waiting out any compile already on it —
            // this path's or the dictation path's (issue #428, second review).
            let engineHolder = "prewarm:\(identifier)"
            try await DictationCoordinator.shared.acquireNeuralEngine(for: engineHolder)
            defer { DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder) }

            // Step 3: Switch to prewarming state — download is done, CoreML compilation starts.
            modelStates[identifier] = .prewarming
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)
            PersistentLog.log(.modelPrewarmStarted(name: identifier))

            // Step 4: Load and compile CoreML models.
            // ParakeetEngine.prepare() loads the files step 1 just downloaded and compiles
            // them; it never downloads anything itself (issue #252). This method is the
            // only place a Parakeet download starts.
            //
            // Phase 37 instrumentation mirrors the WhisperKit path: measure prewarm
            // duration + jetsam-headroom delta so both engines produce comparable
            // gating signals.
            let prewarmStart = Date()
            let availableBeforeMB = DeviceCapabilities.current().availableMemoryMB

            let parakeetEngine = ParakeetEngine()
            try await parakeetEngine.prepare(modelIdentifier: identifier)

            let prewarmDurationMs = Int(Date().timeIntervalSince(prewarmStart) * 1000)
            let availableAfterMB = DeviceCapabilities.current().availableMemoryMB
            let consumedMB = max(0, availableBeforeMB - availableAfterMB)

            // Update state
            if !downloadedModels.contains(identifier) {
                downloadedModels.append(identifier)
            }

            // Issue #174: a freshly downloaded model becomes the active one —
            // see comment in the WhisperKit path.
            activeModel = identifier

            modelStates[identifier] = .ready
            persistState()

            PersistentLog.log(.modelCompilationCompleted(name: identifier, durationMs: prewarmDurationMs))
            PersistentLog.log(.modelPrewarmPeakMemory(modelName: identifier, peakMB: consumedMB))
            PersistentLog.log(.modelDownloadCompleted(name: identifier))
            PersistentLog.log(.modelSelected(name: identifier))

            // Released early for the same reason as the WhisperKit path above.
            DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)

            // Issue #144: same proactive load as the WhisperKit path — see comment there.
            DictationCoordinator.shared.preloadActiveModel()
        } catch {
            modelStates[identifier] = .error(error.localizedDescription)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Deliberately NO cleanupModelFiles here after a download failure:
            // the downloader moves each file into place atomically, so anything on
            // disk is a complete file — leaving the cache intact lets a retry skip
            // already-downloaded files and resume where it left off. Since issue
            // #235, tapping the card's "Retry" affordance retries in place; the
            // full reset lives in the overflow menu's "Delete partial download"
            // entry (cleanupFailedModel).
            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Applies one downloader progress tick: percentage bar, MB counter, and
    /// decile-throttled persistent logging (~10 log lines per download).
    /// Shared by the WhisperKit and Parakeet download paths (issue #210).
    private func updateDownloadProgress(_ progress: ModelRepoDownloader.Progress, identifier: String) {
        downloadProgress[identifier] = Float(progress.fraction)
        downloadByteInfo[identifier] = ModelDownloadBytes(progress)

        let decile = Int(progress.fraction * 10)
        if decile > (lastLoggedDeciles[identifier] ?? -1) {
            lastLoggedDeciles[identifier] = decile
            PersistentLog.log(.modelDownloadProgress(
                name: identifier,
                percent: Int(progress.fraction * 100),
                mbDownloaded: Int(progress.bytesDownloaded / 1_000_000),
                mbTotal: Int(progress.totalBytes / 1_000_000)
            ))
        }
    }

    /// Sets the active model for transcription and eagerly loads it into RAM.
    ///
    /// Issue #144: Before this proactive load, `selectModel` only wrote `activeModel`
    /// to App Group. The actual WhisperKit/Parakeet swap was deferred to the next
    /// `ensureEngineReady` call (triggered by the user tapping the mic). For large
    /// models like Whisper turbo, the swap took 1-3 minutes — and any mic taps
    /// during that window cascaded into concurrent `transcribe()` calls that
    /// cancelled each other with `Swift.CancellationError`.
    ///
    /// We now flip `modelLoadState` to `.loading` immediately and trigger the load
    /// up front. If the keyboard is tapped while a load is in flight, it opens
    /// Dictus in a prepare-only flow; `ModelLoadingOverlay` surfaces the wait.
    func selectModel(_ identifier: String) {
        guard downloadedModels.contains(identifier) else { return }
        // A fresh request: the preparation screen is welcome again (issue #428).
        preparationDismissedByUser = false
        activeModel = identifier
        persistState()
        PersistentLog.log(.modelSelected(name: identifier))
        // Trigger an eager load so the model is in RAM before the next mic tap.
        DictationCoordinator.shared.preloadActiveModel()
    }

    /// The user took the escape offered on the preparation screen (issue #428).
    ///
    /// Two things have to happen together, which is why they live behind one call:
    /// the coordinator has to stop waiting for the load (and let the next one start),
    /// and this manager has to remember the decision so the views that auto-present
    /// the screen do not immediately undo it.
    ///
    /// What does NOT happen is the compile stopping. It cannot be stopped; see
    /// `DictationCoordinator.abandonInFlightModelLoad`.
    func abandonPreparation(modelIdentifier: String) {
        preparationDismissedByUser = true
        DictationCoordinator.shared.abandonInFlightModelLoad(
            reason: "user-left-preparation-screen",
            modelIdentifier: modelIdentifier
        )
    }

    /// Deletes a model from disk and updates state.
    ///
    /// WHY guard count > 1:
    /// The app must always have at least one model available for transcription.
    /// Without this guard, the user could delete all models and the keyboard
    /// would have no model to use, resulting in a broken experience.
    func deleteModel(_ identifier: String) throws {
        guard downloadedModels.count > 1 else {
            PersistentLog.log(.modelDeleteFailed(name: identifier, error: "cannot delete last model"))
            throw ModelManagerError.cannotDeleteLastModel
        }

        let engine = ModelInfo.forIdentifier(identifier)?.engine ?? .whisperKit

        // Remove model files from App Group container
        if let modelsDir = modelsDirectory {
            let modelPath = modelsDir.appendingPathComponent(identifier)
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
            }
        }

        // Remove from WhisperKit's on-disk repo location
        // (Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier} —
        // same path construction as the download, see whisperKitRepoDirectory).
        if let whisperKitDir = whisperKitRepoDirectory?.appendingPathComponent(identifier) {
            if FileManager.default.fileExists(atPath: whisperKitDir.path) {
                try FileManager.default.removeItem(at: whisperKitDir)
            }
        }

        // Remove FluidAudio/Parakeet cached models
        // FluidAudio stores downloaded + compiled CoreML models in Application Support/FluidAudio/Models/{version}/
        // Clean ALL known AsrModelVersion caches so this works for any current or future Parakeet model.
        if engine == .parakeet {
            for version: AsrModelVersion in [.v2, .v3] {
                let versionDir = AsrModels.defaultCacheDirectory(for: version)
                if FileManager.default.fileExists(atPath: versionDir.path) {
                    try FileManager.default.removeItem(at: versionDir)
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
        PersistentLog.log(.modelDeleted(name: identifier, engine: engine.displayName))
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
    /// Called from the error card's overflow menu ("Delete partial download",
    /// issue #235) when the user wants to free disk space instead of retrying.
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

        // Clean from WhisperKit's on-disk repo location (same path construction
        // as the download, see whisperKitRepoDirectory).
        if let whisperKitDir = whisperKitRepoDirectory?.appendingPathComponent(identifier) {
            try? FileManager.default.removeItem(at: whisperKitDir)
        }

        // Clean FluidAudio/Parakeet cached models (all versions)
        if ModelInfo.allIncludingDeprecated.first(where: { $0.identifier == identifier })?.engine == .parakeet {
            for version: AsrModelVersion in [.v2, .v3] {
                try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: version))
            }
        }

        PersistentLog.log(.modelCleanupPerformed(name: identifier, reason: "download-or-prewarm-failure"))

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
    case prewarmTimeout(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteLastModel:
            return "Cannot delete the last remaining model"
        case .noContainer:
            return "App Group container not available"
        case .parakeetUnavailable:
            return "Parakeet requires iOS 17+ or FluidAudio is not linked"
        case .prewarmTimeout(let seconds):
            return "Model optimization did not complete within \(seconds)s"
        }
    }

    /// Whether this is the prewarm deadline guard firing rather than a real
    /// failure of the model files (issue #405). The one prewarm failure whose
    /// downloaded payload is still worth keeping — see `ModelCleanupPolicy`.
    var isPrewarmTimeout: Bool {
        if case .prewarmTimeout = self { return true }
        return false
    }
}

/// Races an async operation against a timeout. Cancels the operation and throws
/// `.prewarmTimeout` if the deadline expires first.
///
/// WHY: WhisperKit's async init for certain model variants on iPhone ANE can hang
/// indefinitely when CoreML fails to compile the model (see issue #104,
/// 2026-04-22 on-device test: `ANE model load has failed … Must re-compile the E5
/// bundle` followed by `await WhisperKit(config)` never returning). Without a
/// timeout, ModelManager stays stuck in `.prewarming` forever and the Settings
/// UI shows the optimization spinner indefinitely, forcing the user to force-quit.
@MainActor
func withPrewarmTimeout<T: Sendable>(
    seconds: Int,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw ModelManagerError.prewarmTimeout(seconds: seconds)
        }
        // First to finish wins. Cancel the other before returning.
        //
        // WHY the force unwrap cannot trap: `next()` returns nil only when the
        // group has no unfinished child tasks. Two were just added above and
        // none has been awaited yet, so there is always one result to take.
        // swiftlint:disable:next force_unwrapping
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
