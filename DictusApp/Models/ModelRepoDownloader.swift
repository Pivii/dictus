// DictusApp/Models/ModelRepoDownloader.swift
// Downloads model files from a HuggingFace repo with real byte-level progress.
import Foundation
import DictusCore
import FluidAudio

/// Downloads a HuggingFace model repo (Parakeet or WhisperKit) into the exact
/// directory the respective engine expects, reporting real byte-level progress.
///
/// WHY this exists (issue #207, App Review rejection of 1.7.1 build 19):
/// FluidAudio's `DownloadUtils.downloadRepo` attaches a `URLSessionDownloadDelegate`
/// but downloads via the async `URLSession.download(for:)` convenience API — and that
/// API never delivers `didWriteData` callbacks, even with a delegate attached (verified
/// empirically; only the classic `downloadTask(with:)` + delegate pattern fires them).
/// Progress therefore only advanced when a whole file completed. Since
/// `Encoder.mlmodelc/weights/weight.bin` alone is ~92% of the ~483 MB payload, the bar
/// sat at ~5% for minutes and then jumped to ~97% — App Review read that as a freeze.
///
/// Issue #210 generalized the class (formerly `ParakeetModelDownloader`) so WhisperKit
/// models get the same MB counter, stall detection, and resume. The engine-specific
/// knowledge (repo path, file selection, on-disk layout, final verification) lives in
/// `Configuration.parakeet()` / `Configuration.whisperKit(variant:)`; the download
/// machinery is shared.
///
/// Issue #449 moved the bytes themselves out of this class. What is left here is what
/// only this class knows — which repository, which files, which revision, and what a
/// finished download has to look like — and the transfer belongs to
/// `BackgroundModelDownloadService`, which owns one background `URLSession` for the
/// whole app. The delegate-based `downloadTask` this file used to run was foreground
/// only: leaving Dictus suspended it, the 30 s stall detector fired on the user's
/// return, and the retry started the current file at byte zero. On a 445 MB weight blob
/// that meant onboarding never finished unless the user stared at it.
///
/// Parity contracts to re-check on dependency bumps:
/// - FluidAudio 0.12.4 `DownloadUtils.downloadRepo` (file selection + layout) so that
///   `AsrModels.load` finds the cached files and goes straight to CoreML compilation.
///   Since issue #252 nothing downloads Parakeet on the load path, so a file this
///   downloader misses is a hard failure rather than a silent second download.
/// - WhisperKit `WhisperKit.download` / HubApi snapshot layout
///   (`Documents/huggingface/models/{repo}/{variant}`) so that
///   `WhisperKitConfig(modelFolder:)` and `ModelManager.deleteModel` keep working.
final class ModelRepoDownloader {

    // MARK: - Public types

    /// Aggregate download progress across all repo files, weighted by bytes.
    struct Progress: Sendable {
        let bytesDownloaded: Int64
        let totalBytes: Int64
        let completedFiles: Int
        let totalFiles: Int

        var fraction: Double {
            totalBytes > 0 ? min(Double(bytesDownloaded) / Double(totalBytes), 1.0) : 0
        }
    }

    struct Configuration: Sendable {
        /// Attempts per repository-listing request before the download fails
        /// (backoff 2s/4s/8s).
        ///
        /// The transfer's own attempt budget and its stall timeout moved to
        /// `BackgroundModelDownloadService` with the bytes (issue #449); this one
        /// covers the tree API calls that still run here, in the foreground.
        var maxAttemptsPerFile: Int = 3
        /// HuggingFace repo id, e.g. "argmaxinc/whisperkit-coreml".
        let repoPath: String
        /// Repo-relative directory prefixes (with trailing "/") whose contents are
        /// downloaded recursively. Everything outside them is skipped.
        let directoryPatterns: [String]
        /// When true, root-level `.json`/`.txt` metadata files are also included
        /// (FluidAudio parity — covers `parakeet_vocab.json` at the repo root).
        let includesRootMetadata: Bool
        /// Repo-relative paths that must exist on disk after the download —
        /// the final-verification tripwire (see Phase 5 in `download`).
        ///
        /// A function of the destination directory rather than a list fixed up
        /// front, since issue #433: a WhisperKit variant has to be checked against
        /// the bundles it actually shipped, and that is only knowable once the
        /// files are there. The turbos add a fourth `.mlmodelc` whose weights are
        /// the last bytes of the whole download, so a fixed three-bundle list
        /// declared its download verified at the one moment it most likely was not.
        let requiredPaths: @Sendable (URL) -> [String]

