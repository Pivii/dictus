// DictusCore/Sources/DictusCore/UserDictionary.swift
// Persistent user-learned words dictionary stored in App Group.
import Foundation

/// Stores words the user has taught the keyboard through usage patterns.
///
/// WHAT BELONGS IN IT (#287):
/// Only words the base dictionary does not know. A learned word is immune from
/// autocorrect for as long as it is in here, and #288 will propagate this set
/// into speech recognition — so an entry that merely duplicates the trie costs
/// storage, a write per word boundary, and a wrong word in another subsystem,
/// while protecting nothing (the trie never corrects a word it knows).
///
/// HOW WORDS ARE LEARNED:
/// 1. Rejection learning: user types "helo" → autocorrected to "hello" → the
///    user rejects the correction → `learn()` records "helo" on that single
///    occurrence. The user stated what they meant, so no repetition is asked for.
/// 2. Repetition learning: the user types a word the trie does not know and the
///    pipeline declines to correct → `recordUsage()` counts it, and the word is
///    learned on the `repetitionThreshold`-th occurrence. The caller is the one
///    that checks the trie (see `recordUsage`) — passive typing says nothing on
///    its own, so it buys the weaker evidence a second occurrence.
///
/// HOW WORDS ARE FORGOTTEN:
/// Three bounds, none of which needs the user to do anything (#287 decisions 6
/// and 7 — there is deliberately no per-word removal UI, so an entry that should
/// not be there has to age out on its own):
/// - the dictionary is capped at `maxLearnedWords`, and past the cap the
///   least-recently-used entries are dropped — see `shouldEvictFirst()` for why
///   recency and not usage count;
/// - an entry not used for `staleAfterDays` is discarded on load;
/// - entries the base dictionary already knows are pruned once, on the first
///   load that can ask a loaded dictionary — see `pruneTrieDuplicatesIfNeeded`.
///
/// HOW THE LIFECYCLE IS REPORTED (#307):
/// Every event above — learning, eviction, reset, the load-time migration, the
/// stale discard and the duplicate prune — writes two lines: a count to
/// `PersistentLog`, which any exported log carries, and the words themselves to
/// `AutocorrectDebugLog`, which only exists in Debug builds and only writes once
/// the Developer toggle is on. See `logLearned()`.
///
/// WHY App Group UserDefaults:
/// The dictionary must be shared between DictusApp and DictusKeyboard extension.
/// UserDefaults via App Group is the simplest cross-process storage on iOS.
/// For a typical user dictionary (hundreds to low thousands of words), the
/// serialization overhead is negligible.
///
/// WHY a separate class in DictusCore:
/// Both the keyboard extension (for learning + lookup) and the main app
/// (for a future "manage learned words" UI) need access to the same data.
public final class UserDictionary {

    /// Singleton shared instance. Uses App Group storage.
    public static let shared = UserDictionary()

    /// Key in App Group UserDefaults for the learned words dictionary.
    /// Stored as [String: Int] where key = lowercase word, value = usage count.
    ///
    /// WHY the keys are internal rather than private: the tests seed a store
    /// through this exact key to reproduce a dictionary written by an earlier
    /// build. Doing it that way exercises the real load path instead of adding
    /// a test-only entry point to the production API.
    static let storageKey = "dictus.userDictionary"

    /// Key for the repetition counter (words being "observed" before learning).
    /// Stored as [String: Int] where key = lowercase word, value = times typed.
    static let pendingKey = "dictus.userDictionary.pending"

    /// Key for the per-entry last-used timestamps.
    /// Stored as [String: Int] where key = lowercase word, value = seconds
    /// since 1970.
    ///
    /// WHY a parallel key instead of a richer value inside `storageKey`:
    /// `storageKey` has to keep its exact [String: Int] shape. #103's iCloud
    /// key-value merge strategy reads it as word → count and resolves conflicts
    /// with max(count), and an older build of the app or the extension must
    /// still decode the store it finds. Splitting recency into its own key
    /// leaves both of those working unchanged — a reader that knows nothing
    /// about recency simply ignores this key. It is also the cheapest shape to
    /// serialise, which matters because `saveToDefaults()` runs on every word
    /// boundary.
    static let lastUsedKey = "dictus.userDictionary.lastUsed"

