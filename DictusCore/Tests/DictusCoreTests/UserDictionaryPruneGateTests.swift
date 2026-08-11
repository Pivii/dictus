// DictusCore/Tests/DictusCoreTests/UserDictionaryPruneGateTests.swift
// Tests for the one precondition the user-dictionary prune runs under (#287).
import XCTest
@testable import DictusCore

/// WHY these exist: three defects on this branch were all the same missing
/// invariant — the prune asking a dictionary that was not the one the user was
/// typing in — each found on a different call site. The rule is now stated in
/// one place, and this is what holds it there. The keyboard extension has no
/// test bundle, so a rule that lives in the extension is a rule nothing checks.
final class UserDictionaryPruneGateTests: XCTestCase {

    private func decide(
        alreadyPruned: Bool = false,
        mounted: String? = "fr",
        active: String = "fr"
    ) -> UserDictionaryPruneGate.Decision {
        UserDictionaryPruneGate.decide(
            alreadyPruned: alreadyPruned, mountedLanguage: mounted, activeLanguage: active
        )
    }

    func testItRunsWhenTheMountedDictionaryIsTheActiveLanguage() {
        XCTAssertEqual(decide(), .run)
    }

    func testItDoesNotRunTwice() {
        XCTAssertEqual(decide(alreadyPruned: true), .alreadyDone)
    }

    /// The already-pruned answer wins over everything else: once the one shot is
    /// spent there is nothing to report as a failure, and a mismatch at that
    /// point is not a problem anyone needs to hear about.
    func testAlreadyDoneOutranksAnyOtherReason() {
        XCTAssertEqual(decide(alreadyPruned: true, mounted: nil), .alreadyDone)
        XCTAssertEqual(decide(alreadyPruned: true, mounted: "de", active: "fr"), .alreadyDone)
    }

    /// Nothing mounted: no load has finished, or one is in flight and has already
    /// torn down the dictionary it replaces. This is the state the keyboard is in
    /// for much of a session, and answering it wrong is what kept the prune from
    /// ever running.
    func testItWaitsWhenNoDictionaryIsMounted() {
        XCTAssertEqual(decide(mounted: nil), .notMounted)
    }

    /// The case that motivated the whole type: the language was changed from the
    /// app while this keyboard process stayed alive, so the previous language's
    /// trie is still mounted and would happily answer for every word. Pruning
    /// there judges one language's vocabulary by another's — and spends the one
    /// shot doing it, so the language the user actually selected never gets a
    /// pass of its own.
    func testItRefusesADictionaryFromAnotherLanguage() {
        XCTAssertEqual(
            decide(mounted: "fr", active: "de"),
            .languageMismatch(mounted: "fr", active: "de")
        )
    }

    /// The reasons reach an export, so they have to stay greppable and carry no
    /// user content — language codes only.
    func testReasonsAreLogSafeTokens() {
        XCTAssertEqual(decide(mounted: nil).reason, "dictionary-not-mounted")
        XCTAssertEqual(
            decide(mounted: "fr", active: "de").reason,
            "language-mismatch mounted=fr active=de"
        )
        XCTAssertEqual(decide(alreadyPruned: true).reason, "already-done")
    }
}
