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
/// WHY completeness is read from the files INSIDE a bundle (issues #252, #438):
/// A `.mlmodelc` directory can exist while the download that was filling it was
/// interrupted, so directory existence alone — which is all `AsrModels.modelsExist`
/// checks — is not enough. `coremldata.bin` is not enough either: the repository is
/// listed breadth first, so every bundle's small top-level files are published before
/// any bundle's `weights/`, and a transfer stopped inside `Encoder.mlmodelc/weights/
/// weight.bin` (445 MB of the 482 MB payload) leaves all four bundles holding their
/// marker and none of them holding a model. `requiredBundleEntries` is what a bundle
/// has to hold for the answer to mean anything.
public enum ParakeetModelRepository {

    /// Marker file every compiled Core ML bundle contains once it is fully written.
    public static let compiledModelMarkerFile = "coremldata.bin"

    /// Entries that must exist INSIDE a compiled Parakeet bundle for it to hold a model
    /// rather than a shell.
    ///
    /// Established from the repository, not copied from WhisperKit (issue #438): the
    /// tree of `FluidInference/parakeet-tdt-0.6b-v3-coreml` at revision `7dd20fe` was
    /// read on 2026-09-02, and all four bundles FluidAudio requires — `Preprocessor`,
    /// `Encoder`, `Decoder`, `JointDecision` — carry exactly these three, plus
    /// `metadata.json` and `analytics/coremldata.bin`.
    ///
    /// Those last two are deliberately left out. Two other bundles in the same
    /// repository (`Encoder_v2`, `ParakeetDecoder`) ship without `metadata.json`, which
    /// makes it the least stable entry of the five, and requiring it catches nothing
    /// `weights/weight.bin` does not already catch — the weights are the last bytes of
    /// every bundle and 92% of the payload of the whole download.
    public static let requiredBundleEntries = [
        compiledModelMarkerFile,
        "model.mil",
        "weights/weight.bin"
    ]

    /// Repo-relative paths a completed Parakeet download must have left on disk: the
    /// leaf files inside every required bundle, plus the vocabulary at the root.
    ///
    /// This is what `ModelRepoDownloader`'s final-verification tripwire checks, and it
    /// is the same requirement `isCompiledModelBundle` below applies one bundle at a
    /// time for the load guard: both read `requiredBundleEntries`, so the download's
    /// promise and the load guard's belief cannot drift apart (same arrangement as
    /// `WhisperModelRepository.requiredDownloadPaths`, issue #433).
    ///
    /// WHY a fixed list rather than the disk enumeration the WhisperKit side does: there
    /// the set of bundles is a property of the variant and only knowable from the files.
    /// Here it is `ModelNames.ASR.requiredModels`, a compile-time constant the caller
    /// hands over — and the FluidAudio cache is one directory per `AsrModelVersion`
    /// shared by every model of that version, so enumerating it would demand
    /// completeness of bundles this downloader never fetched.
    ///
    /// - Parameters:
    ///   - requiredModelBundles: names of the compiled `.mlmodelc` bundles the engine
    ///     loads. Sorted here because the caller's set has no order, and a list that
    ///     reorders itself between calls is one no test can pin down.
    ///   - vocabularyFileName: name of the vocabulary file at the repository root.
    public static func requiredDownloadPaths(
        requiredModelBundles: Set<String>,
        vocabularyFileName: String
    ) -> [String] {
        requiredModelBundles.sorted().flatMap { bundle in
            requiredBundleEntries.map { entry in "\(bundle)/\(entry)" }
        } + [vocabularyFileName]
    }

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
        guard isRegularFile(vocabulary, fileManager: fileManager) else { return false }

        return requiredModelBundles.allSatisfy { bundleName in
            isCompiledModelBundle(
                cacheDirectory.appendingPathComponent(bundleName, isDirectory: true),
                fileManager: fileManager
            )
        }
    }

    /// Whether the URL is a compiled Core ML bundle holding a model, rather than a
    /// directory an interrupted download left behind.
    public static func isCompiledModelBundle(
        _ bundleURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return requiredBundleEntries.allSatisfy { entry in
            isRegularFile(bundleURL.appendingPathComponent(entry), fileManager: fileManager)
        }
    }

    /// Whether the path holds a file rather than a directory.
    ///
    /// WHY the distinction matters: `fileExists(atPath:)` alone answers yes for a
    /// directory too, so a `coremldata.bin/` or `parakeet_vocab.json/` directory would
    /// read as a usable cache and the failure would only surface once FluidAudio tried
    /// to read it — which is the wipe-and-re-download path this check exists to avoid.
    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
