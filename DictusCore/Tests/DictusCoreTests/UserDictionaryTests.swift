// DictusCore/Tests/DictusCoreTests/UserDictionaryTests.swift
// Tests for UserDictionary.recordUsage — the repetition-learning counter path.
import XCTest
@testable import DictusCore

/// WHY these tests exist: `recordUsage` is called from the keyboard extension on
/// every word boundary and is the only place the pending → learned promotion
/// happens. Its two counter branches (bump an already-learned word, increment a
/// pending word and promote it at the threshold) had no coverage.
///
/// WHY they drive the shared singleton: `UserDictionary` has a private init and
/// reads App Group UserDefaults directly, so there is no seam to inject storage.
/// `resetAll()` in tearDown restores a clean slate, matching the approach in
/// KeyboardModeTests and SupportedLanguageActivationTests.
final class UserDictionaryTests: XCTestCase {

    /// WHY reset in setUp as well as tearDown: the singleton reads App Group
    /// UserDefaults, which outlive the test process. A run that crashes or is
    /// interrupted before tearDown leaves entries behind, and the next run's
    /// first test then observes a word it never recorded. Resetting on both
    /// edges makes each test independent of what ran before it.
    override func setUp() {
        super.setUp()
        UserDictionary.shared.resetAll()
    }

    override func tearDown() {
        UserDictionary.shared.resetAll()
        super.tearDown()
    }

    // MARK: - Promotion from pending to learned

    func testRecordUsageLearnsAWordOnceTheThresholdIsReached() {
        let word = "zorglub"
        var crossedThreshold = false
        for _ in 0..<UserDictionary.repetitionThreshold {
            crossedThreshold = UserDictionary.shared.recordUsage(word)
        }

        XCTAssertTrue(crossedThreshold, "The call reaching the threshold must report the word as just learned")
        XCTAssertTrue(UserDictionary.shared.isLearned(word))
        // The promoted word carries the pending count it accumulated, not a reset to 1.
        XCTAssertEqual(UserDictionary.shared.allLearnedWords[word], UserDictionary.repetitionThreshold)
    }

    func testRecordUsageBelowTheThresholdDoesNotLearnTheWord() throws {
        try XCTSkipIf(
            UserDictionary.repetitionThreshold < 2,
            "Threshold is 1, so there is no below-threshold call to observe"
        )
        let word = "zorglub"
        XCTAssertFalse(UserDictionary.shared.recordUsage(word))
        XCTAssertFalse(UserDictionary.shared.isLearned(word))
    }

    // MARK: - Bumping an already-learned word

    func testRecordUsageBumpsTheCountOfAnAlreadyLearnedWord() {
        let word = "zorglub"
        UserDictionary.shared.learn(word)
        XCTAssertEqual(UserDictionary.shared.allLearnedWords[word], 1)

        let crossedThreshold = UserDictionary.shared.recordUsage(word)

        XCTAssertFalse(crossedThreshold, "An already-learned word must not report as newly learned")
        XCTAssertEqual(UserDictionary.shared.allLearnedWords[word], 2)
    }

    func testRecordUsageMatchesAnAlreadyLearnedWordRegardlessOfCase() {
        UserDictionary.shared.learn("zorglub")

        XCTAssertFalse(UserDictionary.shared.recordUsage("ZorGluB"))

        // Case-folded onto the same key rather than creating a second entry.
        XCTAssertEqual(UserDictionary.shared.allLearnedWords["zorglub"], 2)
        XCTAssertNil(UserDictionary.shared.allLearnedWords["ZorGluB"])
    }

    // MARK: - Guards

    func testRecordUsageIgnoresEmptyAndSingleCharacterWords() {
        XCTAssertFalse(UserDictionary.shared.recordUsage(""))
        XCTAssertFalse(UserDictionary.shared.recordUsage("a"))
        XCTAssertEqual(UserDictionary.shared.count, 0)
    }

    // MARK: - Seeding a store (#304)

