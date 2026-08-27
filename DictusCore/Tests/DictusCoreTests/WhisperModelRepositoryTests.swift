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

    /// Writes one compiled Core ML bundle into `folder`.
    ///
    /// `complete: false` leaves out `weights/weight.bin` and keeps everything else,
    /// which is the exact shape an interrupted download leaves behind: the directory
    /// and its small top-level files landed, the weights did not.
    private func makeBundle(_ name: String, in folder: URL, complete: Bool) throws {
        let bundleURL = folder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent("weights", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("payload".utf8).write(to: bundleURL.appendingPathComponent("coremldata.bin"))
        try Data("payload".utf8).write(to: bundleURL.appendingPathComponent("model.mil"))
        if complete {
            try Data("payload".utf8).write(to: bundleURL.appendingPathComponent("weights/weight.bin"))
        }
    }

    /// Creates the variant folder with the exact file set a FINISHED download leaves
    /// behind: `config.json` plus the three compiled bundles every variant ships, each
    /// holding the entries `hasCompleteDownload` requires. `extraBundles` adds the ones
    /// only some variants have — the turbos' `TextDecoderContextPrefill`.
    @discardableResult
    private func makeCompleteDownload(_ identifier: String, extraBundles: [String] = []) throws -> URL {
        let folder = try makeModelFolder(identifier, withCompiledModels: true)
        for bundle in WhisperModelRepository.requiredCompiledBundleNames + extraBundles {
            try makeBundle(bundle, in: folder, complete: true)
        }
        return folder
    }

    /// Root of the fake repository, which is what `requiredDownloadPaths` takes.
    private var repositoryDirectory: URL {
        documents.appendingPathComponent(WhisperModelRepository.relativeRepositoryPath, isDirectory: true)
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

    func testRequiredDownloadPathsNameTheLeafFilesInsideEachBundle() throws {
        // The downloader's final tripwire and this check read the same list, which is
        // the only reason the reconciliation may trust files the download placed. The
        // list has to name leaves: the tripwire checks with `FileManager.fileExists`,
        // which answers true for a directory, so a bundle-level list would let an
        // interrupted download through the very check meant to catch it.
        try makeCompleteDownload("openai_whisper-small")

        XCTAssertEqual(
            WhisperModelRepository.requiredDownloadPaths(
                forVariant: "openai_whisper-small",
                in: repositoryDirectory
            ),
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

    func testRequiredDownloadPathsCoverABundleTheVariantAddsBeyondTheThree() throws {
        // The turbos ship a fourth bundle. The required set is read off the disk so it
        // grows with the variant instead of going stale the next time the repository
        // adds one.
        let turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
        try makeCompleteDownload(turbo, extraBundles: ["TextDecoderContextPrefill"])

        let paths = WhisperModelRepository.requiredDownloadPaths(
            forVariant: turbo,
            in: repositoryDirectory
        )

        XCTAssertEqual(paths.count, 13, "four bundles x three entries, plus config.json")
        XCTAssertTrue(paths.contains("\(turbo)/TextDecoderContextPrefill.mlmodelc/weights/weight.bin"))
    }

    func testAVariantFolderWithNoExtraBundlesRequiresOnlyTheThree() throws {
        try makeCompleteDownload("openai_whisper-medium")

        let paths = WhisperModelRepository.requiredDownloadPaths(
            forVariant: "openai_whisper-medium",
            in: repositoryDirectory
        )

        XCTAssertEqual(paths.count, 10)
    }

    func testATurboWhoseLastBundleLostItsWeightsIsNotComplete() throws {
        // THE CASE THIS EXISTS FOR. `listRequiredFiles` walks the repository breadth
        // first, so every bundle's small top-level files are fetched before any
        // bundle's `weights/`, and the prefill bundle is enqueued last — its
        // `weights/weight.bin` (12 MB on this variant) is the final file of the whole
        // download. Interrupt it there and the three universal bundles are complete
        // while the fourth is hollow. WhisperKit gates on the directory existing and
        // then throws loading it, so listing this as downloaded would give the user a
        // card that fails every selection.
        let turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
        let folder = try makeCompleteDownload(turbo)
        try makeBundle("TextDecoderContextPrefill", in: folder, complete: false)

        XCTAssertFalse(WhisperModelRepository.hasCompleteDownload(turbo, documentsDirectory: documents))
    }

    func testATurboWithEveryBundleCompleteIsComplete() throws {
        // The other half of the pair: widening the required set must not refuse a
        // download that actually finished.
        let turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
        try makeCompleteDownload(turbo, extraBundles: ["TextDecoderContextPrefill"])

        XCTAssertTrue(WhisperModelRepository.hasCompleteDownload(turbo, documentsDirectory: documents))
    }

    func testEveryRequiredPathIsPresentAfterACompleteDownload() throws {
        // Ties the two together from the other side: the exact shape the test helper
        // builds — which mirrors what a finished download leaves — satisfies every
        // path the tripwire would check, so making the tripwire stricter cannot fail
        // a healthy download. Run on the turbo shape, which is the one that gained
        // paths.
        let turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
        try makeCompleteDownload(turbo, extraBundles: ["TextDecoderContextPrefill"])

        let paths = WhisperModelRepository.requiredDownloadPaths(
            forVariant: turbo,
            in: repositoryDirectory
        )
        for path in paths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryDirectory.appendingPathComponent(path).path),
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
