// DictusCore/Sources/DictusCore/ModelDownloadManifest.swift
// The durable record of how far a model download got, and the arithmetic over it.
import Foundation

/// One aligned span of a repository file, as requested with an HTTP `Range` header.
public struct ModelDownloadChunkSpan: Equatable, Sendable {
    /// First byte, inclusive.
    public let start: Int64
    /// Last byte, inclusive, or `nil` for an open-ended request when the repository
    /// listing did not know the file's size.
    public let end: Int64?

    public init(start: Int64, end: Int64?) {
        self.start = start
        self.end = end
    }
}

/// What a model download has already received, in a form that survives the process.
///
/// WHY this exists (issue #449): before it, "how far did we get" was answered by
/// `FileManager.fileExists` over the destination directory, and nothing at all was
/// known about the file currently in flight. That was enough while a whole file was
/// the unit of progress (issue #210), and it stopped being enough the moment the unit
/// had to be smaller than `Encoder.mlmodelc/weights/weight.bin`, which is 445 MB of a
/// 483 MB payload. A user who left Dictus during that one file restarted it from byte
/// zero, three times over, and the download never finished.
///
/// The manifest is the durable half of the answer. It names the exact revision the
/// bytes came from, the file the transfer is on, and how many of that file's bytes are
/// already appended to the partial on disk. Everything else — which chunks are in
/// flight, which task belongs to which chunk — is derived from it.
///
/// WHY THE ARITHMETIC LIVES HERE AND NOT IN THE DOWNLOADER: the downloader is a
/// `URLSession` delegate in the DictusApp target, which has no test bundle. Chunk
/// boundaries, contiguity and completion are exactly the kind of off-by-one that a
/// device test finds three days later and a unit test finds in a second. Same reasoning
/// as `ModelCleanupPolicy` and `WhisperModelRepository.requiredDownloadPaths`.
public struct ModelDownloadManifest: Codable, Equatable, Sendable {

    /// One repository file and what has been received of it.
    public struct FileEntry: Codable, Equatable, Sendable {
        /// Repository-relative path, which is also the path under the cache directory.
        public let path: String
        /// Size the repository listing reported, or a negative number when unknown.
        public let size: Int64
        /// SHA-256 the repository listing reported for LFS blobs, or `nil`.
        ///
        /// Only LFS entries carry one (`lfs.oid`). A plain file's `oid` is a git blob
        /// SHA-1 over a different preimage and would fail every comparison, so it is
        /// deliberately not stored: the big files are all LFS, and those are the ones
        /// worth verifying.
        public let sha256: String?
        /// Bytes durably appended to this file's partial on disk. Always a multiple of
        /// the chunk size, or the whole size once the last chunk lands.
        public var appendedBytes: Int64
        /// Strong validator (`ETag`) of the response the last chunk came from, replayed
        /// as `If-Range` so a resumed request cannot silently append bytes from a
        /// different revision of the file.
        public var validator: String?
        /// The file is fully received, verified and published into the cache directory.
        public var completed: Bool

        public init(
            path: String,
            size: Int64,
            sha256: String? = nil,
            appendedBytes: Int64 = 0,
            validator: String? = nil,
            completed: Bool = false
        ) {
            self.path = path
            self.size = size
            self.sha256 = sha256
            self.appendedBytes = appendedBytes
            self.validator = validator
            self.completed = completed
        }
    }

    /// Catalogue identifier of the model being downloaded.
    public let modelIdentifier: String
    /// Hugging Face repository id, e.g. `argmaxinc/whisperkit-coreml`.
    public let repositoryID: String
    /// The revision every URL is pinned to — a commit SHA whenever one could be
    /// resolved, otherwise `main`.
    ///
    /// WHY pinned (maintainer's note on issue #449): the durable URL has to be the
    /// canonical `/resolve/<commit>/<path>` one. Resuming against `main` means the
    /// bytes already on disk and the bytes about to arrive can come from two different
    /// revisions of the same file, and the redirected CDN URLs are short-lived and
    /// cannot be persisted at all.
    public let revision: String
    /// Bytes per aligned chunk. Stored rather than assumed so a manifest written by an
    /// older build keeps being read with the boundaries it was written with.
    public let chunkSize: Int64
    /// Files in download order.
    public var files: [FileEntry]

    public init(
        modelIdentifier: String,
        repositoryID: String,
        revision: String,
        chunkSize: Int64,
        files: [FileEntry]
    ) {
        self.modelIdentifier = modelIdentifier
        self.repositoryID = repositoryID
        self.revision = revision
        self.chunkSize = chunkSize
        self.files = files
    }

    // MARK: - Aggregate progress

    /// Sum of every known file size. Unknown sizes count as zero, as they always have.
    public var totalBytes: Int64 {
        files.reduce(0) { $0 + max(0, $1.size) }
    }

    /// Bytes durably on disk across every file, completed and in progress.
    ///
    /// Clamped to the file's own size so this can never exceed `totalBytes`: a file
    /// whose size the listing did not report contributes zero to both sides rather than
    /// a chunk-slot to one of them (see `absorbContiguousChunks`).
    public var receivedBytes: Int64 {
        files.reduce(0) { partial, file in
            let size = max(0, file.size)
            return partial + (file.completed ? size : min(max(0, file.appendedBytes), size))
        }
    }

