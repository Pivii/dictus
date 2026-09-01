// DictusCore/Tests/DictusCoreTests/ModelDownloadManifestTests.swift
// Chunk arithmetic and state transitions of a resumable model download (issue #449).
import XCTest
@testable import DictusCore

final class ModelDownloadManifestTests: XCTestCase {

    /// 32 MB, the value `BackgroundModelDownloadService` ships.
    private let chunkSize: Int64 = 32 * 1024 * 1024

    private func manifest(files: [ModelDownloadManifest.FileEntry]) -> ModelDownloadManifest {
        ModelDownloadManifest(
            modelIdentifier: "parakeet-tdt-0.6b-v3",
            repositoryID: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            revision: "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe",
            chunkSize: chunkSize,
            files: files
        )
    }

    private func entry(
        _ path: String,
        size: Int64,
        appended: Int64 = 0,
        completed: Bool = false,
        sha256: String? = nil
    ) -> ModelDownloadManifest.FileEntry {
        ModelDownloadManifest.FileEntry(
            path: path,
            size: size,
            sha256: sha256,
            appendedBytes: appended,
            completed: completed
        )
    }

    // MARK: - Chunk arithmetic

    func testCountsChunksForTheRealEncoderWeightFile() {
        // 445187200 bytes, measured against the repository on 2026-09-01.
        let subject = manifest(files: [entry("Encoder.mlmodelc/weights/weight.bin", size: 445_187_200)])
        XCTAssertEqual(subject.chunkCount(ofFileAt: 0), 14)
    }

    func testCountsOneChunkForAFileSmallerThanAChunk() {
        XCTAssertEqual(manifest(files: [entry("config.json", size: 812)]).chunkCount(ofFileAt: 0), 1)
    }

    func testCountsExactlyOneChunkForAFileOfExactlyOneChunk() {
        XCTAssertEqual(manifest(files: [entry("a", size: chunkSize)]).chunkCount(ofFileAt: 0), 1)
    }

    func testCountsNoChunksForAnEmptyFile() {
        // Hugging Face answers HTTP 500 for these; the downloader creates them locally.
        XCTAssertEqual(manifest(files: [entry("empty", size: 0)]).chunkCount(ofFileAt: 0), 0)
        XCTAssertNil(manifest(files: [entry("empty", size: 0)]).span(ofChunk: 0, inFileAt: 0))
    }

    func testSpansAreContiguousAndTheLastOneIsShort() {
        let size = chunkSize * 2 + 1000
        let subject = manifest(files: [entry("a", size: size)])
        XCTAssertEqual(subject.chunkCount(ofFileAt: 0), 3)
        XCTAssertEqual(subject.span(ofChunk: 0, inFileAt: 0), ModelDownloadChunkSpan(start: 0, end: chunkSize - 1))
        XCTAssertEqual(
            subject.span(ofChunk: 1, inFileAt: 0),
            ModelDownloadChunkSpan(start: chunkSize, end: chunkSize * 2 - 1)
        )
        XCTAssertEqual(
            subject.span(ofChunk: 2, inFileAt: 0),
            ModelDownloadChunkSpan(start: chunkSize * 2, end: size - 1)
        )
        XCTAssertNil(subject.span(ofChunk: 3, inFileAt: 0))
    }

    func testAnUnknownSizeIsOneOpenEndedChunk() {
        let subject = manifest(files: [entry("a", size: -1)])
        XCTAssertEqual(subject.chunkCount(ofFileAt: 0), 1)
        XCTAssertEqual(subject.span(ofChunk: 0, inFileAt: 0), ModelDownloadChunkSpan(start: 0, end: nil))
    }

    // MARK: - Where to resume

    func testResumesAtTheChunkAfterWhatIsOnDisk() {
        let subject = manifest(files: [entry("a", size: chunkSize * 4, appended: chunkSize * 2)])
        XCTAssertEqual(subject.nextChunkIndex(ofFileAt: 0), 2)
        XCTAssertFalse(subject.isFileFullyReceived(at: 0))
    }

    func testAShortLastChunkStillCountsAsReceived() {
        // The regression this branch exists for: 40 MB with 32 MB chunks holds 40 MB when
        // done, and a plain division says chunk 1 — the one just finished — is next.
        let size = chunkSize + 8 * 1024 * 1024
        let subject = manifest(files: [entry("a", size: size, appended: size)])
        XCTAssertEqual(subject.chunkCount(ofFileAt: 0), 2)
        XCTAssertEqual(subject.nextChunkIndex(ofFileAt: 0), 2)
        XCTAssertTrue(subject.isFileFullyReceived(at: 0))
    }

