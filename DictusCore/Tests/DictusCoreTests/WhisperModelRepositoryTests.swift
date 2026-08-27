// DictusCore/Tests/DictusCoreTests/WhisperModelRepositoryTests.swift
// Tests for the local WhisperKit model repository resolution (issue #249).
import XCTest
@testable import DictusCore

final class WhisperModelRepositoryTests: XCTestCase {

    /// Stand-in for the app's Documents directory so tests never touch the real one.
    private var documents: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        documents = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WhisperModelRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let documents {
            try? FileManager.default.removeItem(at: documents)
        }
        documents = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Creates `<documents>/huggingface/models/argmaxinc/whisperkit-coreml/<identifier>`
    /// and returns it, optionally populated with the compiled Core ML bundles a real
    /// download leaves behind.
    @discardableResult
    private func makeModelFolder(_ identifier: String, withCompiledModels: Bool) throws -> URL {
        let folder = documents
            .appendingPathComponent(WhisperModelRepository.relativeRepositoryPath, isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // config.json ships with every variant and is present even in a partial download.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        if withCompiledModels {
            for bundle in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
                try FileManager.default.createDirectory(
                    at: folder.appendingPathComponent(bundle, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        }
        return folder
    }

    /// Creates the variant folder with the exact file set a FINISHED download leaves
    /// behind: `config.json` plus the three compiled bundles, each holding the entries
    /// `hasCompleteDownload` requires. Used by the issue #433 tests, which care about
    /// what is inside a bundle and not merely that it exists.
    @discardableResult
    private func makeCompleteDownload(_ identifier: String) throws -> URL {
        let folder = try makeModelFolder(identifier, withCompiledModels: true)
        for bundle in WhisperModelRepository.requiredCompiledBundleNames {
            let bundleURL = folder.appendingPathComponent("\(bundle).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(
                at: bundleURL.appendingPathComponent("weights", isDirectory: true),
                withIntermediateDirectories: true
            )
            for entry in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                try Data("payload".utf8).write(to: bundleURL.appendingPathComponent(entry))
            }
        }
        return folder
    }

    // MARK: - Path construction

    func testRepositoryURLMatchesTheHubApiLayout() {
        let repository = WhisperModelRepository.repositoryURL(documentsDirectory: documents)
        XCTAssertEqual(
            repository?.path,
            documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml").path
        )
    }

    func testModelFolderURLIsReturnedEvenWhenNothingIsOnDisk() {
        // Delete and cleanup need the path before checking whether it exists.
        let folder = WhisperModelRepository.modelFolderURL(
            for: "openai_whisper-small",
            documentsDirectory: documents
        )
        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-small")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder?.path ?? ""))
    }

    func testModelFolderURLUsesTheIdentifierVerbatim() {
        // Quantized variants keep the suffix in both the catalog and the repo folder.
        let folder = WhisperModelRepository.modelFolderURL(
            for: "openai_whisper-small_216MB",
            documentsDirectory: documents
        )
        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-small_216MB")
    }

    // MARK: - Installed detection

    func testInstalledModelFolderIsResolvedForACompleteDownload() throws {
        let expected = try makeModelFolder("openai_whisper-medium", withCompiledModels: true)

        let resolved = WhisperModelRepository.installedModelFolderURL(
            for: "openai_whisper-medium",
            documentsDirectory: documents
        )

        XCTAssertEqual(resolved?.path, expected.path)
        XCTAssertTrue(
            WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents)
        )
    }

