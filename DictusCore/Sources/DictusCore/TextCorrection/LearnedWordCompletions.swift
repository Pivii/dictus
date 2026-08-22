// DictusCore/Sources/DictusCore/TextCorrection/LearnedWordCompletions.swift
// Merges the user's learned words into the system completion list (#346).
import Foundation

/// Places one learned word in the suggestion bar: first slot in `.completions`,
/// third slot in `.corrections`. These two are the only routes a learned word
/// has into the bar, and both are tap-only.
///
/// WHY tap-only is the whole of the L3 guarantee (ADR 0004). A learned word is
/// **offered** (L1) and **immune** to autocorrect (L2), but it is never an
/// autocorrect **target** (L3) — the keyboard must not rewrite another word
/// into it. On space only `spellCheck` can apply anything, and `spellCheck`
/// never sees this file. `.corrections` is the one mode that previews an
/// automatic action, and it previews it in slot 1, which `correctionsRow` fills
/// from the corrector and never from the learned set.
///
/// So the rule holds by construction, not by a gate: nothing here can reach the
/// document without a tap. Re-check exactly that before letting a learned word
/// reach `spellCheck`, the trie, or slot 1 of the corrections row.
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
        guard let display = offer(for: typedPrefix, in: learnedWords) else {
            return Array(systemCompletions.prefix(limit))
        }

        // The system checker can know the word too — it is only absent from the
        // *trie*, which is what learning gates on. Dropping it here is what
        // makes "at most once" true rather than merely likely.
        let rest = systemCompletions.filter { $0.lowercased() != display.lowercased() }
        return [display] + rest.prefix(limit - 1)
    }

    /// Builds the `.corrections` row: `[typed | correction | third slot]`, where
    /// the third slot is a learned word extending what was typed, and otherwise
    /// the alternative correction it replaces.
    ///
    /// WHY the third slot and not the second, which is the one the user's eye
    /// goes to. Slot 1 is what space applies on its own; it is the preview of
    /// the automatic action, and the whole of ADR 0004 rests on a learned word
    /// never reaching it. Putting one there would be L3 — the keyboard deciding
    /// on its own that the user meant a word it learned — and that is #114's to
    /// grant, not this one's. Apple's keyboard does promote a learned word to
    /// the applied slot once four characters are typed; Dictus deliberately
    /// stops one slot short of that.
    ///
    /// WHY the row is built here rather than at its two call sites: `update`
    /// and `updateAsync` both assemble it, and the sync and async paths showing
    /// different bars for the same keystroke is the class of bug #114 item 4.4
    /// already tracks. One function is also the only version of this that
    /// `swift test` can reach.
    ///
    /// - Parameters:
    ///   - typedWord: the partial word as typed. Slot 0, and the prefix the
    ///     learned word must extend.
    ///   - correction: what space would apply. Slot 1, never a learned word.
    ///   - alternative: the runner-up correction, kept in slot 2 when no
    ///     learned word claims it.
    ///   - learnedWords: `UserDictionary.learnedWordsByLastUsed`.
    public static func correctionsRow(
        typedWord: String,
        correction: String,
        alternative: String?,
        learnedWords: [String: Int]
    ) -> [String] {
        var row = [typedWord, correction]

        // A learned word equal to something already in the row would show the
        // same string twice. It cannot equal `typedWord` — the match is a
        // strict extension — but `correction` is a separate source and nothing
        // stops the two agreeing.
        let learned = offer(for: typedWord, in: learnedWords)
            .flatMap { $0.lowercased() == correction.lowercased() ? nil : $0 }

        if let third = learned ?? alternative {
            row.append(third)
        }
        return row
    }

    /// The one learned word that strictly extends `typedPrefix`, cased to match
    /// it, or nil when nothing qualifies.
    ///
    /// This is the single selector both bar layouts share: whichever slot a
    /// learned word lands in, it is chosen by the same rules.
    public static func offer(for typedPrefix: String, in learnedWords: [String: Int]) -> String? {
        guard let match = bestMatch(for: typedPrefix, in: learnedWords) else { return nil }
        // Casing is reconstructed, never stored: `UserDictionary` lowercases its
        // keys, so the form the user typed is gone by the time we read it back.
        // This is the same test the accent path applies in
        // `TextPredictionEngine.spellCheck`.
        let isCapitalized = typedPrefix.first?.isUppercase == true
        return isCapitalized ? match.capitalized : match
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
