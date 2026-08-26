// DictusCore/Tests/DictusCoreTests/ModelLoadStateTests.swift
// The launch-time correction of a persisted "loading" (#428).
//
// This is the rule that decides whether the app can be opened at all. `modelLoadState`
// is persisted in the App Group and read by the keyboard to decide whether to answer a
// mic tap by opening Dictus with `intent=prepare` — an intent that replaces the whole
// tab bar with the preparation screen. Before #428 nothing ever reset the value, so a
// Turbo compile killed mid-flight left "loading" behind for good and every later launch
// walked back into a screen with no Settings, no model list and no way out.
import XCTest
@testable import DictusCore

final class ModelLoadStateTests: XCTestCase {

    private let suiteName = "solutions.pivi.dictus.tests.modelLoadState"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A suite of its own: this rule is about what a *fresh process* finds on disk,
        // and borrowing the App Group would let another test's leftovers decide it.
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private var persisted: String? {
        defaults.string(forKey: SharedKeys.modelLoadState)
    }

    // MARK: - The correction

    /// The case that produced the issue: a process died mid-compile, and the state it
    /// wrote outlived it.
    func testAPersistedLoadingIsResetAtLaunch() {
        defaults.set(ModelLoadState.loading.rawValue, forKey: SharedKeys.modelLoadState)

        XCTAssertTrue(
            ModelLoadState.clearStaleLoadingState(in: defaults),
            "A stale loading must be reported as corrected so the launch can log it"
        )
        XCTAssertEqual(persisted, ModelLoadState.idle.rawValue)
    }

    /// The invariant stated as the reason it is safe: no load can be in flight in a
    /// process that has not started one, so there is never a `loading` worth keeping.
    func testTheResetIsUnconditionalForLoading() {
        for _ in 0..<3 {
            defaults.set(ModelLoadState.loading.rawValue, forKey: SharedKeys.modelLoadState)
            XCTAssertTrue(ModelLoadState.clearStaleLoadingState(in: defaults))
            XCTAssertEqual(persisted, ModelLoadState.idle.rawValue)
        }
    }

    /// Running it twice must not report a second correction — the launch logs on the
    /// return value, and a line claiming a reset that did not happen is a lie in the
    /// one log an agent reads to tell #428 apart from a healthy slow compile.
    func testTheResetIsIdempotent() {
        defaults.set(ModelLoadState.loading.rawValue, forKey: SharedKeys.modelLoadState)

        XCTAssertTrue(ModelLoadState.clearStaleLoadingState(in: defaults))
        XCTAssertFalse(ModelLoadState.clearStaleLoadingState(in: defaults))
        XCTAssertEqual(persisted, ModelLoadState.idle.rawValue)
    }

    // MARK: - What it must not touch

    /// `ready` is just as stale as `loading` after a process death, and is deliberately
    /// left alone: believing it costs one lazy load on the next dictation, while
    /// believing `loading` costs the user the entire app.
    func testAPersistedReadyIsLeftAlone() {
        defaults.set(ModelLoadState.ready.rawValue, forKey: SharedKeys.modelLoadState)

        XCTAssertFalse(ModelLoadState.clearStaleLoadingState(in: defaults))
        XCTAssertEqual(persisted, ModelLoadState.ready.rawValue)
    }

    func testAPersistedIdleIsLeftAlone() {
        defaults.set(ModelLoadState.idle.rawValue, forKey: SharedKeys.modelLoadState)

        XCTAssertFalse(ModelLoadState.clearStaleLoadingState(in: defaults))
        XCTAssertEqual(persisted, ModelLoadState.idle.rawValue)
    }

    /// A fresh install has no key at all, and must not gain one. `ModelLoadState`'s
    /// readers already treat absence as idle; writing "idle" here would put a value in
    /// the App Group on every launch for no reader's benefit.
    func testAnAbsentKeyStaysAbsent() {
        XCTAssertNil(persisted)

        XCTAssertFalse(ModelLoadState.clearStaleLoadingState(in: defaults))
        XCTAssertNil(persisted, "A fresh install must not be given a key it never had")
    }

    /// A value from a build that is not this one must not be silently rewritten either.
    /// Only the one string that locks the user out is this function's business.
    func testAnUnrecognisedValueIsLeftAlone() {
        defaults.set("compiling", forKey: SharedKeys.modelLoadState)

        XCTAssertFalse(ModelLoadState.clearStaleLoadingState(in: defaults))
        XCTAssertEqual(persisted, "compiling")
    }

    // MARK: - The reader's contract

    /// What the app reads after the reset. `idle` means "no load in flight", which is
    /// exactly what a fresh process knows to be true, and it is the value the keyboard
    /// treats as "a mic tap is allowed".
    func testIdleIsTheValueTheKeyboardAccepts() {
        XCTAssertEqual(ModelLoadState(rawValue: "idle"), .idle)
        XCTAssertNotEqual(ModelLoadState.idle, .loading)
    }
}
