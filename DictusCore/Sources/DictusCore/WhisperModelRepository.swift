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
