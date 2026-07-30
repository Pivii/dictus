// DictusCore/Sources/DictusCore/ParakeetModelRepository.swift
// Completeness check for the on-disk FluidAudio (Parakeet) model cache.
import Foundation

/// Decides whether the Parakeet model cache on disk is complete enough to be loaded
/// without any network access.
///
/// WHY this type exists (issue #252):
/// The Parakeet dictation path called `AsrModels.downloadAndLoad`, which loads locally
/// when the files are there but **downloads on the dictation hot path** when they are
/// not — the behaviour issue #249 removed for Whisper. FluidAudio offers no download-free
/// entry point: `AsrModels.loadFromCache` reads like one, but it goes through
/// `DownloadUtils.loadModels`, which downloads whenever a required bundle is missing and,
/// on any load failure, deletes the cache and downloads it again. The guard therefore has
/// to sit in front of FluidAudio, which is what this type is for.
///
/// WHY the file names are parameters rather than constants here:
/// FluidAudio is a DictusApp-only dependency (it is never linked into the keyboard
/// extension), so DictusCore cannot import it. The caller passes FluidAudio's own
/// `ModelNames.ASR` values, which keeps a single source of truth: if the dependency
/// renames a bundle, the app picks the new name up at compile time and this check follows.
///
/// WHY `coremldata.bin` is the completeness marker:
/// It is exactly what FluidAudio's own loader verifies immediately before handing a
/// bundle to `MLModel(contentsOf:)`. A `.mlmodelc` directory can exist while the
/// download that was filling it was interrupted, so directory existence alone (what
/// `AsrModels.modelsExist` checks) is not enough — a partial cache must read as absent,
/// mirroring the compiled-bundle requirement #249 introduced for Whisper.
public enum ParakeetModelRepository {

    /// Marker file every compiled Core ML bundle contains once it is fully written.
    public static let compiledModelMarkerFile = "coremldata.bin"

    /// The cache directory when it holds a complete, loadable model set, otherwise `nil`.
    ///
    /// Callers on the dictation path must treat `nil` as "ask the user to download it in
    /// the model manager" rather than downloading it themselves (issue #252).
    ///
    /// - Parameters:
    ///   - cacheDirectory: Directory the engine caches its models in.
    ///   - requiredModelBundles: Names of the compiled `.mlmodelc` bundles the engine loads.
    ///   - vocabularyFileName: Name of the vocabulary file the engine reads alongside them.
    ///   - fileManager: Injectable for tests.
    public static func installedCacheDirectory(
        _ cacheDirectory: URL,
        requiredModelBundles: Set<String>,
        vocabularyFileName: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard isCacheComplete(
            cacheDirectory,
            requiredModelBundles: requiredModelBundles,
            vocabularyFileName: vocabularyFileName,
            fileManager: fileManager
        ) else {
            return nil
        }
        return cacheDirectory
    }

    /// Whether every required bundle is a compiled Core ML directory and the vocabulary
    /// file is present, so the model set can be loaded without touching the network.
    public static func isCacheComplete(
        _ cacheDirectory: URL,
        requiredModelBundles: Set<String>,
        vocabularyFileName: String,
        fileManager: FileManager = .default
    ) -> Bool {
        // An empty required set would make any directory, including a missing one, pass.
        guard !requiredModelBundles.isEmpty else { return false }

        let vocabulary = cacheDirectory.appendingPathComponent(vocabularyFileName)
        guard fileManager.fileExists(atPath: vocabulary.path) else { return false }

        return requiredModelBundles.allSatisfy { bundleName in
            isCompiledModelBundle(
                cacheDirectory.appendingPathComponent(bundleName, isDirectory: true),
                fileManager: fileManager
            )
        }
    }

    /// Whether the URL is a compiled Core ML bundle rather than a leftover directory.
    public static func isCompiledModelBundle(
        _ bundleURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        let marker = bundleURL.appendingPathComponent(compiledModelMarkerFile)
        return fileManager.fileExists(atPath: marker.path)
    }
}