    /// Number of files fully received and published.
    public var completedFileCount: Int {
        files.filter(\.completed).count
    }

    /// Every file has been received, verified and published.
    public var isTransferComplete: Bool {
        files.allSatisfy(\.completed)
    }

    /// Index of the file the transfer is on, or `nil` when everything is done.
    ///
    /// Files are taken in order, one at a time. Sequential matches what the downloader
    /// has always done: bandwidth is dominated by one huge weight file per repository,
    /// so parallelism across files would buy nothing and would make the aggregate
    /// percentage move backwards.
    public var currentFileIndex: Int? {
        files.firstIndex { !$0.completed }
    }

    // MARK: - Chunk arithmetic

    /// How many aligned chunks a file is made of.
    ///
    /// Zero for an empty file — Hugging Face answers HTTP 500 for those, so the
    /// downloader creates them locally instead of asking. One for a file whose size the
    /// listing did not report, fetched open-ended in a single request.
    public func chunkCount(ofFileAt index: Int) -> Int {
        guard files.indices.contains(index) else { return 0 }
        let size = files[index].size
        if size < 0 { return 1 }
        if size == 0 { return 0 }
        return Int((size + chunkSize - 1) / chunkSize)
    }

    /// The byte span of one chunk, or `nil` when the index is out of range.
    public func span(ofChunk chunkIndex: Int, inFileAt index: Int) -> ModelDownloadChunkSpan? {
        guard files.indices.contains(index), chunkIndex >= 0 else { return nil }
        let size = files[index].size
        guard size != 0 else { return nil }
        guard chunkIndex < chunkCount(ofFileAt: index) else { return nil }
        if size < 0 {
            return ModelDownloadChunkSpan(start: 0, end: nil)
        }
        let start = Int64(chunkIndex) * chunkSize
        let end = min(start + chunkSize, size) - 1
        return ModelDownloadChunkSpan(start: start, end: end)
    }

    /// The first chunk of a file that is not yet appended to its partial on disk.
    ///
    /// A partial `appendedBytes` is always chunk-aligned, which is what makes this a
    /// division rather than a search: a chunk is only ever folded into the partial when
    /// every chunk before it already has been.
    ///
    /// The last chunk is the exception and gets its own branch. It is short whenever the
    /// size is not a multiple of `chunkSize`, so a completed 40 MB file with 32 MB chunks
    /// holds 40 MB and would divide down to chunk 1 — the chunk it just finished — and
    /// the download would loop on it forever.
    public func nextChunkIndex(ofFileAt index: Int) -> Int {
        guard files.indices.contains(index), chunkSize > 0 else { return 0 }
        let file = files[index]
        let appended = max(0, file.appendedBytes)
        if file.size > 0, appended >= file.size { return chunkCount(ofFileAt: index) }
        return Int(appended / chunkSize)
    }

    /// Every chunk of the file has been folded into its partial on disk.
    public func isFileFullyReceived(at index: Int) -> Bool {
        guard files.indices.contains(index) else { return false }
        return nextChunkIndex(ofFileAt: index) >= chunkCount(ofFileAt: index)
    }

    /// Chunk indices worth starting now for the file at `index`, given what is already
    /// downloading and how many transfers may be in flight at once.
    ///
    /// WHY a window rather than the whole file at once: every chunk that is in flight
    /// when the process dies is paid for again, and every chunk that is queued but not
    /// started still occupies the background session. Two in flight keeps the transfer
    /// moving across a suspension without putting a whole 445 MB file's worth of
    /// temporary storage at risk.
    public func chunksToEnqueue(
        ofFileAt index: Int,
        inFlight: Set<Int>,
        window: Int
    ) -> [Int] {
        guard window > 0, files.indices.contains(index), !files[index].completed else { return [] }
        let total = chunkCount(ofFileAt: index)
        guard total > 0 else { return [] }
        let start = nextChunkIndex(ofFileAt: index)
        guard start < total else { return [] }

        var result: [Int] = []
        var candidate = start
        while candidate < total, inFlight.count + result.count < window {
            if !inFlight.contains(candidate) {
                result.append(candidate)
            }
            candidate += 1
        }
        return result
    }

    // MARK: - Mutation