    // MARK: - The in-flight window

    func testFillsTheWindowFromTheResumePoint() {
        let subject = manifest(files: [entry("a", size: chunkSize * 10, appended: chunkSize * 3)])
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [], alreadyStored: [], window: 2),
            [3, 4]
        )
    }

    func testSkipsChunksAlreadyInFlightAndStopsAtTheWindow() {
        let subject = manifest(files: [entry("a", size: chunkSize * 10, appended: chunkSize * 3)])
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [3], alreadyStored: [], window: 2),
            [4]
        )
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [3, 4], alreadyStored: [], window: 2),
            []
        )
    }

    func testNeverAsksAgainForAChunkThatLandedOutOfOrder() {
        // Simulator, 2026-09-01: chunk 13 of the encoder weights landed before chunk 12,
        // and the next scan asked for it a second time — 32 MB for nothing. It is on
        // disk, so it is stepped over, and the window stays full of real work.
        let subject = manifest(files: [entry("a", size: chunkSize * 20, appended: chunkSize * 12)])
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [12], alreadyStored: [13], window: 2),
            [14]
        )
    }

    func testNeverEnqueuesPastTheEndOfTheFile() {
        let subject = manifest(files: [entry("a", size: chunkSize + 10, appended: chunkSize)])
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [], alreadyStored: [], window: 4),
            [1]
        )
        // And a stored last chunk leaves nothing at all to ask for.
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [], alreadyStored: [1], window: 4),
            []
        )
    }

    func testEnqueuesNothingForACompletedFile() {
        let subject = manifest(files: [entry("a", size: chunkSize, completed: true)])
        XCTAssertEqual(
            subject.chunksToEnqueue(ofFileAt: 0, inFlight: [], alreadyStored: [], window: 2),
            []
        )
    }

    // MARK: - Absorbing chunks

    func testAbsorbsOnlyContiguousChunks() {
        // Two transfers in flight can land out of order; the later one waits rather than
        // being written into the middle of the file.
        var subject = manifest(files: [entry("a", size: chunkSize * 4)])
        XCTAssertEqual(subject.absorbContiguousChunks(ofFileAt: 0, available: [1]), [])
        XCTAssertEqual(subject.files[0].appendedBytes, 0)

        XCTAssertEqual(subject.absorbContiguousChunks(ofFileAt: 0, available: [0, 1]), [0, 1])
        XCTAssertEqual(subject.files[0].appendedBytes, chunkSize * 2)
    }

    func testAbsorbingTheLastShortChunkFinishesTheFile() {
        let size = chunkSize + 100
        var subject = manifest(files: [entry("a", size: size, appended: chunkSize)])
        XCTAssertEqual(subject.absorbContiguousChunks(ofFileAt: 0, available: [1]), [1])
        XCTAssertEqual(subject.files[0].appendedBytes, size)
        XCTAssertTrue(subject.isFileFullyReceived(at: 0))
    }

    func testAbsorbingAnUnknownSizeChunkFinishesTheFileWithoutInflatingProgress() {
        var subject = manifest(files: [entry("a", size: -1)])
        XCTAssertEqual(subject.absorbContiguousChunks(ofFileAt: 0, available: [0]), [0])
        XCTAssertTrue(subject.isFileFullyReceived(at: 0))
        // A chunk slot was recorded so the arithmetic moves on, but nothing is credited
        // to the percentage — the file's own size is unknown and counts as zero.
        XCTAssertEqual(subject.receivedBytes, 0)
    }

    // MARK: - Aggregate progress

    func testProgressCountsCompletedFilesAtFullSizeAndPartialsAtWhatIsAppended() {
        let subject = manifest(files: [
            entry("done", size: 1_000, completed: true),
            entry("partial", size: chunkSize * 3, appended: chunkSize),
            entry("pending", size: 500)
        ])
        XCTAssertEqual(subject.totalBytes, 1_000 + chunkSize * 3 + 500)
        XCTAssertEqual(subject.receivedBytes, 1_000 + chunkSize)
        XCTAssertEqual(subject.completedFileCount, 1)
        XCTAssertEqual(subject.currentFileIndex, 1)
        XCTAssertFalse(subject.isTransferComplete)
    }

    func testReceivedBytesNeverExceedTotalBytes() {
        let subject = manifest(files: [entry("a", size: 10, appended: chunkSize)])
        XCTAssertEqual(subject.receivedBytes, 10)
    }

    func testAFinishedTransferReportsItself() {
        let subject = manifest(files: [
            entry("a", size: 10, completed: true),
            entry("b", size: 20, completed: true)
        ])
        XCTAssertTrue(subject.isTransferComplete)
        XCTAssertNil(subject.currentFileIndex)
    }

    // MARK: - Mutation

    func testMarkingCompletedSetsAppendedBytesToTheWholeSize() {
        var subject = manifest(files: [entry("a", size: 4_096)])
        subject.markCompleted(fileAt: 0)
        XCTAssertTrue(subject.files[0].completed)
        XCTAssertEqual(subject.files[0].appendedBytes, 4_096)
    }

    func testResettingAFileForgetsItsBytesAndItsValidator() {
        var subject = manifest(files: [entry("a", size: chunkSize * 2, appended: chunkSize)])
        subject.setValidator("\"abc\"", ofFileAt: 0)
        subject.resetFile(at: 0)
        XCTAssertEqual(subject.files[0].appendedBytes, 0)
        XCTAssertNil(subject.files[0].validator)
        XCTAssertFalse(subject.files[0].completed)
    }

    func testDiskCompletionWinsInBothDirections() {
        var subject = manifest(files: [
            entry("published", size: 10),
            entry("vanished", size: chunkSize, appended: chunkSize, completed: true)
        ])
        subject.applyOnDiskCompletion(["published"])
        XCTAssertTrue(subject.files[0].completed)
        // The manifest called it complete and the cache directory does not have it, so
        // its bytes are forgotten rather than skipped into a failing tripwire.
        XCTAssertFalse(subject.files[1].completed)
        XCTAssertEqual(subject.files[1].appendedBytes, 0)
    }

    // MARK: - Reconciliation

    func testARelistedRepositoryThatMatchesIsTheSameDownload() {
        let files = [entry("a", size: 10), entry("b", size: 20)]
        let subject = manifest(files: files)
        XCTAssertTrue(subject.describesSameDownload(
            repositoryID: subject.repositoryID,
            revision: subject.revision,
            files: files,
            chunkSize: chunkSize
        ))
    }

    func testADifferentRevisionOrFileSetIsADifferentDownload() {
        let files = [entry("a", size: 10)]
        let subject = manifest(files: files)
        XCTAssertFalse(subject.describesSameDownload(
            repositoryID: subject.repositoryID,
            revision: "main",
            files: files,
            chunkSize: chunkSize
        ))
        XCTAssertFalse(subject.describesSameDownload(
            repositoryID: subject.repositoryID,
            revision: subject.revision,
            files: [entry("a", size: 11)],
            chunkSize: chunkSize
        ))
        XCTAssertFalse(subject.describesSameDownload(
            repositoryID: "someone/else",
            revision: subject.revision,
            files: files,
            chunkSize: chunkSize
        ))
        XCTAssertFalse(subject.describesSameDownload(
            repositoryID: subject.repositoryID,
            revision: subject.revision,
            files: files,
            chunkSize: chunkSize * 2
        ))
    }

    // MARK: - Persistence

    func testSurvivesACodableRoundTrip() throws {
        var subject = manifest(files: [
            entry("Encoder.mlmodelc/weights/weight.bin", size: 445_187_200, appended: chunkSize,
                  sha256: "e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421"),
            entry("parakeet_vocab.json", size: 812, completed: true)
        ])
        subject.setValidator("\"34dd332d\"", ofFileAt: 0)
        let restored = try JSONDecoder().decode(
            ModelDownloadManifest.self,
            from: JSONEncoder().encode(subject)
        )
        XCTAssertEqual(restored, subject)
        XCTAssertEqual(restored.files[0].validator, "\"34dd332d\"")
        XCTAssertEqual(restored.nextChunkIndex(ofFileAt: 0), 1)
    }

    // MARK: - Task identity

    func testTaskTagRoundTrips() throws {
        let tag = ModelDownloadTaskTag(
            modelIdentifier: "openai_whisper-large-v3-v20240930_turbo_632MB",
            fileIndex: 7,
            chunkIndex: 13
        )
        XCTAssertEqual(ModelDownloadTaskTag.decode(tag.encoded), tag)
    }

    func testTaskTagRefusesAnythingThisAppDidNotWrite() {
        for description in [nil, "", "some-other-task", "dictus-model-download|a|b|c",
                            "dictus-model-download|a|1", "dictus-model-download||1|2"] {
            XCTAssertNil(ModelDownloadTaskTag.decode(description), "should refuse \(description ?? "nil")")
        }
    }
}
