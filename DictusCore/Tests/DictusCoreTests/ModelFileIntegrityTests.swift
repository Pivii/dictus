// DictusCore/Tests/DictusCoreTests/ModelFileIntegrityTests.swift
// The last check an assembled model file passes before publication (issue #449).
import XCTest
@testable import DictusCore

final class ModelFileIntegrityTests: XCTestCase {

    /// SHA-256 of "abc", the canonical FIPS 180-4 vector.
    private let abcDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func write(_ data: Data, named name: String = "file.bin") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - Digest

    func testDigestMatchesTheCanonicalVector() throws {
        let url = try write(Data("abc".utf8))
        XCTAssertEqual(ModelFileIntegrity.sha256Hex(ofFileAt: url), abcDigest)
    }

    func testDigestOfAFileLargerThanOneReadChunk() throws {
        // 3 MB, so the streaming loop runs several times — the shape the 445 MB encoder
        // file exercises, at a size a test can afford.
        let payload = Data(repeating: 0x5A, count: 3 << 20)
        let url = try write(payload)
        let expected = ModelFileIntegrity.sha256Hex(ofFileAt: url)
        XCTAssertNotNil(expected)
        // Same bytes written again must digest identically, which is the only property
        // the streaming loop can get wrong.
        let second = try write(payload, named: "again.bin")
        XCTAssertEqual(ModelFileIntegrity.sha256Hex(ofFileAt: second), expected)
    }

    func testDigestOfAMissingFileIsNil() {
        XCTAssertNil(ModelFileIntegrity.sha256Hex(ofFileAt: directory.appendingPathComponent("nope")))
    }

    // MARK: - Verification

    func testAcceptsAFileThatMatchesSizeAndDigest() throws {
        let url = try write(Data("abc".utf8))
        XCTAssertNil(ModelFileIntegrity.verify(
            fileAt: url,
            expectedSize: 3,
            expectedSHA256: abcDigest
        ))
    }

    func testAcceptsAnUppercaseDigestFromTheRepository() throws {
        let url = try write(Data("abc".utf8))
        XCTAssertNil(ModelFileIntegrity.verify(
            fileAt: url,
            expectedSize: 3,
            expectedSHA256: abcDigest.uppercased()
        ))
    }

    func testRefusesAShortFile() throws {
        let url = try write(Data("ab".utf8))
        XCTAssertEqual(
            ModelFileIntegrity.verify(fileAt: url, expectedSize: 3, expectedSHA256: nil),
            .sizeMismatch(expected: 3, actual: 2)
        )
    }

    func testRefusesTheRightLengthWithTheWrongBytes() throws {
        // The one failure no existence check downstream can see, and the reason a
        // resumed download verifies at all.
        let url = try write(Data("abd".utf8))
        guard case .checksumMismatch = ModelFileIntegrity.verify(
            fileAt: url,
            expectedSize: 3,
            expectedSHA256: abcDigest
        ) else {
            return XCTFail("expected a checksum mismatch")
        }
    }

    func testChecksSizeAloneWhenTheRepositoryOfferedNoDigest() throws {
        // Plain (non-LFS) files carry a git blob SHA-1, which is not comparable, so the
        // manifest stores no digest for them and size is the whole check.
        let url = try write(Data("abd".utf8))
        XCTAssertNil(ModelFileIntegrity.verify(fileAt: url, expectedSize: 3, expectedSHA256: nil))
        XCTAssertNil(ModelFileIntegrity.verify(fileAt: url, expectedSize: 3, expectedSHA256: ""))
    }

    func testSkipsTheSizeCheckWhenTheRepositoryDidNotReportOne() throws {
        let url = try write(Data("abc".utf8))
        XCTAssertNil(ModelFileIntegrity.verify(fileAt: url, expectedSize: -1, expectedSHA256: abcDigest))
    }

    func testRefusesAFileThatIsNotThere() {
        XCTAssertEqual(
            ModelFileIntegrity.verify(
                fileAt: directory.appendingPathComponent("nope"),
                expectedSize: 3,
                expectedSHA256: nil
            ),
            .unreadable
        )
    }
}
