// DictusCore/Sources/DictusCore/TextCorrection/LearnedWordCompletions.swift
// Merges the user's learned words into the system completion list (#346).
import Foundation

/// Builds the `.completions` list the suggestion bar shows for a partial word,
/// giving one learned word the first slot when it extends what was typed.
///
/// WHY this is the only route a learned word takes into the bar (ADR 0004).
/// A learned word is **offered** (L1) and **immune** to autocorrect (L2), but it
/// is never an autocorrect **target** (L3) — the keyboard must not rewrite
/// another word into it. That rule is not a gate anyone has to enforce here: on
/// space only `spellCheck` can apply anything, and every suggestion mode except
/// `.corrections` is tap-only. A candidate that arrives through this function
/// and never through `spellCheck` is structurally incapable of being applied on
/// its own. Re-check that before letting a learned word reach `spellCheck`, the
/// trie, or `.corrections`.
///
/// WHY it lives in DictusCore rather than beside its one caller in the keyboard
/// extension: DictusCore is the only target `swift test` can see, and #287's
/// block A spent three device passes on learning logic that was correct only
/// where it happened to be called from. `UserDictionaryPruneGate` is the same
/// shape for the same reason.
public enum LearnedWordCompletions {

    /// Returns the completion list for `typedPrefix`, at most `limit` entries.
    ///
    /// - Parameters:
    ///   - typedPrefix: the partial word the user is typing, as typed. Its
    ///     capitalization is what the returned learned word mirrors.
    ///   - learnedWords: every learned word mapped to the epoch-second stamp of
    ///     its last use (`UserDictionary.learnedWordsByLastUsed`). Keys are
    ///     lowercased by the store; they are lowercased again here so a caller
    ///     cannot make the match depend on that.
    ///   - systemCompletions: the completions the system checker produced,
    ///     already ranked. Passed **unclipped** — the cap is applied after the
    ///     merge, otherwise a learned word that also appears in the ranked list
    ///     would cost a slot instead of filling one.
    ///   - limit: how many slots the suggestion bar has.
    public static func merge(
        typedPrefix: String,
        learnedWords: [String: Int],
        systemCompletions: [String],
        limit: Int = 3
    ) -> [String] {
        guard limit > 0 else { return [] }
        guard let match = bestMatch(for: typedPrefix, in: learnedWords) else {
            return Array(systemCompletions.prefix(limit))
        }

        // Casing is reconstructed, never stored: `UserDictionary` lowercases its
        // keys, so the form the user typed is gone by the time we read it back.
        // This is the same test the accent path applies in
        // `TextPredictionEngine.spellCheck`.
        let isCapitalized = typedPrefix.first?.isUppercase == true
        let display = isCapitalized ? match.capitalized : match

        // The system checker can know the word too — it is only absent from the
        // *trie*, which is what learning gates on. Dropping it here is what
        // makes "at most once" true rather than merely likely.
        let rest = systemCompletions.filter { $0.lowercased() != match }
        return [display] + rest.prefix(limit - 1)
    }

    /// The single learned word that gets the first slot, lowercased, or nil.
    ///
    /// WHY at most one, and why it takes the first slot rather than being ranked
    /// among the others: there is no scale on which a learned word and a system
    /// completion can be compared — the learned set carries a usage count that
    /// counts word boundaries, and the trie carries log-normalized frequencies
    /// (#326), so any arithmetic mixing them is a guess dressed as a number.
    /// One reserved slot is a decision instead of a guess, and it is bounded by
    /// how small the learned set became once #287 stopped learning trie words.
    private static func bestMatch(for typedPrefix: String, in learnedWords: [String: Int]) -> String? {
        let lowered = typedPrefix.lowercased()
        guard !lowered.isEmpty else { return nil }

        var best: (word: String, lastUsed: Int)?
        for (rawWord, lastUsed) in learnedWords {
            let word = rawWord.lowercased()
            // STRICT extension: a match equal to what was typed is dropped. The
            // word is already on screen in full, so echoing it back would spend
            // a slot on a tap that changes nothing.
            guard word.count > lowered.count, word.hasPrefix(lowered) else { continue }
            if let current = best, !isBetter(word: word, lastUsed: lastUsed, than: current) { continue }
            best = (word, lastUsed)
        }
        return best?.word
    }

    /// Whether a candidate outranks the current best.
    ///
    /// Recency wins (decision 4, using the `lastUsed` stamps #305 added). The
    /// comparison on the word itself only makes the order total, so the same
    /// dictionary always offers the same word — two entries stamped in the same
    /// second must not depend on `Dictionary` iteration order.
    private static func isBetter(
        word: String,
        lastUsed: Int,
        than current: (word: String, lastUsed: Int)
    ) -> Bool {
        if lastUsed != current.lastUsed { return lastUsed > current.lastUsed }
        return word < current.word
    }
}
