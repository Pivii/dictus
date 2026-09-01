// DictusCore/Tests/DictusCoreTests/Polish/SmartModeFanGestureTests.swift
// How often the long press may ask for the fan (issue #460, review round 2).
//
// WHY this suite reaches across targets: the rule is about `DictusKeyboard`, which has no
// test bundle — this package is the only suite in the repo. Same `#filePath` pattern as
// `DictationErrorCopyTests` and `ProProductCatalogTests`, and each of those carries its own
// copy of the reading helpers rather than sharing one, which is the convention here.
//
// The rule cannot be checked by running anything: it is about how often a SwiftUI gesture
// calls a function, and calling it twice is correct code that is merely expensive. What it
// can be checked against is the source, and a green build did not catch it.
import XCTest
@testable import DictusCore

final class SmartModeFanGestureTests: XCTestCase {

    private static let toolbar = "DictusKeyboard/Views/ToolbarView.swift"

    // MARK: - The refused press asks once

    /// `onChanged` fires on every drag update, and `isSmartModeFanOpen` stays false after a
    /// refusal, so an unguarded call site asks `open()` dozens of times per press — each
    /// ask reaching `SystemLanguageModel.default.availability` on the main thread. Rare
    /// before #460 hid the fan; every long press of every user after it.
    func testTheFanIsAskedForAtMostOnceForEachRefusedPress() throws {
        let source = try source(at: Self.toolbar)
        let call = try XCTUnwrap(
            line(containing: "fanGestureDidOpen = onSmartModeFanOpen?()", in: source),
            "\(Self.toolbar) no longer calls onSmartModeFanOpen the way this test reads it"
        )
        let guardLine = try XCTUnwrap(
            previousNonEmptyLine(before: call.number, in: source),
            "the call to onSmartModeFanOpen has nothing in front of it"
        )
        XCTAssertTrue(guardLine.contains("!fanGestureWasRefused"),
                      "\(Self.toolbar):\(call.number) asks for the fan without checking "
                      + "whether this press was already refused: \(guardLine)")
    }

    /// Only a refusal latches. A fan that opened and was then closed by its own idle
    /// backstop has to reopen under a continued drag, which is the stated reason
    /// `isSmartModeFanOpen` is the state rather than `fanGestureDidOpen` — a latch set on
    /// every ask would have quietly undone it.
    func testOnlyARefusalLatchesTheGesture() throws {
        let source = try source(at: Self.toolbar)
        XCTAssertTrue(source.contains("fanGestureWasRefused = !fanGestureDidOpen"),
                      "the latch is set from something other than the refusal, which would "
                      + "stop a backstop-closed fan reopening mid-press")
    }

    /// A latch cleared on release sticks after a cancelled touch — no `onEnded` arrives —
    /// and leaves every later long press inert. It is cleared where a press *begins*:
    /// inside the branch that runs for everything which is not yet a completed long
    /// press, which `.first(true)` reaches the moment the finger lands.
    ///
    /// The `else` block is read whole rather than searched for a line, because the
    /// property's own declaration (`= false`) matches that line too — the first shape of
    /// this test passed on the declaration and would have gone green with no reset at all.
    func testTheLatchIsClearedWhenAPressBegins() throws {
        let source = try source(at: Self.toolbar)
        let block = try XCTUnwrap(
            elseBlock(after: "guard case .second(true, let drag) = value else", in: source),
            "\(Self.toolbar) no longer shapes the long-press guard the way this test reads it"
        )
        XCTAssertTrue(block.contains("fanGestureWasRefused = false"),
                      "a press that begins does not clear the refusal latch, so one "
                      + "cancelled gesture would leave every later long press inert:\n\(block)")
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

    private func line(containing needle: String, in source: String) -> (number: Int, text: String)? {
        for (index, text) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where text.contains(needle) {
            return (number: index + 1, text: String(text))
        }
        return nil
    }

    /// The nearest line above `number` that carries code, comments skipped: a guard can be
    /// separated from what it guards by an explanation, and this codebase writes long ones.
    private func previousNonEmptyLine(before number: Int, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = number - 2
        while index >= 0 {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("//") { return trimmed }
            index -= 1
        }
        return nil
    }

    /// The `{ … }` block that follows `marker`, braces balanced.
    private func elseBlock(after marker: String, in source: String) -> String? {
        guard let start = source.range(of: marker),
              let open = source.range(of: "{", range: start.upperBound..<source.endIndex) else {
            return nil
        }
        var depth = 1
        var index = open.upperBound
        while index < source.endIndex, depth > 0 {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" { depth -= 1 }
            index = source.index(after: index)
        }
        return String(source[open.upperBound..<index])
    }

}
