// DictusCore/Tests/DictusCoreTests/UserDictionaryWriteCostTests.swift
// Measures what a word-boundary write costs when the dictionary sits at its cap.
import XCTest
@testable import DictusCore

/// WHY this exists: `saveToDefaults()` re-serialises the whole dictionary on
/// every word boundary, so it is on the typing hot path. #304 added a second
/// persisted map (the last-used timestamps), and the acceptance criterion is
/// that a dictionary at the cap still writes within the same order of magnitude
/// of time. That is a measurement, not something an assertion can settle.
///
/// WHY the tests assert nothing about the elapsed time: absolute timings depend
/// on the machine, so a threshold here would either be meaningless or flaky.
/// They print the number and assert the structural invariant instead. To compare
/// against a revision, run this file on both:
///
///     cd DictusCore && swift test --filter UserDictionaryWriteCostTests
final class UserDictionaryWriteCostTests: XCTestCase {

    private let iterations = 200

    override func setUp() {
        super.setUp()
        UserDictionary.shared.resetAll()
    }

    override func tearDown() {
        UserDictionary.shared.resetAll()
        super.tearDown()
    }

    private func fillToCap() {
        for index in 0..<UserDictionary.maxLearnedWords {
            UserDictionary.shared.learn("perfword\(index)")
        }
        XCTAssertEqual(UserDictionary.shared.count, UserDictionary.maxLearnedWords)
    }

    private func measureWrites(_ label: String, _ body: (Int) -> Void) {
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<iterations {
            body(index)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let perWrite = elapsed / Double(iterations) * 1000
        print("MEASURE \(label): \(iterations) writes in \(elapsed)s -> \(perWrite) ms/write")
    }

    /// The common case: the dictionary is at the cap and the user types a word it
    /// already knows. No eviction fires; this is the plain serialisation cost.
    func testSteadyStateWriteAtTheCap() {
        fillToCap()

        measureWrites("steady-state") { _ in
            UserDictionary.shared.recordUsage("perfword0")
        }

        XCTAssertEqual(UserDictionary.shared.count, UserDictionary.maxLearnedWords)
    }

    /// The overflow case: every write adds a new word, exceeds the cap and runs
    /// one eviction. This is the path the ordering change lands on.
    func testEvictingWriteAtTheCap() {
        fillToCap()

        measureWrites("evicting") { index in
            UserDictionary.shared.learn("overflowword\(index)")
        }

        XCTAssertEqual(UserDictionary.shared.count, UserDictionary.maxLearnedWords)
    }
}