    /// Folds every chunk that is now contiguous with the partial into `appendedBytes`,
    /// and returns them in the order the caller must append their bytes.
    ///
    /// - Parameters:
    ///   - index: file being assembled.
    ///   - available: chunk indices whose bytes are durably on disk, appended or not.
    /// - Returns: the chunk indices absorbed, in ascending order. Empty when the next
    ///   chunk has not landed yet — a later chunk that arrived first simply waits, which
    ///   is what lets more than one transfer be in flight without reordering the file.
    public mutating func absorbContiguousChunks(
        ofFileAt index: Int,
        available: Set<Int>
    ) -> [Int] {
        guard files.indices.contains(index) else { return [] }
        let total = chunkCount(ofFileAt: index)
        var absorbed: [Int] = []
        var next = nextChunkIndex(ofFileAt: index)

        while next < total, available.contains(next) {
            guard let span = span(ofChunk: next, inFileAt: index) else { break }
            if let end = span.end {
                files[index].appendedBytes = end + 1
            } else {
                // Unknown size: the single open-ended chunk IS the whole file, and its
                // real length is only known once it is on disk. One chunk slot is
                // recorded so `nextChunkIndex` moves past it and the file reads as fully
                // received; `receivedBytes` clamps that slot to the file's own size, so
                // the aggregate percentage is not credited for bytes nobody counted.
                files[index].appendedBytes = chunkSize
            }
            absorbed.append(next)
            next += 1
        }
        return absorbed
    }

    /// Records the strong validator the last accepted response carried.
    public mutating func setValidator(_ validator: String?, ofFileAt index: Int) {
        guard files.indices.contains(index) else { return }
        files[index].validator = validator
    }

    /// Marks a file received, verified and published.
    public mutating func markCompleted(fileAt index: Int) {
        guard files.indices.contains(index) else { return }
        files[index].completed = true
        if files[index].size > 0 {
            files[index].appendedBytes = files[index].size
        }
    }

    /// Throws away everything received for a file, so the next attempt starts at byte 0.
    ///
    /// Used when the server ignored the range (`200`), when the resource changed size
    /// under us, and when the assembled file failed its size or SHA-256 check. All three
    /// mean the bytes on disk cannot be trusted, and the validator that vouched for them
    /// cannot either.
    public mutating func resetFile(at index: Int) {
        guard files.indices.contains(index) else { return }
        files[index].appendedBytes = 0
        files[index].validator = nil
        files[index].completed = false
    }

    /// Makes the manifest agree with the cache directory, in both directions.
    ///
    /// A file present on disk is complete whatever the manifest last recorded — the
    /// download may have been finished by an earlier attempt, or the file may have been
    /// there all along. A file the manifest calls complete and disk does not have is
    /// reset to zero, because the alternative is a download that skips it, hands an
    /// incomplete cache to the final tripwire, and fails the same way on every retry.
    public mutating func applyOnDiskCompletion(_ completedPaths: Set<String>) {
        for index in files.indices {
            if completedPaths.contains(files[index].path) {
                markCompleted(fileAt: index)
            } else if files[index].completed {
                resetFile(at: index)
            }
        }
    }

    // MARK: - Reconciliation

    /// Whether a manifest describes the same download as a freshly listed repository.
    ///
    /// A manifest that disagrees with the listing — a different revision, a different
    /// file set, different sizes — describes bytes that no longer mean anything, and
    /// resuming onto it would append the new repository's bytes to the old one's
    /// partial. The downloader starts over instead.
    public func describesSameDownload(
        repositoryID: String,
        revision: String,
        files listedFiles: [FileEntry],
        chunkSize: Int64
    ) -> Bool {
        guard self.repositoryID == repositoryID,
              self.revision == revision,
              self.chunkSize == chunkSize,
              self.files.count == listedFiles.count else {
            return false
        }
        return zip(self.files, listedFiles).allSatisfy { mine, listed in
            mine.path == listed.path && mine.size == listed.size && mine.sha256 == listed.sha256
        }
    }
}

// MARK: - Task identity

/// Which chunk of which file of which model a background `URLSession` task is fetching.
///
/// WHY it travels as a string: `URLSessionTask.taskDescription` is the only field that
/// survives the process. When a relaunched app recreates the background session, the
/// system hands back the tasks that were still running, and this is what says which
/// chunk each of them belongs to. Without it a restored session either abandons live
/// transfers or starts second copies of them, which is exactly what acceptance
/// criterion 6 of issue #449 forbids.
public struct ModelDownloadTaskTag: Equatable, Sendable {
    public let modelIdentifier: String
    public let fileIndex: Int
    public let chunkIndex: Int

    private static let prefix = "dictus-model-download"
    private static let separator: Character = "|"

    public init(modelIdentifier: String, fileIndex: Int, chunkIndex: Int) {
        self.modelIdentifier = modelIdentifier
        self.fileIndex = fileIndex
        self.chunkIndex = chunkIndex
    }

    /// The `taskDescription` value.
    public var encoded: String {
        "\(Self.prefix)\(Self.separator)\(modelIdentifier)"
            + "\(Self.separator)\(fileIndex)\(Self.separator)\(chunkIndex)"
    }

    /// Parses a `taskDescription`, or returns nil for anything this app did not write.
    public static func decode(_ description: String?) -> ModelDownloadTaskTag? {
        guard let description else { return nil }
        let parts = description.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == prefix,
              !parts[1].isEmpty,
              let fileIndex = Int(parts[2]),
              let chunkIndex = Int(parts[3]),
              fileIndex >= 0,
              chunkIndex >= 0 else {
            return nil
        }
        return ModelDownloadTaskTag(
            modelIdentifier: String(parts[1]),
            fileIndex: fileIndex,
            chunkIndex: chunkIndex
        )
    }
}
