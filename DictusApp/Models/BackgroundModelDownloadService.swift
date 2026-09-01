// DictusApp/Models/BackgroundModelDownloadService.swift
// The one background URLSession that moves model bytes, and the state machine over it.
import Foundation
import DictusCore

/// Transfers model repository files in a background `URLSession`, one aligned byte
/// range at a time, and keeps a durable record of how far it got.
///
/// WHY THIS EXISTS (issue #449). Until it, the download was a foreground-only
/// `URLSessionConfiguration.ephemeral` session created per file, and its retry restarted
/// the current file from byte zero. A user who left Dictus during
/// `Encoder.mlmodelc/weights/weight.bin` — 445 MB of Parakeet's 483 MB payload — had the
/// transfer suspended with the process, met the 30 s stall detector on their return, and
/// watched the bar go back to 0%. Measured on a 15 Pro Max on 2026-08-28: three attempts,
/// 98 MB then 289 MB then the whole thing, and the only one that finished was the one
/// where the user did not touch their phone for four minutes.
///
/// Three things had to change together, and none of them works without the other two:
///
/// 1. **A background session.** `URLSessionConfiguration.background` transfers keep
///    running while the process is suspended and are handed back to the app when it
///    returns, so leaving Dictus stops costing anything.
/// 2. **Chunks instead of whole files.** A `URLSessionDownloadTask` writes to a temp
///    file the system owns and only reveals in `didFinishDownloadingTo`, which fires on
///    success alone — so the bytes of a whole-file task that never finished are
///    unreachable. Fixed 32 MB aligned ranges are moved out of that temp location the
///    moment each one lands, which is what makes progress durable rather than merely
///    in flight.
/// 3. **A manifest.** The chunk that is safe to ask for next is a fact about the disk,
///    and it has to survive the process to be worth anything. `ModelDownloadManifest`
///    holds it, alongside the exact repository revision the bytes came from.
///
/// WHY HTTP RANGE AND NOT `URLSession` RESUME DATA. The issue's implementation direction
/// asked for resume data first and byte ranges as the fallback. Resume data cannot carry
/// acceptance criterion 3 — force-quit Dictus mid-file, relaunch, keep the bytes. iOS
/// cancels a background session's tasks when the user force-quits and does not relaunch
/// the app, and resume data is only ever handed to a *running* process through
/// `didCompleteWithError`. A process that was killed receives nothing and has nothing to
/// resume from. The maintainer's own follow-up note on the issue specifies the range path
/// in full and never mentions resume data, so that is what is built here; the two are
/// deliberately not mixed, because resume data replays a request with a `Range` header of
/// its own and the interaction with ours is not something anyone should have to reason
/// about at 2 am.
///
/// WHAT IT NEVER DOES: compile. A model that finishes downloading while Dictus is in the
/// background is left downloaded, and the Core ML prewarm waits for the foreground.
/// Issues #427 and #428 measured what an abandoned compile is worth in a suspended
/// process — nothing, and sometimes the process.
final class BackgroundModelDownloadService: NSObject, @unchecked Sendable {

    // MARK: - Configuration

    /// Stable across launches, which is the whole point: recreating a session with this
    /// identifier is what reconnects the app to transfers the system kept running.
    static let sessionIdentifier = "com.pivi.dictus.model-download"

    /// Bytes per aligned range request.
    ///
    /// The trade is between requests and re-paid bytes. Every chunk boundary is a
    /// durable savepoint, and every chunk in flight when the process dies is downloaded
    /// again. At 32 MB the 445 MB encoder costs 14 requests and a kill costs at most
    /// ~7% of it, against 100% before this existed.
    static let chunkSize: Int64 = 32 * 1024 * 1024

    /// How many chunks may be transferring at once.
    ///
    /// More than one so a suspended app does not stop dead the instant the current chunk
    /// lands and nobody is awake to ask for the next; few enough that a kill never puts
    /// more than 64 MB at risk.
    static let chunksInFlight = 2

    /// Seconds without a single received byte before a chunk is abandoned. Same value
    /// and same meaning as before (issue #207): `timeoutIntervalForRequest` is an IDLE
    /// timeout that resets whenever data arrives, so a slow connection never trips it.
    static let stallTimeout: TimeInterval = 30

    /// Attempts per file before the whole download fails (backoff 2s/4s/8s).
    static let maxAttemptsPerFile = 3

    // MARK: - Singleton

    static let shared = BackgroundModelDownloadService()

