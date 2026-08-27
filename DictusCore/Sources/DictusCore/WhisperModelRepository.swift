// DictusCore/Sources/DictusCore/WhisperModelRepository.swift
// Single source of truth for where downloaded WhisperKit models live on disk.
import Foundation

/// Resolves the on-disk location of downloaded WhisperKit model variants.
///
/// WHY this type exists (issue #249):
/// The layout `Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier}`
/// was known only to `ModelManager`, which used it for download, delete and cleanup
/// (issue #210). The dictation path had no notion of it and therefore built its
/// `WhisperKitConfig` from the model *name* with `download: true`. WhisperKit then
/// resolved the identifier against the Hugging Face hub over the network, so a cold
/// start with no connectivity failed with `downloadError` even though the model was
/// already on the device. Both sides now resolve the folder through this type.
///
/// WHY `Documents/huggingface`:
/// WhisperKit stores models through `HubApi`, whose default download base is the
/// process's Documents directory plus `huggingface`, and whose repo layout is
/// `<base>/models/<repo id>/<variant>`. `ModelRepoDownloader` writes the exact same
/// layout, and `WhisperKitConfig(modelFolder:)` reads it back.
///
/// IMPORTANT: the Documents directory is per-process. Only DictusApp downloads and
/// loads models, so these helpers must be called from the app. The keyboard
/// extension has its own (empty) Documents directory and would always see the
/// models as missing.
public enum WhisperModelRepository {

    /// Hugging Face repository hosting the Core ML Whisper variants.
    public static let repositoryID = "argmaxinc/whisperkit-coreml"

    /// Repository location relative to the Documents directory.
    public static let relativeRepositoryPath = "huggingface/models/argmaxinc/whisperkit-coreml"

    /// Compiled Core ML bundle extension. A variant folder without at least one of
    /// these is a partial or wiped download, never something WhisperKit can load.
    private static let compiledModelExtension = "mlmodelc"

    /// Documents directory of the current process, or `nil` when unavailable.
    public static var defaultDocumentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Root of the local WhisperKit repository.
    /// - Parameter documentsDirectory: Override for tests. `nil` uses the process's
    ///   own Documents directory.
    public static func repositoryURL(documentsDirectory: URL? = nil) -> URL? {
        guard let documents = documentsDirectory ?? defaultDocumentsDirectory else { return nil }
        return documents.appendingPathComponent(relativeRepositoryPath, isDirectory: true)
    }

    /// Folder a variant occupies once downloaded, whether or not it exists yet.
    /// Used by download, delete and cleanup, which need the path even when empty.
    public static func modelFolderURL(
        for identifier: String,
        documentsDirectory: URL? = nil
    ) -> URL? {
        repositoryURL(documentsDirectory: documentsDirectory)?
            .appendingPathComponent(identifier, isDirectory: true)
    }

