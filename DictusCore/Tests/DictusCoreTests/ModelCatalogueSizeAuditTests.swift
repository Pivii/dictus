// DictusCore/Tests/DictusCoreTests/ModelCatalogueSizeAuditTests.swift
// Re-measures every catalogue size against the repository that serves it (issue #372).
import XCTest
@testable import DictusCore

/// The audit that keeps `ModelInfo.sizeBytes` honest.
///
/// WHY it is opt-in rather than part of the suite:
/// it talks to huggingface.co. `swift test` is the repo's only suite, it runs on
/// every change, and it is offline and deterministic — a network call would make
/// an unrelated change fail on a hotel connection or on a HuggingFace outage. So
/// this file is skipped unless it is asked for:
///
///     DICTUS_MODEL_SIZE_AUDIT=1 swift test --filter ModelCatalogueSizeAuditTests
///
/// Run it when a catalogue size is touched, when the WhisperKit or FluidAudio
/// dependency is bumped, or when a `modelDownloadSizeMismatch` line shows up in a
/// user's log. In the field that log line is what catches drift; this is what says
/// by how much and for which models.
final class ModelCatalogueSizeAuditTests: XCTestCase {

    /// Where a model's files come from, mirroring `ModelRepoDownloader.Configuration`.
    ///
    /// WHY the values are transcribed instead of imported: `Configuration` lives in
    /// DictusApp and its Parakeet case reads `Repo.parakeet` / `ModelNames.ASR` from
    /// FluidAudio, which DictusCore does not depend on. If a FluidAudio bump moves
    /// the repository or renames a required model, this transcription is what has to
    /// be updated — the audit would otherwise measure the wrong tree.
    private struct RepoSource {
        let repoPath: String
        /// Repo-relative directory prefixes (trailing "/") walked recursively.
        let directoryPatterns: [String]
        /// Whether root-level `.json`/`.txt` files are downloaded too.
        let includesRootMetadata: Bool

        static func whisperKit(variant: String) -> RepoSource {
            RepoSource(
                repoPath: "argmaxinc/whisperkit-coreml",
                directoryPatterns: ["\(variant)/"],
                includesRootMetadata: false
            )
        }

        /// Mirrors `Configuration.parakeet()`: FluidAudio's `Repo.parakeet.remotePath`
        /// and the four folders in `ModelNames.ASR.requiredModels`.
        static func parakeet() -> RepoSource {
            RepoSource(
                repoPath: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                directoryPatterns: [
                    "Decoder.mlmodelc/",
                    "Encoder.mlmodelc/",
                    "JointDecision.mlmodelc/",
                    "Preprocessor.mlmodelc/"
                ],
                includesRootMetadata: true
            )
        }

        static func forModel(_ model: ModelInfo) -> RepoSource {
            switch model.engine {
            case .whisperKit: return .whisperKit(variant: model.identifier)
            case .parakeet: return .parakeet()
            }
        }
    }

    private struct TreeItem: Decodable {
        let path: String
        let type: String
        let size: Int?
    }

    func testDeclaredSizesMatchWhatTheRepositoriesServe() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DICTUS_MODEL_SIZE_AUDIT"] == "1",
            "Network audit — set DICTUS_MODEL_SIZE_AUDIT=1 to run it"
        )

        var failures: [String] = []
        for model in ModelInfo.allIncludingDeprecated {
            let measured = try await measuredBytes(for: model)
            let declaredMB = model.sizeBytes / 1_000_000
            let measuredMB = measured / 1_000_000
            let ratio = Double(measured) / Double(model.sizeBytes)
            // Printed for every entry, passing or not: the point of running this is
            // to read the numbers, not only to learn that they were acceptable.
            print(String(format: "%@: declared %ld MB, served %ld MB (%.2fx)",
                         model.identifier, declaredMB, measuredMB, ratio))
            if model.sizeHasDrifted(fromMeasured: measured) {
                failures.append("\(model.identifier): declares \(declaredMB) MB, "
                    + "repository serves \(measuredMB) MB")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Catalogue sizes have drifted beyond \(Int(ModelInfo.sizeTolerance * 100))% — "
                + "correct ModelInfo.sizeBytes:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Repository walk

    /// Sums the files the downloader would fetch, walking the tree the same way
    /// `ModelRepoDownloader.listRequiredFiles()` does — directory by directory,
    /// descending only into the required prefixes. A flat recursive listing would
    /// disagree for Parakeet, where the root-metadata rule would otherwise sweep up
    /// `.json` files sitting in folders the real walk never enters.
    private func measuredBytes(for model: ModelInfo) async throws -> Int64 {
        let source = RepoSource.forModel(model)
        var total: Int64 = 0
        var pendingDirectories = [""]

        while let directory = pendingDirectories.first {
            pendingDirectories.removeFirst()
            for item in try await fetchTree(repoPath: source.repoPath, path: directory) {
                if item.type == "directory" {
                    let isRequired = source.directoryPatterns.contains {
                        item.path.hasPrefix($0) || $0.hasPrefix(item.path + "/")
                    }
                    if isRequired { pendingDirectories.append(item.path) }
                } else if item.type == "file", shouldInclude(item.path, source) {
                    total += Int64(max(0, item.size ?? 0))
                }
            }
        }
        return total
    }

    private func shouldInclude(_ filePath: String, _ source: RepoSource) -> Bool {
        if source.directoryPatterns.contains(where: { filePath.hasPrefix($0) }) { return true }
        guard source.includesRootMetadata else { return false }
        return filePath.hasSuffix(".json") || filePath.hasSuffix(".txt")
    }

    private func fetchTree(repoPath: String, path: String) async throws -> [TreeItem] {
        let apiPath = path.isEmpty ? "tree/main" : "tree/main/\(path)"
        let urlString = "https://huggingface.co/api/models/\(repoPath)/\(apiPath)"
        let url = try XCTUnwrap(URL(string: urlString), "Cannot build \(urlString)")
        let (data, response) = try await URLSession.shared.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertTrue((200..<300).contains(statusCode), "HTTP \(statusCode) for \(urlString)")
        return try JSONDecoder().decode([TreeItem].self, from: data)
    }
}