    /// WHY the tests write App Group UserDefaults directly instead of calling
    /// `learn()`: the eviction order turns on last-used timestamps, and
    /// `nowStamp()` has second resolution, so a test that learned its words
    /// normally would stamp all of them within the same second and could never
    /// tell a recent entry from an old one. Seeding the store and calling
    /// `reload()` also exercises the real load path, which is where the
    /// migration rule lives.
    ///
    /// Pass `lastUsed: nil` to seed a store written before recency existed.
    private func seedStore(words: [String: Int], lastUsed: [String: Int]?) {
        let defaults = AppGroup.defaults
        defaults.set(words, forKey: UserDictionary.storageKey)
        defaults.removeObject(forKey: UserDictionary.pendingKey)
        if let lastUsed {
            defaults.set(lastUsed, forKey: UserDictionary.lastUsedKey)
        } else {
            defaults.removeObject(forKey: UserDictionary.lastUsedKey)
        }
        UserDictionary.shared.reload()
    }

    private var persistedTimestamps: [String: Int] {
        AppGroup.defaults.dictionary(forKey: UserDictionary.lastUsedKey) as? [String: Int] ?? [:]
    }

    private static let now = Int(Date().timeIntervalSince1970)
    private static let aMinuteAgo = now - 60
    private static let tenDaysAgo = now - 10 * 86_400
    private static let threeHundredDaysAgo = now - 300 * 86_400

    /// `count` filler words, named so they never collide with the words a test
    /// makes assertions about.
    private func fillers(count: Int, usageCount: Int) -> [String: Int] {
        var words: [String: Int] = [:]
        for index in 0..<count {
            words["filler\(index)"] = usageCount
        }
        return words
    }

    private func stamp(_ words: [String: Int], at time: Int) -> [String: Int] {
        words.mapValues { _ in time }
    }

    // MARK: - Eviction order (#304)

    /// AC 1: overflowing the cap no longer removes entries chosen by lowest count.
    /// "kubernetes" has the lowest usage count in the store by a wide margin —
    /// under the old ascending-count policy it was guaranteed to be the first
    /// word deleted. It is also the most recently used, so it must survive.
    func testEvictionKeepsTheLowestCountWordWhenItIsTheMostRecentlyUsed() {
        var words = fillers(count: UserDictionary.maxLearnedWords - 1, usageCount: 500)
        words["kubernetes"] = 1
        var timestamps = stamp(words, at: Self.tenDaysAgo)
        timestamps["kubernetes"] = Self.aMinuteAgo
        seedStore(words: words, lastUsed: timestamps)

        UserDictionary.shared.learn("nouveau")

        XCTAssertEqual(UserDictionary.shared.count, UserDictionary.maxLearnedWords)
        XCTAssertTrue(
            UserDictionary.shared.isLearned("kubernetes"),
            "The lowest-count word was the most recently used, so it must not be the one evicted"
        )
    }

    /// AC 2: an entry used recently survives an eviction that removes an entry
    /// not used for a long time, regardless of their relative counts.
    func testEvictionRemovesTheOldestEntryEvenWhenItHasTheHighestCount() {
        var words = fillers(count: UserDictionary.maxLearnedWords - 2, usageCount: 50)
        words["bonjour"] = 999
        words["kubernetes"] = 2
        var timestamps = stamp(words, at: Self.aMinuteAgo)
        timestamps["bonjour"] = Self.tenDaysAgo
        seedStore(words: words, lastUsed: timestamps)

        UserDictionary.shared.learn("nouveau")

        XCTAssertFalse(
            UserDictionary.shared.isLearned("bonjour"),
            "The least recently used entry is evicted even though it has the highest count"
        )
        XCTAssertTrue(UserDictionary.shared.isLearned("kubernetes"))
        XCTAssertEqual(UserDictionary.shared.count, UserDictionary.maxLearnedWords)
    }

    /// The tiebreak, and the reason the migrated cohort is safe: among entries of
    /// equal recency the most-typed one goes first, because a word with a high
    /// count is almost certainly one the trie already knows, so losing it changes
    /// nothing the user can observe.
    func testEvictionBreaksATimestampTieByRemovingTheMostUsedEntry() {
        var words = fillers(count: UserDictionary.maxLearnedWords - 2, usageCount: 100)
        words["bonjour"] = 900
        words["kubernetes"] = 2
        seedStore(words: words, lastUsed: stamp(words, at: Self.aMinuteAgo))

        UserDictionary.shared.learn("nouveau")

        XCTAssertFalse(UserDictionary.shared.isLearned("bonjour"))
        XCTAssertTrue(UserDictionary.shared.isLearned("kubernetes"))
    }

    // MARK: - Migration of entries written before recency existed (#304)

