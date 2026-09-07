// DictusCore/Tests/DictusCoreTests/DictationErrorCopyTests.swift
// The error-copy contract of #313, checked against the sources that have to keep it.
//
// WHY this suite lives here and reaches across targets: the rule it enforces is about
// `DictusApp`, and `DictusApp` has no test bundle — this package is the only suite in the
// repo. `ProProductCatalogTests` already established the pattern of resolving a repo path
// from `#filePath` rather than copying a file into test resources, for the same reason it
// gives: a copy would drift, and drift is the failure being checked for.
//
// What it cannot check is what the strings *say*. That is a human's job, and the PR asks
// for it by hand. What it can check is the two mechanical halves of the contract, which are
// exactly the two that were broken and would break again silently:
//
//   1. every sentence written for a user is a catalog key with a French translation
//   2. no call site hands a raw thrown error to the surface the user is looking at
import XCTest
@testable import DictusCore

final class DictationErrorCopyTests: XCTestCase {

    /// The sources that produce the messages a failed dictation shows.
    private static let messageSources = [
        "DictusApp/DictationCoordinator.swift",
        "DictusApp/Audio/DictationFailureMessage.swift",
        "DictusApp/Audio/UnifiedAudioEngine.swift",
        "DictusApp/Audio/TranscriptionService.swift",
        "DictusApp/Audio/ParakeetEngine.swift",
        "DictusApp/Audio/SpeechModelProtocol.swift",
        "DictusApp/DictationHandoff.swift"
    ]

    private static let catalogPath = "DictusApp/Localizable.xcstrings"

    /// The keyboard extension writes exactly one dictation failure message of its own
    /// (#483), and it has its own catalog to write it into.
    private static let keyboardMessageSource = "DictusKeyboard/KeyboardCallGuard.swift"
    private static let keyboardCatalogPath = "DictusKeyboard/Localizable.xcstrings"

    // MARK: - Every sentence is a translated catalog key

    /// The half of the contract that fails silently. A new `String(localized:)` compiles,
    /// runs, and shows its English source string on a French device — which is how six
    /// English literals and two French ones were shipped before this issue.
    func testEverySentenceWrittenForAUserIsATranslatedCatalogKey() throws {
        let catalog = try catalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        var checked = 0
        for path in Self.messageSources {
            for sentence in try localizedLiterals(in: path) {
                checked += 1
                guard let entry = strings[sentence] as? [String: Any] else {
                    XCTFail("\(path) writes \"\(sentence)\", which is not a key in \(Self.catalogPath)")
                    continue
                }
                let unit = (entry["localizations"] as? [String: Any])
                    .flatMap { $0["fr"] as? [String: Any] }
                    .flatMap { $0["stringUnit"] as? [String: Any] }
                guard let unit else {
                    XCTFail("\"\(sentence)\" has no French translation — a French device would read the English")
                    continue
                }
                XCTAssertEqual(unit["state"] as? String, "translated",
                               "\"\(sentence)\" has a French entry that is not marked translated")
                let value = (unit["value"] as? String) ?? ""
                XCTAssertFalse(value.isEmpty, "\"\(sentence)\" has an empty French translation")
            }
        }

        XCTAssertGreaterThan(checked, 10,
                             "The scan found almost nothing — the literal pattern it looks for has probably changed")
    }

    /// The catalog declares `sourceLanguage: en`, so a French key would be read as the
    /// source string and shown to an English device. Every key is English; French lives in
    /// the translation entries and nowhere else (#418).
    func testTheSentencesAreEnglishKeysAndNotFrenchOnes() throws {
        for path in Self.messageSources {
            for sentence in try localizedLiterals(in: path) {
                XCTAssertFalse(sentence.contains { "àâäçéèêëîïôöùûüœÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŒ".contains($0) },
                               "\(path) uses a French sentence as a catalog key: \"\(sentence)\"")
            }
        }
    }

    // MARK: - No raw error text reaches the screen

    /// What #311, #313 and #417 are all instances of: a `catch` forwarding whatever it
    /// caught to the user. `DictationFailureMessage.userFacing(for:)` is the only way an
    /// error may become a message, because it is the only thing that knows to substitute a
    /// written sentence for a CoreAudio number or a FluidAudio string.
    ///
    /// Read over the whole call and not one line of it: SwiftLint's line-length rule
    /// actively pushes a long `handleError(...)` onto a second line — this file's own
    /// sources do it — so a single-line check would wave through exactly the wrapped
    /// call it exists to catch (#313 review).
    func testNoCallSiteForwardsAThrownErrorToTheUser() throws {
        for path in Self.messageSources {
            let source = try source(at: path)
            for call in handleErrorCalls(in: source) where call.argument.contains("localizedDescription") {
                XCTFail("\(path):\(call.line) hands raw error text to the user: \(call.argument)")
            }
        }
    }