    private override init() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "solutions.pivi.dictus.model-download"
        self.queue = queue
        super.init()
    }

    /// Serial queue that is BOTH the session's delegate queue and the only place any
    /// member below is read or written. That is what makes `@unchecked Sendable` true
    /// here: there is exactly one thread of control over this object's state.
    private let queue: OperationQueue

    /// Created on first use and never again — two live sessions sharing one background
    /// identifier is a documented crash.
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        // The user is watching a progress bar; this is not a nice-to-have transfer the
        // system may defer to a better moment.
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = Self.stallTimeout
        configuration.httpMaximumConnectionsPerHost = Self.chunksInFlight
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    /// In-flight downloads, keyed by catalogue model identifier. One per model, which is
    /// what makes reopening onboarding unable to start a second copy (criterion 6).
    private var runs: [String: DownloadRun] = [:]

    /// What each live task is fetching, and how it ended, keyed by `taskIdentifier`.
    private var outcomes: [Int: ChunkOutcome] = [:]

    /// Handed over by `AppDelegate` when iOS relaunches the app to deliver background
    /// events. Must be called on the main thread once the events are drained.
    private var backgroundCompletionHandler: (@Sendable () -> Void)?

    // MARK: - Public API

    /// Runs (or joins) the transfer of one model and returns when every file is on disk.
    ///
    /// Calling this for a model already transferring attaches to that run instead of
    /// starting anything: same tasks, same manifest, one more progress observer. That is
    /// acceptance criterion 6 — reopening onboarding cannot launch a second download.
    ///
    /// - Parameters:
    ///   - manifest: the freshly listed repository state. Merged with whatever is already
    ///     on disk; a manifest that describes a different revision or file set replaces it.
    ///   - destination: directory that maps to the repository root.
    ///   - onProgress: called on the delegate queue — hop to the main actor for UI.
    func run(
        manifest: ModelDownloadManifest,
        destination: URL,
        onProgress: @escaping @Sendable (ModelRepoDownloader.Progress) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.addOperation { [self] in
                let run = adopt(manifest: manifest, destination: destination)
                run.observers.append(onProgress)
                run.continuations.append(continuation)
                run.emitProgress(force: true)
                pump(run)
            }
        }
    }

    /// Recreates the background session so the system hands back transfers that outlived
    /// the process, and rebuilds a run for every manifest still on disk.
    ///
    /// Called once, from `AppDelegate`, before anything else can touch a model.
    ///
    /// It deliberately does NOT resume a download that has no live task. A relaunch with
    /// zero tasks is the force-quit shape, and restarting the transfer from here would
    /// mean downloading half a gigabyte for a user who has not asked for anything yet.
    /// `ModelManager` decides that, from the foreground, and its call lands on the very
    /// run this rebuilt.
    func restore() {
        queue.addOperation { [self] in
            let manifests = ManifestStore.loadAll()
            for (identifier, manifest) in manifests {
                guard let destination = Self.destinationDirectory(for: identifier) else { continue }
                _ = adopt(manifest: manifest, destination: destination)
            }
            session.getAllTasks { [self] tasks in
                queue.addOperation { [self] in
                    var adopted = 0
                    for task in tasks {
                        guard let download = task as? URLSessionDownloadTask,
                              let tag = ModelDownloadTaskTag.decode(task.taskDescription),
                              let run = runs[tag.modelIdentifier],
                              tag.fileIndex == run.manifest.currentFileIndex else {
                            task.cancel()
                            continue
                        }
                        run.inFlight.insert(tag.chunkIndex)
                        run.tasks[tag.chunkIndex] = download
                        run.liveChunkBytes[tag.chunkIndex] = download.countOfBytesReceived
                        adopted += 1
                    }
                    PersistentLog.log(.modelDownloadSessionRestored(
                        tasks: adopted,
                        models: manifests.count
                    ))
                    for run in runs.values where !run.inFlight.isEmpty {
                        run.emitProgress(force: true)
                    }
                }
            }
        }
    }

    /// Identifiers with a manifest on disk that has not finished transferring.
    /// Read straight from the file system so a fresh process can answer it.
    static func interruptedModelIdentifiers() -> [String] {
        ManifestStore.loadAll()
            .filter { !$0.value.isTransferComplete }
            .keys
            .sorted()
    }

    /// Durable progress of an interrupted download, for a screen that has to show
    /// something before the first delegate callback of this process arrives.
    static func persistedProgress(for identifier: String) -> ModelRepoDownloader.Progress? {
        guard let manifest = ManifestStore.load(identifier) else { return nil }
        return ModelRepoDownloader.Progress(
            bytesDownloaded: manifest.receivedBytes,
            totalBytes: manifest.totalBytes,
            completedFiles: manifest.completedFileCount,
            totalFiles: manifest.files.count
        )
    }

    /// Throws away everything a model's interrupted download is holding: the manifest,
    /// the partials, the chunks. Called by the "Delete partial download" path and by
    /// model deletion, both of which mean the user wants the disk space back.
    func discardStaging(for identifier: String) {
        queue.addOperation { [self] in
            if let run = runs[identifier] {
                run.cancelAllTasks()
                finish(run, error: CancellationError())
            }
            ManifestStore.discard(identifier)
        }
    }

    /// Handed the completion handler iOS gives the app delegate when it relaunches to
    /// deliver background events. Kept until the session says it has no more.
    func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
        queue.addOperation { [self] in
            backgroundCompletionHandler = handler
            // Touch the session so it exists and starts draining. Without this the
            // handler would sit here until something else happened to create it.
            _ = session
        }
    }

    /// The directory a model's repository files land in, resolved from the catalogue
    /// rather than persisted: an app container path is not stable across installs.
    static func destinationDirectory(for identifier: String) -> URL? {
        ModelRepoDownloader.destinationDirectory(for: identifier)
    }

    // MARK: - Run lifecycle (delegate queue only)

    /// Returns the run for this model, creating it or replacing its manifest as needed.
    private func adopt(manifest: ModelDownloadManifest, destination: URL) -> DownloadRun {
        if let existing = runs[manifest.modelIdentifier] {
            // A live run wins over a fresh listing of the same download — its tasks are
            // already moving. Only a listing that describes something ELSE (a new
            // revision, a changed file set) is allowed to replace it.
            if existing.manifest.describesSameDownload(
                repositoryID: manifest.repositoryID,
                revision: manifest.revision,
                files: manifest.files,
                chunkSize: manifest.chunkSize
            ) {
                return existing
            }
            existing.cancelAllTasks()
            finish(existing, error: CancellationError())
            ManifestStore.discard(manifest.modelIdentifier)
        }

        var merged = manifest
        if let stored = ManifestStore.load(manifest.modelIdentifier),
           stored.describesSameDownload(
                repositoryID: manifest.repositoryID,
                revision: manifest.revision,
                files: manifest.files,
                chunkSize: manifest.chunkSize
           ) {
            merged = stored
            // The caller listed the cache directory a moment ago; that reading wins over
            // whatever the stored manifest last believed about which files are published.
            merged.applyOnDiskCompletion(Set(manifest.files.filter(\.completed).map(\.path)))
        } else {
            ManifestStore.discard(manifest.modelIdentifier)
        }

        let run = DownloadRun(manifest: merged, destination: destination)
        runs[manifest.modelIdentifier] = run
        ManifestStore.save(run.manifest)
        return run
    }

    /// Moves the run forward: publish what is finished, ask for what is next.
    private func pump(_ run: DownloadRun) {
        guard !run.isFinished else { return }

        while let fileIndex = run.manifest.currentFileIndex {
            let file = run.manifest.files[fileIndex]
            let destination = run.destination.appendingPathComponent(file.path)

            // Already published — by an earlier run, or by the retry-in-place path that
            // skips files on disk. Costs nothing and keeps the manifest honest.
            if FileManager.default.fileExists(atPath: destination.path) {
                complete(file: fileIndex, in: run)
                continue
            }

            // Hugging Face answers HTTP 500 for a zero-byte file, so it is created here
            // instead of asked for. Unchanged behaviour from the previous downloader.
            if file.size == 0 {
                do {
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                } catch {
                    finish(run, error: error)
                    return
                }
                FileManager.default.createFile(atPath: destination.path, contents: Data())
                complete(file: fileIndex, in: run)
                continue
            }

            if run.manifest.isFileFullyReceived(at: fileIndex) {
                // A refused publication has already decided what happens next — a
                // scheduled retry or the end of the run — and must not fall through into
                // the enqueue below, which would start the retry immediately and skip
                // the backoff it was just given.
                guard publish(file: fileIndex, in: run) else { return }
                continue
            }

            let next = run.manifest.chunksToEnqueue(
                ofFileAt: fileIndex,
                inFlight: run.inFlight,
                window: Self.chunksInFlight
            )
            for chunkIndex in next {
                start(chunk: chunkIndex, ofFile: fileIndex, in: run)
            }
            return
        }

        // Nothing left to take: every file is published.
        ManifestStore.discard(run.manifest.modelIdentifier)
        finish(run, error: nil)
    }

    /// Marks a file done without touching disk — it is already where it belongs.
    private func complete(file index: Int, in run: DownloadRun) {
        run.manifest.markCompleted(fileAt: index)
        run.inFlight.removeAll()
        run.tasks.removeAll()
        run.liveChunkBytes.removeAll()
        run.attempts = 0
        ManifestStore.save(run.manifest)
        run.emitProgress(force: true)
    }

    private func start(chunk chunkIndex: Int, ofFile fileIndex: Int, in run: DownloadRun) {
        let file = run.manifest.files[fileIndex]
        guard let span = run.manifest.span(ofChunk: chunkIndex, inFileAt: fileIndex),
              let url = Self.fileURL(manifest: run.manifest, path: file.path) else {
            finish(run, error: ModelRepoDownloader.DownloadError.invalidResponse)
            return
        }

        var request = URLRequest(url: url)
        let rangeValue = span.end.map { HTTPRangeResume.rangeHeaderValue(start: span.start, end: $0) }
            ?? HTTPRangeResume.rangeHeaderValue(start: span.start)
        request.setValue(rangeValue, forHTTPHeaderField: "Range")
        // `If-Range` turns "give me these bytes" into "give me these bytes only if the
        // file is still the one I already hold part of". Without it a repository that
        // changed under us answers 206 with the new file's bytes at the old file's
        // offset, and the result is a file of exactly the right length made of two
        // different downloads — which nothing downstream can detect.
        if span.start > 0, let validator = file.validator {
            request.setValue(validator, forHTTPHeaderField: "If-Range")
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = ModelDownloadTaskTag(
            modelIdentifier: run.manifest.modelIdentifier,
            fileIndex: fileIndex,
            chunkIndex: chunkIndex
        ).encoded
        run.inFlight.insert(chunkIndex)
        run.tasks[chunkIndex] = task
        run.liveChunkBytes[chunkIndex] = 0

        if span.start > 0, !run.hasLoggedResume(forFile: fileIndex) {
            PersistentLog.log(.modelDownloadResumed(
                name: run.manifest.modelIdentifier,
                path: file.path,
                offsetMB: Int(span.start / 1_000_000),
                totalMB: Int(max(0, file.size) / 1_000_000),
                source: run.continuations.isEmpty ? "relaunch" : "manifest"
            ))
        }
        task.resume()
    }

    /// Verifies an assembled partial and moves it into the cache directory.
    /// - Returns: whether the file was published; false means this run is retrying or over.
    @discardableResult
    private func publish(file index: Int, in run: DownloadRun) -> Bool {
        let file = run.manifest.files[index]
        let partial = ManifestStore.partialURL(run.manifest.modelIdentifier, fileIndex: index)
        let destination = run.destination.appendingPathComponent(file.path)

        if let failure = ModelFileIntegrity.verify(
            fileAt: partial,
            expectedSize: file.size,
            expectedSHA256: file.sha256
        ) {
            PersistentLog.log(.modelDownloadIntegrityFailed(
                name: run.manifest.modelIdentifier,
                path: file.path,
                reason: failure.logReason
            ))
            ManifestStore.discardFile(run.manifest.modelIdentifier, fileIndex: index)
            run.manifest.resetFile(at: index)
            ManifestStore.save(run.manifest)
            retryOrFail(
                run,
                error: ModelRepoDownloader.DownloadError.integrityFailed(path: file.path)
            )
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Remove any stale destination, then move — atomically publishing a complete
            // file or nothing. The property everything downstream leans on: a file that
            // exists is a file that finished (see `WhisperModelRepository`).
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            finish(run, error: error)
            return false
        }

        ManifestStore.discardFile(run.manifest.modelIdentifier, fileIndex: index)
        complete(file: index, in: run)
        return true
    }

    /// One more attempt at the current file, or the end of the road for this download.
    private func retryOrFail(_ run: DownloadRun, error: Error) {
        run.attempts += 1
        guard run.attempts < Self.maxAttemptsPerFile,
              ModelRepoDownloader.isRetryable(error),
              let fileIndex = run.manifest.currentFileIndex else {
            finish(run, error: error)
            return
        }

        PersistentLog.log(.modelDownloadStalled(
            name: run.manifest.modelIdentifier,
            path: run.manifest.files[fileIndex].path,
            timeoutSeconds: Int(Self.stallTimeout),
            attempt: run.attempts
        ))

        let delay = pow(2.0, Double(run.attempts))
        let identifier = run.manifest.modelIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.queue.addOperation {
                guard let live = self.runs[identifier], !live.isFinished else { return }
                self.pump(live)
            }
        }
    }

    /// Ends a run: everyone waiting is told, and the model is no longer in flight.
    private func finish(_ run: DownloadRun, error: Error?) {
        guard !run.isFinished else { return }
        run.isFinished = true
        runs.removeValue(forKey: run.manifest.modelIdentifier)
        let continuations = run.continuations
        run.continuations.removeAll()
        run.observers.removeAll()
        for continuation in continuations {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    // MARK: - URL construction

    /// The canonical, commit-pinned resolver URL for one repository file.
    ///
    /// Never the redirected CDN URL: those carry a short-lived signature and are
    /// worthless the moment they are persisted (maintainer's note on issue #449).
    static func fileURL(manifest: ModelDownloadManifest, path: String) -> URL? {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(
            string: "https://huggingface.co/\(manifest.repositoryID)"
                + "/resolve/\(manifest.revision)/\(encoded)"
        )
    }

    // MARK: - Chunk outcome

    /// How one chunk task ended, recorded in `didFinishDownloadingTo` and acted on in
    /// `didCompleteWithError` — the only callback URLSession guarantees fires once per
    /// task, and therefore the only safe place to move the state machine.
    fileprivate enum ChunkOutcome {
        case stored(validator: String?)
        case restartFile(reason: String)
        case failed(Error)
    }

    fileprivate func record(outcome: ChunkOutcome, for task: URLSessionTask) {
        outcomes[task.taskIdentifier] = outcome
    }

    fileprivate func takeOutcome(for task: URLSessionTask) -> ChunkOutcome? {
        outcomes.removeValue(forKey: task.taskIdentifier)
    }

    fileprivate func run(for tag: ModelDownloadTaskTag) -> DownloadRun? {
        runs[tag.modelIdentifier]
    }

    fileprivate func handleChunkCompletion(
        tag: ModelDownloadTaskTag,
        run: DownloadRun,
        outcome: ChunkOutcome?,
        transportError: Error?
    ) {
        run.inFlight.remove(tag.chunkIndex)
        run.tasks.removeValue(forKey: tag.chunkIndex)
        run.liveChunkBytes.removeValue(forKey: tag.chunkIndex)
        guard !run.isFinished else { return }

        if let transportError {
            let mapped = Self.mapped(transportError, path: run.pathOfFile(tag.fileIndex))
            retryOrFail(run, error: mapped)
            return
        }

        switch outcome {
        case .stored(let validator):
            run.manifest.setValidator(validator, ofFileAt: tag.fileIndex)
            // The offset the partial is authoritative up to, read BEFORE the manifest
            // advances. `append` truncates to it first, which is what makes the whole
            // operation replayable: a process that died between writing bytes and saving
            // the manifest left bytes past this point, and they are dropped rather than
            // appended to a second time.
            let appendAt = run.manifest.files[tag.fileIndex].appendedBytes
            let absorbed = run.manifest.absorbContiguousChunks(
                ofFileAt: tag.fileIndex,
                available: ManifestStore.storedChunkIndices(
                    run.manifest.modelIdentifier,
                    fileIndex: tag.fileIndex
                )
            )
            do {
                try ManifestStore.append(
                    chunks: absorbed,
                    ofFile: tag.fileIndex,
                    model: run.manifest.modelIdentifier,
                    startingAt: appendAt
                )
            } catch {
                finish(run, error: error)
                return
            }
            run.attempts = 0
            ManifestStore.save(run.manifest)
            run.emitProgress(force: !absorbed.isEmpty)
            pump(run)

        case .restartFile:
            ManifestStore.discardFile(run.manifest.modelIdentifier, fileIndex: tag.fileIndex)
            run.manifest.resetFile(at: tag.fileIndex)
            ManifestStore.save(run.manifest)
            run.cancelAllTasks()
            run.inFlight.removeAll()
            run.liveChunkBytes.removeAll()
            run.emitProgress(force: true)
            pump(run)

        case .failed(let error):
            retryOrFail(run, error: error)

        case nil:
            // No outcome and no error means `didFinishDownloadingTo` never ran, which
            // URLSession only does for a cancelled task.
            retryOrFail(run, error: ModelRepoDownloader.DownloadError.invalidResponse)
        }
    }

    /// Turns a URLSession transport error into the vocabulary the model card speaks.
    private static func mapped(_ error: Error, path: String) -> Error {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut else {
            return error
        }
        return ModelRepoDownloader.DownloadError.stalled(
            path: path,
            timeoutSeconds: Int(stallTimeout)
        )
    }

    fileprivate func drainBackgroundEventsIfNeeded() {
        guard let handler = backgroundCompletionHandler else { return }
        backgroundCompletionHandler = nil
        DispatchQueue.main.async { handler() }
    }
}

// MARK: - URLSession delegate

/// Callback contract this relies on, unchanged from the previous downloader:
/// - `didWriteData` fires repeatedly as bytes arrive;
/// - `didFinishDownloadingTo` fires on success, and the temp file at `location` is
///   deleted the moment the callback returns, so the move MUST happen inside it;
/// - `didCompleteWithError` fires exactly once per task, after `didFinishDownloadingTo`
///   on success, which makes it the single place the state machine may advance.
extension BackgroundModelDownloadService: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let tag = ModelDownloadTaskTag.decode(downloadTask.taskDescription),
              let run = run(for: tag) else { return }
        run.liveChunkBytes[tag.chunkIndex] = totalBytesWritten
        run.emitProgress(force: false)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let tag = ModelDownloadTaskTag.decode(downloadTask.taskDescription),
              let run = run(for: tag),
              let response = downloadTask.response as? HTTPURLResponse,
              let span = run.manifest.span(ofChunk: tag.chunkIndex, inFileAt: tag.fileIndex) else {
            return
        }

        let path = run.pathOfFile(tag.fileIndex)
        let status = response.statusCode
        if status == 429 || status == 503 {
            record(
                outcome: .failed(ModelRepoDownloader.DownloadError.rateLimited(statusCode: status)),
                for: downloadTask
            )
            return
        }

        let decision = HTTPRangeResume.decide(
            statusCode: status,
            contentRangeHeader: response.value(forHTTPHeaderField: "Content-Range"),
            expectedStart: span.start,
            expectedTotal: run.manifest.files[tag.fileIndex].size > 0
                ? run.manifest.files[tag.fileIndex].size
                : nil
        )

        switch decision {
        case .appendFrom:
            do {
                try ManifestStore.store(
                    chunkAt: location,
                    model: run.manifest.modelIdentifier,
                    fileIndex: tag.fileIndex,
                    chunkIndex: tag.chunkIndex
                )
            } catch {
                record(outcome: .failed(error), for: downloadTask)
                return
            }
            let validator = response.value(forHTTPHeaderField: "ETag")
            PersistentLog.log(.modelDownloadChunk(
                name: run.manifest.modelIdentifier,
                path: path,
                index: tag.chunkIndex,
                count: run.manifest.chunkCount(ofFileAt: tag.fileIndex),
                statusCode: status,
                host: response.url?.host ?? "unknown",
                validated: validator != nil
            ))
            record(outcome: .stored(validator: validator), for: downloadTask)

        case .restartFromZero(let reason):
            PersistentLog.log(.modelDownloadRangeRejected(
                name: run.manifest.modelIdentifier,
                path: path,
                statusCode: status,
                reason: reason
            ))
            record(outcome: .restartFile(reason: reason), for: downloadTask)

        case .reject(let reason):
            PersistentLog.log(.modelDownloadRangeRejected(
                name: run.manifest.modelIdentifier,
                path: path,
                statusCode: status,
                reason: reason
            ))
            record(
                outcome: .failed(
                    ModelRepoDownloader.DownloadError.httpError(path: path, statusCode: status)
                ),
                for: downloadTask
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let outcome = takeOutcome(for: task)
        guard let tag = ModelDownloadTaskTag.decode(task.taskDescription),
              let run = run(for: tag) else {
            return
        }
        // A task this run cancelled itself (a file restart, a discarded download) is not
        // the network failing, and must not spend one of the file's three attempts.
        guard !run.isAbandoned(task) else { return }
        handleChunkCompletion(tag: tag, run: run, outcome: outcome, transportError: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        drainBackgroundEventsIfNeeded()
    }
}

// MARK: - One model's transfer

/// Live state of one model's download. Touched only on the service's delegate queue.
private final class DownloadRun {
    var manifest: ModelDownloadManifest
    let destination: URL

    /// Chunk indices of the current file that have a task running.
    var inFlight: Set<Int> = []
    /// The live task per in-flight chunk, so a restart can stop them.
    var tasks: [Int: URLSessionDownloadTask] = [:]
    /// Tasks this run cancelled itself, whose completion must not count as a failure.
    var abandonedTaskIdentifiers: Set<Int> = []
    /// Bytes received so far per in-flight chunk, for the percentage between savepoints.
    var liveChunkBytes: [Int: Int64] = [:]
    /// Consecutive failures on the current file. Reset by any chunk that lands.
    var attempts = 0
    var isFinished = false

    var continuations: [CheckedContinuation<Void, Error>] = []
    var observers: [@Sendable (ModelRepoDownloader.Progress) -> Void] = []

    private var loggedResumeForFile: Set<Int> = []
    private var lastReportedFraction: Double = -1
    private var lastReportDate = Date.distantPast

    init(manifest: ModelDownloadManifest, destination: URL) {
        self.manifest = manifest
        self.destination = destination
    }

    func pathOfFile(_ index: Int) -> String {
        manifest.files.indices.contains(index) ? manifest.files[index].path : "?"
    }

    /// One resume line per file, not one per chunk: after the first, every chunk of a
    /// large file starts at a non-zero offset and the log would say so fourteen times.
    func hasLoggedResume(forFile index: Int) -> Bool {
        defer { loggedResumeForFile.insert(index) }
        return loggedResumeForFile.contains(index)
    }

    /// Stops every transfer of this run and remembers which tasks were stopped.
    ///
    /// WHY the identifiers are remembered: a cancelled task still delivers
    /// `didCompleteWithError`, with a cancellation error, some time after this returns.
    /// Without this set the state machine would read that as the network failing and
    /// spend one of the file's three attempts on a task it killed itself.
    func cancelAllTasks() {
        for (_, task) in tasks {
            abandonedTaskIdentifiers.insert(task.taskIdentifier)
            task.cancel()
        }
        tasks.removeAll()
        inFlight.removeAll()
        liveChunkBytes.removeAll()
    }

    /// Whether this completion belongs to a task this run cancelled on purpose.
    func isAbandoned(_ task: URLSessionTask) -> Bool {
        abandonedTaskIdentifiers.remove(task.taskIdentifier) != nil
    }

    /// Emits aggregate progress, throttled the same way the previous downloader was:
    /// `didWriteData` fires hundreds of times a second and each tick would otherwise
    /// hammer a `@Published` property on the main actor.
    func emitProgress(force: Bool) {
        guard !observers.isEmpty else { return }
        let live = liveChunkBytes.values.reduce(0, +)
        let progress = ModelRepoDownloader.Progress(
            bytesDownloaded: min(manifest.receivedBytes + live, manifest.totalBytes),
            totalBytes: manifest.totalBytes,
            completedFiles: manifest.completedFileCount,
            totalFiles: manifest.files.count
        )
        let now = Date()
        let shouldEmit = force
            || progress.fraction - lastReportedFraction >= 0.005
            || now.timeIntervalSince(lastReportDate) >= 0.3
        guard shouldEmit else { return }
        lastReportedFraction = progress.fraction
        lastReportDate = now
        for observer in observers {
            observer(progress)
        }
    }
}

// MARK: - Durable staging area

/// Where an unfinished model download keeps its manifest, its partials and the chunks
/// that have landed but are not yet folded in.
///
/// WHY A STAGING DIRECTORY OF ITS OWN, and not the engine's cache directory: everything
/// in there is a promise. `AsrModels.modelsExist`, `WhisperModelRepository`,
/// `ParakeetModelRepository` and the downloader's own tripwire all read that directory
/// as "a file that exists is a file that finished", and a half-written weight blob
/// sitting next to the finished ones would break that promise for every one of them.
/// Partial bytes live here until they are whole; a file crosses over by one atomic move.
///
/// WHY `Application Support` and not the App Group container: only DictusApp downloads
/// models. The keyboard extension has no business seeing a half-downloaded file, and
/// the extension's 50 MB budget has no business paying for the directory scan.
enum ManifestStore {

    private static let folderName = "DictusModelDownloads"
    private static let manifestFileName = "manifest.json"

    /// Root of the staging area, created on demand.
    static var rootDirectory: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let root = support.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// One model's staging directory.
    ///
    /// The folder name is a sanitized identifier and is never parsed back: `loadAll`
    /// reads the identifier out of the manifest itself, so a model whose identifier
    /// needed escaping still reports its real name.
    static func directory(_ model: String) -> URL? {
        let safe = model.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "_"
        }
        guard let root = rootDirectory else { return nil }
        return root.appendingPathComponent(String(safe), isDirectory: true)
    }

    static func manifestURL(_ model: String) -> URL? {
        directory(model)?.appendingPathComponent(manifestFileName)
    }

    /// The partial being assembled for one file. Empty path when the container is
    /// unreachable, which every caller turns into a plain file-system failure.
    static func partialURL(_ model: String, fileIndex: Int) -> URL {
        directory(model)?.appendingPathComponent("\(fileIndex).part")
            ?? URL(fileURLWithPath: "/dev/null/\(fileIndex).part")
    }

    static func chunkURL(_ model: String, fileIndex: Int, chunkIndex: Int) -> URL {
        directory(model)?.appendingPathComponent("\(fileIndex)-\(chunkIndex).chunk")
            ?? URL(fileURLWithPath: "/dev/null/\(fileIndex)-\(chunkIndex).chunk")
    }

    // MARK: Manifest

    static func save(_ manifest: ModelDownloadManifest) {
        guard let directory = directory(manifest.modelIdentifier),
              let url = manifestURL(manifest.modelIdentifier) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        // Atomic so a manifest is never read half written by the next launch.
        try? data.write(to: url, options: .atomic)
    }

    static func load(_ model: String) -> ModelDownloadManifest? {
        guard let url = manifestURL(model),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModelDownloadManifest.self, from: data)
    }

    /// Every manifest on disk, keyed by the identifier each one names.
    static func loadAll() -> [String: ModelDownloadManifest] {
        guard let root = rootDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: nil
              ) else {
            return [:]
        }
        var result: [String: ModelDownloadManifest] = [:]
        for entry in entries {
            let url = entry.appendingPathComponent(manifestFileName)
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(ModelDownloadManifest.self, from: data)
            else { continue }
            result[manifest.modelIdentifier] = manifest
        }
        return result
    }

    static func discard(_ model: String) {
        guard let directory = directory(model) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Drops one file's partial and every chunk of it, leaving the rest of the download
    /// intact. Used when a range was refused or an assembled file failed its checksum.
    static func discardFile(_ model: String, fileIndex: Int) {
        try? FileManager.default.removeItem(at: partialURL(model, fileIndex: fileIndex))
        for index in storedChunkIndices(model, fileIndex: fileIndex) {
            try? FileManager.default.removeItem(
                at: chunkURL(model, fileIndex: fileIndex, chunkIndex: index)
            )
        }
    }

    // MARK: Chunks

    /// Chunk indices whose bytes are durably on disk for this file.
    static func storedChunkIndices(_ model: String, fileIndex: Int) -> Set<Int> {
        guard let directory = directory(model),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        let prefix = "\(fileIndex)-"
        let suffix = ".chunk"
        var result: Set<Int> = []
        for entry in entries where entry.hasPrefix(prefix) && entry.hasSuffix(suffix) {
            let middle = entry.dropFirst(prefix.count).dropLast(suffix.count)
            if let index = Int(middle) { result.insert(index) }
        }
        return result
    }

    /// Moves a completed chunk out of the system's temporary location, which is emptied
    /// the instant `didFinishDownloadingTo` returns. This move is the whole reason the
    /// download is chunked: it is where in-flight bytes become durable ones.
    static func store(chunkAt location: URL, model: String, fileIndex: Int, chunkIndex: Int) throws {
        guard let directory = directory(model) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = chunkURL(model, fileIndex: fileIndex, chunkIndex: chunkIndex)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: location, to: destination)
    }

    /// Appends chunks, in the order given, to the file's partial and deletes them.
    ///
    /// Streamed in 1 MB reads: a chunk is 32 MB and this runs in an app iOS already
    /// watches for memory (issues #104, #362).
    static func append(chunks: [Int], ofFile fileIndex: Int, model: String, startingAt: Int64) throws {
        guard !chunks.isEmpty else { return }
        let partial = partialURL(model, fileIndex: fileIndex)
        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let writer = try FileHandle(forWritingTo: partial)
        defer { try? writer.close() }
        // Everything past the manifest's offset is unaccounted for — bytes a process
        // that died mid-append wrote and never recorded. Dropping them is what makes an
        // append idempotent, and an append that is not idempotent silently doubles a
        // chunk inside a 445 MB file.
        try writer.truncate(atOffset: UInt64(max(0, startingAt)))
        try writer.seekToEnd()

        for chunkIndex in chunks {
            let source = chunkURL(model, fileIndex: fileIndex, chunkIndex: chunkIndex)
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            while let data = try reader.read(upToCount: 1 << 20), !data.isEmpty {
                try writer.write(contentsOf: data)
            }
            try? reader.close()
            try? FileManager.default.removeItem(at: source)
        }
        try writer.synchronize()
    }
}