    /// Folder of a variant that is actually usable offline, or `nil` when the model
    /// is absent or the folder holds no compiled Core ML bundle.
    ///
    /// Callers on the dictation path must treat `nil` as "ask the user to download
    /// it in the model manager" rather than downloading it themselves (issue #249).
    public static func installedModelFolderURL(
        for identifier: String,
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let folder = modelFolderURL(for: identifier, documentsDirectory: documentsDirectory) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        guard let entries = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return nil
        }
        let hasCompiledModel = entries.contains { entry in
            (entry as NSString).pathExtension == compiledModelExtension
        }
        return hasCompiledModel ? folder : nil
    }

    /// Whether the variant is present on disk and loadable without any network access.
    public static func isModelInstalled(
        _ identifier: String,
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        installedModelFolderURL(
            for: identifier,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        ) != nil
    }

    // MARK: - Download completeness (issue #433)

    /// The compiled Core ML bundles every variant in the catalogue ships, without
    /// their `.mlmodelc` extension. Verified against the repository tree of all seven
    /// catalogue variants (tiny, base, small, small_216MB, medium, both turbos) on
    /// 2026-08-27.
    ///
    /// This is a FLOOR, not the whole required set. It exists to catch the one shape
    /// on-disk enumeration cannot see — a bundle that was never created at all — and
    /// `requiredDownloadPaths` adds every other `.mlmodelc` the variant folder
    /// actually holds. An earlier version of this fix treated the three as the whole
    /// answer and argued the omission of the turbos' `TextDecoderContextPrefill`
    /// was safe. It was not, and download order is why: `listRequiredFiles` walks
    /// the repository breadth first, so every bundle's small top-level files are
    /// fetched before any bundle's `weights/`, and the prefill bundle is enqueued
    /// last. Its `weights/weight.bin` (12 MB on turbo_632MB, ~98 MB on the 954MB
    /// legacy variant) is therefore the very last file of the whole download. A
    /// force quit, a dropped network or a jetsam in that final stretch left all
    /// three bundles above complete and the prefill one hollow — and WhisperKit's
    /// `prefillData?.loadModel(at:)` throws on exactly that, after
    /// `FileManager.fileExists` on the directory waved it through. The model would
    /// have been listed as downloaded and failed every selection.
    public static let requiredCompiledBundleNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    /// Root metadata file present in every variant folder.
    public static let configurationFileName = "config.json"

    /// Entries that must exist INSIDE a compiled bundle for it to hold a model
    /// rather than an empty shell. Same 2026-08-27 verification as the bundle list:
    /// all seven variants carry these three in each of their bundles, plus
    /// `metadata.json` and `analytics/coremldata.bin`, plus `model.mlmodel` on the
    /// five non-turbo variants only.
    ///
    /// WHY naming a bundle is not enough (issue #433): `ModelRepoDownloader` creates
    /// each file's parent directory before it starts downloading the file, so
    /// `AudioEncoder.mlmodelc/` exists on disk from the moment the first byte of its
    /// first file is requested. A download interrupted inside `weights/weight.bin` —
    /// which is 92% of the payload and therefore where an interruption almost always
    /// lands — leaves all three bundle directories present and every one of them
    /// unusable. Presence of the directory says nothing; presence of its contents
    /// says everything.
    ///
    /// This applies to the download's own final tripwire exactly as it applies to
    /// `hasCompleteDownload`, which is why both read the leaf paths below rather than
    /// the bundle directories. The tripwire checks with `FileManager.fileExists`,
    /// which answers true for a directory, so a bundle-level list let it pass on the
    /// very shape it exists to catch (CodeRabbit, PR #435).
    private static let requiredBundleEntries = ["coremldata.bin", "model.mil", "weights/weight.bin"]

    /// Repo-relative paths a completed download of `variant` must have produced: the
    /// leaf files inside every compiled bundle it ships, plus the root `config.json`.
    ///
    /// Single source of truth for the downloader's own final-verification tripwire
    /// and for `hasCompleteDownload` below, so the two cannot drift apart: the
    /// reconciliation is only allowed to trust files the download promised to place,
    /// and that promise is worth exactly as much as what the tripwire checks.
    ///
    /// WHY it reads the disk instead of returning a fixed list: the set of bundles is
    /// a property of the variant, not of this file. Hardcoding three made the check
    /// blind to the turbos' fourth bundle (see `requiredCompiledBundleNames`), and
    /// hardcoding four would only move the blindness to whatever the repository adds
    /// next. Every `.mlmodelc` the folder holds has to be complete; the floor above
    /// covers the bundles that are missing outright.
    ///
    /// - Parameter repositoryDirectory: root of the local WhisperKit repository —
    ///   the directory the variant folder sits in. The downloader passes the cache
    ///   directory it wrote into; `hasCompleteDownload` passes `repositoryURL`.
    public static func requiredDownloadPaths(
        forVariant variant: String,
        in repositoryDirectory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        let variantFolder = repositoryDirectory.appendingPathComponent(variant, isDirectory: true)
        let shipped = (try? fileManager.contentsOfDirectory(atPath: variantFolder.path)) ?? []
        let extraBundles = shipped
            .filter { ($0 as NSString).pathExtension == compiledModelExtension }
            .map { ($0 as NSString).deletingPathExtension }
            .filter { !requiredCompiledBundleNames.contains($0) }
            // Sorted because `contentsOfDirectory` gives no ordering guarantee, and a
            // list that reorders itself between calls is one no test can pin down.
            .sorted()

        return (requiredCompiledBundleNames + extraBundles).flatMap { bundle in
            requiredBundleEntries.map { entry in
                "\(variant)/\(bundle).\(compiledModelExtension)/\(entry)"
            }
        } + ["\(variant)/\(configurationFileName)"]
    }

    /// Whether every file a finished download of this variant leaves behind is on disk.
    ///
    /// WHY this is a sibling of `isModelInstalled` rather than a hardening of it
    /// (issue #433): the two answer different questions and pay for a wrong answer in
    /// opposite currencies. `installedModelFolderURL` answers "is there something here
    /// WhisperKit can be pointed at", and both its callers — the dictation load path
    /// and `WhisperKitEngine.prepare` — read `nil` as "send the user to the model
    /// manager to download it". A false negative there tells someone holding a
    /// perfectly good 1.5 GB model to fetch it again. This one answers "did the
    /// download of this variant finish", and a false negative here only reproduces
    /// the bug that already exists — the model stays invisible until the user
    /// downloads it again, which is exactly today's behaviour. Strictness is cheap on
    /// this side and expensive on that one, so it lives on this side.
    ///
    /// WHY presence is enough, with no size or checksum check: `ModelRepoDownloader`
    /// downloads into a temp location and moves each file into place atomically, so a
    /// file that exists is a file that completed. That is the same property the
    /// resume-on-retry behaviour already depends on.
    public static func hasCompleteDownload(
        _ identifier: String,
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let repository = repositoryURL(documentsDirectory: documentsDirectory) else {
            return false
        }
        let required = requiredDownloadPaths(
            forVariant: identifier,
            in: repository,
            fileManager: fileManager
        )
        return required.allSatisfy { path in
            isRegularFile(repository.appendingPathComponent(path), fileManager: fileManager)
        }
    }

    /// Variants whose files are completely on disk while the caller's bookkeeping
    /// says they are not downloaded, in the order `identifiers` gives them.
    ///
    /// This is the whole of issue #433's reconciliation, kept here as a pure function
    /// so it is reachable from a test: `ModelManager` lives in the app target, which
    /// has no test bundle. It deliberately returns identifiers and nothing else — the
    /// caller decides what to do with them, and in particular the reconciliation is
    /// never allowed to elect an active model (see `ModelManager.loadState`).
    ///
    /// Note it only ever reports models to ADD. A listed model whose files have gone
    /// missing is a different question with a different blast radius, and it is not
    /// this one.
    public static func unlistedCompleteDownloads(
        among identifiers: [String],
        listedAsDownloaded: [String],
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        let listed = Set(listedAsDownloaded)
        return identifiers.filter { identifier in
            guard !listed.contains(identifier) else { return false }
            return hasCompleteDownload(
                identifier,
                documentsDirectory: documentsDirectory,
                fileManager: fileManager
            )
        }
    }

    /// `fileExists` that refuses a directory. A `.mlmodelc` bundle is itself a
    /// directory, so every entry this check looks for has to be a real file for the
    /// answer to mean anything.
    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// Names of the tokenizer repositories cached alongside the models.
    ///
    /// WHY this exists: WhisperKit loads the tokenizer separately from the model,
    /// from `Documents/huggingface/models/openai/whisper-*`, which is populated the
    /// first time a variant is loaded online (the prewarm that follows every
    /// download). It is not part of the variant folder, so a model folder can be
    /// complete while the tokenizer cache is not. This is diagnostic only — the
    /// mapping from variant to tokenizer repo lives inside WhisperKit and is
    /// deliberately not duplicated here. Logged on the dictation load path so an
    /// offline failure can be attributed to the tokenizer rather than the model.
    public static func cachedTokenizerRepositoryNames(
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let documents = documentsDirectory ?? defaultDocumentsDirectory else { return [] }
        let openAIDirectory = documents
            .appendingPathComponent("huggingface/models/openai", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(atPath: openAIDirectory.path) else {
            return []
        }
        return entries.sorted()
    }
}
