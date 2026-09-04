// DictusCore/Tests/DictusCoreTests/Polish/SmartModeProCopyTests.swift
// No sentence naming Dictus Pro is reachable in the keyboard while the paywall is
// hidden (issue #460), checked against the source that has to keep it.
//
// WHY this suite reaches across targets: the rule is about `DictusKeyboard`, which has no
// test bundle — this package is the only suite in the repo. `DictationErrorCopyTests` and
// `ProProductCatalogTests` established the pattern of resolving a repo path from
// `#filePath` rather than copying a file into test resources, for the reason they give: a
// copy would drift, and drift is the failure being checked for.
//
// What it can and cannot do. `SmartModeSurfaceTests` proves the *policy* — with the flag
// down, nothing sells Pro. This proves the two copy paths are wired to that policy and
// cannot be called around it: the gate is a parameter with no default, so the compiler
// asks every call site, and each Dictus Pro literal sits behind it. What neither can do is
// render a SwiftUI view; #460's acceptance asks for a test over the reason and status
// message paths instead of a long press on a device, and this is that test.
import XCTest
@testable import DictusCore

final class SmartModeProCopyTests: XCTestCase {

    private static let fanSource = "DictusKeyboard/KeyboardSmartModeFan.swift"

    /// Every file in the keyboard that calls one of the two copy functions.
    private static let callSites = [
        "DictusKeyboard/KeyboardSmartModeFan.swift",
        "DictusKeyboard/KeyboardPolishCoordinator.swift"
    ]

    private static let gatedFunctions = ["localizedReason", "localizedSkipNotice"]

    // MARK: - The gate cannot be skipped

    /// No default value, which is the whole mechanism. #460 exists because
    /// `localizedReason` answered `.notSubscribed` with a product name whatever the flag
    /// said; a default would restore exactly that, silently, at the next call site.
    func testBothCopyFunctionsRequireTheGateWithNoDefault() throws {
        let source = try source(at: Self.fanSource)
        for name in Self.gatedFunctions {
            let declaration = try XCTUnwrap(
                signature(ofFunction: name, in: source),
                "\(Self.fanSource) declares no \(name)"
            )
            XCTAssertTrue(declaration.contains("sellsPro: Bool"),
                          "\(name) does not take the #460 gate: \(declaration)")
            XCTAssertFalse(declaration.contains("sellsPro: Bool ="),
                           "\(name) gives the gate a default, which is the trap #460 is")
        }
    }

    /// Every call passes it, and none of them hard-codes the answer. `sellsPro: true`
    /// compiles and would put the sentence straight back; the value has to come from
    /// `SmartModeSurface`, which every file that calls one of these has to reach for.
    func testEveryCallSiteAnswersTheGateFromThePolicy() throws {
        var found = 0
        for path in Self.callSites {
            let source = try source(at: path)
            var callsHere = 0
            for name in Self.gatedFunctions {
                for call in calls(to: "\(name)(", in: source) {
                    found += 1
                    callsHere += 1
                    XCTAssertTrue(call.argument.contains("sellsPro:"),
                                  "\(path):\(call.line) calls \(name) without the gate")
                    XCTAssertFalse(call.argument.contains("sellsPro: true"),
                                   "\(path):\(call.line) hard-codes the gate open: \(call.argument)")
                }
            }
            if callsHere > 0 {
                XCTAssertTrue(source.contains("SmartModeSurface.sellsPro"),
                              "\(path) answers the gate without consulting the policy")
            }
        }
        XCTAssertGreaterThanOrEqual(found, 2,
                                    "The scan found almost no calls — the pattern it looks "
                                    + "for has probably changed")
    }

    // MARK: - Every Dictus Pro sentence sits behind it

    /// The acceptance criterion itself. Each sentence naming the product lives in a
    /// `case` of one of the two switches, and that case has to consult `sellsPro` before
    /// it can reach the literal.
    func testEverySentenceNamingDictusProIsBehindTheGate() throws {
        let source = try source(at: Self.fanSource)
        var checked = 0
        for name in Self.gatedFunctions {
            let body = try XCTUnwrap(body(ofFunction: name, in: source))
            for branch in switchBranches(in: body) where branch.contains("Dictus Pro") {
                checked += 1
                XCTAssertTrue(branch.contains("sellsPro"),
                              "\(name) names Dictus Pro in a branch that never consults the "
                              + "#460 gate:\n\(branch)")
            }
        }
        XCTAssertEqual(checked, 2,
                       "Expected exactly the two Dictus Pro sentences #460 names — the fan's "
                       + "reason line and the skipped-dictation notice. Found \(checked).")
    }

