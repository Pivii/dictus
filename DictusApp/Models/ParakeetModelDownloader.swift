// DictusApp/Models/ParakeetModelDownloader.swift
// Downloads Parakeet model files from HuggingFace with real byte-level progress.
import Foundation
import DictusCore
import FluidAudio

/// Downloads the Parakeet v3 model repo from HuggingFace into the exact directory
/// FluidAudio's `AsrModels` expects, reporting real byte-level progress.
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
/// This downloader mirrors FluidAudio's file selection and on-disk layout so that
/// `AsrModels.downloadAndLoad` finds the cached files and skips straight to CoreML
/// compilation. Reference implementation for parity: FluidAudio 0.12.4
/// `DownloadUtils.downloadRepo` — re-check the parity rules on any FluidAudio bump.
final class ParakeetModelDownloader {

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
        /// Seconds without a single received byte before a file attempt is aborted.
        /// Applied as `timeoutIntervalForRequest`, which for download tasks is an
        /// IDLE timeout that resets whenever data arrives — a slow-but-alive
        /// connection never trips it, only a genuine stall does.
        var stallTimeout: TimeInterval = 30
        /// Attempts per file before the whole download fails (backoff 2s/4s/8s).
        var maxAttemptsPerFile: Int = 3
        /// HuggingFace repo. Matches FluidAudio's `Repo.parakeet.remotePath`.
        var repoPath: String = Repo.parakeet.remotePath
    }

    enum DownloadError: LocalizedError {
        case invalidResponse
        case rateLimited(statusCode: Int)
        case httpError(path: String, statusCode: Int)
        case stalled(path: String, timeoutSeconds: Int)
        case missingRequiredFile(String)

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
            }
        }
    }

    // MARK: - Init

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Downloads all required repo files into `cacheDir` — the FluidAudio repo
    /// directory itself (`AsrModels.defaultCacheDirectory(for: .v3)`), NOT its parent.
    ///
    /// Files already present on disk are skipped, which makes a retry after a
    /// failure resume where it left off (every file on disk is complete because
    /// downloads land in a temp location and are moved atomically on completion).
    ///
    /// - Parameters:
    ///   - cacheDir: Destination repo directory.
    ///   - modelName: Model identifier, used only for persistent logging.
    ///   - onProgress: Throttled (~0.5% or 300ms) aggregate progress. May be
    ///     called on a background queue — hop to the main actor before touching UI.
    func download(
        to cacheDir: URL,
        modelName: String,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        // Phase 1: list the repo tree and select files (parity with FluidAudio).
        let files = try await listRequiredFiles()

        // Phase 2: byte-weighted totals. The HF tree API reports real LFS blob
        // sizes (verified: Encoder weight.bin = 445187200), so byte weighting is
        // accurate. Unknown sizes (-1) count as 0, same as FluidAudio.
        let totalBytes: Int64 = files.reduce(0) { $0 + Int64(max(0, $1.size)) }
        let reporter = ProgressReporter(
            totalBytes: totalBytes,
            totalFiles: files.count,
            onProgress: onProgress
        )

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Phase 3: sequential per-file download loop. Sequential matches FluidAudio
        // and keeps progress monotonic; bandwidth is dominated by one 445 MB file,
        // so parallelism would buy nothing.
        for file in files {
            try Task.checkCancellation()

            let destination = cacheDir.appendingPathComponent(file.path)

            // Skip complete files — this is what makes retry resumable.
            if FileManager.default.fileExists(atPath: destination.path) {
                reporter.fileCompleted(sizeBytes: Int64(max(0, file.size)))
                continue
            }

            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // HuggingFace returns HTTP 500 for 0-byte files — create locally instead.
            if file.size == 0 {
                FileManager.default.createFile(atPath: destination.path, contents: Data())
                reporter.fileCompleted(sizeBytes: 0)
                continue
            }

            try await downloadFileWithRetry(
                file,
                to: destination,
                modelName: modelName,
                reporter: reporter
            )
            reporter.fileCompleted(sizeBytes: Int64(max(0, file.size)))
        }

        // Phase 4: parity tripwire — mirror AsrModels.modelsExist so we fail loudly
        // here (with a localized error) instead of silently handing an incomplete
        // cache to FluidAudio. If the repo layout ever drifts, this is the signal.
        for model in ModelNames.ASR.requiredModels {
            let path = cacheDir.appendingPathComponent(model)
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw DownloadError.missingRequiredFile(model)
            }
        }
        let vocabPath = cacheDir.appendingPathComponent(ModelNames.ASR.vocabularyFile)
        guard FileManager.default.fileExists(atPath: vocabPath.path) else {
            throw DownloadError.missingRequiredFile(ModelNames.ASR.vocabularyFile)
        }
    }

    // MARK: - File listing (HuggingFace tree API)

    struct RepoFile: Sendable {
        let path: String
        let size: Int
    }

    private struct TreeItem: Decodable {
        let path: String
        let type: String
        let size: Int?
    }

    /// Recursively lists the repo tree and returns the files FluidAudio would
    /// download: everything under the four required `.mlmodelc` directories, plus
    /// root-level `.json`/`.txt` files (covers `parakeet_vocab.json`).
    private func listRequiredFiles() async throws -> [RepoFile] {
        let patterns = ModelNames.ASR.requiredModels.map { "\($0)/" }.sorted()
        var files: [RepoFile] = []
        var pendingDirectories = [""]

        while let directory = pendingDirectories.first {
            pendingDirectories.removeFirst()
            let items = try await fetchTree(path: directory)

            for item in items {
                if item.type == "directory" {
                    // Recurse only into (ancestors of) the required model dirs.
                    if Self.shouldRecurse(into: item.path, patterns: patterns) {
                        pendingDirectories.append(item.path)
                    }
                } else if item.type == "file" {
                    if Self.shouldInclude(filePath: item.path, patterns: patterns) {
                        files.append(RepoFile(path: item.path, size: item.size ?? -1))
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

    /// Parity with FluidAudio's file filter (DownloadUtils.swift:329-331).
    static func shouldInclude(filePath: String, patterns: [String]) -> Bool {
        patterns.contains { filePath.hasPrefix($0) }
            || filePath.hasSuffix(".json")
            || filePath.hasSuffix(".txt")
    }

    /// Fetches one directory listing from the HF tree API, with retry/backoff
    /// (mirrors FluidAudio's `fetchHuggingFaceFile` retry envelope).
    private func fetchTree(path: String) async throws -> [TreeItem] {
        let apiPath = path.isEmpty ? "tree/main" : "tree/main/\(path)"
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

    // MARK: - Single-file download with retry

    private func downloadFileWithRetry(
        _ file: RepoFile,
        to destination: URL,
        modelName: String,
        reporter: ProgressReporter
    ) async throws {
        let encodedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
        guard let url = URL(string: "https://huggingface.co/\(configuration.repoPath)/resolve/main/\(encodedPath)") else {
            throw DownloadError.invalidResponse
        }

        var lastError: Error = DownloadError.invalidResponse
        for attempt in 1...configuration.maxAttemptsPerFile {
            do {
                try await downloadFile(from: url, filePath: file.path, to: destination) { bytesWritten in
                    reporter.currentFileBytes(bytesWritten)
                }
                return
            } catch {
                lastError = error
                // A retry restarts the file from byte 0 (no resume-data complexity),
                // so the aggregate bar can step back slightly after a mid-file retry.
                reporter.currentFileBytes(0)
                guard attempt < configuration.maxAttemptsPerFile, Self.isRetryable(error) else {
                    throw error
                }
                PersistentLog.log(.modelDownloadStalled(
                    name: modelName,
                    path: file.path,
                    timeoutSeconds: Int(configuration.stallTimeout),
                    attempt: attempt
                ))
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
            }
        }
        throw lastError
    }

    /// True for transient failures worth retrying (stall, connection loss, rate limit).
    static func isRetryable(_ error: Error) -> Bool {
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .rateLimited, .stalled:
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

    /// Downloads one file using the classic delegate-based `URLSessionDownloadTask`
    /// — the ONLY URLSession variant that delivers `didWriteData` byte callbacks
    /// (the async `download(for:)` API silently drops them; see issue #207).
    ///
    /// SWIFT CONCEPT — bridging delegates to async/await:
    /// `withCheckedThrowingContinuation` "parks" the current `await` and hands us a
    /// one-shot `continuation` handle. The delegate resumes it exactly once (from
    /// `didCompleteWithError`, which URLSession guarantees is called exactly once
    /// per task), turning the callback-style API back into a plain `try await`.
    private func downloadFile(
        from url: URL,
        filePath: String,
        to destination: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let config = URLSessionConfiguration.ephemeral
        // Idle-based stall detector — resets on every received byte. Deliberately
        // NOT setting timeoutIntervalForResource (a 445 MB file on a slow link
        // legitimately takes many minutes) and NOT setting a per-request
        // timeoutInterval (it would override this value — that's exactly how
        // FluidAudio ends up with an 1800s effective timeout).
        config.timeoutIntervalForRequest = configuration.stallTimeout
        // Fail fast into our retry path when there's no connectivity, instead of
        // waiting silently for the network to come back.
        config.waitsForConnectivity = false

        let delegate = FileDownloadDelegate(
            destination: destination,
            filePath: filePath,
            stallTimeoutSeconds: Int(configuration.stallTimeout),
            onBytes: onBytes
        )
        // delegateQueue nil → URLSession creates a private SERIAL queue, so the
        // delegate's download-state members need no locking.
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: URLRequest(url: url))
                delegate.start(task: task, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
    }
}

// MARK: - Progress reporting

/// Thread-safe aggregate progress accumulator with throttling.
///
/// `didWriteData` can fire hundreds of times per second; forwarding every tick to
/// a `@Published` property on the main actor would hammer SwiftUI. We only emit
/// when the fraction advanced ≥ 0.5% or ≥ 300ms elapsed, plus on file completion.
///
/// Marked `@unchecked Sendable` because Sendable conformance can't be proven for
/// lock-guarded mutable state — every member below is only touched under `lock`.
private final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let totalBytes: Int64
    private let totalFiles: Int
    private let onProgress: @Sendable (ParakeetModelDownloader.Progress) -> Void

    private var completedBytes: Int64 = 0
    private var completedFiles = 0
    private var currentBytes: Int64 = 0
    private var lastReportedFraction: Double = -1
    private var lastReportDate = Date.distantPast

    init(
        totalBytes: Int64,
        totalFiles: Int,
        onProgress: @escaping @Sendable (ParakeetModelDownloader.Progress) -> Void
    ) {
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
        self.onProgress = onProgress
    }

    /// Bytes received so far for the file currently downloading.
    func currentFileBytes(_ bytes: Int64) {
        lock.lock()
        currentBytes = bytes
        let progress = makeProgress()
        let now = Date()
        let shouldEmit = progress.fraction - lastReportedFraction >= 0.005
            || now.timeIntervalSince(lastReportDate) >= 0.3
        if shouldEmit {
            lastReportedFraction = progress.fraction
            lastReportDate = now
        }
        lock.unlock()
        if shouldEmit { onProgress(progress) }
    }

    /// The current file finished (or was skipped); fold it into the completed base.
    func fileCompleted(sizeBytes: Int64) {
        lock.lock()
        completedBytes += sizeBytes
        completedFiles += 1
        currentBytes = 0
        let progress = makeProgress()
        lastReportedFraction = progress.fraction
        lastReportDate = Date()
        lock.unlock()
        onProgress(progress)
    }

    private func makeProgress() -> ParakeetModelDownloader.Progress {
        ParakeetModelDownloader.Progress(
            bytesDownloaded: completedBytes + currentBytes,
            totalBytes: totalBytes,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
    }
}

// MARK: - URLSession delegate

/// Forwards byte-level progress and bridges completion back to a continuation.
///
/// Callback contract this relies on (verified against URLSession semantics):
/// - `didWriteData` fires repeatedly as bytes arrive.
/// - `didFinishDownloadingTo` fires on success; the temp file at `location` is
///   deleted by the system the moment the callback returns, so the move to the
///   destination MUST happen synchronously inside it.
/// - `didCompleteWithError` fires exactly once per task (after
///   `didFinishDownloadingTo` on success), making it the single safe place to
///   resume the continuation — no double-resume possible.
///
/// `@unchecked Sendable`: `moveOrHTTPError` is only touched on the session's
/// private serial delegate queue; `continuation`/`task` are cross-thread
/// (set from the async caller, read from the delegate queue and cancellation
/// handler) and are guarded by `lock`.
private final class FileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let filePath: String
    private let stallTimeoutSeconds: Int
    private let onBytes: @Sendable (Int64) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    // Delegate-queue-only state (serial queue — no locking needed).
    private var moveOrHTTPError: Error?

    init(
        destination: URL,
        filePath: String,
        stallTimeoutSeconds: Int,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) {
        self.destination = destination
        self.filePath = filePath
        self.stallTimeoutSeconds = stallTimeoutSeconds
        self.onBytes = onBytes
    }

    /// Stores the continuation before starting the task so no delegate callback
    /// can observe a nil continuation.
    func start(task: URLSessionDownloadTask, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        self.task = task
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    /// Called from the structured-concurrency cancellation handler (any thread).
    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onBytes(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Validate the HTTP status before accepting the payload — HuggingFace
        // serves error bodies (429/503/500) that would otherwise be saved as
        // corrupt model files.
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            if response.statusCode == 429 || response.statusCode == 503 {
                moveOrHTTPError = ParakeetModelDownloader.DownloadError.rateLimited(statusCode: response.statusCode)
            } else {
                moveOrHTTPError = ParakeetModelDownloader.DownloadError.httpError(
                    path: filePath, statusCode: response.statusCode)
            }
            return
        }
        do {
            // Remove any stale destination (e.g. leftover from a manual copy),
            // then move — atomically publishing a complete file or nothing.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveOrHTTPError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }

        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                // timeoutIntervalForRequest tripped = no bytes for the stall window.
                continuation.resume(throwing: ParakeetModelDownloader.DownloadError.stalled(
                    path: filePath, timeoutSeconds: stallTimeoutSeconds))
            } else {
                continuation.resume(throwing: error)
            }
        } else if let moveOrHTTPError {
            continuation.resume(throwing: moveOrHTTPError)
        } else {
            continuation.resume(returning: ())
        }
    }
}