        /// Parakeet v3 repo. Matches FluidAudio's `Repo.parakeet.remotePath`,
        /// its file selection, and mirrors `AsrModels.modelsExist` verification.
        static func parakeet() -> Configuration {
            Configuration(
                repoPath: Repo.parakeet.remotePath,
                directoryPatterns: ModelNames.ASR.requiredModels.map { "\($0)/" }.sorted(),
                includesRootMetadata: true,
                requiredPaths: { _ in ModelNames.ASR.requiredModels + [ModelNames.ASR.vocabularyFile] }
            )
        }

        /// One WhisperKit variant from argmaxinc/whisperkit-coreml.
        ///
        /// WHY exact-folder matching is safe here: `WhisperKit.download` resolves the
        /// variant with the glob `"*{variant}/*"`, but every identifier in our catalog
        /// (`ModelInfo`) IS the exact top-level folder name in the repo, so the glob
        /// resolves to that folder and nothing else. Selecting `{variant}/` directly
        /// downloads the same file set into the same layout.
        ///
        /// Required paths moved to `WhisperModelRepository` for issue #433, which
        /// added a second reader: the launch reconciliation that decides whether the
        /// files of an interrupted preparation amount to a finished download. That
        /// decision is only defensible if it names the very paths this tripwire
        /// guarantees, so the two are now literally the same list.
        ///
        /// Two things that list learned, both of them holes this tripwire had:
        ///
        /// - It names the leaf files inside a bundle, not the bundle directory.
        ///   Phase 4 below checks with `FileManager.fileExists`, which answers true
        ///   for a directory, and this downloader creates a file's parent directory
        ///   before fetching the file — so a bundle-level list passed on an
        ///   `AudioEncoder.mlmodelc/` that existed and was empty.
        /// - It reads the bundles the variant actually shipped instead of assuming
        ///   the three every variant has. The turbos ship a fourth,
        ///   `TextDecoderContextPrefill.mlmodelc`, and because `listRequiredFiles`
        ///   walks the repo breadth first, that bundle's `weights/weight.bin` is the
        ///   last file of the entire download. A fixed three-bundle list therefore
        ///   declared the download verified at precisely the moment it most likely
        ///   was not.
        ///
        /// The `directoryPatterns` glob has always pulled the whole variant folder,
        /// so nothing about what gets DOWNLOADED changes here — only what gets
        /// checked afterwards.
        static func whisperKit(variant: String) -> Configuration {
            Configuration(
                repoPath: WhisperModelRepository.repositoryID,
                directoryPatterns: ["\(variant)/"],
                includesRootMetadata: false,
                requiredPaths: { cacheDir in
                    WhisperModelRepository.requiredDownloadPaths(forVariant: variant, in: cacheDir)
                }
            )
        }
    }