    /// Key for the one-shot flag recording that the trie-duplicate prune has run.
    /// See `pruneTrieDuplicatesIfNeeded(using:)`.
    static let prunedTrieDuplicatesKey = "dictus.userDictionary.prunedTrieDuplicates"

    /// Number of times a word the base dictionary does not know must be typed
    /// before `recordUsage` learns it (#287 decision 3).
    ///
    /// WHY 2 and not 1: at 1 the `pendingWords` counter below could never hold
    /// anything, so passive typing — which states nothing about intent — was
    /// enough to grant a word permanent immunity from autocorrect. Two
    /// occurrences is the probation AOSP LatinIME uses for the same signal, and
    /// it is the cheapest gate that costs no new stored data.
    ///
    /// This threshold gates `recordUsage` only. Rejecting an autocorrection is a
    /// different, much stronger signal and goes through `learn()`, which is not
    /// subject to it.
    public static let repetitionThreshold = 2

    /// Maximum number of learned words. When exceeded, the least-recently-used
    /// words are dropped — see `shouldEvictFirst()`.
    /// 1000 words ≈ 30 KB in UserDefaults — negligible for memory.
    /// Generous cap for personal vocabulary (names, slang, jargon, brands).
    /// Prevents unbounded growth from accidental learning over months/years.
    public static let maxLearnedWords = 1000

    /// Maximum number of words held in probation at once.
    ///
    /// WHY a cap exists at all: raising `repetitionThreshold` above 1 is what
    /// brings `pendingWords` to life, and everything that reaches it is by
    /// definition a word the base dictionary does not know — a name, a piece of
    /// jargon, or a typo the corrector had no candidate for. Typos never come
    /// back for a second occurrence, so without a bound the pad would grow for
    /// the life of the install, and `savePendingToDefaults()` runs on every word
    /// boundary.
    ///
    /// WHY half the learned cap: a pending entry is weaker evidence than a
    /// learned one, so it deserves less room than the vocabulary it feeds.
    static let maxPendingWords = 500

    /// A learned word unused for this long is discarded on load (#287 decision 7).
    ///
    /// WHY 300 days: it is AOSP LatinIME's own constant for the same policy, and
    /// what actually ships there — its documented forgetting curve is dead code
    /// at HEAD, so a flat discard plus the recency eviction above is the whole of
    /// the mechanism worth copying. See `docs/research/287-user-dictionary-learning.md`.
    ///
    /// WHY a keyboard needs one: decision 6 leaves "Reset learned words" as the
    /// only exit, so a wrong entry the user cannot see has no other way out.
    static let staleAfterDays = 300

    /// In-memory cache of learned words. Synced to UserDefaults on mutation.
    private var learnedWords: [String: Int] = [:]

    /// Last-used timestamp per learned word, in seconds since 1970.
    ///
    /// INVARIANT: every key of `learnedWords` has an entry here. The invariant
    /// is repaired on load rather than assumed — see `stampEntriesMissingATimestamp()`.
    private var lastUsed: [String: Int] = [:]

    /// Temporary counter for words being observed (not yet learned).
    private var pendingWords: [String: Int] = [:]

    private init() {
        loadFromDefaults()
    }

    // MARK: - Public API

    /// Whether a word has been learned by the user.
    public func isLearned(_ word: String) -> Bool {
        learnedWords[word.lowercased()] != nil
    }

    /// All learned words with their usage counts.
    /// Useful for a future "manage dictionary" UI in the app.
    public var allLearnedWords: [String: Int] {
        learnedWords
    }

    /// Number of learned words.
    public var count: Int { learnedWords.count }

    /// Whether the one-shot duplicate prune has already run on this install.
    ///
    /// WHY it is public: the prune needs a loaded base dictionary, which only the
    /// keyboard extension has, and only at moments it does not control. Its
    /// callers use this to know whether there is still anything to attempt — so
    /// they can stay silent once there is not, and report when there is and they
    /// cannot.
    public var hasPrunedTrieDuplicates: Bool {
        AppGroup.defaults.bool(forKey: Self.prunedTrieDuplicatesKey)
    }

