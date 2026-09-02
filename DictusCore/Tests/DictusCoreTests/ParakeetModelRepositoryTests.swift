// DictusCore/Tests/DictusCoreTests/ParakeetModelRepositoryTests.swift
// Tests for the local Parakeet (FluidAudio) cache completeness check (issues #252, #438).
import XCTest
@testable import DictusCore

final class ParakeetModelRepositoryTests: XCTestCase {

    /// Stand-in for `AsrModels.defaultCacheDirectory(for: .v3)` so tests never touch
    /// the real Application Support directory.
    private var cacheDirectory: URL!

    /// The file names FluidAudio's `ModelNames.ASR` supplies at the call site.
    private let requiredBundles: Set<String> = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecision.mlmodelc"
    ]
    private let vocabularyFileName = "parakeet_vocab.json"

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ParakeetModelRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let cacheDirectory {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        cacheDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Writes the layout a completed download leaves behind: one directory per compiled
    /// bundle holding the entries `requiredBundleEntries` names, plus the vocabulary
    /// file at the root. Mirrors the repository tree of
    /// `FluidInference/parakeet-tdt-0.6b-v3-coreml` read on 2026-09-02.
    private func makeCompleteCache() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for bundle in requiredBundles {
            try makeCompiledBundle(bundle)
        }
        try Data("{}".utf8).write(to: cacheDirectory.appendingPathComponent(vocabularyFileName))
    }

    /// - Parameters:
    ///   - includeMarker: whether `coremldata.bin` lands.
    ///   - includeWeights: whether `weights/weight.bin` lands. False is the shape of a
    ///     transfer stopped inside the weights, which is where 92% of the payload is.
    private func makeCompiledBundle(
        _ name: String,
        includeMarker: Bool = true,
        includeWeights: Bool = true
    ) throws {
        let bundle = cacheDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        // The repository is listed breadth first, so a bundle's small top-level files
        // are published before any bundle's weights.
        try Data("[]".utf8).write(to: bundle.appendingPathComponent("metadata.json"))
        try Data("mil".utf8).write(to: bundle.appendingPathComponent("model.mil"))
        if includeMarker {
            try Data("bin".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
        }
        if includeWeights {
            let weights = bundle.appendingPathComponent("weights", isDirectory: true)
            try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
            try Data("weight".utf8).write(to: weights.appendingPathComponent("weight.bin"))
        }
    }

    /// The tripwire's own check, applied to the cache under test: every required path
    /// present as a regular file. Mirrors Phase 5 of `ModelRepoDownloader.download`.
    private func firstMissingRequiredPath() -> String? {
        ParakeetModelRepository.requiredDownloadPaths(
            requiredModelBundles: requiredBundles,
            vocabularyFileName: vocabularyFileName
        ).first { relativePath in
            var isDirectory: ObjCBool = false
            let url = cacheDirectory.appendingPathComponent(relativePath)
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return !exists || isDirectory.boolValue
        }
    }

    private func isComplete() -> Bool {
        ParakeetModelRepository.isCacheComplete(
            cacheDirectory,
            requiredModelBundles: requiredBundles,
            vocabularyFileName: vocabularyFileName
        )
    }

    private func resolvedCacheDirectory() -> URL? {
        ParakeetModelRepository.installedCacheDirectory(
            cacheDirectory,
            requiredModelBundles: requiredBundles,
            vocabularyFileName: vocabularyFileName
        )
    }

    // MARK: - Complete cache

    func testCompleteCacheResolves() throws {
        try makeCompleteCache()

        XCTAssertTrue(isComplete())
        XCTAssertEqual(resolvedCacheDirectory()?.path, cacheDirectory.path)
    }

    // MARK: - Absent cache

    func testCacheThatWasNeverDownloadedIsAbsent() {
        XCTAssertFalse(isComplete())
        XCTAssertNil(resolvedCacheDirectory())
    }

    func testEmptyCacheDirectoryIsAbsent() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        XCTAssertNil(resolvedCacheDirectory())
    }

    func testDeletingTheCacheMakesItReportAsAbsent() throws {
        try makeCompleteCache()
        XCTAssertNotNil(resolvedCacheDirectory())

        // Mirrors what ModelManager.deleteModel removes for a Parakeet model.
        try FileManager.default.removeItem(at: cacheDirectory)

        XCTAssertNil(resolvedCacheDirectory())
    }

    // MARK: - Partial cache

    func testCacheMissingOneBundleIsAbsent() throws {
        try makeCompleteCache()
        try FileManager.default.removeItem(
            at: cacheDirectory.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
        )

        XCTAssertNil(resolvedCacheDirectory())
    }

    func testBundleWithoutTheCompiledMarkerIsAbsent() throws {
        // An interrupted download can leave the directory and its metadata behind while
        // coremldata.bin never lands. FluidAudio would then wipe the cache and download
        // it again, on the dictation hot path — the very thing issue #252 removes.
        try makeCompleteCache()
        let encoder = cacheDirectory.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
        try FileManager.default.removeItem(at: encoder.appendingPathComponent("coremldata.bin"))

        XCTAssertNil(resolvedCacheDirectory())
    }

    func testBundlePathThatIsAFileIsAbsent() throws {
        try makeCompleteCache()
        let encoder = cacheDirectory.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
        try FileManager.default.removeItem(at: encoder)
        try Data("not a bundle".utf8).write(to: encoder)

        XCTAssertNil(resolvedCacheDirectory())
    }

    func testCacheMissingTheVocabularyIsAbsent() throws {
        // The vocabulary lives at the repo root, outside the bundles, and the engine
        // cannot decode a single token without it.
        try makeCompleteCache()
        try FileManager.default.removeItem(
            at: cacheDirectory.appendingPathComponent(vocabularyFileName)
        )

        XCTAssertNil(resolvedCacheDirectory())
    }

    func testVocabularyThatIsADirectoryIsAbsent() throws {
        // `fileExists` alone answers yes for a directory, which would let an empty
        // `parakeet_vocab.json/` pass and defer the failure to FluidAudio.
        try makeCompleteCache()
        let vocabulary = cacheDirectory.appendingPathComponent(vocabularyFileName)
        try FileManager.default.removeItem(at: vocabulary)
        try FileManager.default.createDirectory(at: vocabulary, withIntermediateDirectories: true)

        XCTAssertNil(resolvedCacheDirectory())
    }

    func testCompiledMarkerThatIsADirectoryIsAbsent() throws {
        try makeCompleteCache()
        let marker = cacheDirectory
            .appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            .appendingPathComponent("coremldata.bin")
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)

        XCTAssertNil(resolvedCacheDirectory())
    }

    // MARK: - Guard against a vacuous pass

    func testEmptyRequirementSetNeverPasses() throws {
        try makeCompleteCache()

        XCTAssertFalse(
            ParakeetModelRepository.isCacheComplete(
                cacheDirectory,
                requiredModelBundles: [],
                vocabularyFileName: vocabularyFileName
            )
        )
    }

    // MARK: - Bundle predicate

    func testIsCompiledModelBundleDistinguishesCompleteFromPartial() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try makeCompiledBundle("Decoder.mlmodelc")
        try makeCompiledBundle("Joint.mlmodelc", includeMarker: false)

        XCTAssertTrue(
            ParakeetModelRepository.isCompiledModelBundle(
                cacheDirectory.appendingPathComponent("Decoder.mlmodelc", isDirectory: true)
            )
        )
        XCTAssertFalse(
            ParakeetModelRepository.isCompiledModelBundle(
                cacheDirectory.appendingPathComponent("Joint.mlmodelc", isDirectory: true)
            )
        )
        XCTAssertFalse(
            ParakeetModelRepository.isCompiledModelBundle(
                cacheDirectory.appendingPathComponent("Absent.mlmodelc", isDirectory: true)
            )
        )
    }

    func testBundleWithoutItsWeightsIsNotACompiledBundle() throws {
        // The shape of a transfer stopped inside `weights/weight.bin`: the directory is
        // there, the marker is there, and there is no model in it.
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try makeCompiledBundle("Encoder.mlmodelc", includeWeights: false)

        XCTAssertFalse(
            ParakeetModelRepository.isCompiledModelBundle(
                cacheDirectory.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            )
        )
    }

    func testBundleWithoutModelMilIsNotACompiledBundle() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try makeCompiledBundle("Encoder.mlmodelc")
        try FileManager.default.removeItem(
            at: cacheDirectory
                .appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
                .appendingPathComponent("model.mil")
        )

        XCTAssertFalse(
            ParakeetModelRepository.isCompiledModelBundle(
                cacheDirectory.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            )
        )
    }

    // MARK: - Required download paths (issue #438)

    func testRequiredDownloadPathsNameLeafFilesNeverBundleDirectories() {
        let paths = ParakeetModelRepository.requiredDownloadPaths(
            requiredModelBundles: requiredBundles,
            vocabularyFileName: vocabularyFileName
        )

        // The whole of issue #438: the tripwire checked these against the file system,
        // and a `.mlmodelc` entry is a directory that exists long before it holds a model.
        for bundle in requiredBundles {
            XCTAssertFalse(paths.contains(bundle), "\(bundle) is a directory, not a file")
        }
    }

    func testRequiredDownloadPathsCoverEveryBundleAndTheVocabulary() {
        let paths = ParakeetModelRepository.requiredDownloadPaths(
            requiredModelBundles: requiredBundles,
            vocabularyFileName: vocabularyFileName
        )

        // Pinned against the repository tree of
        // `FluidInference/parakeet-tdt-0.6b-v3-coreml` at revision `7dd20fe`, read on
        // 2026-09-02: all four bundles carry these three entries.
        XCTAssertEqual(paths, [
            "Decoder.mlmodelc/coremldata.bin",
            "Decoder.mlmodelc/model.mil",
            "Decoder.mlmodelc/weights/weight.bin",
            "Encoder.mlmodelc/coremldata.bin",
            "Encoder.mlmodelc/model.mil",
            "Encoder.mlmodelc/weights/weight.bin",
            "JointDecision.mlmodelc/coremldata.bin",
            "JointDecision.mlmodelc/model.mil",
            "JointDecision.mlmodelc/weights/weight.bin",
            "Preprocessor.mlmodelc/coremldata.bin",
            "Preprocessor.mlmodelc/model.mil",
            "Preprocessor.mlmodelc/weights/weight.bin",
            "parakeet_vocab.json"
        ])
    }

    func testRequiredDownloadPathsAreOrderedTheSameOnEveryCall() {
        // The caller hands over a `Set`, whose iteration order is not stable across
        // instances, and a list that reorders itself is one no test can pin down.
        let first = ParakeetModelRepository.requiredDownloadPaths(
            requiredModelBundles: requiredBundles,
            vocabularyFileName: vocabularyFileName
        )
        let second = ParakeetModelRepository.requiredDownloadPaths(
            requiredModelBundles: Set(requiredBundles.shuffled()),
            vocabularyFileName: vocabularyFileName
        )

        XCTAssertEqual(first, second)
    }

    func testACompletedDownloadSatisfiesEveryRequiredPath() throws {
        try makeCompleteCache()

        XCTAssertNil(firstMissingRequiredPath())
        XCTAssertTrue(isComplete())
    }

    func testADownloadStoppedInsideTheEncoderWeightsFailsTheTripwire() throws {
        // 445 MB of the 482 MB payload is `Encoder.mlmodelc/weights/weight.bin`, so this
        // is where an interruption lands. Every bundle directory is on disk and holds its
        // small top-level files; the encoder holds no model.
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for bundle in requiredBundles {
            try makeCompiledBundle(bundle, includeWeights: bundle != "Encoder.mlmodelc")
        }
        try Data("{}".utf8).write(to: cacheDirectory.appendingPathComponent(vocabularyFileName))

        // What the tripwire used to check — the bundle directories and the vocabulary —
        // is all present, which is why it passed.
        for bundle in requiredBundles {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: cacheDirectory.appendingPathComponent(bundle).path
                )
            )
        }

        XCTAssertEqual(firstMissingRequiredPath(), "Encoder.mlmodelc/weights/weight.bin")
        XCTAssertNil(resolvedCacheDirectory())
    }

    func testARequiredPathThatIsADirectoryFailsTheTripwire() throws {
        // Phase 5 refuses a directory whatever the list names, so the hole cannot be
        // reopened by a future list that names one.
        try makeCompleteCache()
        let weight = cacheDirectory
            .appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            .appendingPathComponent("weights", isDirectory: true)
            .appendingPathComponent("weight.bin")
        try FileManager.default.removeItem(at: weight)
        try FileManager.default.createDirectory(at: weight, withIntermediateDirectories: true)

        XCTAssertEqual(firstMissingRequiredPath(), "Encoder.mlmodelc/weights/weight.bin")
    }
}
