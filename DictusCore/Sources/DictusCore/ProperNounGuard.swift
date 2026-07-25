// DictusCore/Sources/DictusCore/ProperNounGuard.swift
// Conservative proper-noun detection for autocorrect (issue #199).
//
// WHY: for a keyboard, a false-positive correction is worse than a missed one.
// Names, brands and acronyms are usually not in the dictionary, are edit-
// distance-close to common words, and are typed once — so the correction
// pipeline "fixes" them into dictionary words before user-learning can help
// ("Mathilde" -> "matinée"-class corrections). An unknown capitalized word in
// the middle of a sentence is far more likely an intentional name than a typo:
// preserve it.
//
// WHAT THIS IS NOT: a general named-entity recognizer. The rules are pure
// string analysis, deliberately conservative, and only consulted for words the
// dictionary does not know (the caller checks validity/user-dictionary first).

import Foundation

public enum ProperNounGuard {

    /// Whether an unknown word looks like an intentional proper noun / acronym
    /// that autocorrect must preserve.
    ///
    /// Rules:
    /// - Contains a digit or any non-letter character (apostrophes, hyphens):
    ///   not our call — contraction/split branches own those tokens.
    /// - ALL-CAPS with 2+ letters ("SNCF", "EDF", "GPT"): preserve regardless
    ///   of sentence position — sentence-start capitalization never produces
    ///   all-caps.
    /// - Capitalized word (first letter uppercase, rest lowercase) of 3+
    ///   letters in the MIDDLE of a sentence ("vu Mathilde", "avec Pivi"):
    ///   preserve. At sentence start the capitalization is just autocap
    ///   ("Jai faim" must still correct), so the rule is inactive there.
    public static func isLikelyProperNoun(word: String, isAtSentenceStart: Bool) -> Bool {
        guard !word.isEmpty else { return false }
        guard word.allSatisfy({ $0.isLetter }) else { return false }

        // All-caps acronym: position-independent.
        if word.count >= 2 && word.allSatisfy({ $0.isUppercase }) {
            return true
        }

        // Capitalized word: only meaningful mid-sentence.
        guard !isAtSentenceStart else { return false }
        guard word.count >= 3 else { return false }
        guard let first = word.first, first.isUppercase else { return false }
        guard word.dropFirst().allSatisfy({ $0.isLowercase }) else { return false }
        return true
    }

    /// Whether `word` sits at the start of a sentence within `context`
    /// (the text before the cursor, ending with `word`).
    ///
    /// Mirrors the autocapitalization rules: start-of-field, after a newline,
    /// or after sentence-ending punctuation (. ! ? …) all count as sentence
    /// start. Returns `true` (the conservative answer — proper-noun rule
    /// stays inactive, corrections still allowed) when the context does not
    /// end with the word, e.g. under proxy desync.
    ///
    /// KNOWN LIMITATION: abbreviation periods ("M. Dupont") read as sentence
    /// ends, so the name after them is not protected by the mid-sentence rule.
    public static func isAtSentenceStart(context: String, word: String) -> Bool {
        guard !word.isEmpty, context.hasSuffix(word) else { return true }
        let preceding = context.dropLast(word.count)
        if preceding.isEmpty { return true }
        if preceding.last == "\n" { return true }
        let trimmed = preceding.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let last = trimmed.last, ".!?…".contains(last) { return true }
        return false
    }
}