    /// Learn a word on this single occurrence, bypassing the repetition counter.
    /// The word is stored lowercase. If already learned, increments usage count.
    /// Returns true when this call created the entry.
    ///
    /// WHY this bypasses `repetitionThreshold` while `recordUsage` does not
    /// (#287 decision 4): the caller is the undo of an applied autocorrection,
    /// where the user has explicitly said "no, I meant this word". That is the
    /// same trigger Apple documents for its own keyboard dictionary, and asking
    /// for a second occurrence would mean rejecting the same correction twice
    /// before the keyboard stopped making it.
    @discardableResult
    public func learn(_ word: String) -> Bool {
        let key = word.lowercased()
        guard !key.isEmpty, key.count > 1 else { return false }
        // A word already in the dictionary is a usage bump, not a learning event,
        // so only a first entry is reported below.
        let isNew = learnedWords[key] == nil
        learnedWords[key, default: 0] += 1
        let usageCount = learnedWords[key] ?? 1
        lastUsed[key] = Self.nowStamp()
        // Remove from pending if it was being tracked
        pendingWords.removeValue(forKey: key)
        saveToDefaults()
        if isNew {
            logLearned(key, usageCount: usageCount)
        }
        return isNew
    }

    /// Record that a word the base dictionary does not know was typed. If it
    /// reaches the repetition threshold, it's automatically learned. Returns true
    /// if the word was just learned (crossed the threshold this call).
    ///
    /// The caller is responsible for the trie check (#287 decision 2). It is not
    /// done here on purpose: `learn()`'s caller must NOT be subject to it — a word
    /// restored by undoing an autocorrection is absent from the trie by
    /// construction — and expressing that would mean handing `UserDictionary` a
    /// `FrequencyProvider` to make the two call sites share a rule only one of
    /// them wants.
    @discardableResult
    public func recordUsage(_ word: String) -> Bool {
        let key = word.lowercased()
        guard !key.isEmpty, key.count > 1 else { return false }

        // Already learned — just bump usage count
        if let learnedCount = learnedWords[key] {
            learnedWords[key] = learnedCount + 1
            lastUsed[key] = Self.nowStamp()
            saveToDefaults()
            return false
        }

        // Increment pending counter, keeping the new value to decide below.
        let pendingCount = (pendingWords[key] ?? 0) + 1
        pendingWords[key] = pendingCount

        if pendingCount >= Self.repetitionThreshold {
            // Threshold reached — promote to learned
            learnedWords[key] = pendingCount
            lastUsed[key] = Self.nowStamp()
            pendingWords.removeValue(forKey: key)
            saveToDefaults()
            logLearned(key, usageCount: pendingCount)
            return true
        }

        boundPendingWords()
        savePendingToDefaults()
        return false
    }

    /// Keeps the probation pad bounded — see `maxPendingWords`.
    ///
    /// WHY it empties the pad instead of picking victims: at a threshold of 2
    /// every pending entry has been seen exactly once, so there is nothing to
    /// rank them by. The alternative would be a second timestamp map for entries
    /// that are not even vocabulary yet. Emptying costs the words in flight one
    /// extra occurrence, which is the cheapest possible failure for a memo pad.
    private func boundPendingWords() {
        guard pendingWords.count > Self.maxPendingWords else { return }
        pendingWords.removeAll()
    }

    /// Remove a learned word (e.g., user removes it from dictionary management UI).
    public func forget(_ word: String) {
        let key = word.lowercased()
        learnedWords.removeValue(forKey: key)
        lastUsed.removeValue(forKey: key)
        pendingWords.removeValue(forKey: key)
        saveToDefaults()
    }

    /// Remove all learned words and pending observations.
    /// Useful for a "Reset keyboard dictionary" option in settings.
    public func resetAll() {
        let clearedCount = learnedWords.count
        // Snapshotting the words costs an allocation the size of the dictionary,
        // so it happens in Debug builds only — the count above is what every
        // build reports.
        #if DEBUG
        let clearedWords = Array(learnedWords.keys)
        #endif

        learnedWords.removeAll()
        lastUsed.removeAll()
        pendingWords.removeAll()
        saveToDefaults()

        PersistentLog.log(.userDictionaryReset(clearedCount: clearedCount))
        #if DEBUG
        AutocorrectDebugLog.userDictionaryReset(words: clearedWords)
        #endif
    }

    /// Reload from App Group (useful if the other process updated the dictionary).
    public func reload() {
        loadFromDefaults()
    }