    /// Every `handleError(...)` in a source, paired with its full argument text — the
    /// call's parentheses balanced, so a call broken across any number of lines reads as
    /// one string.
    private func handleErrorCalls(in source: String) -> [(line: Int, argument: String)] {
        var calls: [(line: Int, argument: String)] = []
        var searchStart = source.startIndex

        while let open = source.range(of: "handleError(", range: searchStart..<source.endIndex) {
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

            let argument = source[open.upperBound..<index]
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            let line = source[source.startIndex..<open.lowerBound].filter { $0 == "\n" }.count + 1
            calls.append((line: line, argument: argument))
            searchStart = index
        }

        return calls
    }

    /// `errorDescription` is what a user reads, so a case that returns a bare literal has
    /// bypassed the catalog. The shape to copy is `SpeechModelError`: a localized
    /// `errorDescription`, a separate `diagnosticDescription` for the log.
    func testEveryErrorTypeSplitsTheUserTextFromTheLogText() throws {
        let typesAndFiles = [
            ("AudioEngineError", "DictusApp/Audio/UnifiedAudioEngine.swift"),
            ("TranscriptionError", "DictusApp/Audio/TranscriptionService.swift"),
            ("ParakeetEngineError", "DictusApp/Audio/ParakeetEngine.swift"),
            ("SpeechModelError", "DictusApp/Audio/SpeechModelProtocol.swift")
        ]
        for (type, path) in typesAndFiles {
            let source = try source(at: path)
            XCTAssertTrue(source.contains("enum \(type): DiagnosableError")
                          || source.contains("enum \(type): Error, DiagnosableError"),
                          "\(type) does not declare the split — see DiagnosableError in DictationFailureMessage.swift")
            XCTAssertTrue(source.contains("var diagnosticDescription: String"),
                          "\(type) has no diagnosticDescription, so its raw text has nowhere to go but the screen")
        }
    }

    // MARK: - The keyboard says the app's sentence, not one of its own

    /// #483 gave the keyboard extension the ability to decline a mic tap in place, which
    /// means a second surface now writes a dictation failure message. The brief's rule was
    /// "the message shown is the one #313 defines; no second string is invented", and the
    /// two targets have **separate string catalogs** — so the sentence is spelled twice by
    /// construction, and nothing but this test stops the two copies drifting apart into two
    /// different messages for one event.
    func testTheKeyboardsCallMessageIsTheAppsOwnSentence() throws {
        let sentence = "The microphone is busy on a call. Try again once the call ends."

        let keyboardSource = try source(at: Self.keyboardMessageSource)
        XCTAssertTrue(keyboardSource.contains("String(localized: \"\(sentence)\")"),
                      "\(Self.keyboardMessageSource) no longer writes the app's call sentence")

        for path in [Self.catalogPath, Self.keyboardCatalogPath] {
            let strings = try XCTUnwrap(try catalog(at: path)["strings"] as? [String: Any])
            let entry = try XCTUnwrap(strings[sentence] as? [String: Any],
                                      "\(path) has no entry for \"\(sentence)\"")
            let unit = try XCTUnwrap((entry["localizations"] as? [String: Any])
                .flatMap { $0["fr"] as? [String: Any] }
                .flatMap { $0["stringUnit"] as? [String: Any] },
                                     "\(path) has no French translation for the call sentence")
            XCTAssertEqual(unit["state"] as? String, "translated", "in \(path)")
            XCTAssertEqual(unit["value"] as? String,
                           "Le micro est occupé par un appel. Réessayez une fois l'appel terminé.",
                           "\(path) translates the call sentence differently from the other catalog")
        }
    }

    // MARK: - Reading the repo

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
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

    private func catalog(at path: String = DictationErrorCopyTests.catalogPath,
                         file: StaticString = #filePath,
                         line: UInt = #line) throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else {
            XCTFail("String catalog not found at \(url.path)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                             file: file, line: line)
    }

    /// Every `String(localized: "…")` source string in a file.
    ///
    /// Interpolated literals are skipped: their key carries a `%@` placeholder Xcode
    /// substitutes at extraction time, so the literal in the source is not the catalog key
    /// and comparing the two would fail on a string that is perfectly correct.
    private func localizedLiterals(in path: String) throws -> [String] {
        let source = try source(at: path)
        let pattern = #"String\(localized: "((?:[^"\\]|\\.)*)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: source) else { return nil }
            let literal = String(source[captured])
            guard !literal.contains("\\(") else { return nil }
            return literal
        }
    }
}