    func testInstalledModelFolderIsNilWhenTheModelWasNeverDownloaded() {
        XCTAssertNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small",
                documentsDirectory: documents
            )
        )
        XCTAssertFalse(
            WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents)
        )
    }

    func testInstalledModelFolderIsNilForAPartialDownload() throws {
        // A folder with metadata but no compiled bundle must never be handed to
        // WhisperKit — the user has to re-download it from the model manager.
        try makeModelFolder("openai_whisper-small", withCompiledModels: false)

        XCTAssertNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small",
                documentsDirectory: documents
            )
        )
    }

    func testDeletingTheModelFolderMakesItReportAsMissing() throws {
        let folder = try makeModelFolder("openai_whisper-small_216MB", withCompiledModels: true)
        XCTAssertNotNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small_216MB",
                documentsDirectory: documents
            )
        )

        // Mirrors what ModelManager.deleteModel removes.
        try FileManager.default.removeItem(at: folder)

        XCTAssertNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small_216MB",
                documentsDirectory: documents
            )
        )
    }

    func testDeletingOneModelLeavesTheOthersInstalled() throws {
        try makeModelFolder("openai_whisper-small", withCompiledModels: true)
        let medium = try makeModelFolder("openai_whisper-medium", withCompiledModels: true)

        try FileManager.default.removeItem(at: medium)

        XCTAssertTrue(
            WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents)
        )
        XCTAssertFalse(
            WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents)
        )
    }

    // MARK: - Tokenizer cache diagnostics

    func testCachedTokenizerRepositoryNamesIsEmptyWhenNothingWasEverLoaded() {
        XCTAssertTrue(
            WhisperModelRepository.cachedTokenizerRepositoryNames(documentsDirectory: documents).isEmpty
        )
    }

    func testCachedTokenizerRepositoryNamesListsTheOpenAIRepos() throws {
        // WhisperKit caches tokenizers under huggingface/models/openai/<repo>,
        // separately from the variant folder.
        let openAI = documents.appendingPathComponent("huggingface/models/openai", isDirectory: true)
        for repo in ["whisper-small", "whisper-medium"] {
            try FileManager.default.createDirectory(
                at: openAI.appendingPathComponent(repo, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        XCTAssertEqual(
            WhisperModelRepository.cachedTokenizerRepositoryNames(documentsDirectory: documents),
            ["whisper-medium", "whisper-small"]
        )
    }

    // MARK: - Download completeness (issue #433)

    func testCompleteDownloadIsRecognized() throws {
        try makeCompleteDownload("openai_whisper-small")

        XCTAssertTrue(
            WhisperModelRepository.hasCompleteDownload("openai_whisper-small", documentsDirectory: documents)
        )
    }

    func testDownloadInterruptedInsideABundleIsNotComplete() throws {
        // The shape an interrupted download actually leaves: every bundle directory
        // exists, because the downloader creates each file's parent before fetching
        // the file, but the weights never landed. `isModelInstalled` says yes to this
        // and is allowed to — it answers a different question (see the doc comment).
        try makeModelFolder("openai_whisper-medium", withCompiledModels: true)

        XCTAssertTrue(
            WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents)
        )
        XCTAssertFalse(
            WhisperModelRepository.hasCompleteDownload("openai_whisper-medium", documentsDirectory: documents)
        )
    }

    func testAMissingWeightFileAloneMakesTheDownloadIncomplete() throws {
        let folder = try makeCompleteDownload("openai_whisper-medium")
        try FileManager.default.removeItem(
            at: folder.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin")
        )

        XCTAssertFalse(
            WhisperModelRepository.hasCompleteDownload("openai_whisper-medium", documentsDirectory: documents)
        )
    }

    func testAMissingConfigFileMakesTheDownloadIncomplete() throws {
        let folder = try makeCompleteDownload("openai_whisper-small_216MB")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("config.json"))

        XCTAssertFalse(
            WhisperModelRepository.hasCompleteDownload("openai_whisper-small_216MB", documentsDirectory: documents)
        )
    }

    func testAModelThatWasNeverDownloadedIsNotComplete() {
        XCTAssertFalse(
            WhisperModelRepository.hasCompleteDownload("openai_whisper-small", documentsDirectory: documents)
        )
    }

    func testRequiredDownloadPathsNameTheLeafFilesInsideEachBundle() {
        // The downloader's final tripwire and this check read the same list, which is
        // the only reason the reconciliation may trust files the download placed. The
        // list has to name leaves: the tripwire checks with `FileManager.fileExists`,
        // which answers true for a directory, so a bundle-level list would let an
        // interrupted download through the very check meant to catch it.
        XCTAssertEqual(
            WhisperModelRepository.requiredDownloadPaths(forVariant: "openai_whisper-small"),
            [
                "openai_whisper-small/MelSpectrogram.mlmodelc/coremldata.bin",
                "openai_whisper-small/MelSpectrogram.mlmodelc/model.mil",
                "openai_whisper-small/MelSpectrogram.mlmodelc/weights/weight.bin",
                "openai_whisper-small/AudioEncoder.mlmodelc/coremldata.bin",
                "openai_whisper-small/AudioEncoder.mlmodelc/model.mil",
                "openai_whisper-small/AudioEncoder.mlmodelc/weights/weight.bin",
                "openai_whisper-small/TextDecoder.mlmodelc/coremldata.bin",
                "openai_whisper-small/TextDecoder.mlmodelc/model.mil",
                "openai_whisper-small/TextDecoder.mlmodelc/weights/weight.bin",
                "openai_whisper-small/config.json"
            ]
        )
    }

    func testEveryRequiredPathIsPresentAfterACompleteDownload() throws {
        // Ties the two together from the other side: the exact shape the test helper
        // builds — which mirrors what a finished download leaves — satisfies every
        // path the tripwire would check, so making the tripwire stricter cannot fail
        // a healthy download.
        let folder = try makeCompleteDownload("openai_whisper-medium")
        let repository = folder.deletingLastPathComponent()

        for path in WhisperModelRepository.requiredDownloadPaths(forVariant: "openai_whisper-medium") {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repository.appendingPathComponent(path).path),
                "missing \(path)"
            )
        }
    }

    // MARK: - Reconciliation (issue #433)

    func testCompleteFilesAbsentFromTheListAreReconciledIn() throws {
        // The reported bug: the compile was interrupted, so the identifier was never
        // appended, while 500 MB of weights sit on disk unseen and undeletable.
        try makeCompleteDownload("openai_whisper-small")

        let reconciled = WhisperModelRepository.unlistedCompleteDownloads(
            among: ["openai_whisper-small", "openai_whisper-medium"],
            listedAsDownloaded: ["openai_whisper-medium"],
            documentsDirectory: documents
        )

        XCTAssertEqual(reconciled, ["openai_whisper-small"])
    }

    func testPartialFilesAbsentFromTheListAreLeftOut() throws {
        // An interrupted DOWNLOAD, as opposed to an interrupted compile. Listing this
        // would trade one lie for another: the user would be shown a model that cannot
        // load, and selecting it would fail rather than resume.
        try makeModelFolder("openai_whisper-small", withCompiledModels: true)

        let reconciled = WhisperModelRepository.unlistedCompleteDownloads(
            among: ["openai_whisper-small"],
            listedAsDownloaded: [],
            documentsDirectory: documents
        )

        XCTAssertTrue(reconciled.isEmpty)
    }

    func testCompleteFilesAlreadyInTheListChangeNothing() throws {
        try makeCompleteDownload("openai_whisper-small")

        let reconciled = WhisperModelRepository.unlistedCompleteDownloads(
            among: ["openai_whisper-small"],
            listedAsDownloaded: ["openai_whisper-small"],
            documentsDirectory: documents
        )

        XCTAssertTrue(reconciled.isEmpty)
    }

    func testReconciliationReportsOnlyIdentifiersAndNeverElectsAnActiveModel() throws {
        // The regression this guards against is architectural rather than numeric: if
        // reconciliation could name an active model, a device could come up believing
        // transcription is available with no engine loaded. The function returns
        // `[String]` in catalogue order and has no other output, so there is nothing
        // for a caller to mistake for a selection.
        try makeCompleteDownload("openai_whisper-medium")
        try makeCompleteDownload("openai_whisper-small")

        let reconciled = WhisperModelRepository.unlistedCompleteDownloads(
            among: ["openai_whisper-small", "openai_whisper-medium"],
            listedAsDownloaded: [],
            documentsDirectory: documents
        )

        XCTAssertEqual(reconciled, ["openai_whisper-small", "openai_whisper-medium"])
    }

    func testReconciliationIgnoresAVariantWithNoFilesAtAll() throws {
        try makeCompleteDownload("openai_whisper-small")

        let reconciled = WhisperModelRepository.unlistedCompleteDownloads(
            among: ["openai_whisper-tiny", "openai_whisper-small"],
            listedAsDownloaded: [],
            documentsDirectory: documents
        )

        XCTAssertEqual(reconciled, ["openai_whisper-small"])
    }
}
