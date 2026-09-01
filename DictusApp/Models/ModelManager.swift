// DictusApp/Models/ModelManager.swift
// Manages the WhisperKit model lifecycle: download, select, delete, state tracking.
import Foundation
import Combine
import UIKit
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

    /// Rebuilds the counter from a peer instance's broadcast (issue #449), which carries
    /// the two whole megabyte numbers rather than the byte totals behind them.
    init(downloadedMB: Int, totalMB: Int) {
        self.downloadedMB = downloadedMB
        self.totalMB = totalMB
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

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private var loadStateObserver: NSObjectProtocol?
    private var peerStateObserver: NSObjectProtocol?
    private var becameActiveObserver: NSObjectProtocol?

    /// Identity of this instance, so a broadcast of its own writes is ignored.
    private let instanceID = UUID()

    /// Whether this process has already reconciled `downloadedModels` against the
    /// disk (issue #433). Static because the promise is per process, not per
    /// instance: onboarding builds a second `ModelManager` of its own.
    private static var hasReconciledThisProcess = false

    /// Whether this process has already picked up the downloads a previous process left
    /// unfinished (issue #449). Static for the same reason as above, and it matters more
    /// here: two instances re-entering the same preparation would run two Core ML
    /// compiles of the same model.
    private static var hasResumedDownloadsThisProcess = false

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
        // Believe the disk over the bookkeeping, before the states below are seeded
        // from it (#433). Deliberately here and not inside `loadState`, which three
        // views call on `.onAppear` — see `reconcileDownloadedModelsWithDisk`.
        reconcileDownloadedModelsWithDisk()
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
        // WHY `MainActor.assumeIsolated` and not `Task { @MainActor in }`: the write
        // has to land in the same run-loop turn as the post, because it is not the
        // only consumer of that post. `ModelLoadingOverlay` observes the very same
        // notification through a Combine publisher and its `checkForCompletion()`
        // reads `modelManager.modelLoadState` back while the post is still being
        // delivered. Deferring the write by a turn would hand that read the previous
        // value, on the screen #428 is about escaping. `queue: .main` already makes
        // this closure main-thread-only — measured for a post from either a main or a
        // background thread — so there is no assumption here left to violate. The
        // same reasoning, on the same API, is written out at
        // `UnifiedAudioEngine.registerInterruptionObservers`.
        loadStateObserver = NotificationCenter.default.addObserver(
            forName: .dictusModelLoadStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?["state"] as? String,
                  let state = ModelLoadState(rawValue: raw) else { return }
            MainActor.assumeIsolated { self?.modelLoadState = state }
        }
        peerStateObserver = NotificationCenter.default.addObserver(
            forName: .dictusModelPreparationChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // The observer was registered with `queue: .main`, so this body genuinely
            // runs on the main actor; `assumeIsolated` states that to the compiler
            // instead of hopping through a Task, which would let two updates land out
            // of the order they were posted in.
            MainActor.assumeIsolated {
                self?.applyPeerPreparationUpdate(note)
            }
        }
        // What a previous process left mid-transfer (issue #449). Seeded on every
        // instance so both screens agree; only ever driven from one.
        adoptInterruptedDownloads()
    }

    deinit {
        if let observer = loadStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = peerStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = becameActiveObserver {
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

    /// Adds back any WhisperKit variant whose files are completely on disk while
    /// `downloadedModels` says it is not there (issue #433).
    ///
    /// WHY the two can disagree: the identifier is appended only after the whole
    /// download-and-prewarm sequence returns. A compile ended by a force quit or by
    /// iOS reclaiming the process leaves every byte on disk and the list unaware, so
    /// the model reappears under "Available" — where there is no delete affordance,
    /// because the app does not believe you have it. The user is then paying 500 MB
    /// to 1.5 GB for something they cannot see and cannot reclaim.
    ///
    /// WHY there is no third state for it: a model whose files are complete IS
    /// downloaded. Selecting it runs the compile that was interrupted, which is the
    /// ordinary preparation flow `ModelLoadingOverlay` already covers, so nothing new
    /// needs presenting — and the delete entry in the card's overflow menu becomes
    /// reachable, which is the whole point.
    ///
    /// WHAT IT MUST NEVER DO is touch `activeModel`. `persistState` derives
    /// `SharedKeys.modelReady` from this pair, and every reader of that flag treats it
    /// as "there is a model to load". Electing a model whose compile has never
    /// succeeded would announce a working engine on a device that has none. Adding to
    /// the list is a statement about disk; choosing what to load is the user's, or
    /// that of the download that finishes.
    ///
    /// WHY WhisperKit only: Parakeet arrives through FluidAudio, whose cache is one
    /// directory per `AsrModelVersion` shared by every model of that version — so
    /// "are its files complete" and "which model do they belong to" are not the same
    /// question there, and deleting one version's directory removes them all.
    /// Reconciling it is a separate problem and is out of scope here.
    ///
    /// WHY once per process, and why this is not called from `loadState`: what it
    /// repairs is the wreckage of a process that DIED between a finished download and
    /// a finished compile, so the only honest moment to run it is before this process
    /// has done anything of its own. `loadState` is called by `HomeView` and
    /// `ModelManagerView` on `.onAppear` and again when onboarding completes, and a
    /// perfectly ordinary download sits in exactly the repaired state — files
    /// complete, identifier not yet appended — for the entire prewarm window, which
    /// is 27 s for Small and about 3 min 30 for Turbo. Navigating between two tabs in
    /// that window would have adopted the in-flight model early and written
    /// `modelReconciledFromDisk` for a download nobody interrupted, which is both a
    /// race against the prewarm's own bookkeeping and a lie in a log whose reader is
    /// an agent. The flag rather than init alone: onboarding builds its own
    /// `ModelManager`, so "once per instance" is not the same promise.
    private func reconcileDownloadedModelsWithDisk() {
        guard !Self.hasReconciledThisProcess else { return }
        Self.hasReconciledThisProcess = true

        let whisperIdentifiers = ModelInfo.allIncludingDeprecated
            .filter { $0.engine == .whisperKit }
            .map(\.identifier)
        let recovered = WhisperModelRepository.unlistedCompleteDownloads(
            among: whisperIdentifiers,
            listedAsDownloaded: downloadedModels
        )
        guard !recovered.isEmpty else { return }

        downloadedModels.append(contentsOf: recovered)
        for identifier in recovered {
            PersistentLog.log(.modelReconciledFromDisk(name: identifier))
        }
        persistState()
    }

    // MARK: - Interrupted downloads (issue #449)

    /// Shows, and on the first instance resumes, a download a previous process left
    /// mid-file.
    ///
    /// WHY SEEDING AND DRIVING ARE SEPARATE: both `ModelManager` instances have to SHOW
    /// the download — `MainTabView` builds one and onboarding's `ModelDownloadPage`
    /// builds another, and a first-run user who force-quits mid-download comes back to
    /// the onboarding one. Only one of them may DRIVE it, because driving ends in a Core
    /// ML compile and two compiles of the same model would queue on the Neural Engine for
    /// no reason (issue #428). So every instance seeds its state from the manifest on
    /// disk, and the first one in the process re-enters `downloadModel`. The peer
    /// broadcast below keeps the other one's bar moving.
    ///
    /// WHY NEVER FROM THE BACKGROUND: iOS relaunches the app in the background to hand
    /// back finished background transfers, and `MainTabView` may evaluate its body there.
    /// Starting a preparation from that launch would run a Core ML compile in a process
    /// the system is free to suspend or reclaim mid-way — which is exactly what #427
    /// measured the cost of.
    private func adoptInterruptedDownloads() {
        let interrupted = BackgroundModelDownloadService.interruptedModelIdentifiers()
        guard !interrupted.isEmpty else { return }

        for identifier in interrupted where ModelInfo.forIdentifier(identifier) != nil {
            guard modelStates[identifier] != .ready else { continue }
            modelStates[identifier] = .downloading
            lastLoggedDeciles[identifier] = -1
            if let progress = BackgroundModelDownloadService.persistedProgress(for: identifier) {
                downloadProgress[identifier] = Float(progress.fraction)
                downloadByteInfo[identifier] = ModelDownloadBytes(progress)
            }
        }

        guard !Self.hasResumedDownloadsThisProcess else { return }
        guard UIApplication.shared.applicationState != .background else {
            // Measured on the simulator, 2026-09-01: the relaunch that follows a kill
            // evaluates `MainTabView`'s body while the app is still in the background,
            // so this guard fired on the very launch it was written to protect and
            // NOTHING adopted the transfer. It finished, published 445 MB, and no
            // prewarm ever ran — the model was on disk and the app did not know.
            // Deferring instead of dropping is the whole fix: the adoption happens the
            // moment there is a foreground to run a compile in.
            waitForForegroundToAdoptDownloads()
            return
        }
        Self.hasResumedDownloadsThisProcess = true

        for identifier in interrupted where ModelInfo.forIdentifier(identifier) != nil {
            guard modelStates[identifier] != .ready else { continue }
            PersistentLog.log(.diagnosticProbe(
                component: "ModelDownload",
                instanceID: identifier,
                action: "resumedAfterRelaunch",
                details: "percent=\(Int((downloadProgress[identifier] ?? 0) * 100))"
            ))
            Task { [weak self] in
                // Errors land in `downloadModel`'s own catch, which sets `.error` and
                // logs; there is no caller here to hand them to.
                try? await self?.downloadModel(identifier)
            }
        }
    }

    /// Arms a one-shot retry of `adoptInterruptedDownloads` for the next time the app
    /// reaches the foreground.
    ///
    /// One shot because the adoption itself is once per process, and because a second
    /// observer would fire a second `downloadModel` for the same model. The observer
    /// removes itself before doing anything, so an early return inside the adoption
    /// cannot leave it armed.
    private func waitForForegroundToAdoptDownloads() {
        guard becameActiveObserver == nil else { return }
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let observer = self.becameActiveObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.becameActiveObserver = nil
                }
                self.adoptInterruptedDownloads()
            }
        }
    }

    // MARK: - Cross-instance preparation state

    /// Applies a preparation update published by the other `ModelManager` in this
    /// process, so the onboarding page and the model manager never disagree about which
    /// model is downloading or how far along it is.
    ///
    /// WHY this exists at all: the two instances have always been able to diverge — the
    /// old fix was `loadState()` on `.onAppear`, which answers "is it downloaded" and
    /// says nothing about a download in flight. That was survivable while a download only
    /// ever started from the screen you were looking at, and stopped being survivable
    /// when a download can be resumed by the OTHER instance after a relaunch (#449).
    private func applyPeerPreparationUpdate(_ note: Notification) {
        guard let info = note.userInfo,
              let sender = info["sender"] as? String, sender != instanceID.uuidString,
              let identifier = info["id"] as? String,
              let rawState = info["state"] as? String else { return }

        switch rawState {
        case "downloading":
            modelStates[identifier] = .downloading
        case "prewarming":
            modelStates[identifier] = .prewarming
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
        case "ready":
            modelStates[identifier] = .ready
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            loadState()
        case "error":
            modelStates[identifier] = .error(info["error"] as? String ?? "")
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
        default:
            break
        }

        if let fraction = info["progress"] as? Float {
            downloadProgress[identifier] = fraction
        }
        if let downloadedMB = info["downloadedMB"] as? Int, let totalMB = info["totalMB"] as? Int {
            downloadByteInfo[identifier] = ModelDownloadBytes(downloadedMB: downloadedMB, totalMB: totalMB)
        }
    }

    /// Sets a model's lifecycle state and tells the other instance about it.
    private func setState(_ state: ModelState, for identifier: String) {
        modelStates[identifier] = state
        var info: [String: Any] = ["sender": instanceID.uuidString, "id": identifier]
        switch state {
        case .notDownloaded: info["state"] = "notDownloaded"
        case .downloading: info["state"] = "downloading"
        case .prewarming: info["state"] = "prewarming"
        case .ready: info["state"] = "ready"
        case .error(let message):
            info["state"] = "error"
            info["error"] = message
        }
        NotificationCenter.default.post(
            name: .dictusModelPreparationChanged,
            object: nil,
            userInfo: info
        )
    }

    /// Starting point for a download's progress bar: whatever a previous process
    /// durably received, so a resumed transfer does not flash back to 0%.
    private func seedDownloadProgress(for identifier: String) {
        guard let progress = BackgroundModelDownloadService.persistedProgress(for: identifier),
              progress.totalBytes > 0 else {
            downloadProgress[identifier] = 0.0
            return
        }
        downloadProgress[identifier] = Float(progress.fraction)
        downloadByteInfo[identifier] = ModelDownloadBytes(progress)
    }

    /// Downloads a model variant, prewarms it, and updates state.
    ///
    /// WHY engine-aware download:
    /// Both engines download their HuggingFace repo via the shared
    /// ModelRepoDownloader (issue #210), but their on-disk layouts and
    /// prewarm/compile pipelines differ (WhisperKitConfig vs FluidAudio's
    /// AsrModels). This method routes to the correct path based on the engine.
    ///
    /// WHY THE TRANSFER IS A BACKGROUND SESSION (issue #449): it was not, and the comment
    /// that used to sit here said so — background `URLSession` was judged too complex for
    /// v1, on the assumption that "users will have the app open during download". They do
    /// not. A first-run user checks another app while half a gigabyte arrives, iOS
    /// suspends the process, the transfer stops, and the 30 s stall detector meets them on
    /// their return with the file restarted at byte zero.
    /// `BackgroundModelDownloadService` owns the transfer now; this method still owns the
    /// sequence around it, and in particular the Core ML prewarm, which never runs
    /// anywhere but the foreground.
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

        guard let repoDir = whisperKitRepoDirectory else {
            throw ModelManagerError.noContainer
        }

        setState(.downloading, for: identifier)
        seedDownloadProgress(for: identifier)
        lastLoggedDeciles[identifier] = -1
        // One "started" line per TRANSFER, not per attempt (#449). A resume after a
        // relaunch re-enters this method, and so does a retry, so a single download was
        // announcing itself three times — which made acceptance criterion 2 ("exactly
        // one modelDownloadStarted line") unverifiable by its own method. A manifest
        // already on disk means the transfer is under way and has been announced.
        if !BackgroundModelDownloadService.hasUnfinishedTransfer(for: identifier) {
            let catalogSizeMB = Int((ModelInfo.forIdentifier(identifier)?.sizeBytes ?? 0) / 1_000_000)
            PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: catalogSizeMB))
        }

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
            setState(.prewarming, for: identifier)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Take the Neural Engine. This waits out any compile already running,
            // including one started by `ensureEngineReady` on the dictation path, which
            // the old instance-owned flag could not see (issue #428, second review).
            // Captured BEFORE the wait for the Neural Engine, not after it (fourth
            // review, finding 1). The wait is unbounded — it can last as long as another
            // compile runs — and everything this guard exists to notice happens during
            // it. Capturing on the far side made the guard blind to exactly the window
            // it was written for.
            let prewarmEpoch = DictationCoordinator.shared.modelLoadEpoch

            let engineHolder = "prewarm:\(identifier)"
            try await DictationCoordinator.shared.acquireNeuralEngine(for: engineHolder)

            // WHY A FLAG AND NOT A BARE `defer` (issue #427): the engine belongs to
            // whoever is actually compiling on it, and after a deadline expiry that is
            // no longer this scope. The compile carries on — nothing can stop it — so
            // releasing here would let the next model start a second compile on top of
            // it, which is precisely the E5-class failure `acquireNeuralEngine` spends
            // a paragraph telling the next reader not to cause. On expiry the flag goes
            // down and the abandoned compile hands the engine back itself, from
            // `whenLateCompilationLands` below.
            var engineIsOursToRelease = true
            defer {
                if engineIsOursToRelease {
                    DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)
                }
            }

            // This prewarm compiles its own throwaway WhisperKit outside the coordinator's
            // init lock, so abandoning a load does not stop it — and #174 has it adopt the
            // model as active when it finishes. Without the guard below, a user who moved
            // to a different model mid-prewarm had their choice silently reverted, and the
            // model they moved off loaded into RAM instead.

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
            // WHAT THIS GUARD DOES AND DOES NOT DO (issue #427): it bounds the WAIT,
            // never the compile. Nothing can interrupt a Core ML compile — it checks no
            // cancellation flag and offers no suspension point at which it could notice
            // one — so on expiry the compile runs on, keeps the Neural Engine, and
            // finishes on its own. What the budget buys is that the app stops waiting
            // for it, at the deadline, and hands the user back a card they can act on.
            //
            // It did not always buy that. Until #427 this raced a sleep against the
            // compile inside a task group, and a task group cannot return while a child
            // runs: the error was thrown on time and then queued behind the very compile
            // it was meant to bound. Measured 2026-08-26, a 5s budget reported failure
            // after 212s, on a compile that had by then completed and warmed the cache.
            // Any comment or issue reasoning from that behaviour is describing the old
            // code.
            //
            // #362 — Whisper Small on an unsupported A13 — is the case this has to be
            // right for, because there the compile may genuinely never return. It is now
            // bounded, in the only sense available: the spinner ends at 120s even though
            // the compile behind it does not.
            //
            // WHAT AN ABANDONED COMPILE DOES NOT SURVIVE: the app leaving the
            // foreground. Nothing owns it — that is the whole point of abandoning it —
            // so nothing holds the process up for it. iOS may suspend the process on
            // backgrounding, in which case the compile simply stops running, and it may
            // reclaim the process outright, in which case the compile dies with it. Both
            // take with them the warm Core ML cache that abandoning was supposed to buy.
            //
            // Observed 2026-08-30 on an iPhone 15 Pro Max: a 5s deadline fired at
            // 13:06:43, the app backgrounded at 13:07:09, and at 13:08:39 a NEW process
            // logged `appLaunched`. No `abandonedCompileLanded` was ever written and the
            // next attempt paid the full 3 min 46 s again. Whether that process was
            // jetsammed or crashed is NOT established — a debug log cannot tell those
            // apart, only a `.ips` can, and `thermal=serious` in the same snapshot means
            // the memory-pressure reading is at least plausible. So nothing is fixed
            // here on a cause nobody has localised.
            //
            // NOTHING IN THIS DESIGN CAN HOLD THAT WINDOW, and the options were checked
            // rather than assumed. `beginBackgroundTask` has precedent in this app
            // (#311, `coldStartAssertion`) but buys tens of seconds against a compile
            // that runs for two hundred; it would move the kill, not prevent it.
            // `UIBackgroundModes: audio` is already declared and only keeps the process
            // alive while audio is actually capturing, which a prewarm is not. Refusing
            // to abandon while backgrounded changes nothing either: abandoning decides
            // who WAITS, not who runs, and there is no UI in the background to hand back.
            //
            // Say it plainly: the trade #427 made was accepted without this case in
            // mind. Its argument was that the compile finishes anyway and the retry is
            // cheap, which is measured and true with the app in front of the user
            // (`abandonedCompileLanded`, 2026-08-30 12:26), and was never costed for an
            // app the user has walked away from.
            //
            // What bounds the damage is that it is not a regression. When the process
            // does die, the user pays one full compile on the retry — exactly what they
            // paid before this branch existed, and before it they also waited out that
            // compile and were then told it had failed. The failure mode is "abandoning
            // bought nothing", not "abandoning broke something".
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
                } whenLateCompilationLands: { result in
                    // The compile the app gave up on has landed. Two things follow.
                    // The engine is free, and this is the only place that knows it.
                    DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)
                    // And the debug log gets the line that closes the story it opened
                    // with `.modelPrewarmTimeout` — without it, a reader sees a compile
                    // start, a timeout, and no ending, which is the shape of a hang.
                    let landedAfterMs = Int(Date().timeIntervalSince(prewarmStart) * 1000)
                    PersistentLog.log(.diagnosticProbe(
                        component: "ModelPrewarm",
                        instanceID: identifier,
                        action: "abandonedCompileLanded",
                        details: "afterMs=\(landedAfterMs) budget=\(prewarmTimeoutSeconds)s "
                            + "outcome=\(ModelManager.landingOutcome(of: result))"
                    ))
                }
            } catch let err as ModelManagerError {
                if case .prewarmTimeout(let s) = err {
                    // The compile is still on the Neural Engine; it releases it above.
                    engineIsOursToRelease = false
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

            // Issue #174: a freshly downloaded model becomes the active one. The user
            // explicitly chose it; without this they had to tap the card a second time,
            // triggering a redundant second RAM load.
            //
            // Unless they have since chosen otherwise. Escaping this preparation and
            // picking another model is exactly that, and #174's convenience must not
            // overrule it (finding B).
            let userMovedOn = DictationCoordinator.shared.loadWasAbandoned(since: prewarmEpoch)
            if userMovedOn {
                PersistentLog.log(.diagnosticProbe(
                    component: "ModelPrewarm",
                    instanceID: identifier,
                    action: "notAdoptedAsActive",
                    details: "reason=userChoseAnotherModelDuringPrewarm active=\(activeModel ?? "nil")"
                ))
            } else {
                activeModel = identifier
            }

            // Persist BEFORE announcing. `setState` tells the other `ModelManager` in
            // this process that the model is ready, and that instance answers by
            // re-reading the App Group — so announcing first handed it the state from
            // before this download existed. Onboarding then sat on a finished model with
            // no Continue button, because `isModelReady` was still false when it looked
            // (observed on the simulator, 2026-09-01).
            persistState()
            setState(.ready, for: identifier)

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
            //
            // Skipped when the user moved on: this would load the abandoned model into
            // RAM and clear the memory that keeps it from being re-warmed (finding B).
            if !userMovedOn {
                DictationCoordinator.shared.preloadActiveModel()
            }
        } catch is CancellationError {
            // This attempt was superseded by another one for the same model — the only
            // way that happens is a re-listing that found a different repository
            // revision, which supersedes the transfer this call was waiting on. The
            // attempt that replaced it owns the card now, so nothing here may write to
            // it (issue #449).
            throw CancellationError()
        } catch {
            setState(.error(error.localizedDescription), for: identifier)
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
        setState(.downloading, for: identifier)
        seedDownloadProgress(for: identifier)
        lastLoggedDeciles[identifier] = -1
        // One "started" line per TRANSFER, not per attempt (#449). A resume after a
        // relaunch re-enters this method, and so does a retry, so a single download was
        // announcing itself three times — which made acceptance criterion 2 ("exactly
        // one modelDownloadStarted line") unverifiable by its own method. A manifest
        // already on disk means the transfer is under way and has been announced.
        if !BackgroundModelDownloadService.hasUnfinishedTransfer(for: identifier) {
            let catalogSizeMB = Int((ModelInfo.forIdentifier(identifier)?.sizeBytes ?? 0) / 1_000_000)
            PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: catalogSizeMB))
        }

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

            // Same guard as the WhisperKit path, captured before the wait (finding 1).
            let prewarmEpoch = DictationCoordinator.shared.modelLoadEpoch

            // Step 2: Switch to prewarming state BEFORE queueing for the Neural Engine,
            // which is the order the WhisperKit path uses (fourth review, finding 3).
            // Taking the lock first left the card saying "Downloading" at 100% with no
            // progress for as long as another compile held the hardware — the download
            // has finished, and the screen should say what is actually happening.
            setState(.prewarming, for: identifier)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)
            PersistentLog.log(.modelPrewarmStarted(name: identifier))

            // Step 3: take the Neural Engine, waiting out any compile already on it —
            // this path's or the dictation path's (issue #428, second review).
            let engineHolder = "prewarm:\(identifier)"
            try await DictationCoordinator.shared.acquireNeuralEngine(for: engineHolder)

            // Released by whoever is still compiling on the engine — see the WhisperKit
            // path, which explains the flag at length. The two paths have to agree here:
            // an abandoned Parakeet compile holds the same hardware a Whisper compile
            // would.
            var engineIsOursToRelease = true
            defer {
                if engineIsOursToRelease {
                    DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)
                }
            }

            // Step 4: Load and compile CoreML models, under the catalogue's budget.
            // ParakeetEngine.prepare() loads the files step 1 just downloaded and compiles
            // them; it never downloads anything itself (issue #252). This method is the
            // only place a Parakeet download starts.
            //
            // WHY THIS IS GUARDED AT ALL, AND ONLY NOW (issue #422): it never was. The
            // deadline was written for WhisperKit in Phase 37 and `prewarmTimeoutSeconds`
            // sat on this entry declaring a budget nothing read, which is worse than no
            // field — the next reader believes the protection exists. And the asymmetry
            // pointed the wrong way: Parakeet v3 is the recommended model and the one a
            // new user compiles during onboarding, so the unguarded path was the default
            // path. A FluidAudio compile that never returned had no way out but killing
            // the app. It was not fixed alongside #406 on purpose, because adding a new
            // failure mode to the default onboarding model as a side effect of a Turbo
            // fix is not a trade anyone chose; it waited for #427 to decide what a
            // deadline expiring should mean, and now means what it means everywhere
            // else: the app stops waiting, the compile carries on, the files stay.
            //
            // No hang has ever been observed here. This is the absence of a guard being
            // closed, not a reported symptom being fixed, which is the whole argument
            // for leaving the budget generous — see the catalogue entry.
            //
            // Phase 37 instrumentation mirrors the WhisperKit path: measure prewarm
            // duration + jetsam-headroom delta so both engines produce comparable
            // gating signals.
            let prewarmStart = Date()
            let availableBeforeMB = DeviceCapabilities.current().availableMemoryMB

            let prewarmTimeoutSeconds = ModelInfo.forIdentifier(identifier)?.prewarmTimeoutSeconds
                ?? ModelInfo.defaultPrewarmTimeoutSeconds
            do {
                try await withPrewarmTimeout(seconds: prewarmTimeoutSeconds) {
                    // Built inside the operation, not captured: the engine is this
                    // compile's alone, and after a deadline expiry nothing out here is
                    // entitled to touch it any more.
                    let parakeetEngine = ParakeetEngine()
                    try await parakeetEngine.prepare(modelIdentifier: identifier)
                } whenLateCompilationLands: { result in
                    DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)
                    let landedAfterMs = Int(Date().timeIntervalSince(prewarmStart) * 1000)
                    PersistentLog.log(.diagnosticProbe(
                        component: "ModelPrewarm",
                        instanceID: identifier,
                        action: "abandonedCompileLanded",
                        details: "afterMs=\(landedAfterMs) budget=\(prewarmTimeoutSeconds)s "
                            + "outcome=\(ModelManager.landingOutcome(of: result))"
                    ))
                }
            } catch let err as ModelManagerError {
                if case .prewarmTimeout(let s) = err {
                    engineIsOursToRelease = false
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

            // Issue #174: a freshly downloaded model becomes the active one — see the
            // comment in the WhisperKit path, including why the user's later choice wins.
            let userMovedOn = DictationCoordinator.shared.loadWasAbandoned(since: prewarmEpoch)
            if userMovedOn {
                PersistentLog.log(.diagnosticProbe(
                    component: "ModelPrewarm",
                    instanceID: identifier,
                    action: "notAdoptedAsActive",
                    details: "reason=userChoseAnotherModelDuringPrewarm active=\(activeModel ?? "nil")"
                ))
            } else {
                activeModel = identifier
            }

            // Persist BEFORE announcing. `setState` tells the other `ModelManager` in
            // this process that the model is ready, and that instance answers by
            // re-reading the App Group — so announcing first handed it the state from
            // before this download existed. Onboarding then sat on a finished model with
            // no Continue button, because `isModelReady` was still false when it looked
            // (observed on the simulator, 2026-09-01).
            persistState()
            setState(.ready, for: identifier)

            PersistentLog.log(.modelCompilationCompleted(name: identifier, durationMs: prewarmDurationMs))
            PersistentLog.log(.modelPrewarmPeakMemory(modelName: identifier, peakMB: consumedMB))
            PersistentLog.log(.modelDownloadCompleted(name: identifier))
            PersistentLog.log(.modelSelected(name: identifier))

            // Released early for the same reason as the WhisperKit path above.
            DictationCoordinator.shared.releaseNeuralEngine(from: engineHolder)

            // Issue #144: same proactive load as the WhisperKit path — see comment there,
            // including why an abandoned preparation does not get one.
            if !userMovedOn {
                DictationCoordinator.shared.preloadActiveModel()
            }
        } catch is CancellationError {
            // This attempt was superseded by another one for the same model — the only
            // way that happens is a re-listing that found a different repository
            // revision, which supersedes the transfer this call was waiting on. The
            // attempt that replaced it owns the card now, so nothing here may write to
            // it (issue #449).
            throw CancellationError()
        } catch {
            setState(.error(error.localizedDescription), for: identifier)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Deliberately NO cleanupModelFiles here, for any failure:
            // the downloader moves each file into place atomically, so anything on
            // disk is a complete file — leaving the cache intact lets a retry skip
            // already-downloaded files and resume where it left off. Since issue
            // #235, tapping the card's "Retry" affordance retries in place; the
            // full reset lives in the overflow menu's "Delete partial download"
            // entry (cleanupFailedModel).
            //
            // This is also what the prewarm deadline #422 added needs, and it needs
            // nothing else: keeping the payload after a timeout is the policy the
            // WhisperKit path had to be taught in #405, and this path has had it since
            // #210. There is no `ModelCleanupPolicy` call to make here because there is
            // no branch — nothing on this path deletes anything, ever.
            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Applies one downloader progress tick: percentage bar, MB counter, and
    /// decile-throttled persistent logging (~10 log lines per download).
    /// Shared by the WhisperKit and Parakeet download paths (issue #210).
    private func updateDownloadProgress(_ progress: ModelRepoDownloader.Progress, identifier: String) {
        downloadProgress[identifier] = Float(progress.fraction)
        let bytes = ModelDownloadBytes(progress)
        downloadByteInfo[identifier] = bytes
        // The other instance draws the same bar (issue #449) — see `setState`.
        NotificationCenter.default.post(
            name: .dictusModelPreparationChanged,
            object: nil,
            userInfo: [
                "sender": instanceID.uuidString,
                "id": identifier,
                "state": "downloading",
                "progress": Float(progress.fraction),
                "downloadedMB": bytes.downloadedMB,
                "totalMB": bytes.totalMB
            ]
        )

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

        activeModel = identifier
        persistState()
        PersistentLog.log(.modelSelected(name: identifier))
        // Trigger an eager load so the model is in RAM before the next mic tap.
        DictationCoordinator.shared.preloadActiveModel()
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

        // And the staging area of any transfer still holding partial bytes for it
        // (issue #449) — deleting a model has to free the disk it is actually using,
        // and up to two 32 MB chunks plus a partial can be sitting outside the cache.
        BackgroundModelDownloadService.shared.discardStaging(for: identifier)

        downloadedModels.removeAll { $0 == identifier }
        setState(.notDownloaded, for: identifier)

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
        setState(.notDownloaded, for: identifier)
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

        // The manifest, the partials and the chunks a resumable transfer keeps outside
        // the cache directory (issue #449). "Delete partial download" has to mean the
        // whole partial download, or the next attempt resumes onto bytes the user
        // believed they had deleted.
        BackgroundModelDownloadService.shared.discardStaging(for: identifier)

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

    /// How a compile the app had already given up on eventually ended, for the debug
    /// log (issue #427). Nothing branches on this: by the time it is known the download
    /// has already reported its failure and the user has already been told to retry.
    /// It exists so the log reader can tell "abandoned and finished" — the normal case,
    /// and the one that leaves a warm cache — from "abandoned and never came back",
    /// which is the only shape a true hang can now leave.
    private static func landingOutcome<T>(of result: Result<T, Error>) -> String {
        switch result {
        case .success:
            return "success"
        case .failure(let error):
            return "failure:\(error.localizedDescription)"
        }
    }

    /// Persists model state to App Group UserDefaults so the keyboard extension
    /// can read which model is active and whether transcription is available.
    private func persistState() {
        if let data = try? JSONEncoder().encode(downloadedModels) {
            defaults.set(data, forKey: SharedKeys.downloadedModels)
        }
        defaults.set(activeModel, forKey: SharedKeys.activeModel)
        // WHY `isModelReady` and not `!downloadedModels.isEmpty` (issue #433): the two
        // could not disagree before, because the only writer of `downloadedModels` set
        // `activeModel` in the same breath. The launch reconciliation adds a model
        // without electing one, so a device whose first ever download was interrupted
        // now reaches this line with a populated list and no active model. Every reader
        // of this flag — the launch preload, `startDictation`, the foreground warm-up —
        // takes it as "there is a model to load", and there is not one until something
        // chooses it. The stricter definition is the one the flag has always claimed.
        defaults.set(isModelReady, forKey: SharedKeys.modelReady)
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
            // WHY this no longer says the optimization "did not complete" (issue #427):
            // it did, almost every time. The old guard could not interrupt the compile,
            // so it announced a failure for work that finished moments later; and now
            // that the app really does stop waiting at the deadline, the compile it
            // stopped waiting for is still running as this sentence is written. Late is
            // the true claim, failed is not. The compile also warms the Core ML cache on
            // its way out, which is what makes retrying the useful next move rather than
            // a second full wait.
            //
            // No promise about how fast the retry will be: it queues behind the compile
            // still on the Neural Engine, so "in a moment" is as precise as we can
            // honestly be.
            return String(localized: "Optimization did not finish within \(seconds)s. It is still running, so try again in a moment.")
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

/// Runs a Core ML prewarm under the catalogue's budget, and stops waiting on it when
/// the budget runs out.
///
/// WHY THE GUARD EXISTS: WhisperKit's async init for certain model variants on iPhone
/// ANE can hang indefinitely when Core ML fails to compile the model (issue #104,
/// 2026-04-22 on-device test: `ANE model load has failed … Must re-compile the E5
/// bundle` followed by `await WhisperKit(config)` never returning). Without a deadline,
/// `ModelManager` stays in `.prewarming` for the life of the process and the Settings
/// spinner never stops.
///
/// WHY IT IS NOT A TASK GROUP ANY MORE (issue #427): it was, and that version bounded
/// nothing — see `withDetachedDeadline`, which carries the measurement and the reason.
/// This is now a thin translation of that primitive into `ModelManager`'s vocabulary:
/// the same budget, the same `.prewarmTimeout`, and an expiry that actually returns at
/// the deadline.
///
/// THE OPERATION IS ABANDONED, NOT STOPPED. Nothing can stop a Core ML compile. On
/// expiry it keeps running, keeps the Neural Engine, and finishes on its own — which is
/// why `whenLateCompilationLands` exists and why every caller has to use it to hand the
/// engine back. Releasing at the throw instead would let a second compile start on top
/// of the first, and `acquireNeuralEngine` documents at length what that costs.
@MainActor
func withPrewarmTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T,
    whenLateCompilationLands: @escaping @MainActor @Sendable (Result<T, Error>) -> Void
) async throws -> T {
    do {
        return try await withDetachedDeadline(
            seconds: seconds,
            operation: operation,
            onLateCompletion: whenLateCompilationLands
        )
    } catch let expiry as DeadlineExpired {
        throw ModelManagerError.prewarmTimeout(seconds: expiry.seconds)
    }
}
