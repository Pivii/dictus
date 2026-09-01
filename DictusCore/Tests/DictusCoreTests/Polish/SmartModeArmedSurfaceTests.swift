// DictusCore/Tests/DictusCoreTests/Polish/SmartModeArmedSurfaceTests.swift
// The armed mode's name is a Smart Mode surface too (issue #460, review round 2).
//
// WHY this suite reaches across targets: the rule is about `DictusKeyboard`, which has no
// test bundle — this package is the only suite in the repo. Same `#filePath` pattern as
// `DictationErrorCopyTests`, whose reasoning about a copied fixture drifting applies here.
//
// What it checks is what a view is *handed*, which no test in this package can render.
import XCTest
@testable import DictusCore

final class SmartModeArmedSurfaceTests: XCTestCase {

    private static let fanState = "DictusKeyboard/KeyboardSmartModeFan.swift"

    // MARK: - The armed mode is a surface too

    /// The toolbar's centre slot draws `armedMode`. Left ungated it was the one piece of the
    /// feature that survived the hide, and the worst one to leave: a mode name in the bar
    /// with no fan to open and no mode list in the app, so nothing anywhere could clear it.
    func testTheArmedModeIsWithheldWhileTheSurfaceIsHidden() throws {
        let source = try source(at: Self.fanState)
        XCTAssertTrue(source.contains("armedMode = fanIsReachable ? armed : nil"),
                      "\(Self.fanState) publishes the armed mode without asking whether the "
                      + "Smart Mode surface is reachable")
    }

    /// And it withholds rather than disarms. `.notSubscribed` is recoverable and
    /// `resolveArmedMode()` keeps the value on purpose (#392, #423); clearing it here would
    /// throw away a choice over a condition that lifts the day the flag goes up.
    func testWithholdingTheArmedModeDoesNotDisarmIt() throws {
        let source = try source(at: Self.fanState)
        let body = try XCTUnwrap(body(ofFunction: "refresh", in: source))
        XCTAssertFalse(body.contains("SmartModeStore.disarm"),
                       "refresh(status:) disarms, which loses the user's choice over a "
                       + "recoverable condition")
    }

    // MARK: - Reading the repo

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Polish
            .deletingLastPathComponent()  // DictusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // DictusCore
            .deletingLastPathComponent()  // repo root
    }

    private func source(at path: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let url = repoRoot().appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Source not found at \(url.path)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return text
    }

    /// The nearest line above `number` that carries code, comments skipped: a guard can be
    /// separated from what it guards by an explanation, and this codebase writes long ones.

    /// A function's body, braces balanced, string literals skipped so a `{` inside one
    /// cannot unbalance the count.
    private func body(ofFunction name: String, in source: String) -> String? {
        guard let start = source.range(of: "func \(name)("),
              let open = source.range(of: "{", range: start.upperBound..<source.endIndex) else {
            return nil
        }
        var depth = 1
        var index = open.upperBound
        var inString = false

        while index < source.endIndex, depth > 0 {
            let character = source[index]
            if character == "\"" { inString.toggle() }
            if !inString {
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1 }
            }
            index = source.index(after: index)
        }
        return String(source[open.upperBound..<index])
    }
}
