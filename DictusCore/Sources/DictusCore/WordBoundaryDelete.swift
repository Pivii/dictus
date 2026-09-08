// DictusCore/Sources/DictusCore/WordBoundaryDelete.swift
// Self-limiting backward delete for word replacement (issue #530).
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ NOTHING CALLS THIS, AND NOTHING SHOULD. DO NOT WIRE IT UP.               │
// │                                                                          │
// │ It is a FALSIFIED design, kept only so the falsification stays           │
// │ executable — WordBoundaryDeleteTests runs it against the mirror/document │
// │ pair from #530's capture and asserts it does NOT help. Deleting this     │
// │ file deletes the proof and invites a third attempt at the same idea.     │
// │                                                                          │
// │ WHY IT CANNOT WORK, in one line: the loop re-reads the same mirror the   │
// │ guard already read, so the boundary it stops on is the mirror's, offset  │
// │ by exactly the phantom it was meant to catch. Worse, it is dead code by  │
// │ construction — AutocorrectReplacement.check returns .ok(deleteCount:)    │
// │ only when the mirror's last deleteCount characters ARE the word, and a   │
// │ word holds no whitespace, so the stop condition can never be true.       │
// │                                                                          │
// │ The two call sites that briefly used it (DictusKeyboardBridge            │
// │ .applyAutocorrect and KeyboardRootView.applyReplacement) were returned   │
// │ to their blind loops so #530's diagnostic round measures develop's       │
// │ behaviour, not this one's.                                               │
// └──────────────────────────────────────────────────────────────────────────┘
//
// Everything below is the original rationale, preserved as written, so the
// argument that looked convincing can be read next to the reason it was wrong.
//
// THE BUG THIS WAS MEANT TO PREVENT:
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
    ///   - onClamped: called only when the loop stopped short. No production caller
    ///     exists any more — the tests are what exercise it.
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
