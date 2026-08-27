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
        clearStore()
    }

    override func tearDown() {
        clearStore()
        super.tearDown()
    }

    /// The one-shot prune flag outlives the dictionary it describes, so a clean
    /// slate has to clear it too — otherwise the first test to run a prune would
    /// be the only one that could.
    private func clearStore() {
        UserDictionary.shared.resetAll()
        AppGroup.defaults.removeObject(forKey: UserDictionary.prunedTrieDuplicatesKey)
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

    /// Un-skipped by #287: at a threshold of 1 there was no below-threshold call
    /// to observe, which is the whole reason the counter was dead as a gate.
    func testRecordUsageBelowTheThresholdDoesNotLearnTheWord() {
        let word = "zorglub"
        XCTAssertFalse(UserDictionary.shared.recordUsage(word))
        XCTAssertFalse(UserDictionary.shared.isLearned(word))
    }

    /// The observable rule the two sites are held to (#287 decisions 3 and 4):
    /// the word-boundary path learns on the second occurrence, the undo path on
    /// the first.
    func testTypingTwiceLearnsAWordThatTypingOnceDoesNot() {
        XCTAssertFalse(UserDictionary.shared.recordUsage("zorglub"))
        XCTAssertFalse(UserDictionary.shared.isLearned("zorglub"))

        XCTAssertTrue(UserDictionary.shared.recordUsage("zorglub"))
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))
    }

    func testLearnRecordsAWordOnItsFirstOccurrence() {
        XCTAssertTrue(UserDictionary.shared.learn("zorglub"), "The call creating the entry reports it")
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))

        XCTAssertFalse(
            UserDictionary.shared.learn("zorglub"),
            "A second call is a usage bump, not a new entry"
        )
        XCTAssertEqual(UserDictionary.shared.allLearnedWords["zorglub"], 2)
    }

    // MARK: - Bounding the probation pad (#287)

    /// Raising the threshold above 1 is what brings `pendingWords` to life, and
    /// what reaches it is mostly typos that never come back for a second
    /// occurrence. Without a bound the pad would grow for the life of the install
    /// and be re-serialised on every word boundary.
    func testThePendingPadIsBounded() {
        for index in 0...UserDictionary.maxPendingWords {
            UserDictionary.shared.recordUsage("pending\(index)")
        }

        let pending = AppGroup.defaults.dictionary(forKey: UserDictionary.pendingKey) as? [String: Int] ?? [:]
        XCTAssertLessThanOrEqual(pending.count, UserDictionary.maxPendingWords)
        XCTAssertEqual(UserDictionary.shared.count, 0, "Nothing was typed twice, so nothing is learned")
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
    /// Old enough to lose an eviction, young enough to survive the stale discard.
    private static let twoHundredDaysAgo = now - 200 * 86_400
    private static let threeHundredAndOneDaysAgo = now - 301 * 86_400

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
        timestamps["ancient"] = Self.twoHundredDaysAgo
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

    // MARK: - Discarding entries unused for 300 days (#287)

    func testLoadingDiscardsAnEntryUnusedForLongerThanTheStalePeriod() {
        seedStore(
            words: ["zorglub": 3, "oublie": 2],
            lastUsed: ["zorglub": Self.aMinuteAgo, "oublie": Self.threeHundredAndOneDaysAgo]
        )

        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))
        XCTAssertFalse(UserDictionary.shared.isLearned("oublie"))
        XCTAssertNil(persistedTimestamps["oublie"], "The discarded entry takes its stamp with it")
    }

    func testLoadingKeepsAnEntryStillInsideTheStalePeriod() {
        seedStore(words: ["oublie": 2], lastUsed: ["oublie": Self.twoHundredDaysAgo])

        XCTAssertTrue(UserDictionary.shared.isLearned("oublie"))
    }

    /// The cutoff is inclusive: an entry stamped exactly `staleAfterDays` ago has
    /// had the full period elapse.
    ///
    /// WHY the stamp is computed here rather than from the fixtures above: those
    /// are captured once when the class loads, and the load being tested reads
    /// its own clock, so a fixture would sit a few seconds *past* the cutoff and
    /// the boundary would never actually be exercised. Taken as late as possible
    /// the entry lands on the cutoff or a second past it — never inside it — so
    /// this assertion is the right one either way, and it fails outright on a
    /// strict comparison whenever the two clock reads land in the same second.
    func testLoadingDiscardsAnEntryStampedExactlyAtTheCutoff() {
        let cutoff = Int(Date().timeIntervalSince1970) - UserDictionary.staleAfterDays * 86_400
        seedStore(words: ["oublie": 2], lastUsed: ["oublie": cutoff])

        XCTAssertFalse(UserDictionary.shared.isLearned("oublie"))
    }

    /// The interaction that would be silently destructive if the two load steps
    /// ran the other way round: a dictionary written before recency existed has
    /// no stamps at all, and #305 stamps it as of the update. Discarding first
    /// would read those entries as maximally old and delete every one of them on
    /// the first launch after this ships.
    func testALegacyStoreSurvivesItsFirstLoad() {
        seedStore(words: ["kubernetes": 2, "zorglub": 3], lastUsed: nil)

        XCTAssertTrue(UserDictionary.shared.isLearned("kubernetes"))
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))
    }

    // MARK: - The one-shot prune of base-dictionary duplicates (#287)

    /// The store as an existing install carries it: mostly words the base
    /// dictionary already knows, plus the handful of personal ones the feature
    /// exists for.
    private func seedForPrune() {
        seedStore(
            words: ["le": 40, "chat": 12, "pomme": 8, "kubernetes": 2, "zorglub": 3],
            lastUsed: nil
        )
    }

    /// The base dictionary as the corrector sees it: "j'ai" is stored as "ai",
    /// which is why the prune asks about the part after the apostrophe.
    private var frenchWords: MockFrequencyProvider {
        MockFrequencyProvider(frequencies: ["le": 5000, "chat": 900, "pomme": 400, "ai": 8000])
    }

    func testThePruneRemovesEntriesTheBaseDictionaryAlreadyKnows() {
        seedForPrune()

        let removed = UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)

        XCTAssertEqual(removed, 3)
        XCTAssertFalse(UserDictionary.shared.isLearned("le"))
        XCTAssertFalse(UserDictionary.shared.isLearned("chat"))
        XCTAssertFalse(UserDictionary.shared.isLearned("pomme"))
        XCTAssertTrue(UserDictionary.shared.isLearned("kubernetes"), "Personal vocabulary is what survives")
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))
        XCTAssertEqual(Set(persistedTimestamps.keys), ["kubernetes", "zorglub"])
    }

    /// An entry is judged on the part the dictionary actually stores, the same
    /// split `spellCheck` makes before its `already-valid` skip. Without this,
    /// "j'ai" would sit in the dictionary forever: the prune would keep it and no
    /// reader would ever look it up under that spelling.
    func testThePruneJudgesAContractionOnThePartAfterTheApostrophe() {
        seedStore(words: ["j'ai": 12, "zorglub": 3], lastUsed: nil)

        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)

        XCTAssertFalse(UserDictionary.shared.isLearned("j'ai"))
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))
    }

    /// It runs once and never again. This is what bounds the exposure for a user
    /// who types in more than one language: the prune can only offer the active
    /// language's dictionary, so a second run under a second language could
    /// delete what the first language's user had just re-learned.
    func testThePruneRunsOnlyOnce() {
        seedForPrune()
        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)

        UserDictionary.shared.learn("chat")
        let removedAgain = UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)

        XCTAssertEqual(removedAgain, 0)
        XCTAssertTrue(
            UserDictionary.shared.isLearned("chat"),
            "A word deliberately learned after the prune is not taken away again"
        )
    }

    /// A provider that cannot answer is not asked, and the flag stays clear so
    /// the prune waits for a load that can. The trie loads asynchronously and is
    /// unloaded synchronously by the next load request, so this is the state the
    /// keyboard is genuinely in for much of a session — it is what kept the prune
    /// from ever running on device off the load completion alone.
    func testThePruneWaitsForADictionaryThatIsReady() {
        seedForPrune()
        let stillLoading = MockFrequencyProvider(isReady: false, frequencies: ["le": 5000])

        XCTAssertEqual(UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: stillLoading), 0)
        XCTAssertTrue(UserDictionary.shared.isLearned("le"))
        XCTAssertFalse(
            UserDictionary.shared.hasPrunedTrieDuplicates,
            "A declined attempt must not consume the one shot"
        )

        XCTAssertEqual(UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords), 3)
        XCTAssertTrue(UserDictionary.shared.hasPrunedTrieDuplicates)
    }

    /// The flag is what the keyboard reads to decide whether it still owes a
    /// prune, so it has to report the same thing the guard inside acts on — and
    /// it has to survive a dictionary that ends up empty, which is the fresh
    /// install case.
    func testAPruneWithNothingToRemoveStillConsumesTheOneShot() {
        XCTAssertFalse(UserDictionary.shared.hasPrunedTrieDuplicates)

        XCTAssertEqual(UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords), 0)

        XCTAssertTrue(UserDictionary.shared.hasPrunedTrieDuplicates)
    }

    /// Resetting the dictionary re-arms the prune, because the flag describes a
    /// dictionary that no longer exists. It is also the only way a device that
    /// has already pruned can show that the mechanism still works.
    func testResettingTheDictionaryReArmsThePrune() {
        seedForPrune()
        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)
        XCTAssertTrue(UserDictionary.shared.hasPrunedTrieDuplicates)

        UserDictionary.shared.resetAll()

        XCTAssertFalse(UserDictionary.shared.hasPrunedTrieDuplicates)
    }

    /// Re-arming is safe, which is what makes it worth doing: everything learned
    /// after a reset is absent from the base dictionary by construction — the
    /// boundary site gates on exactly that, and a word restored by undo was never
    /// in the dictionary to begin with — so the next prune has nothing to take.
    func testThePruneAfterAResetHasNothingToTake() {
        seedForPrune()
        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)
        UserDictionary.shared.resetAll()

        UserDictionary.shared.learn("zorglub")
        UserDictionary.shared.recordUsage("kubernetes")
        UserDictionary.shared.recordUsage("kubernetes")

        XCTAssertEqual(UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords), 0)
        XCTAssertTrue(UserDictionary.shared.isLearned("zorglub"))
        XCTAssertTrue(UserDictionary.shared.isLearned("kubernetes"))
    }

    /// A word held in probation is the same class of entry and follows the same
    /// rule, so the prune must not leave one behind to be promoted into a
    /// duplicate on its next occurrence.
    func testThePruneAlsoClearsProbationEntriesTheDictionaryKnows() {
        seedStore(words: ["zorglub": 3], lastUsed: nil)
        UserDictionary.shared.recordUsage("pomme")

        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: frenchWords)
        UserDictionary.shared.recordUsage("pomme")

        XCTAssertFalse(
            UserDictionary.shared.isLearned("pomme"),
            "The second occurrence starts probation over instead of promoting a duplicate"
        )
    }
}