    enum DownloadError: LocalizedError {
        case invalidResponse
        case rateLimited(statusCode: Int)
        case httpError(path: String, statusCode: Int)
        case stalled(path: String, timeoutSeconds: Int)
        case missingRequiredFile(String)
        /// An assembled file failed its size or SHA-256 check and was thrown away
        /// (issue #449). Retryable: the next attempt downloads it from byte zero.
        case integrityFailed(path: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return String(localized: "The model server returned an invalid response.")
            case .rateLimited:
                return String(localized: "The model server is busy. Please try again in a few minutes.")
            case .httpError(_, let statusCode):
                return String(localized: "A model file could not be downloaded (error \(statusCode)).")
            case .stalled:
                return String(localized: "The download stalled. Check your internet connection and try again.")
            case .missingRequiredFile:
                return String(localized: "The model download is incomplete. Please try again.")
            case .integrityFailed:
                return String(localized: "A model file arrived damaged. Dictus will download it again.")
            }
        }
    }

    // MARK: - Init

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Downloads all required repo files into `cacheDir` — the directory that maps
    /// to the repo ROOT (repo-relative file paths are preserved below it):
    /// - Parakeet: `AsrModels.defaultCacheDirectory(for: .v3)` (the repo directory
    ///   itself, NOT its parent).
    /// - WhisperKit: `Documents/huggingface/models/argmaxinc/whisperkit-coreml`
    ///   (the variant folder lands inside it, matching HubApi's snapshot layout).
    ///
    /// Files already present on disk are skipped, and the file in flight resumes at the
    /// byte it stopped on — across backgrounding, across a network change, and across
    /// the process being killed (issue #449). What survives the process is the manifest
    /// and the partials `BackgroundModelDownloadService` keeps; what survives inside one
    /// process is the background `URLSession` itself.
    ///
    /// - Parameters:
    ///   - cacheDir: Destination repo directory.
    ///   - modelName: Model identifier, used for logging and to key the manifest.
    ///   - onProgress: Throttled (~0.5% or 300ms) aggregate progress. Called on a
    ///     background queue — hop to the main actor before touching UI.
    func download(
        to cacheDir: URL,
        modelName: String,
        onProgress: @escaping @Sendable (ModelRepoDownloader.Progress) -> Void
    ) async throws {
        // Phase 1: pin the revision. Every URL from here on is the canonical
        // `/resolve/<commit>/<path>` form, which is what makes a resume days later
        // meaningful: `main` can move between the bytes on disk and the bytes about to
        // arrive, and the redirected CDN URLs it lands on carry a short-lived signature
        // that is worthless the moment it is written down (maintainer's note, #449).
        let revision = await resolveRevision()

        // Phase 2: list the repo tree and select files (engine parity via Configuration).
        let files = try await listRequiredFiles(revision: revision)

        // Phase 3: byte-weighted totals. The HF tree API reports real LFS blob
        // sizes (verified: Encoder weight.bin = 445187200), so byte weighting is
        // accurate. Unknown sizes (-1) count as 0, same as FluidAudio.
        let totalBytes: Int64 = files.reduce(0) { $0 + Int64(max(0, $1.size)) }
        Self.logSizeMismatchIfAny(modelName: modelName, measuredBytes: totalBytes)

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Phase 4: hand the transfer to the background session, with what is already on
        // disk marked complete. Sequential per file, as before: bandwidth is dominated
        // by one huge weight file per repo, and parallelism across files would only make
        // the aggregate percentage move backwards.
        let manifest = ModelDownloadManifest(
            modelIdentifier: modelName,
            repositoryID: configuration.repoPath,
            revision: revision,
            chunkSize: BackgroundModelDownloadService.chunkSize,
            files: files.map { file in
                ModelDownloadManifest.FileEntry(
                    path: file.path,
                    size: Int64(file.size),
                    sha256: file.sha256,
                    completed: FileManager.default.fileExists(
                        atPath: cacheDir.appendingPathComponent(file.path).path
                    )
                )
            }
        )

        try await BackgroundModelDownloadService.shared.run(
            manifest: manifest,
            destination: cacheDir,
            onProgress: onProgress
        )

        // Phase 5: parity tripwire — mirror each engine's own existence check
        // (AsrModels.modelsExist for Parakeet, the CoreML bundle set for WhisperKit)
        // so we fail loudly here (with a localized error) instead of silently
        // handing an incomplete cache to the engine. If the repo layout ever
        // drifts, this is the signal.
        for requiredPath in configuration.requiredPaths(cacheDir) {
            let path = cacheDir.appendingPathComponent(requiredPath)
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw DownloadError.missingRequiredFile(requiredPath)
            }
        }
    }

    // MARK: - Destination directories

    /// Where a model's repository files live on disk, resolved from the catalogue.
    ///
    /// WHY it is a function and not a stored path (issue #449): the background service
    /// has to find this directory again in a process that was relaunched by iOS, and an
    /// app container path is not stable across installs — persisting one would send a
    /// resumed download into a directory that no longer exists. `ModelManager` calls the
    /// same function so the two can never disagree about where a model went.
    static func destinationDirectory(for identifier: String) -> URL? {
        switch ModelInfo.forIdentifier(identifier)?.engine {
        case .parakeet:
            return AsrModels.defaultCacheDirectory(for: .v3)
        case .whisperKit, nil:
            return WhisperModelRepository.repositoryURL()
        }
    }

    // MARK: - Catalogue size reconciliation (issue #372)

    /// Compares the size `ModelInfo` promised on the model card against the total
    /// the repository just told us, and logs the pair when they disagree.
    ///
    /// WHY here: this is the only moment in the app where both numbers exist. The
    /// card cannot compute the real total (it would need this network round trip),
    /// so the announced size has to stay a hand-written constant — and it will
    /// drift again the next time a repository is repacked. One line at download
    /// time turns that drift from silent into something a log reader catches for
    /// free. `ModelInfo.sizeHasDrifted(fromMeasured:)` owns the threshold.
    ///
    /// Nothing downstream reads this: it is diagnostics only, the download proceeds
    /// on the measured total exactly as before.
    private static func logSizeMismatchIfAny(modelName: String, measuredBytes: Int64) {
        guard let model = ModelInfo.forIdentifier(modelName),
              model.sizeHasDrifted(fromMeasured: measuredBytes) else { return }
        PersistentLog.log(.modelDownloadSizeMismatch(
            name: modelName,
            catalogMB: Int(model.sizeBytes / 1_000_000),
            actualMB: Int(measuredBytes / 1_000_000)
        ))
    }

    // MARK: - File listing (HuggingFace tree API)

    struct RepoFile: Sendable {
        let path: String
        let size: Int
        /// SHA-256 of the blob, for LFS entries only — the plain `oid` is a git blob
        /// SHA-1 over a different preimage and would fail every comparison.
        let sha256: String?
    }

    private struct TreeItem: Decodable {
        let path: String
        let type: String
        let size: Int?
        let lfs: TreeLFSPointer?
    }

    private struct RepoInfo: Decodable {
        let sha: String?
    }

    /// The commit the whole download is pinned to, or `main` when it cannot be resolved.
    ///
    /// A failure here is not fatal: `main` is what every previous build used, and the
    /// only thing lost is the guarantee that a resume days later reads the same
    /// revision. The `If-Range` validator still catches that case, at the cost of
    /// restarting the file instead of appending to it.
    private func resolveRevision() async -> String {
        guard let url = URL(string: "https://huggingface.co/api/models/\(configuration.repoPath)") else {
            return "main"
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "main"
            }
            let info = try JSONDecoder().decode(RepoInfo.self, from: data)
            guard let sha = info.sha, !sha.isEmpty else { return "main" }
            return sha
        } catch {
            return "main"
        }
    }

    /// Recursively lists the repo tree at `revision` and returns the files the engine
    /// would download: everything under `configuration.directoryPatterns`, plus
    /// root-level `.json`/`.txt` files when `includesRootMetadata` is set.
    private func listRequiredFiles(revision: String) async throws -> [RepoFile] {
        let patterns = configuration.directoryPatterns
        var files: [RepoFile] = []
        var pendingDirectories = [""]

        while let directory = pendingDirectories.first {
            pendingDirectories.removeFirst()
            let items = try await fetchTree(path: directory, revision: revision)

            for item in items {
                if item.type == "directory" {
                    // Recurse only into (ancestors of) the required directories.
                    if Self.shouldRecurse(into: item.path, patterns: patterns) {
                        pendingDirectories.append(item.path)
                    }
                } else if item.type == "file" {
                    if Self.shouldInclude(
                        filePath: item.path,
                        patterns: patterns,
                        includesRootMetadata: configuration.includesRootMetadata
                    ) {
                        files.append(RepoFile(
                            path: item.path,
                            size: item.size ?? -1,
                            sha256: item.lfs?.oid
                        ))
                    }
                }
            }
        }
        return files
    }

    /// Parity with FluidAudio's directory filter (DownloadUtils.swift:311-313).
    static func shouldRecurse(into directoryPath: String, patterns: [String]) -> Bool {
        patterns.contains {
            directoryPath.hasPrefix($0) || $0.hasPrefix(directoryPath + "/")
        }
    }

    /// Parity with FluidAudio's file filter (DownloadUtils.swift:329-331) when
    /// `includesRootMetadata` is true; plain prefix match otherwise (WhisperKit —
    /// the variant folder already contains its own config/generation JSON files).
    static func shouldInclude(
        filePath: String,
        patterns: [String],
        includesRootMetadata: Bool
    ) -> Bool {
        if patterns.contains(where: { filePath.hasPrefix($0) }) {
            return true
        }
        guard includesRootMetadata else { return false }
        return filePath.hasSuffix(".json") || filePath.hasSuffix(".txt")
    }

    /// Fetches one directory listing from the HF tree API, with retry/backoff
    /// (mirrors FluidAudio's `fetchHuggingFaceFile` retry envelope).
    private func fetchTree(path: String, revision: String) async throws -> [TreeItem] {
        let apiPath = path.isEmpty ? "tree/\(revision)" : "tree/\(revision)/\(path)"
        guard let url = URL(string: "https://huggingface.co/api/models/\(configuration.repoPath)/\(apiPath)") else {
            throw DownloadError.invalidResponse
        }

        var lastError: Error = DownloadError.invalidResponse
        for attempt in 1...configuration.maxAttemptsPerFile {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw DownloadError.invalidResponse
                }
                if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
                    throw DownloadError.rateLimited(statusCode: httpResponse.statusCode)
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw DownloadError.httpError(path: path, statusCode: httpResponse.statusCode)
                }
                return try JSONDecoder().decode([TreeItem].self, from: data)
            } catch {
                lastError = error
                if attempt < configuration.maxAttemptsPerFile, Self.isRetryable(error) {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                } else {
                    throw error
                }
            }
        }
        throw lastError
    }

    /// True for transient failures worth retrying (stall, connection loss, rate limit).
    static func isRetryable(_ error: Error) -> Bool {
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .rateLimited, .stalled, .integrityFailed:
                // An integrity failure is retryable on purpose: the file it refused has
                // been thrown away, so the next attempt downloads it from byte zero. A
                // resume that appended the wrong bytes is exactly the thing a second,
                // clean download fixes.
                return true
            case .invalidResponse, .httpError, .missingRequiredFile:
                return false
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed:
            return true
        default:
            return false
        }
    }
}

/// The `lfs` object a Hugging Face tree entry carries for a large blob.
///
/// Declared at file scope rather than nested inside `TreeItem`: the repo's lint rule
/// allows one level of nesting, and `TreeItem` already spends it.
///
/// `oid` is the blob's SHA-256, which is what `ModelFileIntegrity` verifies an assembled
/// file against. Plain files have no `lfs` object at all, and their top-level `oid` is a
/// git blob SHA-1 over a different preimage — comparable to nothing, which is why it is
/// not read here.
private struct TreeLFSPointer: Decodable {
    let oid: String?
}