    /// The other half: a branch that mentions the gate must actually branch on it, rather
    /// than mentioning it in a comment on the way to the same sentence.
    func testTheGatedBranchesReturnSomethingElseFirst() throws {
        let source = try source(at: Self.fanSource)
        for name in Self.gatedFunctions {
            let body = try XCTUnwrap(body(ofFunction: name, in: source))
            for branch in switchBranches(in: body) where branch.contains("Dictus Pro") {
                let guardIndex = branch.range(of: "guard sellsPro else")?.lowerBound
                let literalIndex = branch.range(of: "Dictus Pro")?.lowerBound
                guard let guardIndex, let literalIndex else {
                    return XCTFail("\(name)'s Dictus Pro branch has no `guard sellsPro else`")
                }
                XCTAssertLessThan(guardIndex, literalIndex,
                                  "\(name) reaches the Dictus Pro sentence before checking "
                                  + "the gate")
            }
        }
    }

    // MARK: - The fan itself never opens

    /// A long press with the flag down presents nothing at all — no fan, and not the
    /// "pick your modes" line either, which would advertise a screen the app does not
    /// offer while the flag is down. The refusal also lands before `presentAreaMode`,
    /// which is what keeps it clear of the keyboard's declared height constraint (#166).
    func testTheHiddenFanIsRefusedBeforeAnythingIsPresented() throws {
        let source = try source(at: Self.fanSource)
        let body = try XCTUnwrap(body(ofFunction: "open", in: source))

        let refusal = try XCTUnwrap(body.range(of: "entryPoint != .hidden")?.lowerBound,
                                    "open() does not consult SmartModeSurface.fanEntryPoint")
        for presentation in ["presentAreaMode(", "presentStatusMessage(", "HapticFeedback."] {
            guard let index = body.range(of: presentation)?.lowerBound else { continue }
            XCTAssertLessThan(refusal, index,
                              "open() reaches \(presentation) before refusing a hidden fan")
        }
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

    /// A function's declaration, from `func` to the `{` that opens its body, joined onto
    /// one line so a signature broken across several reads as one string.
    private func signature(ofFunction name: String, in source: String) -> String? {
        guard let start = source.range(of: "func \(name)("),
              let open = source.range(of: "{", range: start.upperBound..<source.endIndex) else {
            return nil
        }
        return source[start.lowerBound..<open.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    /// A function's body, braces balanced. String literals are skipped so a `{` inside
    /// one cannot unbalance the count.
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

    /// A switch body split at its `case` labels, so each returned string is everything
    /// one branch can execute.
    private func switchBranches(in body: String) -> [String] {
        var branches: [String] = []
        var current: [String] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("case ") {
                if !current.isEmpty { branches.append(current.joined(separator: "\n")) }
                current = []
            }
            current.append(String(line))
        }
        if !current.isEmpty { branches.append(current.joined(separator: "\n")) }
        return branches
    }

    /// Every call to `opening` in a source, paired with its full argument text — the
    /// call's parentheses balanced, so a call broken across lines reads as one string.
    /// The same walker `DictationErrorCopyTests` uses, and for the same reason: SwiftLint
    /// pushes long calls onto a second line, and a per-line check would wave through
    /// exactly the wrapped call it exists to catch.
    private func calls(to opening: String, in source: String) -> [(line: Int, argument: String)] {
        var calls: [(line: Int, argument: String)] = []
        var searchStart = source.startIndex

        while let open = source.range(of: opening, range: searchStart..<source.endIndex) {
            // The declaration is not a call. `func localizedReason(` opens the same way.
            let precedingLine = source[source.startIndex..<open.lowerBound]
                .split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
            var depth = 1
            var index = open.upperBound
            var inString = false

            while index < source.endIndex, depth > 0 {
                let character = source[index]
                if character == "\"" { inString.toggle() }
                if !inString {
                    if character == "(" { depth += 1 }
                    if character == ")" { depth -= 1 }
                }
                index = source.index(after: index)
            }

            if !precedingLine.contains("func ") {
                let argument = source[open.upperBound..<index]
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                let line = source[source.startIndex..<open.lowerBound].filter { $0 == "\n" }.count + 1
                calls.append((line: line, argument: argument))
            }
            searchStart = index
        }

        return calls
    }
}