    // MARK: - Reporting

    /// Report a word entering the dictionary (#307).
    ///
    /// WHY two loggers and not one: `LogEvent` is privacy-safe by construction and
    /// ships in every build, so it carries the counts — which is what an exported
    /// log needs to answer "how big did this dictionary get, and did it evict".
    /// The word itself is user content and goes only to `AutocorrectDebugLog`,
    /// which does not exist in a Release binary and is a no-op until the Developer
    /// toggle is on. Every reporting site in this file follows that split.
    ///
    /// Called after `saveToDefaults()` so `learnedWords.count` is the size the
    /// dictionary settled at, eviction included.
    private func logLearned(_ key: String, usageCount: Int) {
        PersistentLog.log(.userDictionaryWordLearned(learnedCount: learnedWords.count))
        #if DEBUG
        AutocorrectDebugLog.userDictionaryLearned(
            word: key,
            usageCount: usageCount,
            learnedCount: learnedWords.count
        )
        #endif
    }

    // MARK: - Persistence

    /// Current time as stored in `lastUsed`. Second resolution: the eviction
    /// order only needs to tell days apart, and same-second ties have a defined
    /// tiebreak anyway.
    private static func nowStamp() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    private func loadFromDefaults() {
        let defaults = AppGroup.defaults
        learnedWords = defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:]
        pendingWords = defaults.dictionary(forKey: Self.pendingKey) as? [String: Int] ?? [:]
        lastUsed = defaults.dictionary(forKey: Self.lastUsedKey) as? [String: Int] ?? [:]
        stampEntriesMissingATimestamp()
        discardStaleEntries()
    }

    /// Drops entries unused for `staleAfterDays` (#287 decision 7).
    ///
    /// WHY it runs after `stampEntriesMissingATimestamp()` and not before: that
    /// migration stamps a legacy entry with **the moment the gap was noticed**,
    /// not with a maximally old value, so a dictionary written before recency
    /// existed arrives here fully stamped as of now and nothing in it is old
    /// enough to discard. Running this first would delete the entire cohort on
    /// the first launch after the update.
    ///
    /// WHY on every load rather than once: this is a standing policy, not a
    /// version step. It is also the only thing that ever removes a wrong entry
    /// below the cap, since #287 decision 6 deliberately ships no per-word
    /// removal UI.
    private func discardStaleEntries() {
        let cutoff = Self.nowStamp() - Self.staleAfterDays * 86_400
        // `<=` and not `<`: an entry stamped exactly at the cutoff has had the
        // full period elapse, so it goes. `?? 0` cannot fire — every learned word
        // carries a stamp by the time this runs. Treating an unstamped entry as
        // maximally old is the safe reading if that ever breaks: it discards an
        // entry rather than keeping one forever with no way to remove it.
        let stale = learnedWords.keys.filter { (lastUsed[$0] ?? 0) <= cutoff }
        guard !stale.isEmpty else { return }

        for word in stale {
            learnedWords.removeValue(forKey: word)
            lastUsed.removeValue(forKey: word)
        }
        let defaults = AppGroup.defaults
        defaults.set(learnedWords, forKey: Self.storageKey)
        defaults.set(lastUsed, forKey: Self.lastUsedKey)

        PersistentLog.log(.userDictionaryStaleDiscarded(
            removed: stale.count,
            learnedCount: learnedWords.count,
            days: Self.staleAfterDays
        ))
        #if DEBUG
        AutocorrectDebugLog.userDictionaryStaleDiscarded(words: stale)
        #endif
    }

    /// Removes, once ever, every entry the base dictionary already knows
    /// (#287 decision 9). Returns how many entries were dropped.
    ///
    /// WHY this is safe: a word present in the base dictionary is never
    /// autocorrected — `TextPredictionEngine.spellCheck` returns nil at its
    /// `already-valid` branch before any candidate is generated — so the entry's
    /// immunity was protecting nothing. And a word learned by rejecting an
    /// autocorrection is absent from the dictionary by construction, since
    /// otherwise there would have been no correction to reject.
    ///
    /// WHY once and not on every load: the caller can only offer the *active*
    /// language's dictionary. Running repeatedly would delete a bilingual user's
    /// other-language entries again after each re-learning, which is a churn loop;
    /// running once bounds the exposure to a single pass, and normal learning
    /// puts back anything it took (see the PR for the full argument).
    ///
    /// - Parameter provider: the loaded base dictionary. A provider that is not
    ///   ready is not asked and the flag is not set, so the prune simply waits
    ///   for a load that can answer.
    @discardableResult
    public func pruneTrieDuplicatesIfNeeded(using provider: FrequencyProvider) -> Int {
        let defaults = AppGroup.defaults
        guard !hasPrunedTrieDuplicates, provider.isReady else {
            return 0
        }

        let duplicates = learnedWords.keys.filter { provider.knowsWord($0) }
        for word in duplicates {
            learnedWords.removeValue(forKey: word)
            lastUsed.removeValue(forKey: word)
        }
        // The pad holds the same class of entry and is subject to the same rule,
        // so a word about to be promoted into a duplicate is dropped with them.
        pendingWords = pendingWords.filter { !provider.knowsWord($0.key) }

        defaults.set(true, forKey: Self.prunedTrieDuplicatesKey)
        defaults.set(learnedWords, forKey: Self.storageKey)
        defaults.set(lastUsed, forKey: Self.lastUsedKey)
        defaults.set(pendingWords, forKey: Self.pendingKey)

        PersistentLog.log(.userDictionaryPruned(
            removed: duplicates.count,
            learnedCount: learnedWords.count
        ))
        #if DEBUG
        AutocorrectDebugLog.userDictionaryPruned(words: duplicates)
        #endif
        return duplicates.count
    }

    /// MIGRATION RULE for entries written before recency existed: a learned word
    /// found without a timestamp is stamped with the moment the gap was noticed,
    /// and that stamp is persisted. In other words, **the update itself counts as
    /// their last use.**
    ///
    /// WHY not "maximally old", the obvious alternative: it would put the user's
    /// entire existing dictionary at the front of the eviction queue, so the
    /// first overflow after shipping this change would delete their personal
    /// vocabulary wholesale — the exact damage this change exists to stop.
    ///
    /// WHY the migrated cohort is still safe when it eventually gets cut: every
    /// legacy entry shares one timestamp, so they are all ties, and ties break by
    /// descending usage count (see `shouldEvictFirst()`). The first legacy entries
    /// to go are therefore the most-typed ones — ordinary words the trie already
    /// knows — and the low-count names and jargon are the last of the cohort to
    /// go. Anything the user types after the update gets a fresh stamp and leaves
    /// the cohort entirely.
    ///
    /// WHY the stamp is persisted rather than recomputed on each load: a stamp
    /// recomputed as "now" every time would keep legacy entries permanently
    /// fresh, so they would never age out and newer words would be evicted
    /// instead — the policy inverted.
    ///
    /// WHY this runs on every load and not behind a one-shot migration flag: it
    /// is an invariant repair, not a version step. It also covers an entry
    /// written by an older build of the other process, which knows nothing about
    /// `lastUsedKey`.
    private func stampEntriesMissingATimestamp() {
        let before = lastUsed
        let stamp = Self.nowStamp()
        // Collecting the stamped words costs nothing in the steady state, which is
        // the only case that runs often: past the first load there is nothing left
        // to stamp and this array stays empty.
        var stampedWords: [String] = []
        for word in learnedWords.keys where lastUsed[word] == nil {
            lastUsed[word] = stamp
            stampedWords.append(word)
        }
        // Drop stamps whose word is no longer learned, so this map cannot
        // outgrow the dictionary it describes.
        let sizeBeforePrune = lastUsed.count
        lastUsed = lastUsed.filter { learnedWords[$0.key] != nil }
        let droppedStamps = sizeBeforePrune - lastUsed.count

        // This guard is also what keeps the migration off the log on an ordinary
        // load: `reload()` runs on every keyboard appearance, and a store that is
        // already fully stamped changes nothing and reports nothing.
        guard lastUsed != before else { return }
        AppGroup.defaults.set(lastUsed, forKey: Self.lastUsedKey)

        PersistentLog.log(.userDictionaryMigrated(
            stamped: stampedWords.count,
            droppedStamps: droppedStamps,
            learnedCount: learnedWords.count
        ))
        #if DEBUG
        AutocorrectDebugLog.userDictionaryMigrated(words: stampedWords)
        #endif
    }

    /// One entry as the eviction order sees it. Materialised once per eviction so
    /// the comparison below reads plain fields instead of hashing a string into
    /// two dictionaries every time it runs.
    private struct EvictionEntry {
        let word: String
        let count: Int
        let used: Int
    }

    /// Whether `lhs` should be evicted before `rhs`.
    ///
    /// WHY recency first, not usage count: the dictionary exists to hold words
    /// the base lexicon does not know — a colleague's name, a project name, a
    /// technical term. Those are typed a handful of times and sit at a count of
    /// 2 or 3, while every correctly-spelled word the user types is also learned
    /// and climbs into the hundreds. Evicting by lowest count therefore deleted
    /// exactly the vocabulary the feature protects and kept the words that never
    /// needed protecting (#304). Recency is what AOSP LatinIME protects too
    /// (`EntryInfoToTurncate::Comparator`).
    ///
    /// WHY the count tiebreak runs DESCENDING, the opposite of AOSP's: a learned
    /// word's only effect here is that autocorrect leaves it alone
    /// (`TextPredictionEngine.spellCheck`, the single read site of `isLearned`).
    /// A word with a high count is almost certainly an ordinary word the trie
    /// already knows, so dropping it changes nothing the user can observe — the
    /// trie still spells it and autocorrect still leaves it alone. Dropping a
    /// name typed twice is what the user notices. Between two entries of equal
    /// recency, the most-typed one is the cheapest to lose.
    ///
    /// The final comparison on the word itself only makes the order total, so
    /// the same dictionary always evicts the same entry.
    private static func shouldEvictFirst(_ lhs: EvictionEntry, _ rhs: EvictionEntry) -> Bool {
        if lhs.used != rhs.used { return lhs.used < rhs.used }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.word < rhs.word
    }

    /// The `limit` words that should be evicted first.
    ///
    /// WHY repeated minimum scans and not a sort: `saveToDefaults()` runs on
    /// every word boundary, and the dictionary overflows one word at a time, so
    /// `limit` is 1 in normal use. That makes this a single O(n) pass over the
    /// entries, where sorting the whole dictionary to read one element off the
    /// front is O(n log n). A larger `limit` only happens if something dumps many
    /// entries at once, and O(n · limit) is still acceptable there.
    private func evictionCandidates(limit: Int) -> [String] {
        // `?? 0` is unreachable by construction: every learned word is stamped on
        // load and on every mutation. Treating an unstamped entry as the oldest
        // possible is the safe reading if that ever breaks — it only affects
        // which word is dropped, never correctness.
        var remaining = learnedWords.map {
            EvictionEntry(word: $0.key, count: $0.value, used: lastUsed[$0.key] ?? 0)
        }
        var candidates: [String] = []
        while candidates.count < limit, !remaining.isEmpty {
            var worstIndex = 0
            for index in 1..<remaining.count where Self.shouldEvictFirst(remaining[index], remaining[worstIndex]) {
                worstIndex = index
            }
            candidates.append(remaining[worstIndex].word)
            remaining.remove(at: worstIndex)
        }
        return candidates
    }

    private func saveToDefaults() {
        // Evict least-recently-used words if we exceed the cap.
        // Keeps the dictionary bounded so it can't grow indefinitely from
        // accidental learning.
        if learnedWords.count > Self.maxLearnedWords {
            let toRemove = learnedWords.count - Self.maxLearnedWords
            let evicted = evictionCandidates(limit: toRemove)
            for key in evicted {
                learnedWords.removeValue(forKey: key)
                lastUsed.removeValue(forKey: key)
            }
            PersistentLog.log(.userDictionaryEvicted(
                removed: evicted.count,
                learnedCount: learnedWords.count,
                cap: Self.maxLearnedWords
            ))
            #if DEBUG
            AutocorrectDebugLog.userDictionaryEvicted(words: evicted)
            #endif
        }

        let defaults = AppGroup.defaults
        defaults.set(learnedWords, forKey: Self.storageKey)
        defaults.set(lastUsed, forKey: Self.lastUsedKey)
        defaults.set(pendingWords, forKey: Self.pendingKey)
    }

    private func savePendingToDefaults() {
        AppGroup.defaults.set(pendingWords, forKey: Self.pendingKey)
    }
}
