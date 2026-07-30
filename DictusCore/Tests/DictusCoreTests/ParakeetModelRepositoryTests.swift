// DictusCore/Tests/DictusCoreTests/ParakeetModelRepositoryTests.swift
// Tests for the local Parakeet (FluidAudio) cache completeness check (issue #252).
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
    /// bundle, each holding `coremldata.bin`, plus the vocabulary file at the root.
    private func makeCompleteCache() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for bundle in requiredBundles {
            try makeCompiledBundle(bundle)
        }
        try Data("{}".utf8).write(to: cacheDirectory.appendingPathComponent(vocabularyFileName))
    }

    private func makeCompiledBundle(_ name: String, includeMarker: Bool = true) throws {
        let bundle = cacheDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        // metadata.json is written early in a download; coremldata.bin marks completion.
        try Data("[]".utf8).write(to: bundle.appendingPathComponent("metadata.json"))
        if includeMarker {
            try Data("bin".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
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
}
