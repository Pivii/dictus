// DictusCore/Tests/DictusCoreTests/UserDictionaryLoggingTests.swift
// Tests that UserDictionary's lifecycle reaches the exported log, counts only.
import XCTest
@testable import DictusCore

/// WHY these tests exist (#307): the user dictionary reported its whole lifecycle
/// with `print()`, which reaches Xcode's console and nowhere else, so no exported
/// log could say what it did. The fix is only worth anything if the lines really
/// land in `dictus_debug.log` and really carry no typed word, and neither of those
/// is provable by reading the code.
///
/// WHY they drive the real log file instead of a temp one: the acceptance criteria
/// are about what an export shows, and `PersistentLog`'s file path is not
/// injectable. On a Mac the App Group container resolves under
/// `~/Library/Group Containers/group.solutions.pivi.dictus`, so these tests write
/// and delete a host-side file that nothing reads — the log that matters is the
/// one on the device.
///
/// WHY setUp creates that directory: `FileManager.containerURL` hands back the
/// path whether or not it exists, and an unsigned test host has never had it
/// created for it. On device the container is always there. The test skips
/// rather than fails if the directory cannot be made, so a locked-down machine
/// reports "not run" instead of "broken".
///
/// WHY the assertions are on substrings of the file rather than on `LogEvent`
/// values: an event that formats correctly but never reaches the file would pass
/// the second kind of test and fail the criterion.
final class UserDictionaryLoggingTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try XCTUnwrap(AppGroup.containerURL, "No App Group container URL")
        do {
            try FileManager.default.createDirectory(
                at: container, withIntermediateDirectories: true
            )
        } catch {
            throw XCTSkip("Cannot create the App Group container on this host: \(error)")
        }
        setDeveloperToggle(false)
        UserDictionary.shared.resetAll()
        AppGroup.defaults.removeObject(forKey: UserDictionary.prunedTrieDuplicatesKey)
        clearLog()
    }

    override func tearDown() {
        setDeveloperToggle(false)
        UserDictionary.shared.resetAll()
        AppGroup.defaults.removeObject(forKey: UserDictionary.prunedTrieDuplicatesKey)
        clearLog()
        // Leave nothing behind on the host: this file is a test artifact here,
        // unlike on device where it is the log the maintainer exports.
        if let url = AppGroup.containerURL?.appendingPathComponent("dictus_debug.log") {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// `SharedKeys.autocorrectDebugLogging` — the Developer toggle in Settings.
    private func setDeveloperToggle(_ enabled: Bool) {
        AppGroup.defaults.set(enabled, forKey: SharedKeys.autocorrectDebugLogging)
    }

    /// Empty the file and forget the duplicate-collapsing run, so each test reads
    /// only its own lines.
    private func clearLog() {
        PersistentLog.clear()
        PersistentLog.resetCollapseStateForTesting()
    }

    /// The log file's contents, with every queued write on disk first.
    private func logContents() -> String {
        PersistentLog.flush()
        return PersistentLog.read()
    }

    /// Seeds a store through the App Group keys and reloads, the way
    /// `UserDictionaryTests` does. Pass `lastUsed: nil` for a store written before
    /// recency existed (#304).
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

    private func fillers(count: Int, usageCount: Int) -> [String: Int] {
        var words: [String: Int] = [:]
        for index in 0..<count {
            words["filler\(index)"] = usageCount
        }
        return words
    }

    private func assertLogContains(_ needle: String, _ log: String, line: UInt = #line) {
        XCTAssertTrue(
            log.contains(needle),
            "Expected the log to contain \"\(needle)\".\n--- log ---\n\(log)",
            line: line
        )
    }

    private func assertLogNamesNoWord(_ words: [String], _ log: String, line: UInt = #line) {
        for word in words {
            XCTAssertFalse(
                log.contains(word),
                "The privacy-safe log named the word \"\(word)\".\n--- log ---\n\(log)",
                line: line
            )
        }
    }

    // MARK: - AC 1 and 2: counts reach the export, words do not

    func testLearningReportsTheDictionarySizeAndNotTheWord() {
        UserDictionary.shared.learn("zorglub")
        UserDictionary.shared.learn("kubernetes")

        let log = logContents()
        assertLogContains("userDictionaryWordLearned learnedCount=1", log)
        assertLogContains("userDictionaryWordLearned learnedCount=2", log)
        assertLogNamesNoWord(["zorglub", "kubernetes"], log)
    }

    /// The promotion path the keyboard actually runs on every word boundary.
    func testRecordUsageReportsALearnedWordAndNotTheWord() {
        for _ in 0..<UserDictionary.repetitionThreshold {
            UserDictionary.shared.recordUsage("zorglub")
        }

        let log = logContents()
        assertLogContains("userDictionaryWordLearned learnedCount=1", log)
        assertLogNamesNoWord(["zorglub"], log)
    }

    /// A word already in the dictionary is a usage bump, not a learning event.
    /// Without this the log would report a "learned" line on nearly every word
    /// boundary once the dictionary is warm.
    func testBumpingAnAlreadyLearnedWordReportsNothing() {
        UserDictionary.shared.learn("zorglub")
        clearLog()

        UserDictionary.shared.recordUsage("zorglub")
        UserDictionary.shared.learn("zorglub")

        XCTAssertFalse(logContents().contains("userDictionaryWordLearned"))
    }

    func testEvictionReportsHowManyEntriesItRemovedAndNotWhich() {
        let cap = UserDictionary.maxLearnedWords
        let words = fillers(count: cap, usageCount: 5)
        let stamp = Int(Date().timeIntervalSince1970) - 86_400
        seedStore(words: words, lastUsed: words.mapValues { _ in stamp })
        clearLog()

        UserDictionary.shared.learn("nouveau")

        let log = logContents()
        assertLogContains("userDictionaryEvicted removed=1 learnedCount=\(cap) cap=\(cap)", log)
        assertLogNamesNoWord(["filler", "nouveau"], log)
    }

    func testResetReportsHowManyWordsItClearedAndNotWhich() {
        UserDictionary.shared.learn("zorglub")
        UserDictionary.shared.learn("kubernetes")
        clearLog()

        UserDictionary.shared.resetAll()

        let log = logContents()
        assertLogContains("userDictionaryReset clearedCount=2", log)
        assertLogNamesNoWord(["zorglub", "kubernetes"], log)
    }

    /// The criterion that started this issue: device-validating #304 meant asking
    /// whether an existing install's vocabulary survived the update, and the log
    /// could not say. Now it can, by count.
    func testMigrationReportsHowManyLegacyEntriesItStampedAndNotWhich() {
        seedStore(words: ["kubernetes": 2, "bonjour": 900, "zorglub": 3], lastUsed: nil)

        let log = logContents()
        assertLogContains("userDictionaryMigrated stamped=3 droppedStamps=0 learnedCount=3", log)
        assertLogNamesNoWord(["kubernetes", "bonjour", "zorglub"], log)
    }

    /// The two removals #287 added report the same way: a count in every build,
    /// the words only behind the Developer toggle.
    func testTheStaleDiscardReportsHowManyEntriesItDroppedAndNotWhich() {
        let old = Int(Date().timeIntervalSince1970) - 301 * 86_400
        seedStore(words: ["oublie": 2, "zorglub": 3], lastUsed: ["oublie": old, "zorglub": Int(Date().timeIntervalSince1970)])

        let log = logContents()
        assertLogContains("userDictionaryStaleDiscarded removed=1 learnedCount=1 days=300", log)
        assertLogNamesNoWord(["oublie", "zorglub"], log)
    }

    /// The line that lets an export answer "what did the migration take off me",
    /// which is the only recourse a user has: #287 decision 6 ships no per-word
    /// removal UI, so nothing else can name what disappeared.
    func testThePruneReportsHowManyDuplicatesItRemovedAndNotWhich() {
        seedStore(words: ["le": 40, "zorglub": 3], lastUsed: nil)
        clearLog()

        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(
            using: MockFrequencyProvider(frequencies: ["le": 5000])
        )

        let log = logContents()
        assertLogContains("userDictionaryPruned removed=1 learnedCount=1", log)
        assertLogNamesNoWord(["zorglub"], log)
    }

    /// `reload()` runs on every keyboard appearance, so a store that is already
    /// stamped must report nothing at all — otherwise the line is noise on a path
    /// that runs constantly (#255).
    func testLoadingAnAlreadyStampedStoreReportsNothing() {
        let now = Int(Date().timeIntervalSince1970)
        seedStore(words: ["zorglub": 3], lastUsed: ["zorglub": now])
        clearLog()

        UserDictionary.shared.reload()

        XCTAssertFalse(logContents().contains("userDictionaryMigrated"))
    }

    // MARK: - AC 3: the Developer toggle adds the words

    /// With the toggle on, in a Debug build, the same four events additionally
    /// name the words involved. The `USERDICT-` lines below come from
    /// `AutocorrectDebugLog`, which does not exist in a Release binary.
    func testWithTheDeveloperToggleOnTheEventsNameTheWords() {
        setDeveloperToggle(true)

        // Learned.
        UserDictionary.shared.learn("zorglub")
        assertLogContains("USERDICT-LEARN word=\"zorglub\" count=1 learnedCount=1", logContents())

        // Migrated: a legacy store arriving without timestamps.
        clearLog()
        seedStore(words: ["kubernetes": 2], lastUsed: nil)
        assertLogContains("USERDICT-MIGRATE words=[\"kubernetes\"]", logContents())

        // Evicted.
        clearLog()
        let cap = UserDictionary.maxLearnedWords
        var words = fillers(count: cap - 1, usageCount: 5)
        words["oubliable"] = 900
        let stamp = Int(Date().timeIntervalSince1970) - 86_400
        var stamps = words.mapValues { _ in stamp }
        stamps["oubliable"] = stamp - 86_400
        seedStore(words: words, lastUsed: stamps)
        clearLog()
        UserDictionary.shared.learn("nouveau")
        assertLogContains("USERDICT-EVICT words=[\"oubliable\"]", logContents())

        // Discarded for going stale, and pruned as a duplicate of the base
        // dictionary — the two removals #287 added.
        UserDictionary.shared.resetAll()
        let old = Int(Date().timeIntervalSince1970) - 301 * 86_400
        clearLog()
        seedStore(words: ["oublie": 2], lastUsed: ["oublie": old])
        assertLogContains("USERDICT-STALE words=[\"oublie\"]", logContents())

        AppGroup.defaults.removeObject(forKey: UserDictionary.prunedTrieDuplicatesKey)
        seedStore(words: ["le": 40], lastUsed: nil)
        clearLog()
        UserDictionary.shared.pruneTrieDuplicatesIfNeeded(
            using: MockFrequencyProvider(frequencies: ["le": 5000])
        )
        assertLogContains("USERDICT-PRUNE words=[\"le\"]", logContents())

        // Reset.
        UserDictionary.shared.resetAll()
        UserDictionary.shared.learn("zorglub")
        UserDictionary.shared.learn("kubernetes")
        clearLog()
        UserDictionary.shared.resetAll()
        assertLogContains("USERDICT-RESET words=[\"kubernetes\", \"zorglub\"]", logContents())
    }
}
