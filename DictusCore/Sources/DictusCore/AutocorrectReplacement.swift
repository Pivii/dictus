// DictusCore/Sources/DictusCore/AutocorrectReplacement.swift
// Boundary-safe validation for autocorrect word replacement (issue #191).
//
// THE BUG THIS PREVENTS:
// The keyboard used to replace a word by issuing `word.count` deleteBackward()
// calls, trusting a word captured from an earlier proxy read. When the proxy's
// reported context desyncs from the live document (rapid delete/retype produces
// phantom duplicated-letter words like "quee"), the fixed count over-deletes
// past the word into the preceding space: "pense quee" -> "penseque".
//
// THE INVARIANT:
// Before deleting anything, the caller re-reads the live context and this check
// confirms (a) the context actually ends with the word about to be replaced and
// (b) the character before that word is a boundary (whitespace, punctuation,
// symbol, or start-of-field). If either fails, the caller must skip the
// replacement — never a destructive guess.

import Foundation

public enum AutocorrectReplacement {

    /// Result of validating a pending word replacement against the live context.
    public enum CheckResult: Equatable {
        /// Safe to replace: delete exactly `deleteCount` characters
        /// (grapheme clusters, matching one deleteBackward() call each).
        case ok(deleteCount: Int)
        /// Unsafe: skip the replacement. `reason` is a machine-readable slug
        /// for DEBUG logs ("empty-word", "no-context", "suffix-mismatch",
        /// "no-boundary-before").
        case failed(reason: String)
    }

    /// Validates that `word` can be safely deleted from the end of `context`.
    ///
    /// - Parameters:
    ///   - context: the LIVE documentContextBeforeInput, re-read immediately
    ///     before applying the replacement (never a value captured earlier).
    ///   - word: the word the correction pipeline intends to replace.
    public static func check(context: String?, word: String) -> CheckResult {
        guard !word.isEmpty else {
            return .failed(reason: "empty-word")
        }
        guard let context = context, !context.isEmpty else {
            return .failed(reason: "no-context")
        }
        // Swift String comparison uses canonical equivalence, so precomposed
        // vs decomposed accents ("é" vs "e" + combining acute) still match here.
        guard context.hasSuffix(word) else {
            return .failed(reason: "suffix-mismatch")
        }
        // The character immediately before the word must be a boundary.
        // Letters/digits mean the word is glued to the previous token — the
        // word extraction disagreed with the raw text, deleting would merge words.
        // nil = word is at start-of-field, which is a valid boundary.
        // Punctuation is allowed: apostrophes ("l'ami" -> replacing "ami") and
        // hyphens are legitimate intra-token boundaries.
        if let preceding = context.dropLast(word.count).last,
           preceding.isLetter || preceding.isNumber {
            return .failed(reason: "no-boundary-before")
        }
        // Grapheme count of the verified suffix — canonically equivalent strings
        // have the same grapheme count, and deleteBackward() removes one
        // grapheme per call.
        return .ok(deleteCount: word.count)
    }
}
