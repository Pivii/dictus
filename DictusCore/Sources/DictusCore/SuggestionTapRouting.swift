// DictusCore/Sources/DictusCore/SuggestionTapRouting.swift
// Routes a suggestion-bar tap to replace-or-insert (issue #335).
//
// THE BUG THIS PREVENTS:
// The bar's `.undoAvailable` mode fills slots 1-2 with completions of the word
// currently being typed, but the tap handler routed every non-zero slot of that
// mode to the insert-only prediction path. Tapping "concerné" while "concerne"
// was on screen produced "concerneconcerné" — the partial word was never deleted.
//
// THE INVARIANT:
// What a tap must do is decided by the LIVE document, never by the bar's mode
// and never by `currentWord` alone: the suggestion state keeps a stale
// `currentWord` when the cursor sits right after a space. If the live context
// ends mid-word, the tap replaces that word (with the #191 boundary check
// gating the delete); if it ends on a boundary, the tap inserts. When the live
// context ends mid-word but no longer matches `currentWord`, the tap does
// nothing: a tap that does nothing is recoverable, one that corrupts the text
// is not.

import Foundation

public enum SuggestionTapRouting {

    /// What the caller must do with the tapped suggestion.
    public enum Decision: Equatable {
        /// The cursor is mid-word and the word matches: delete exactly
        /// `deleteCount` characters (one deleteBackward() call each), then
        /// insert the suggestion.
        case replace(deleteCount: Int)
        /// The cursor is on a word boundary: insert the suggestion as-is.
        case insert
        /// The cursor is mid-word but the document no longer ends with the word
        /// the bar was built from. Do nothing. `reason` is the machine-readable
        /// slug from `AutocorrectReplacement` for DEBUG logs.
        case abort(reason: String)
    }

    /// Decides how a suggestion tap must be applied to the document.
    ///
    /// - Parameters:
    ///   - context: the LIVE documentContextBeforeInput, re-read at tap time
    ///     (never a value captured when the bar was built).
    ///   - currentWord: the partial word the suggestion bar was computed from.
    ///     Only consulted when the live context ends mid-word.
    public static func decide(context: String?, currentWord: String) -> Decision {
        // No context at all, or a context ending on a boundary: there is no
        // partial word to replace, whatever `currentWord` still holds.
        guard let lastChar = context?.last else {
            return .insert
        }
        if lastChar.isWhitespace || lastChar.isNewline {
            return .insert
        }
        // Mid-word: the delete is only safe if the live context still ends with
        // the word, preceded by a boundary (#191).
        switch AutocorrectReplacement.check(context: context, word: currentWord) {
        case .ok(let deleteCount):
            return .replace(deleteCount: deleteCount)
        case .failed(let reason):
            return .abort(reason: reason)
        }
    }
}