    /// AC 3, first half: a store with no timestamps at all gets every entry
    /// stamped as of the moment the gap was noticed, and the stamps are written
    /// back — not recomputed on each load, which would keep legacy entries
    /// permanently fresh and invert the policy.
    func testLoadingALegacyStoreStampsEveryEntryAsOfTheUpdate() {
        let words = ["kubernetes": 2, "bonjour": 900, "zorglub": 3]
        seedStore(words: words, lastUsed: nil)

        let stamps = persistedTimestamps
        XCTAssertEqual(Set(stamps.keys), Set(words.keys), "Every learned word must carry a stamp")
        XCTAssertEqual(Set(stamps.values).count, 1, "The legacy entries form one cohort of equal recency")

        let elapsed = Self.now - (stamps["kubernetes"] ?? 0)
        XCTAssertTrue(
            (-5...60).contains(elapsed),
            "The stamp must be the moment of the update, not the epoch (elapsed: \(elapsed)s)"
        )
    }

    /// AC 3, and the constraint the migration rule exists to satisfy: shipping
    /// this change must not wipe a user's existing personal vocabulary on the
    /// first eviction. The seeded store is what a real install looks like — a
    /// mass of ordinary words with high counts plus a couple of personal words
    /// with low ones — and 100 evictions later the personal words are still there.
    ///
    /// This holds whether the new words are stamped later than the migration
    /// cohort or in the very same second: if later, the cohort is evicted oldest
    /// first; if tied, the descending-count tiebreak takes the common words first.
    /// Either way the low-count personal entries are last in line.
    func testTheFirstEvictionsAfterMigrationRemoveCommonWordsAndKeepPersonalOnes() {
        var words: [String: Int] = [:]
        for index in 0..<(UserDictionary.maxLearnedWords - 2) {
            words["common\(index)"] = 100 + index
        }
        words["kubernetes"] = 2
        words["zorglub"] = 3
        seedStore(words: words, lastUsed: nil)

        for index in 0..<100 {
            UserDictionary.shared.learn("nouveau\(index)")
        }

        XCTAssertEqual(UserDictionary.shared.count, UserDictionary.maxLearnedWords)
        XCTAssertTrue(UserDictionary.shared.isLearned("kubernetes"), "Personal vocabulary must survive")
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"), "Personal vocabulary must survive")
        XCTAssertFalse(
            UserDictionary.shared.isLearned("common997"),
            "The highest-count entry of the migrated cohort is the first to go"
        )
    }

    /// AC 3, the rejected alternative made explicit: migrated entries are treated
    /// as used at the update, NOT as maximally old. "legacy" arrives without a
    /// stamp and "ancient" arrives with a genuinely old one — the genuinely old
    /// one is what gets evicted. Had migration meant "maximally old", "legacy"
    /// would have gone first.
    func testAMigratedEntryOutranksAnEntryThatIsGenuinelyOld() {
        var words = fillers(count: UserDictionary.maxLearnedWords - 2, usageCount: 100)
        words["legacy"] = 5
        words["ancient"] = 5
        var timestamps = stamp(words, at: Self.aMinuteAgo)
        timestamps["ancient"] = Self.threeHundredDaysAgo
        timestamps.removeValue(forKey: "legacy")
        seedStore(words: words, lastUsed: timestamps)

        UserDictionary.shared.learn("nouveau")

        XCTAssertFalse(UserDictionary.shared.isLearned("ancient"))
        XCTAssertTrue(
            UserDictionary.shared.isLearned("legacy"),
            "An entry migrated on load counts as used at the update, not as maximally old"
        )
    }

    // MARK: - Timestamp bookkeeping (#304)

    func testForgettingAWordAlsoDropsItsTimestamp() {
        UserDictionary.shared.learn("zorglub")
        XCTAssertNotNil(persistedTimestamps["zorglub"])

        UserDictionary.shared.forget("zorglub")

        XCTAssertNil(persistedTimestamps["zorglub"])
    }

    /// A stamp whose word is no longer learned is dropped on load, so the
    /// timestamp map cannot outgrow the dictionary it describes.
    func testLoadingPrunesStampsForWordsThatAreNoLongerLearned() {
        seedStore(
            words: ["zorglub": 3],
            lastUsed: ["zorglub": Self.aMinuteAgo, "ghost": Self.aMinuteAgo]
        )

        XCTAssertEqual(Set(persistedTimestamps.keys), ["zorglub"])
    }
}
