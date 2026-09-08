// DictusCore/Sources/DictusCore/WordBoundaryDelete.swift
// Self-limiting backward delete for word replacement (issue #530).
//
// THE BUG THIS PREVENTS:
// A word replacement used to issue exactly `deleteCount` deleteBackward() calls,
// where the count came from AutocorrectReplacement.check reading
// documentContextBeforeInput. That check cannot detect a lying proxy — see the
// header of AutocorrectReplacement.swift — so when the proxy reported one
// character the document did not have, the loop deleted one character too many,
// crossed the space before the word and merged two words:
// "Une fois ton" + correcting "tonn" -> "ton" produced "Une foiston ".
// Measured on device on 2026-09-08, and it cascades: every repair attempt the
// user makes arms the next apply.
//
// THE INVARIANT:
// A replacement deletes at most up to the nearest word boundary. Before each
// deleteBackward() the tail is re-read, and the loop stops if the next character
// to be removed is whitespace or a newline — even with deletions left on the
// count. The count becomes a ceiling instead of a contract.
//
// WHY THIS IS CORRECT AND NOT JUST A SMALLER BLAST RADIUS:
// Under an over-count the surplus characters are phantoms — the proxy invented
// them, so they are not in the document. Stopping at the boundary therefore
// deletes exactly the real word: "Une fois ton" loses "ton", leaves "Une fois ",
// and the caller's insert restores "Une fois ton ". The over-count case comes
// out right, not merely non-destructive. Under the opposite desync — the proxy
// reporting fewer characters than the document holds — a stray character
// survives, which is a typo one backspace clears rather than destroyed text.
//
// PUNCTUATION STAYS CROSSABLE:
// Whitespace and newline only. The apostrophe in "l'ami" is a legitimate
// intra-token boundary that AutocorrectReplacement.check already allows, so
// clamping on it would break replacing "ami".

import Foundation

public enum WordBoundaryDelete {

    /// What a delete pass actually did.
    public struct Outcome: Equatable {
        /// The count the caller was handed by the boundary check.
        public let planned: Int
        /// How many deleteBackward() calls were issued. Never exceeds `planned`.
        public let deleted: Int

        /// True when the loop stopped on a boundary before spending the count —
        /// the signature of a proxy desync, and the only sign of one that is
        /// visible from inside the extension. Callers log it (#530 criterion 4).
        public var wasClamped: Bool { deleted < planned }

        public init(planned: Int, deleted: Int) {
            self.planned = planned
            self.deleted = deleted
        }
    }

    /// Deletes backwards up to `deleteCount` graphemes, stopping at a word boundary.
    ///
    /// The closures are the caller's live proxy, injected rather than passed as an
    /// object: `UITextDocumentProxy` is itself a protocol, so it cannot be given a
    /// retroactive conformance, and an adapter type would exist for nothing.
    ///
    /// - Parameters:
    ///   - deleteCount: the ceiling, normally from `AutocorrectReplacement.check`.
    ///   - contextBeforeInput: reads the LIVE documentContextBeforeInput. Called
    ///     once per iteration — never hoisted, the whole point is that the value
    ///     changes under the loop.
    ///   - deleteBackward: issues one deleteBackward() on the live proxy.
    ///   - onClamped: called only when the loop stopped short, so callers report a
    ///     desync without binding a result they would not otherwise read. Reporting
    ///     is part of this contract rather than the call site's because a clamp is
    ///     the only evidence of a desync the extension can produce (#530).
    /// - Returns: what was planned and what was actually deleted.
    @discardableResult
    public static func perform(
        deleteCount: Int,
        contextBeforeInput: () -> String?,
        deleteBackward: () -> Void,
        onClamped: (Outcome) -> Void = { _ in }
    ) -> Outcome {
        var deleted = 0
        while deleted < deleteCount {
            // A nil or empty context is start-of-field: nothing left to delete,
            // and a further deleteBackward() would reach into a document the
            // replacement never owned.
            guard let last = contextBeforeInput()?.last else { break }
            // `isNewline` is a subset of `isWhitespace`; both are named because
            // the invariant is stated over both, so narrowing one later cannot
            // silently drop the other.
            if last.isWhitespace || last.isNewline { break }
            deleteBackward()
            deleted += 1
        }
        let outcome = Outcome(planned: deleteCount, deleted: deleted)
        if outcome.wasClamped { onClamped(outcome) }
        return outcome
    }
}
