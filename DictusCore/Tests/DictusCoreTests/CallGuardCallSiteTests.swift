// DictusCore/Tests/DictusCoreTests/CallGuardCallSiteTests.swift
// Where the call guard is asked, checked against the source that has to keep asking it.
//
// WHY this suite reaches across targets: the rule itself is `ActiveCallPolicy` and it is
// tested next door. What broke was not the rule but the *call site* — `startRecording()`
// skips `startEngine()` when the engine is already warm, and `startEngine()` was the only
// place the guard was consulted, so a dictation started on a warm engine never asked
// CallKit at all (CodeRabbit on PR #513, and the same file says so itself thirty lines
// below, in a comment written for #293).
//
// `UnifiedAudioEngine` is `@MainActor`, owns a live `AVAudioEngine` and lives in DictusApp,
// which has no test bundle — so the omission cannot be caught by exercising it. It can be
// caught by reading the source, which is the pattern `DictationErrorCopyTests` and
// `ProProductCatalogTests` already established here for exactly that reason.
import XCTest
@testable import DictusCore

final class CallGuardCallSiteTests: XCTestCase {

    private static let enginePath = "DictusApp/Audio/UnifiedAudioEngine.swift"
    private static let guardCall = "refuseIfACallHoldsTheMicrophone()"

    /// The path the app's own mic button takes when the engine is already warm.
    func testStartRecordingAsksTheCallGuard() throws {
        let body = try body(of: "func startRecording() throws {", in: Self.enginePath)
        XCTAssertTrue(body.contains(Self.guardCall),
                      "startRecording() no longer asks the call guard, so a dictation on a warm "
                      + "engine would never consult CallKit")
    }

    /// It has to be the first statement, not merely present. `cancelIdleRelease()` drops
    /// the timer that bounds a warm engine (#256): a guard that throws after it would leave
    /// the engine warm with nothing armed to release it.
    func testTheGuardRunsBeforeAnythingItCouldStrand() throws {
        let body = try body(of: "func startRecording() throws {", in: Self.enginePath)
        let guardIndex = try XCTUnwrap(body.range(of: Self.guardCall)?.lowerBound)

        for statement in ["cancelIdleRelease()", "engine.isRunning", "isRecording = true"] {
            let index = try XCTUnwrap(body.range(of: statement)?.lowerBound,
                                      "startRecording() no longer contains \(statement)")
            XCTAssertLessThan(guardIndex, index,
                              "the call guard must run before \(statement) in startRecording()")
        }
    }

    /// The cold path keeps its own check. The fix adds a second asking point; it does not
    /// move the first one.
    func testStartEngineStillAsksTheCallGuard() throws {
        let body = try body(of: "private func startEngine(context: String) throws {",
                            in: Self.enginePath)
        XCTAssertTrue(body.contains(Self.guardCall),
                      "startEngine() no longer asks the call guard")
    }

    // MARK: - Reading the repo

    /// The text between a function's opening brace and its matching close, with comment
    /// lines removed.
    ///
    /// WHY the stripping: this file's assertions are about the order of *statements*, and
    /// the comments in `startRecording()` name the very calls being ordered — the first
    /// version of `testTheGuardRunsBeforeAnythingItCouldStrand` failed because the guard's
    /// own explanation mentions `cancelIdleRelease()` above the guard call.
    private func body(of signature: String,
                      in path: String,
                      file: StaticString = #filePath,
                      line: UInt = #line) throws -> String {
        let source = try source(at: path, file: file, line: line)
        guard let signatureRange = source.range(of: signature) else {
            XCTFail("\(path) no longer declares `\(signature)`", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }

        var depth = 1
        var index = signatureRange.upperBound
        while index < source.endIndex, depth > 0 {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if depth == 0 { break }
            index = source.index(after: index)
        }
        return String(source[signatureRange.upperBound..<index])
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func source(at path: String,
                        file: StaticString = #filePath,
                        line: UInt = #line) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DictusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // DictusCore
            .deletingLastPathComponent()  // repo root
        let url = root.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Source not found at \(url.path)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return text
    }
}
