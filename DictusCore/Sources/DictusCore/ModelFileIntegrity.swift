// DictusCore/Sources/DictusCore/ModelFileIntegrity.swift
// The last check a downloaded model file passes before it is published.
import Foundation
import CryptoKit

/// Verifies an assembled model file against what the repository promised.
///
/// WHY this exists (issue #449, maintainer's note): a byte-range resume appends bytes
/// from one response onto bytes from another, across process launches and network
/// changes. Every guard around that path — `If-Range`, the exact `Content-Range` start,
/// the pinned commit revision — is there to make a wrong append impossible, and this is
/// what proves it. The failure it catches is the only one the existence checks
/// downstream cannot see: a file of exactly the right length made of the wrong bytes.
/// `WhisperModelRepository.hasCompleteDownload` and the downloader's own tripwire both
/// answer "is it there", and both would wave that file through.
///
/// SHA-256 is checked only when the repository listing supplied one. Hugging Face gives
/// `lfs.oid` for LFS blobs, which is every large weight file, and nothing usable for
/// small plain files — their `oid` is a git blob SHA-1 over a different preimage. Size
/// is checked always.
public enum ModelFileIntegrity {

    /// Why an assembled file was refused.
    public enum Failure: Equatable, Sendable {
        case unreadable
        case sizeMismatch(expected: Int64, actual: Int64)
        case checksumMismatch(expected: String, actual: String)

        /// Compact form for the debug log. Carries no path — the caller logs that.
        public var logReason: String {
            switch self {
            case .unreadable:
                return "unreadable"
            case .sizeMismatch(let expected, let actual):
                return "size expected=\(expected) actual=\(actual)"
            case .checksumMismatch:
                // The digests themselves are 64 hex characters each and say nothing a
                // reader can act on; that they differ is the whole finding.
                return "sha256 mismatch"
            }
        }
    }

    /// Bytes read per digest update. Large enough that a 445 MB file costs a few
    /// thousand reads, small enough that none of it is resident.
    private static let readChunkSize = 1 << 20

    /// Checks an assembled file's size and, when one is known, its SHA-256.
    ///
    /// - Parameters:
    ///   - url: the assembled partial, before it is moved into the cache directory.
    ///   - expectedSize: size the repository listing reported; skipped when negative.
    ///   - expectedSHA256: lowercase hex digest, or `nil` when the listing had none.
    /// - Returns: `nil` when the file may be published, otherwise the reason it may not.
    public static func verify(
        fileAt url: URL,
        expectedSize: Int64,
        expectedSHA256: String?,
        fileManager: FileManager = .default
    ) -> Failure? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let actualSize = (attributes[.size] as? NSNumber)?.int64Value else {
            return .unreadable
        }
        if expectedSize >= 0, actualSize != expectedSize {
            return .sizeMismatch(expected: expectedSize, actual: actualSize)
        }
        guard let expectedSHA256, !expectedSHA256.isEmpty else { return nil }
        guard let actual = sha256Hex(ofFileAt: url) else { return .unreadable }
        guard actual == expectedSHA256.lowercased() else {
            return .checksumMismatch(expected: expectedSHA256.lowercased(), actual: actual)
        }
        return nil
    }

    /// Streaming SHA-256 of a file, as lowercase hex, or `nil` when it cannot be read.
    ///
    /// Streamed rather than `Data(contentsOf:)` because the file this exists for is
    /// 445 MB and the app it runs in is one iOS already watches for memory (issue #104,
    /// #362). `defer`-closes the handle on every exit, including the throwing ones.
    public static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data: Data?
            do {
                data = try handle.read(upToCount: readChunkSize)
            } catch {
                return nil
            }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
